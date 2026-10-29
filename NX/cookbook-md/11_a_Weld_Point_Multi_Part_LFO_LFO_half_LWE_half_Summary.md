# 11_a · Weld-Point Multi-Part LFO, LFO_half & LWE_half Aggregation (Open C)

## Description
[Doc 11](11_Weld_Point_LFO_LFO_half_LWE_half_Extraction.md) computes LFO / LFO_half / LWE_half for **one weld point on a single part**;
this skill is its **multi-part wrapper**: in reality **one weld point usually joins 2~N sheet-metal parts**, so each **part involved in that weld point** must be measured separately,
the results **aggregated into a table**, and the **minimum of each metric across the parts** taken as the weld point's final LFO / LFO_half / LWE_half.

**Flow**:
1. **Get the part-number list for the weld point from the context** (e.g. `["V2S9-R21124-A_14", "V2S9-R21125-B_02", ...]`).
2. **Strip the version suffix from each part number** (`V2S9-R21124-A_14` -> `V2S9-R21124-A`, **rule fixed**, see section 1) and then match against the **Item ID** in NX.
3. **Open the assembly once**, load all components; **reuse for each part** the single-part measurement of [doc 11](11_Weld_Point_LFO_LFO_half_LWE_half_Extraction.md)
   (activate part -> build the 10 mm probe line -> ray finds the intersecting faces -> LFO_half / LFO / LWE_half). **The first part "creates" this logic; the other parts reuse the same function**.
4. **One row per part** aggregated into a table; **weld final value = per-metric minimum across parts** (LFO_half, LFO, LWE_half each take their own independent min).

> This skill **does not change** the single-part measurement algorithm of [doc 11](11_Weld_Point_LFO_LFO_half_LWE_half_Extraction.md); it only adds an outer "multi-part loop + aggregation + min".
> **All mandatory constraints** of the single-part measurement (10 mm probe line, only one intersecting face for LFO/LFO_half, both faces used to exclude adjacent faces for LWE_half, etc.) **carry over unchanged from doc 11**.

> **MANDATORY constraints (fixed, no deviation) -- generated code must satisfy every row:**
>
> | # | Constraint | Hard requirement | Forbidden |
> | --- | --- | --- | --- |
> | Input | Part list | **Parse all part numbers joined by the weld point from the context** (>= 1), measure each | Measuring only the first / missing some |
> | Match | Strip version | **Strip the trailing `_<digits>` version suffix before matching the Item ID** (`StripVersion` is fixed, see section 1) | Matching with the version attached, stripping a non-numeric suffix |
> | Reuse | Single-part measurement | **Every part calls the same `MeasureWeldOnPart()`** (internally doc 11 sections 2~7) | Writing a separate algorithm per part |
> | Session | Open count | **`OpenDisplay` the assembly only once**; for each part `SetWorkComponent` to activate, switch back to root when done | Reopening the assembly per part |
> | Aggregate | Table | **One row per part** with partNo / ItemID / LFO / LFO_half / LWE_half / status | Printing only the final value without per-part details |
> | Aggregate | Take min | **Weld final LFO_half = min(per-part LFO_half)**; LFO and LWE_half **each independently** min | Average / max / first |
> | Aggregate | Skip failures | A part that is unmatched / not intersected gets a `FAIL` row and is **excluded from the min**, without interrupting the other parts | Exiting entirely on one failure |

## Keywords
weld point, multi-part, LFO, LFO_half, LWE_half, StripVersion, strip version, version suffix,
Item ID, part number list, MeasureWeldOnPart, SetWorkComponent, reuse, summary table, min, minimum,
aggregate, per-part, RootComponent, GetChildren, FindOccurrence, UF_ATTR

---

## 0. Input / output contract

| Item | Description |
| --- | --- |
| Input · weld point | `weldName`, `weldPos[3]` (assembly-space coordinates), `weldIjk[3]` (normal, not necessarily normalized) |
| Input · part-number list | `targetPartNos` (**all part numbers joined by this weld point**, may carry a `_NN` version suffix; taken from the context) |
| Input · path | `assemblyPath` (assembly `.prt`) |
| Output · per-part table | One row per part: input part number / version-stripped key / matched Item ID / LFO / LFO_half / LWE_half / status |
| Output · weld final value | **LFO_half = min(per part)**, **LFO = min(per part)**, **LWE_half = min(per part)** (each takes its own minimum independently) |

> Each metric's min may come from a **different part** (independent minimum), as agreed with the user.

---

## 1. Strip the version suffix (fixed rule)

**Rule (hard-coded)**: if a part number ends with `_` + **digits only**, remove that suffix; otherwise keep it as is.
Examples: `V2S9-R21124-A_14` -> `V2S9-R21124-A`; `ABC-123` -> `ABC-123` (no numeric suffix, untouched).

```cpp
#include <string>
#include <cctype>

// Strip the trailing "_<digits>" version suffix; use the stripped key to match the NX Item ID (rule fixed)
static std::string StripVersion(const std::string& partNo)
{
    size_t us = partNo.find_last_of('_');
    if (us == std::string::npos || us + 1 >= partNo.size())
        return partNo;                                   // no '_' or '_' at the end: leave unchanged
    for (size_t i = us + 1; i < partNo.size(); ++i)
        if (!std::isdigit(static_cast<unsigned char>(partNo[i])))
            return partNo;                               // suffix contains a non-digit: not a version, leave unchanged
    return partNo.substr(0, us);                         // "_<digits only>" -> remove
}
```

---

## 2. Single-part measurement function (reuses doc 11 sections 2~7)

Wrap the whole "match leaf -> activate -> probe line -> ray finds faces -> LFO_half/LFO/LWE_half" sequence of [doc 11](11_Weld_Point_LFO_LFO_half_LWE_half_Extraction.md) into one function
that is **called once per part**. The internal logic is identical to doc 11; it only writes the result into a `PartMeasure` struct (failure does not throw, it returns `ok=false`).

```cpp
// Measurement result of a single part
struct PartMeasure
{
    std::string partNoIn;        // input part number (with version)
    std::string itemIdKey;       // matching key after stripping the version
    std::string matchedItemId;   // Item ID actually matched
    double score = 0.0;          // match score
    double lfo = 0.0, lfoHalf = 0.0, lweHalf = 0.0;
    bool   ok = false;           // whether all three measurements succeeded
    std::string note;            // failure reason / remark
};

// Reuses the doc 11 single-part measurement: in the already opened assembly, find the leaf part by itemIdKey, activate it, measure LFO/LFO_half/LWE_half.
// Reuses the helper functions of doc 11 sections 2/3/4: ToLower, GetItemId, ItemIdMatchScore, BestMatch,
//   FindBestLeafByItemId, Dot/Cross/Normalize/RotateAroundAxis, CollectActiveFaces.
static PartMeasure MeasureWeldOnPart(
    NXOpen::Session* theSession,
    NXOpen::Assemblies::Component* root,        // assembly root component (for traversal and switching back)
    NXOpen::Part* topPart,                       // assembly part (used to switch back the work component)
    const std::string& partNoIn,
    const double weldPos[3], const double weldIjk[3])
{
    PartMeasure r;
    r.partNoIn  = partNoIn;
    r.itemIdKey = StripVersion(partNoIn);        // section 1: strip the version, then match the Item ID

    try
    {
        // -- 2.1 Match the leaf part (doc 11 section 2) --
        BestMatch best;
        if (root != nullptr) FindBestLeafByItemId(root, r.itemIdKey, best);
        if (best.comp == nullptr || best.score < 0.85)
        { r.note = "leaf part not matched"; return r; }

        r.matchedItemId = best.itemId;
        r.score         = best.score;

        PartLoadStatus* ws = nullptr;
        theSession->Parts()->SetWorkComponent(best.comp, &ws);   // activate this part
        if (ws) { delete ws; ws = nullptr; }
        NXOpen::Assemblies::Component* activeComp = best.comp;
        NXOpen::Part* activePart = dynamic_cast<NXOpen::Part*>(best.comp->Prototype());

        // -- 2.2 Build the 10 mm probe line (doc 11 section 3, mandatory: length=10, midpoint=weld point, direction=normalized IJK) --
        const double kLineLength = 10.0;
        double dir[3] = { weldIjk[0], weldIjk[1], weldIjk[2] }; Normalize(dir);
        double half = kLineLength * 0.5, segStart[3], segEnd[3];
        UF_CURVE_line_t lineData;
        for (int i = 0; i < 3; ++i)
        {
            segStart[i] = weldPos[i] - dir[i]*half;
            segEnd[i]   = weldPos[i] + dir[i]*half;
            lineData.start_point[i] = segStart[i];
            lineData.end_point[i]   = segEnd[i];
        }
        tag_t lineTag = NULL_TAG;
        if (UF_CURVE_create_line(&lineData, &lineTag) != 0 || lineTag == NULL_TAG)
        { r.note = "failed to create probe line"; return r; }

        // -- 2.3 Extract faces + ray finds the two intersecting faces, pick only one (doc 11 section 4) --
        std::vector<tag_t> bodyTags, faceTags;
        CollectActiveFaces(activeComp, activePart, bodyTags, faceTags);

        double xform[16]; UF_MTX4_identity(xform);
        tag_t face1 = NULL_TAG, face2 = NULL_TAG;
        int numHits = 0; UF_MODL_ray_hit_point_info_p_t hits = nullptr;
        if (UF_MODL_trace_a_ray((int)bodyTags.size(), bodyTags.data(),
                                segStart, dir, xform, 0, &numHits, &hits) == 0 && hits)
        {
            for (int i = 0; i < numHits && (face1==NULL_TAG || face2==NULL_TAG); ++i)
            {
                tag_t f = hits[i].hit_face;
                if (f == NULL_TAG) continue;
                if (face1 == NULL_TAG) face1 = f; else if (f != face1) face2 = f;
            }
            UF_free(hits);
        }
        if (face1 == NULL_TAG)
        { UF_OBJ_delete_object(lineTag); r.note = "probe line does not intersect the part"; return r; }
        tag_t chosenFace = face1;                         // LFO/LFO_half use only one face

        // -- 2.4 LFO_half = minimum edge <-> line distance of the chosen face (doc 11 section 5) --
        double lfoHalf = std::numeric_limits<double>::max();
        uf_list_p_t edgeList = nullptr;
        if (UF_MODL_ask_face_edges(chosenFace, &edgeList) == 0 && edgeList)
        {
            int ec = 0; UF_MODL_ask_list_count(edgeList, &ec);
            for (int i = 0; i < ec; ++i)
            {
                tag_t et = NULL_TAG;
                if (UF_MODL_ask_list_item(edgeList, i, &et) != 0 || et == NULL_TAG) continue;
                double d=0,p1[3]={0},p2[3]={0},g[3]={0,0,0},acc=0;
                if (UF_MODL_ask_minimum_dist_3(2, lineTag, et, 0, g, 0, g, &d, p1, p2, &acc) == 0)
                    if (d < lfoHalf) lfoHalf = d;
            }
            UF_MODL_delete_list(&edgeList);
        }

        // -- 2.5 LFO = shortest intersection of the section swept around the line with the same face (doc 11 section 6) --
        double lfo = std::numeric_limits<double>::max(); int bestDeg = -1;
        double ref[3] = { 1.0,0.0,0.0 };
        if (std::fabs(Dot(ref, dir)) > 0.9) { ref[0]=0; ref[1]=1; ref[2]=0; }
        double u[3]; Cross(dir, ref, u); Normalize(u);
        const double kPi = 3.14159265358979;
        for (int deg = 0; deg < 180; ++deg)
        {
            double ang = deg*kPi/180.0, inPlane[3];
            RotateAroundAxis(u, dir, ang, inPlane);
            double n[3]; Cross(dir, inPlane, n); Normalize(n);
            tag_t planeTag = NULL_TAG; double org[3] = { weldPos[0],weldPos[1],weldPos[2] };
            if (UF_MODL_create_plane(org, n, &planeTag) != 0 || planeTag == NULL_TAG) continue;

            int numInt = 0; UF_MODL_intersect_info_p_t* inter = nullptr;   // 5th argument = double pointer
            if (UF_MODL_intersect_objects(chosenFace, planeTag, 0.001, &numInt, &inter) == 0 && inter)
            {
                double tot = 0.0; bool has = false;
                for (int k = 0; k < numInt; ++k)
                {
                    UF_MODL_intersect_info_p_t item = inter[k];           // the element itself is a pointer
                    if (item != nullptr && item->intersect_type == UF_MODL_INTERSECT_CURVE)
                    {
                        tag_t c = item->intersect.curve.identifier; double len = 0.0;
                        if (UF_CURVE_ask_arc_length(c, 0.0, 1.0, UF_MODL_MMETER, &len) == 0) { tot += len; has = true; }
                        UF_OBJ_delete_object(c);
                    }
                }
                for (int k = 0; k < numInt; ++k) UF_free(inter[k]);        // free each element
                UF_free(inter);                                            // then free the array
                if (has && tot > 1e-6 && tot < lfo) { lfo = tot; bestDeg = deg; }
            }
            UF_OBJ_delete_object(planeTag);
        }

        // -- 2.6 LWE_half = after excluding intersecting/adjacent faces, minimum face <-> line distance of the remaining faces (doc 11 section 7, both faces used for exclusion) --
        double lweHalf = std::numeric_limits<double>::max();
        double g0[3] = { 0,0,0 };
        for (tag_t f : faceTags)
        {
            if (f == face1 || f == face2) continue;       // exclude the two intersecting faces themselves
            bool adjacent = false;
            double dF=0, pa[3]={0}, pb[3]={0}, acc=0;
            if (UF_MODL_ask_minimum_dist_3(2, f, face1, 0, g0, 0, g0, &dF, pa, pb, &acc) == 0 && dF < 1e-6)
                adjacent = true;
            if (!adjacent && face2 != NULL_TAG &&
                UF_MODL_ask_minimum_dist_3(2, f, face2, 0, g0, 0, g0, &dF, pa, pb, &acc) == 0 && dF < 1e-6)
                adjacent = true;
            if (adjacent) continue;                       // exclude faces adjacent to / touching the intersecting faces
            double dLine=0, q1[3]={0}, q2[3]={0}, acc2=0;
            if (UF_MODL_ask_minimum_dist_3(2, lineTag, f, 0, g0, 0, g0, &dLine, q1, q2, &acc2) == 0)
                if (dLine < lweHalf) lweHalf = dLine;
        }
        UF_OBJ_delete_object(lineTag);

        // -- 2.7 Decide success and fill back --
        bool okLfoHalf = (lfoHalf != std::numeric_limits<double>::max());
        bool okLfo     = (bestDeg >= 0);
        bool okLwe     = (lweHalf != std::numeric_limits<double>::max());
        r.lfoHalf = okLfoHalf ? lfoHalf : 0.0;
        r.lfo     = okLfo     ? lfo     : 0.0;
        r.lweHalf = okLwe     ? lweHalf : 0.0;
        r.ok      = okLfoHalf && okLfo && okLwe;
        if (!r.ok) r.note = "some metrics failed to measure";
    }
    catch (const NXException& ex) { r.ok = false; r.note = std::string("NXException: ") + ex.Message(); }
    catch (const std::exception& ex) { r.ok = false; r.note = std::string("error: ") + ex.what(); }

    // Switch back to the assembly root so the next part activates cleanly
    if (topPart != nullptr)
    {
        PartLoadStatus* rs = nullptr;
        theSession->Parts()->SetWork(topPart);   // or SetWorkComponent(root, &rs)
        if (rs) { delete rs; rs = nullptr; }
    }
    return r;
}
```

> **"The first part creates, the rest reuse"**: `MeasureWeldOnPart` is the reused logic -- the assembly is opened only once,
> and the loop just calls it for each part number; there is no need to reopen the assembly or write another algorithm per part.

---

## 3. Aggregate the minimum + print the table

After running `MeasureWeldOnPart` for all parts, successful rows take part in the min; each metric takes its minimum **independently**.

```cpp
struct WeldAggregate
{
    double lfo = 0.0, lfoHalf = 0.0, lweHalf = 0.0;
    bool   hasLfo = false, hasLfoHalf = false, hasLweHalf = false;
    std::string lfoFrom, lfoHalfFrom, lweHalfFrom;   // which part each minimum came from
};

static WeldAggregate AggregateMin(const std::vector<PartMeasure>& rows)
{
    WeldAggregate a;
    for (const PartMeasure& r : rows)
    {
        if (!r.ok) continue;                              // failed rows are excluded from the min
        if (!a.hasLfoHalf || r.lfoHalf < a.lfoHalf) { a.lfoHalf = r.lfoHalf; a.hasLfoHalf = true; a.lfoHalfFrom = r.matchedItemId; }
        if (!a.hasLfo     || r.lfo     < a.lfo)     { a.lfo     = r.lfo;     a.hasLfo     = true; a.lfoFrom     = r.matchedItemId; }
        if (!a.hasLweHalf || r.lweHalf < a.lweHalf) { a.lweHalf = r.lweHalf; a.hasLweHalf = true; a.lweHalfFrom = r.matchedItemId; }
    }
    return a;
}

static void PrintReport(const std::string& weldName, const double weldPos[3], const double dir[3],
                        const std::vector<PartMeasure>& rows, const WeldAggregate& a)
{
    std::cout << "==== Weld Point (multi-part) LFO / LWE Result ====" << std::endl;
    std::cout << "Name     : " << weldName << std::endl;
    std::cout << "Position : (" << weldPos[0] << ", " << weldPos[1] << ", " << weldPos[2] << ")" << std::endl;
    std::cout << "IJK      : (" << dir[0] << ", " << dir[1] << ", " << dir[2] << ")" << std::endl;
    std::cout << "Parts    : " << rows.size() << std::endl << std::endl;

    // Per-part detail table
    std::cout << "| PartNo(in)          | ItemID(key)        | Matched            | LFO      | LFO_half | LWE_half | Status |" << std::endl;
    std::cout << "|---------------------|--------------------|--------------------|----------|----------|----------|--------|" << std::endl;
    for (const PartMeasure& r : rows)
    {
        std::cout << "| " << r.partNoIn
                  << " | " << r.itemIdKey
                  << " | " << (r.matchedItemId.empty() ? "-" : r.matchedItemId)
                  << " | " << (r.ok ? r.lfo     : 0.0)
                  << " | " << (r.ok ? r.lfoHalf : 0.0)
                  << " | " << (r.ok ? r.lweHalf : 0.0)
                  << " | " << (r.ok ? "OK" : ("FAIL:" + r.note)) << " |" << std::endl;
    }

    // Weld final value = per-metric minimum across parts
    std::cout << std::endl << "---- Weld final (min across parts) ----" << std::endl;
    std::cout << "LFO      : " << (a.hasLfo     ? a.lfo     : 0.0) << " mm  (from " << a.lfoFrom     << ")" << std::endl;
    std::cout << "LFO_half : " << (a.hasLfoHalf ? a.lfoHalf : 0.0) << " mm  (from " << a.lfoHalfFrom << ")" << std::endl;
    std::cout << "LWE_half : " << (a.hasLweHalf ? a.lweHalf : 0.0) << " mm  (from " << a.lweHalfFrom << ")" << std::endl;
}
```

---

## 4. Complete `NxMain` (open the assembly once, measure each part in a loop, aggregate the minimum)

```cpp
#include <iostream>
#include <string>
#include <vector>
#include <cmath>
#include <limits>

#include <NXOpen/Session.hxx>
#include <NXOpen/Part.hxx>
#include <NXOpen/PartCollection.hxx>
#include <NXOpen/PartLoadStatus.hxx>
#include <NXOpen/LoadOptions.hxx>
#include <NXOpen/NXException.hxx>
#include <NXOpen/Body.hxx>
#include <NXOpen/BodyCollection.hxx>
#include <NXOpen/NXObject.hxx>
#include <NXOpen/Assemblies_ComponentAssembly.hxx>
#include <NXOpen/Assemblies_Component.hxx>

#include <uf.h>
#include <uf_modl.h>
#include <uf_curve.h>
#include <uf_mtx.h>
#include <uf_obj.h>
#include <uf_attr.h>
#include <cctype>

using namespace NXOpen;

// Paste the helper functions of doc 11 sections 2/3/4: ToLower, GetItemId, ItemIdMatchScore,
//    BestMatch, FindBestLeafByItemId, Dot/Cross/Normalize/RotateAroundAxis, CollectActiveFaces.
// Paste section 1 StripVersion, section 2 PartMeasure/MeasureWeldOnPart, section 3 WeldAggregate/AggregateMin/PrintReport of this document.

// DLL entry: argv[0] = DLL path, argv[1] = first user argument
extern "C" __declspec(dllexport) int NxMain(int argc, char* argv[])
{
    // Inputs: assembly path + weld point + part-number list joined by the weld point (taken from the context)
    std::string assemblyPath = (argc >= 2) ? argv[1] : "C:\\path\\to\\assembly.prt";
    std::string weldName     = "WPWDPZ1B82620_01_R_00";
    double weldPos[3] = { 2999.643, 102.671, 478.413 };      // weld position (assembly space)
    double weldIjk[3] = { 0.0, 0.913, 0.408 };               // weld normal IJK

    // Several part numbers joined by this weld point (with version; parsed from the context)
    std::vector<std::string> targetPartNos = {
        "V2S9-R21124-A_14",
        "V2S9-R21125-B_02"
        // ... the remaining part numbers involved in this weld point in the context
    };

    if (UF_initialize() != 0)
    {
        std::cerr << "UF_initialize failed. Check NX runtime / license." << std::endl;
        std::cerr.flush();
        return 1;
    }

    int rc = 0;
    try
    {
        Session* theSession = Session::GetSession();
        theSession->Parts()->LoadOptions()->SetComponentsToLoad(NXOpen::LoadOptions::LoadComponentsAll);

        // Open the assembly only once
        PartLoadStatus* ls = nullptr;
        Part* topPart = theSession->Parts()->OpenDisplay(assemblyPath.c_str(), &ls);
        if (ls) { delete ls; ls = nullptr; }
        if (topPart == nullptr) throw NXException::Create("Cannot open the assembly.");

        NXOpen::Assemblies::ComponentAssembly* ca = topPart->ComponentAssembly();
        NXOpen::Assemblies::Component* root = ca ? ca->RootComponent() : nullptr;
        if (root == nullptr) throw NXException::Create("The opened part is not an assembly (no RootComponent).");

        // The normalized direction is used only for the report
        double dir[3] = { weldIjk[0], weldIjk[1], weldIjk[2] };
        double dn = std::sqrt(dir[0]*dir[0]+dir[1]*dir[1]+dir[2]*dir[2]);
        if (dn > 1e-12) { dir[0]/=dn; dir[1]/=dn; dir[2]/=dn; }

        // Reuse the same measurement function for each part (the first "creates" the logic, the rest reuse it)
        std::vector<PartMeasure> rows;
        for (const std::string& pn : targetPartNos)
            rows.push_back(MeasureWeldOnPart(theSession, root, topPart, pn, weldPos, weldIjk));

        // Aggregate the minimum and print the table
        WeldAggregate agg = AggregateMin(rows);
        PrintReport(weldName, weldPos, dir, rows, agg);
    }
    catch (const NXException& ex) { std::cerr << "NX exception: " << ex.Message() << std::endl; rc = 1; }
    catch (const std::exception& ex) { std::cerr << "Error: " << ex.what() << std::endl; rc = 1; }

    UF_terminate();
    std::cout.flush();
    std::cerr.flush();
    return rc;
}
```

---

## 5. Output example

```
==== Weld Point (multi-part) LFO / LWE Result ====
Name     : WPWDPZ1B82620_01_R_00
Position : (2999.643, 102.671, 478.413)
IJK      : (0, 0.913, 0.408)
Parts    : 2

| PartNo(in)          | ItemID(key)        | Matched            | LFO      | LFO_half | LWE_half | Status |
|---------------------|--------------------|--------------------|----------|----------|----------|--------|
| V2S9-R21124-A_14    | V2S9-R21124-A      | V2S9-R21124-A      | 12.83    | 6.02     | 8.44     | OK |
| V2S9-R21125-B_02    | V2S9-R21125-B      | V2S9-R21125-B      | 11.10    | 5.35     | 9.12     | OK |

---- Weld final (min across parts) ----
LFO      : 11.10 mm  (from V2S9-R21125-B)
LFO_half : 5.35 mm  (from V2S9-R21125-B)
LWE_half : 8.44 mm  (from V2S9-R21124-A)
```

> Note: the three minima may come from **different parts** (in this example LFO/LFO_half come from part B, LWE_half from part A).

---

## 6. Gotchas

- **Version stripping is fixed**: only strip the trailing `_<digits only>`; `V2S9-R21124-A_14` -> `V2S9-R21124-A`. If the data uses another version format (e.g. `-14`, `.14`), extend `StripVersion` as needed, but do not change the default rule.
- **Open the assembly only once**: keep `OpenDisplay` outside the loop; inside the loop `SetWorkComponent` to activate each part and `SetWork(topPart)` to switch back when done, to avoid session-state leakage.
- **A failed part does not sink the whole run**: a part that is unmatched / not intersected -> that row is marked `FAIL` and excluded from the min; the other parts are measured as usual.
- **Each min is independent**: LFO / LFO_half / LWE_half **separately** take the cross-part minimum and may come from different parts; do not take all three from the same part.
- **All mandatory constraints carry over from doc 11**: 10 mm probe line, only one intersecting face for LFO/LFO_half, both faces excluding adjacent faces for LWE_half -- this skill only adds the loop and aggregation on the outside and **must not** change the single-part algorithm.
- **Consistent coordinate system**: weld coordinates/normals are in assembly space; `MeasureWeldOnPart` uses `FindOccurrence` to take occurrence faces (assembly space), the same system as the weld point.
- **Load all components**: `SetComponentsToLoad(LoadComponentsAll)` must be set before opening the assembly, otherwise the leaf `Prototype()`/attributes are empty.
- **Resource cleanup**: the `lineTag`, `planeTag`, intersection curves, `inter[k]`/`inter`, and `hits` of each part measurement are all released in pairs inside `MeasureWeldOnPart`.

---

## 7. Relation to doc 11

| | [Doc 11](11_Weld_Point_LFO_LFO_half_LWE_half_Extraction.md) (single part) | **11_a (this doc, multi-part)** |
| --- | --- | --- |
| Input | One weld point + **one** part number | One weld point + **a set of** part numbers (parsed from the context) |
| Strip version | Strips the suffix internally when scoring the match | **Explicit, fixed `StripVersion`** before matching |
| Measurement | Done once directly in the entry function | Wrapped as `MeasureWeldOnPart()`, **reused for every part** |
| Session | Open once, measure one | Open once, **loop over several**, switch back to root afterwards |
| Output | A single LFO/LFO_half/LWE_half | **Per-part table** + weld final value with **per-metric cross-part min** |
| Algorithm constraints | Defined there (mandatory) | **Carried over unchanged**, only the outer loop and aggregation added |

## 8. API quick reference

| Function / struct | Purpose |
| --- | --- |
| `StripVersion(partNo)` | Strip the trailing `_<digits>` version (fixed), producing the Item ID matching key |
| `MeasureWeldOnPart(session, root, topPart, partNo, pos, ijk)` -> `PartMeasure` | Reuses the doc 11 single-part measurement, returns LFO/LFO_half/LWE_half |
| `Parts()->SetWorkComponent(comp, &ls)` | Activate the current part |
| `Parts()->SetWork(topPart)` | Switch back to the assembly root after measuring (clean activation for the next part) |
| `AggregateMin(rows)` -> `WeldAggregate` | Independent cross-part minimum for each metric |
| `PrintReport(...)` | Print the per-part detail table + the weld's final minimum values |
| All helper functions of doc 11 sections 2~7 | Match leaf / build line / ray finds faces / measure distance / intersect (reused, not rewritten) |

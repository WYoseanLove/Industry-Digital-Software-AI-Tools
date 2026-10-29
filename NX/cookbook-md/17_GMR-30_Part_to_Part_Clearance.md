# 17 · GMR-30 Sheet-Metal Mating-Face Edge-to-Edge Clearance (Part-to-Part Clearance >= 4mm) (Open C)

## Description
End-to-end batch-DLL skill: **input** an assembly `.prt` path and **two sheet-metal part numbers**; the program **opens the assembly remotely**,
locates the two sheet-metal parts in the structure tree by **Item ID** (first strip a version suffix such as `_14`, then match),
extracts **all planar faces** of each part (a face is judged planar by **whether its normal varies with position on the face**: a single normal = planar, varying normal = curved, curved faces are skipped),
then finds the **mating face pairs** among the planar faces of the two parts (normals parallel or opposite at 180 degrees, and face-to-face distance ~ 0),
and for every mating pair **extracts the edges of each face** (keeping only edges that are the **intersection of one planar face and one non-planar face**; edges between two planar faces are passed), and computes the **minimum distance between every pair of edges** of the two parts:
- `min distance > 4mm` -> **PASS**;
- `min distance < 4mm` -> **FAIL**, output the **two nearest-point coordinates** on the two edges of that region; **output ALL** regions that do not satisfy 4mm;
- if the two nearest points have **identical coordinates** (the edges intersect) -> **ignore** that region.

The snippets reuse docs 00~11 of this library: entry/session (00), assembly traversal (07), Item ID matching (10/11), face/edge extraction (03), minimum distance (05).

> **MANDATORY constraint table (fixed, no deviation) -- generated code must satisfy every row; changing any one is an implementation error:**
>
> | # | Constraint | Hard requirement | Forbidden |
> | --- | --- | --- | --- |
> | Input | Part numbers | **Exactly two** sheet-metal part numbers; one assembly path | Fewer / more than two parts |
> | Match | Strip version | **Strip the trailing `_<digits>` version suffix before matching the Item ID** (`StripVersion` fixed, see section 1) | Comparing with the version attached, stripping a non-numeric suffix |
> | Locate | Traversal | From `RootComponent`, `GetChildren()` **recursing down to the leaves** (`GetChildren()` empty = "a part with no children of its own") | Looking only at the top / intermediate levels |
> | Locate | Match basis | **The Item ID user attribute of the leaf part** (read via `UF_ATTR`) **equals** the version-stripped part number | Locating by `DisplayName` / file name / tree-node name |
> | Planar test | Method | **Sample the normal at several UV points on the face**: **unique normal (consistent at all sample points) = planar**; normal varies with position = curved -> **skip** (see section 3) | Taking only one-point normal / using a face as planar without testing |
> | Pairing | Condition | Planar faces of the two parts: **normals parallel or opposite (`abs(dot)~1`, i.e. 0 or 180 degrees)** **and** **minimum face-to-face distance ~ 0** (mating) | Checking only normals without distance, or only distance without normals |
> | Pairing | Scope | Find **all** pairs of planar faces between the two parts that satisfy the condition | Taking only the first pair / missing pairs |
> | Edge filter | Target edges (fixed; omitting this is an implementation error) | **MANDATORY**: measure only edges that are the **intersection of one planar face and one non-planar face** (`UF_MODL_ask_edge_faces` gets the two adjacent faces of the edge, judge planarity with the section 3 unique-normal test, keep only if `planarCount==1`, exactly one planar and one non-planar); **edges between two planar faces and edges between two non-planar faces are passed outright** | Using two-plane intersection edges, measuring without checking adjacent faces, using face centroids / vertices |
> | Measure | Edge distance | For each mating pair: take each face's **target boundary edges**, **every edge of face A x every edge of face B**, compute the minimum distance | Measuring only one edge |
> | Intersection ignore | Coincident nearest points | If the **two nearest-point coordinates are identical** for the minimum edge-to-edge distance (`|p1-p2|~0`), the edges **intersect**: **ignore that region** | Treating an intersection as a < 4mm failure |
> | Verdict | Threshold | **`> 4mm` PASS; `< 4mm` FAIL** (`const double kClearance = 4.0;`) | Changing the threshold, mixing `<=` / `>=` at the boundary |
> | Output | Failures | Output **all** regions that do not satisfy 4mm, each with **two nearest-point coordinates on the two edges** (one 3D point each for object1/object2) | Reporting only the single minimum, reporting distance without coordinates |

## Keywords
part to part clearance, mating face, sheet metal, edge to edge, 4mm, StripVersion, strip version,
Item ID, leaf component, UF_ATTR, planar face, planar test, unique normal, UF_MODL_ask_face_props,
UF_MODL_ask_face_uv_minmax, UF_MODL_ask_face_type, unit normal, parallel antiparallel, |dot|,
UF_MODL_ask_body_faces, UF_MODL_ask_face_edges, UF_MODL_ask_minimum_dist_3, nearest point,
ComponentAssembly, RootComponent, GetChildren, FindOccurrence, SetWorkComponent, PASS, FAIL

---

## 0. Input / output contract

| Item | Description |
| --- | --- |
| Input · path | `assemblyPath` (assembly `.prt`) |
| Input · part numbers | `partNoA`, `partNoB` (two sheet-metal part numbers, may carry a `_NN` version suffix, e.g. `V2S9-R21124-A_14`) |
| Threshold | `kClearance = 4.0` mm (the shortest edge-to-edge distance **must be > 4mm**) |
| Output · pass | Per mating pair: `PASS  minDist=<value> mm` |
| Output · fail | **Every** region with `minDist < 4mm` prints one `FAIL  minDist=<value> mm` line, plus the two nearest points on the two edges `P1(x,y,z)` / `P2(x,y,z)` |
| Ignore | The two nearest points have identical coordinates (edges intersect) -> skip without reporting |

> Unlike the weld-point scenario, this is a **face-to-face mating** measurement; both parts' geometry uses the **occurrence (assembly space)**, so distances are measured directly in one coordinate system with no manual transformation.

---

## 1. Strip the version suffix (fixed rule, reuses 11_a section 1)

**Rule (hard-coded)**: if a part number ends with `_` + **digits only**, remove that suffix; otherwise keep it as is.
Examples: `V2S9-R21124-A_14` -> `V2S9-R21124-A`; `ABC-123` -> `ABC-123` (no numeric suffix, untouched).

```cpp
#include <string>
#include <cctype>

static std::string StripVersion(const std::string& partNo)
{
    size_t us = partNo.find_last_of('_');
    if (us == std::string::npos || us + 1 >= partNo.size()) return partNo;   // no '_' or '_' at the end: leave unchanged
    for (size_t i = us + 1; i < partNo.size(); ++i)
        if (!std::isdigit(static_cast<unsigned char>(partNo[i]))) return partNo; // suffix contains a non-digit: not a version
    return partNo.substr(0, us);                                             // "_<digits only>" -> remove
}

static std::string ToLower(std::string s)
{
    for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return s;
}
```

---

## 2. Open the assembly, locate the two leaf parts by Item ID (reuses 07 / 10 / 11 sections 1~2)

> **MANDATORY**: the assembly must **first be asked to load all child components**, otherwise the leaf `Prototype()`/attributes are unavailable;
> read the **Item ID** only at **leaf parts where `GetChildren()` is empty** ("parts with no children of their own"); a hit is when it **equals** the **version-stripped** part number.

```cpp
#include <NXOpen/Session.hxx>
#include <NXOpen/Part.hxx>
#include <NXOpen/PartCollection.hxx>
#include <NXOpen/PartLoadStatus.hxx>
#include <NXOpen/LoadOptions.hxx>
#include <NXOpen/Assemblies_ComponentAssembly.hxx>
#include <NXOpen/Assemblies_Component.hxx>
#include <uf.h>
#include <uf_attr.h>
#include <vector>

// Read the leaf part's Item ID (UF_ATTR, most stable in batch; same as doc 11 section 2.1)
static std::string GetItemId(NXOpen::Part* part)
{
    std::string itemId;
    if (part == nullptr) return itemId;
    const tag_t objTag = part->Tag();
    UF_ATTR_iterator_t iter;
    if (UF_ATTR_init_user_attribute_iterator(&iter) != 0) return itemId;
    for (;;)
    {
        UF_ATTR_info_t info; UF_ATTR_init_user_attribute_info(&info);
        logical has = false;
        int irc = UF_ATTR_get_next_user_attribute(objTag, &iter, &info, &has);
        if (irc != 0 || !has) { UF_ATTR_free_user_attribute_info_strings(&info); break; }
        std::string title = info.title ? info.title : "";
        std::string value = info.string_value ? info.string_value : "";
        std::string low = ToLower(title);
        if (itemId.empty() &&
            (low.find("item id") != std::string::npos || low.find("itemid") != std::string::npos ||
             low.find("item_id") != std::string::npos || low.find("dbc_part_no") != std::string::npos))
            itemId = value;
        UF_ATTR_free_user_attribute_info_strings(&info);
        if (!itemId.empty()) break;
    }
    UF_ATTR_release_user_attribute_iterator(&iter);
    return itemId;
}

// "Equal" after stripping versions: case-insensitive, strip the "_NN" suffix on both sides before comparing
static bool ItemIdMatches(const std::string& itemId, const std::string& partNo)
{
    if (itemId.empty()) return false;
    std::string a = ToLower(StripVersion(itemId));
    std::string b = ToLower(StripVersion(partNo));
    return a == b;
}

// Recursive traversal: match by Item ID only at leaves (no children), return the hit leaf component
static NXOpen::Assemblies::Component* FindLeafByItemId(
    NXOpen::Assemblies::Component* comp, const std::string& partNo)
{
    if (comp == nullptr) return nullptr;
    std::vector<NXOpen::Assemblies::Component*> children = comp->GetChildren();
    if (children.empty())                                       // "a part with no children of its own" = leaf
    {
        NXOpen::Part* proto = dynamic_cast<NXOpen::Part*>(comp->Prototype());
        std::string itemId = GetItemId(proto);
        std::cout << "  leaf: " << comp->DisplayName().GetText() << "  ItemID=" << itemId << std::endl;
        return ItemIdMatches(itemId, partNo) ? comp : nullptr;  // Item ID equals the version-stripped part number = hit
    }
    for (NXOpen::Assemblies::Component* c : children)
        if (NXOpen::Assemblies::Component* hit = FindLeafByItemId(c, partNo)) return hit;
    return nullptr;
}
```

Call (open the assembly + locate the two parts):

```cpp
Session* theSession = Session::GetSession();
theSession->Parts()->LoadOptions()->SetComponentsToLoad(NXOpen::LoadOptions::LoadComponentsAll);

PartLoadStatus* ls = nullptr;
Part* topPart = theSession->Parts()->OpenDisplay(assemblyPath.c_str(), &ls);
if (ls) { delete ls; ls = nullptr; }
if (topPart == nullptr) throw NXException::Create("Cannot open the assembly part.");

NXOpen::Assemblies::ComponentAssembly* ca = topPart->ComponentAssembly();
NXOpen::Assemblies::Component* root = ca ? ca->RootComponent() : nullptr;
if (root == nullptr) throw NXException::Create("The opened part is not an assembly (no components); this skill requires an assembly.");

NXOpen::Assemblies::Component* compA = FindLeafByItemId(root, partNoA);
NXOpen::Assemblies::Component* compB = FindLeafByItemId(root, partNoB);
if (compA == nullptr) throw NXException::Create("Part A not found: " + partNoA);
if (compB == nullptr) throw NXException::Create("Part B not found: " + partNoB);
```

---

## 3. Extract each part's planar faces -- judged by "does the normal vary with position" (core)

> **MANDATORY (no deviation) -- planarity may only be judged by "unique normal":**
> 1. Take the face's UV parameter range (`UF_MODL_ask_face_uv_minmax`) and compute one **unit normal** (`UF_MODL_ask_face_props`) at **several UV sample points** (the 3x3 grid, >= 5 points).
> 2. **All sample normals agree with each other (`|dot| >= 0.9995`, about <= 1.8 degrees) -> planar**; if any point's normal deviates -> the normal varies with position -> **curved, skip**.
> 3. The representative normal of a planar face is the normalized reference normal.
>
> Note: `UF_MODL_ask_face_type(face,&type)` returning `22` (plane) can serve as a **quick bypass**, but the **primary criterion is still the unique-normal test above** (for splines/near-planar faces with tiny curvature the normal method is more robust).

```cpp
#include <uf_modl.h>
#include <NXOpen/Body.hxx>
#include <NXOpen/BodyCollection.hxx>
#include <cmath>

static double Dot(const double a[3], const double b[3]) { return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]; }
static void Normalize(double a[3]) { double n=std::sqrt(Dot(a,a)); if (n>1e-12){a[0]/=n;a[1]/=n;a[2]/=n;} }

// A planar face (used for mating measurement)
struct PlanarFace
{
    tag_t  faceTag = NULL_TAG;
    double normal[3] = {0,0,0};       // representative normal (normalized)
};

// Compute the unit normal at the given (u,v); returns true on success
static bool FaceNormalAt(tag_t face, double u, double v, double outNorm[3])
{
    double param[2] = { u, v };
    double point[3], u1[3], v1[3], u2[3], v2[3], unitNorm[3], radii[2];
    if (UF_MODL_ask_face_props(face, param, point, u1, v1, u2, v2, unitNorm, radii) != 0) return false;
    outNorm[0]=unitNorm[0]; outNorm[1]=unitNorm[1]; outNorm[2]=unitNorm[2];
    Normalize(outNorm);
    return true;
}

// Sample normals at several points: unique normal -> planar (fill rep normal, return true); varying normal -> curved (return false)
static bool IsPlanarByNormal(tag_t face, double repNormal[3])
{
    double uv[4] = {0,0,0,0};                                   // {umin,umax,vmin,vmax}
    if (UF_MODL_ask_face_uv_minmax(face, uv) != 0) return false;

    const double fu[3] = { 0.05, 0.5, 0.95 };                  // sampling fractions (avoid degenerate boundaries)
    const double fv[3] = { 0.05, 0.5, 0.95 };
    double norms[9][3]; int n = 0;
    for (int i = 0; i < 3; ++i)
        for (int j = 0; j < 3; ++j)
        {
            double u = uv[0] + (uv[1]-uv[0]) * fu[i];
            double v = uv[2] + (uv[3]-uv[2]) * fv[j];
            if (FaceNormalAt(face, u, v, norms[n])) ++n;
        }
    if (n < 3) return false;                                    // too few samples, conservatively treat as non-planar

    // Use the first sample as reference and check that all sample normals agree
    double* ref = norms[0];
    for (int k = 1; k < n; ++k)
        if (std::fabs(Dot(ref, norms[k])) < 0.9995) return false; // one point's normal deviates -> curved

    repNormal[0]=ref[0]; repNormal[1]=ref[1]; repNormal[2]=ref[2];
    Normalize(repNormal);
    return true;
}

// Collect all "planar faces" of a part (occurrence, assembly space)
static void CollectPlanarFaces(
    NXOpen::Assemblies::Component* comp, std::vector<PlanarFace>& out)
{
    NXOpen::Part* proto = dynamic_cast<NXOpen::Part*>(comp->Prototype());
    if (proto == nullptr) return;
    BodyCollection* bodies = proto->Bodies();
    for (BodyCollection::iterator it = bodies->begin(); it != bodies->end(); ++it)
    {
        NXOpen::Body* pb = *it;
        if (pb == nullptr || !pb->IsSolidBody()) continue;
        NXOpen::Body* use = pb;
        NXOpen::Body* occ = dynamic_cast<NXOpen::Body*>(comp->FindOccurrence(pb)); // map into assembly space
        if (occ) use = occ;

        uf_list_p_t fl = nullptr;
        if (UF_MODL_ask_body_faces(use->Tag(), &fl) == 0 && fl)
        {
            int fc = 0; UF_MODL_ask_list_count(fl, &fc);
            for (int i = 0; i < fc; ++i)
            {
                tag_t ft = NULL_TAG;
                if (UF_MODL_ask_list_item(fl, i, &ft) != 0 || ft == NULL_TAG) continue;
                PlanarFace pf; pf.faceTag = ft;
                if (IsPlanarByNormal(ft, pf.normal)) out.push_back(pf);  // keep only planar faces, skip curved
            }
            UF_MODL_delete_list(&fl);
        }
    }
}

std::vector<PlanarFace> planesA, planesB;
CollectPlanarFaces(compA, planesA);
CollectPlanarFaces(compB, planesB);
std::cout << "Planar faces: A=" << planesA.size() << "  B=" << planesB.size() << std::endl;
```

---

## 4. Find all "mating face pairs" of the two parts (normals parallel/opposite AND distance ~ 0)

> **MANDATORY**: a pair of planar faces `(fa, fb)` is a **mating pair** if and only if **both** hold:
> 1. **Normals parallel or opposite**: `|dot(nA, nB)| >= 0.999` (0 or 180 degrees, same order of magnitude as the section 3 consistency threshold);
> 2. **Minimum face-to-face distance ~ 0**: `UF_MODL_ask_minimum_dist_3(2, fa, fb, ...)` gives `d <= 1e-3` (mating/contact).
> Neither may be omitted; traverse **all** A x B combinations and collect **all** pairs.

```cpp
#include <limits>

struct FacePair { tag_t fa = NULL_TAG; tag_t fb = NULL_TAG; };

std::vector<FacePair> pairs;
for (const PlanarFace& a : planesA)
    for (const PlanarFace& b : planesB)
    {
        if (std::fabs(Dot(a.normal, b.normal)) < 0.999) continue;   // (1) normals must be parallel/opposite

        double d = 0, p1[3] = {0}, p2[3] = {0}, g[3] = {0,0,0}, acc = 0;
        if (UF_MODL_ask_minimum_dist_3(2, a.faceTag, b.faceTag, 0, g, 0, g, &d, p1, p2, &acc) != 0)
            continue;
        if (d > 1e-3) continue;                                     // (2) face-to-face distance must be ~ 0 (mating)

        FacePair fp; fp.fa = a.faceTag; fp.fb = b.faceTag;
        pairs.push_back(fp);
    }
std::cout << "Mating face pairs: " << pairs.size() << std::endl;
```

---

## 5. For each mating pair: filter target edges -> pairwise minimum distance -> ignore intersections -> output all < 4mm regions

> **MANDATORY**: for each mating pair, take **fa's target edges** x **fb's target edges**, all combinations,
> compute the "edge <-> edge" minimum distance with `UF_MODL_ask_minimum_dist_3(2, edgeA, edgeB, ...)`, and judge each one:
> 1. **Target-edge filter (mandatory, fixed, no deviation; omitting it is an implementation error)**: the edge must be the **intersection of one planar face and one non-planar face** (`UF_MODL_ask_edge_faces` gets the two adjacent faces of the edge, judge planarity with the section 3 unique-normal test, keep only if `planarCount==1`, exactly one planar and one non-planar); **edges between two planar faces and edges between two non-planar faces are passed outright**.
> 2. **Intersection ignore**: if the two nearest points `p1/p2` of a combination have **identical coordinates** (`|p1-p2| <= 1e-6`), the edges **intersect**: **ignore that combination** (not counted as a failure).
> 3. **Output all failing regions**: every combination with `d < 4mm` is a failing region; **output each one** as `FAIL  minDist=<value> mm` with the two nearest points `p1` (on edgeA) / `p2` (on edgeB); combinations with `d > 4mm` pass and are not listed individually.

```cpp
#include <uf_modl.h>
#include <uf.h>
#include <limits>

const double kClearance = 4.0;   // threshold: shortest edge-to-edge distance must be > 4mm

// Get all boundary edge tags of a face
static std::vector<tag_t> FaceEdges(tag_t face)
{
    std::vector<tag_t> edges;
    uf_list_p_t el = nullptr;
    if (UF_MODL_ask_face_edges(face, &el) == 0 && el)
    {
        int ec = 0; UF_MODL_ask_list_count(el, &ec);
        for (int i = 0; i < ec; ++i)
        {
            tag_t et = NULL_TAG;
            if (UF_MODL_ask_list_item(el, i, &et) == 0 && et != NULL_TAG) edges.push_back(et);
        }
        UF_MODL_delete_list(&el);
    }
    return edges;
}

// Target-edge filter: intersection of one planar + one non-planar face -> true (keep); intersection of two planar (or other) faces -> false (pass)
static bool EdgeIsPlaneNonPlaneIntersection(tag_t edge)
{
    int numFaces = 0;
    tag_t* faces = nullptr;
    if (UF_MODL_ask_edge_faces(edge, &numFaces, &faces) != 0 || faces == nullptr) return false;
    int total = 0, planarCount = 0;
    for (int i = 0; i < numFaces; ++i)
    {
        if (faces[i] == NULL_TAG) continue;
        ++total;
        double rep[3];
        if (IsPlanarByNormal(faces[i], rep)) ++planarCount;   // reuse the section 3 "unique normal" planarity test
    }
    UF_free(faces);
    if (total < 2) return false;                              // not an edge shared by two faces: not a face-face intersection, pass
    return (planarCount == 1);                                // exactly one planar + one non-planar = target edge
}

// Keep only the target edges ("planar + non-planar intersection")
static std::vector<tag_t> TargetFaceEdges(tag_t face)
{
    std::vector<tag_t> out;
    for (tag_t e : FaceEdges(face))
        if (EdgeIsPlaneNonPlaneIntersection(e)) out.push_back(e);
    return out;
}

int pairIdx = 0, failCount = 0;
for (const FacePair& fp : pairs)
{
    ++pairIdx;
    std::vector<tag_t> edgesA = TargetFaceEdges(fp.fa);       // keep only "planar + non-planar intersection" edges
    std::vector<tag_t> edgesB = TargetFaceEdges(fp.fb);

    for (tag_t ea : edgesA)
        for (tag_t eb : edgesB)
        {
            double d = 0, p1[3] = {0}, p2[3] = {0}, g[3] = {0,0,0}, acc = 0;
            if (UF_MODL_ask_minimum_dist_3(2, ea, eb, 0, g, 0, g, &d, p1, p2, &acc) != 0) continue;

            // (2) Intersection ignore: identical nearest-point coordinates -> edges intersect, ignore this region
            double dp[3] = { p1[0]-p2[0], p1[1]-p2[1], p1[2]-p2[2] };
            if (std::sqrt(Dot(dp, dp)) <= 1e-6) continue;

            if (d > kClearance) continue;                    // > 4mm passes, not listed individually

            // (3) < 4mm fails: output every failing region one by one
            ++failCount;
            std::cout << "Pair #" << pairIdx << "  FAIL  minDist=" << d << " mm" << std::endl;
            std::cout << "    P1(on edge A) = (" << p1[0] << ", " << p1[1] << ", " << p1[2] << ")" << std::endl;
            std::cout << "    P2(on edge B) = (" << p2[0] << ", " << p2[1] << ", " << p2[2] << ")" << std::endl;
        }
}

if (failCount == 0)
    std::cout << "ALL PASS: no region violates the 4mm clearance." << std::endl;
else
    std::cout << failCount << " region(s) violate the 4mm clearance." << std::endl;
```

> Boundary handling: `d == 4.0` exactly is, per the requirement, "not > 4mm"; the default code judges PASS with `> kClearance`, so `4.0` is judged FAIL.
> **Note**: a tiny `d` with `p1~p2` means the edges **intersect** (already ignored by (2)) and is not a failure; FAIL is output only when `p1!=p2` and `d<4mm`.

---

## 6. Fit into the batch DLL entry `NxMain` (see doc 00)

```cpp
// DLL entry: argv[0] = DLL path, argv[1] = first user argument
extern "C" __declspec(dllexport) int NxMain(int argc, char* argv[])
{
    std::string assemblyPath = (argc >= 2) ? argv[1] : "C:\\path\\to\\assembly.prt";
    std::string partNoA      = (argc >= 3) ? argv[2] : "V2S9-R21124-A_14";
    std::string partNoB      = (argc >= 4) ? argv[3] : "V2S9-R21125-B_02";

    if (UF_initialize() != 0)
    {
        std::cerr << "UF_initialize failed." << std::endl;
        std::cerr.flush();
        return 1;
    }
    int rc = 0;
    try
    {
        // section 2 open the assembly + locate the two leaf parts -> section 3 extract planar faces -> section 4 find mating pairs -> section 5 edge clearance vs 4mm
        // ... (concatenate the sections above in order) ...
    }
    catch (const NXException& ex) { std::cerr << "NX exception: " << ex.Message() << std::endl; rc = 1; }
    catch (const std::exception& ex) { std::cerr << "Error: " << ex.what() << std::endl; rc = 1; }
    UF_terminate();
    std::cout.flush();
    std::cerr.flush();
    return rc;
}
```

> **Linking**: the assembly classes `NXOpen::Assemblies::*` require linking `libnxopencpp.lib libufun.lib libnxopencpp_assemblies.lib` (see doc 00); `nxrun.ps1 build` does this automatically;
> **Running**: `nxrun.ps1 run <X.dll> <assemblyPath> <partNoA> <partNoB>` -- the script prepends `%UGII_ROOT_DIR%` (NXBIN) to `PATH` and loads the DLL (see doc 00).

---

## 7. API quick reference

| Function / member | Purpose |
| --- | --- |
| `StripVersion(partNo)` | Strip the trailing `_<digits>` version suffix (fixed, section 1) |
| `part->ComponentAssembly()->RootComponent()` | Assembly root component |
| `comp->GetChildren()` empty | "A part with no children of its own" = leaf |
| `UF_ATTR_*` iteration | Read the leaf part's Item ID (most stable in batch, see 10/11) |
| `comp->FindOccurrence(body)` | Prototype body -> assembly-space occurrence body |
| `UF_MODL_ask_body_faces(body,&list)` | All faces of a body |
| `UF_MODL_ask_face_uv_minmax(face, uv[4])` | UV parameter range of a face `{umin,umax,vmin,vmax}` |
| `UF_MODL_ask_face_props(face,parm,pt,u1,v1,u2,v2,norm,radii)` | Point / tangents / **unit normal** / curvature radii at a UV |
| `UF_MODL_ask_face_type(face,&type)` | Face type (`22` = plane, quick bypass) |
| `UF_MODL_ask_face_edges(face,&list)` | Boundary edges of a face |
| `UF_MODL_ask_edge_faces(edge,&num,&faces)` | Adjacent faces of an edge (judge "planar + non-planar" intersection; two-plane intersections are passed; `UF_free(faces)` after use) |
| `UF_MODL_ask_minimum_dist_3(2,t1,t2,0,g,0,g,&d,p1,p2,&acc)` | Minimum distance of two objects + nearest points on both sides (`p1~p2` means intersection, ignore) |
| `UF_MODL_ask_list_count/item` / `UF_MODL_delete_list` | Traverse / free UF lists |
| `kClearance = 4.0` | PASS threshold: the shortest edge distance must be `> 4mm` |

## Gotchas

- **Planarity uses the unique normal**: a single-point normal cannot distinguish planar from near-planar spline faces; you must sample multiple points (corners + center), and only `|dot| >= 0.9995` counts as planar. UV sampling avoids degenerate boundaries (use 0.05/0.95 rather than 0/1).
- **Both pairing conditions are required**: normals parallel/opposite **and** face distance ~ 0. Checking only normals mis-pairs "parallel but not mating" faces; checking only distance mis-pairs "touching but not parallel" faces.
- **Edges of mating faces may be at distance 0**: if the two sheet-metal parts have aligned edges, the edge distance can be < 4mm or even 0. But **a distance of 0 may mean the two edges intersect** -- if the `p1` and `p2` returned by `UF_MODL_ask_minimum_dist_3` have **identical coordinates**, the edges intersect and that region should be **ignored**; only `p1!=p2` with `d<4mm` is a real failure.
- **Target edges are "planar + non-planar" intersections**: the boundaries of sheet-metal flanges/fillets are the clearance edges to measure; **intersections of two planar faces** (e.g. a sharp edge between two flats) are not targets -- use `UF_MODL_ask_edge_faces` to get the two adjacent faces, and keep an edge only if `planarCount==1` (one planar + one non-planar).
- **Output all failing regions**: do not report only the global minimum; every non-intersecting edge combination of A x B with `d<4mm` must be output one by one, to locate all risk positions.
- **Occurrence geometry**: both parts use `FindOccurrence` to map into assembly space, guaranteeing distance measurement in one coordinate system with no manual transformation.
- **Resource cleanup**: free `UF_MODL_*` lists with `UF_MODL_delete_list(&list)`; `delete` the `PartLoadStatus*` after use.

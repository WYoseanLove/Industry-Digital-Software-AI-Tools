# 11 Â· Weld-Point Part LFO, LFO_half & LWE_half Extraction (Open C)

## Description
End-to-end remote batch skill: **inputs** are a weld point (name, position coordinates, normal IJK), the matching **sheet-metal part number**, and the **assembly / single-part `.prt` path**.
The program **opens the assembly remotely**, walks the structure tree recursively, reads the **Item ID** at each **leaf part with no children**, and best-matches it against the given sheet-metal part number
(e.g. part number `V2S9-R21124-A_14` and Item ID `V2S9-R21124-A` is the best match). On a hit **NX activates that part** (`SetWorkComponent`);
then a **10 mm probe line** is built from the weld "position + normal" (midpoint = coordinate point, direction = IJK). On the activated part:
1) Extract all feature faces and use a ray to find the **two faces whose intersection distance with the probe line is 0** (LFO uses only one of them);
2) For the edges of the chosen face, compute the minimum "edge <-> probe line" distance; the smallest value = **LFO_half (LFO/2)**;
3) Build a section plane through the probe line, rotate it around the line every 1 degree, intersect with **the same chosen face**, and take the **shortest intersection-curve length = LFO**;
4) For the faces **other than the two intersecting faces**, first exclude every face that **intersects BOTH** of the two intersecting faces (shares an edge with both, or face-to-face minimum distance < 1e-3), and also exclude the **opposite side of the same sheet** (shares an edge with one intersecting face and sits ~one measured thickness from the other); take each remaining face's minimum distance to the probe line; the smallest over all faces = **LWE_half**.
**LFO / LFO_half use only one intersecting face; LWE_half uses both intersecting faces for exclusion.** Snippets come from docs 00~10 of this library.

> **MANDATORY measurement constraints (fixed, no deviation) -- generated code must satisfy every row; changing any one is an implementation error:**
>
> | # | Constraint | Hard requirement | Forbidden |
> | --- | --- | --- | --- |
> | Locate | Traversal | **Starting at `RootComponent`, recurse down the whole structure tree with `GetChildren()`** | Looking only at top/middle levels |
> | Locate | Match level | **Read and match only at leaf parts (empty `GetChildren()`)** | Matching on intermediate assembly nodes |
> | Locate | Match basis | **The leaf part's Item ID user attribute** (read via `UF_ATTR`) best-matched against the part number | **Never** locate by `DisplayName` / tree node name / file name |
> | Locate | On hit | **Take the leaf with the highest score and >= threshold (0.85) -> `SetWorkComponent` to activate**; below threshold = "not found" | Falling back to a non-leaf node |
> | Probe line | Length | **Total length = 10 mm** (`LINE_LEN = 10.0`) | 1000 mm or any other value |
> | Probe line | Midpoint | **Midpoint = weld coordinate** `weldPos` (`weldPos +/- dir*5mm`) | Treating the weld point as an endpoint |
> | Probe line | Direction | **= weld normal IJK, normalized**: `normalize(weldIjk)` | Using an unnormalized vector |
> | LFO | Method | **Sweep a section around the probe line every 1 degree, intersect with the chosen face, take the shortest intersection length** | Distance between two ray hits (plate thickness), edge distance x 2, etc. |
> | LFO_half | Method | **Minimum of the distances from each edge of the chosen face to the probe line** (measured independently) | Back-computing from `LFO*0.5`, plate thickness/2 |
> | LWE_half | Method | **(1) First exclude `face1`/`face2` -- the two faces whose minimum distance to the probe segment is 0; (2) then exclude every face that **intersects BOTH** `face1` **AND** `face2` -- "intersect" = shares an edge tag (topological adjacency) or face-to-face minimum distance < 1e-3; a face intersecting only one of them is a valid candidate; (3) additionally exclude the opposite side of the same sheet (shares an edge with one intersecting face and sits ~one measured thickness from the other); (4) take each remaining face's minimum distance to the probe segment; the smallest = LWE_half** | Measuring without excluding intersecting/adjacent faces, or any other shortcut |

## Keywords
LFO, LFO_half, LFO/2, LWE_half, LWE/2, weld point, sheet metal, Item ID, part number matching, SetWorkComponent, activate part,
UF_MODL_trace_a_ray, hit_face, UF_MODL_ask_face_edges, UF_MODL_ask_minimum_dist_3, adjacent face test, exclude adjacent faces,
UF_MODL_create_plane, RotateAroundAxis, UF_MODL_intersect_objects, UF_CURVE_ask_arc_length,
ComponentAssembly, RootComponent, GetChildren, Prototype, FindOccurrence, UF_ATTR, probe line, section plane, intersection curve

---

## 0. Input / output contract

| Item | Description |
| --- | --- |
| Input Â· weld point | `weldName`, `weldPos[3]` (assembly-space coordinates), `weldIjk[3]` (normal, not necessarily normalized) |
| Input Â· part number | `targetPartNo` (sheet-metal part number, may carry a `_NN` suffix, e.g. `V2S9-R21124-A_14`) |
| Input Â· path | `assemblyPath` (assembly `.prt`; a single-part `.prt` is also supported) |
| Output | Weld name, position, IJK, matched sheet-metal part number (Item ID), NX open path, **LFO**, **LFO_half**, **LWE_half** |

> Weld coordinates/normals are in assembly space (e.g. exported from Vismockup). So measure on the **occurrence geometry** of the activated component (assembly space); the coordinates then agree and no manual transform is needed.

---

## 1. Open the assembly / single part and load all components (see docs 00 / 07 / 09)

```cpp
#include <NXOpen/Session.hxx>
#include <NXOpen/Part.hxx>
#include <NXOpen/PartCollection.hxx>
#include <NXOpen/PartLoadStatus.hxx>
#include <NXOpen/LoadOptions.hxx>
#include <NXOpen/Assemblies_ComponentAssembly.hxx>
#include <NXOpen/Assemblies_Component.hxx>

Session* theSession = Session::GetSession();

// For an assembly, first request "load all child components"; otherwise a leaf part's Prototype()/attributes are unavailable
theSession->Parts()->LoadOptions()->SetComponentsToLoad(NXOpen::LoadOptions::LoadComponentsAll);

PartLoadStatus* ls = nullptr;
Part* topPart = theSession->Parts()->OpenDisplay(assemblyPath.c_str(), &ls);
if (ls) { delete ls; ls = nullptr; }
if (topPart == nullptr) throw NXException::Create("Cannot open the part.");

NXOpen::Assemblies::ComponentAssembly* ca = topPart->ComponentAssembly();
NXOpen::Assemblies::Component* root = ca ? ca->RootComponent() : nullptr;
// root == nullptr -> a single-part .prt was opened (handled as the single-part branch in section 2)
```

---

## 2. Walk the structure tree: print leaf Item IDs, best-match and activate the part (see docs 07 / 10 / 08)

> **MANDATORY (no deviation) -- the part may only be located by the "leaf part's Item ID":**
> 1. **The whole NX structure tree must be walked recursively** (from `RootComponent`, drill down with `GetChildren()`); never only the top/middle levels.
> 2. **Read and match the Item ID only at "leaf parts with no children (empty `GetChildren()`)"**; skip every intermediate assembly node.
> 3. **The match basis must be the leaf part's Item ID user attribute** (read via `UF_ATTR`); **never** substitute the component `DisplayName` / tree node name / file name.
> 4. Score every leaf's Item ID, take the highest-scoring leaf that reaches the threshold as the target; below threshold = "not found", **never** fall back to a non-leaf node.
> In short: "find part = reach leaf -> take the leaf's Item ID -> match"; none of the three may be omitted.

### 2.1 Read a part's Item ID (`UF_ATTR`, the most reliable in batch mode)

```cpp
#include <uf.h>
#include <uf_attr.h>
#include <cctype>

static std::string ToLower(std::string s)
{
    for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return s;
}

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
```

### 2.2 Item ID <-> part number match scoring (best match after stripping the suffix)

```cpp
// Returns a match score in [0,1]; example: itemId="V2S9-R21124-A" vs target="V2S9-R21124-A_14" -> 0.95 (best)
static double ItemIdMatchScore(const std::string& itemId, const std::string& target)
{
    std::string a = ToLower(itemId), b = ToLower(target);
    if (a.empty()) return 0.0;
    if (a == b) return 1.0;                                   // exact equality

    std::string bBase = b;                                    // strip the trailing "_NN" suffix of the part number and compare again
    size_t us = bBase.find_last_of('_');
    if (us != std::string::npos) bBase = bBase.substr(0, us);
    if (a == bBase) return 0.95;                              // item id == suffix-stripped part number -> best match

    if (b.rfind(a, 0) == 0) return 0.90;                      // item id is a prefix of the part number
    if (b.find(a) != std::string::npos || a.find(b) != std::string::npos) return 0.85; // substring of each other
    return 0.0;
}
```

### 2.3 Recursive walk: read Item ID only at **leaf components**, record the best match

```cpp
struct BestMatch
{
    NXOpen::Assemblies::Component* comp = nullptr;
    std::string itemId;
    double score = 0.0;
};

static void FindBestLeafByItemId(
    NXOpen::Assemblies::Component* comp, const std::string& target, BestMatch& best)
{
    if (comp == nullptr) return;

    std::vector<NXOpen::Assemblies::Component*> children = comp->GetChildren();
    if (children.empty())                                     // mandatory: only leaf parts with no children read the Item ID and match
    {
        NXOpen::Part* proto = dynamic_cast<NXOpen::Part*>(comp->Prototype());
        std::string itemId = GetItemId(proto);               // match basis = the leaf's Item ID, not DisplayName
        std::cout << "  leaf: " << comp->DisplayName().GetText()
                  << "  ItemID=" << itemId << std::endl;       // as required: leaves print their item id
        double sc = ItemIdMatchScore(itemId, target);
        if (sc > best.score) { best.score = sc; best.comp = comp; best.itemId = itemId; }
        return;                                                // leaves are not drilled further
    }
    for (NXOpen::Assemblies::Component* c : children)
        FindBestLeafByItemId(c, target, best);                // must recurse down to the leaves
}
```

### 2.4 Activate the best-matching part (`SetWorkComponent`)

```cpp
BestMatch best;
if (root != nullptr) FindBestLeafByItemId(root, targetPartNo, best);

NXOpen::Assemblies::Component* activeComp = nullptr;
NXOpen::Part* activePart = nullptr;

if (best.comp != nullptr && best.score >= 0.85)               // hit: activate the part
{
    PartLoadStatus* ws = nullptr;
    theSession->Parts()->SetWorkComponent(best.comp, &ws);    // NX activation (enter the component)
    if (ws) { delete ws; ws = nullptr; }
    activeComp = best.comp;
    activePart = dynamic_cast<NXOpen::Part*>(best.comp->Prototype());
    std::cout << "Activated: " << best.comp->DisplayName().GetText()
              << "  (ItemID=" << best.itemId << ", score=" << best.score << ")" << std::endl;
}
else if (root == nullptr)                                     // a single-part .prt was opened
{
    activePart = topPart;
    std::cout << "Single part mode. ItemID=" << GetItemId(topPart) << std::endl;
}
else
{
    throw NXException::Create("No leaf part matching the part number was found in the structure tree.");
}
```

---

## 3. Build the 10 mm probe line from the weld "position + normal" (see doc 01)

> **MANDATORY (no deviation) -- the three elements of the probe line are fixed as follows:**
> 1. **Fixed length = 10 mm** (`const double kLineLength = 10.0;`). **Never** change it to 1000 mm or any other value; a long line crosses the part, pulls every "minimum distance to the probe line" to a false 0, and makes the ray pick the wrong intersecting faces.
> 2. **Midpoint = weld coordinate**: `segStart = weldPos - dir*5mm`, `segEnd = weldPos + dir*5mm`, so the midpoint is always `weldPos`. **Never** treat the weld point as an endpoint.
> 3. **Direction = weld normal IJK, normalized** (`dir = normalize(weldIjk)`). The direction must be normalized before use; **never** use an unnormalized vector.
> That is: `length = 10 mm, midpoint = weld point, direction = normal IJK` are hard constraints; changing any one is an implementation error.

```cpp
#include <uf_curve.h>
#include <cmath>

static double Dot(const double a[3], const double b[3]) { return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]; }
static void Cross(const double a[3], const double b[3], double o[3])
{ o[0]=a[1]*b[2]-a[2]*b[1]; o[1]=a[2]*b[0]-a[0]*b[2]; o[2]=a[0]*b[1]-a[1]*b[0]; }
static void Normalize(double a[3]) { double n=std::sqrt(Dot(a,a)); if (n>1e-12){a[0]/=n;a[1]/=n;a[2]/=n;} }
static void RotateAroundAxis(const double v[3], const double k[3], double ang, double o[3])
{
    double c=std::cos(ang), s=std::sin(ang), kxv[3]; Cross(k,v,kxv); double kd=Dot(k,v);
    for (int i=0;i<3;++i) o[i]=v[i]*c+kxv[i]*s+k[i]*kd*(1.0-c);
}

const double kLineLength = 10.0;                              // total probe line length 10 mm
double dir[3] = { weldIjk[0], weldIjk[1], weldIjk[2] };
Normalize(dir);
double half = kLineLength * 0.5;

UF_CURVE_line_t lineData;
double segStart[3], segEnd[3];
for (int i = 0; i < 3; ++i)
{
    segStart[i] = weldPos[i] - dir[i] * half;                 // midpoint = weld coordinate
    segEnd[i]   = weldPos[i] + dir[i] * half;
    lineData.start_point[i] = segStart[i];
    lineData.end_point[i]   = segEnd[i];
}
tag_t lineTag = NULL_TAG;
if (UF_CURVE_create_line(&lineData, &lineTag) != 0 || lineTag == NULL_TAG)
    throw NXException::Create("Failed to create the probe line.");
```

---

## 4. Extract all feature faces of the activated part; find the two intersecting faces with a ray (LFO picks one, LWE_half uses both) (see docs 02 / 03 / 08)

Use the **occurrence (assembly-space)** geometry of the activated part, in the same coordinate system as the weld coordinates.

```cpp
#include <uf_modl.h>
#include <uf_mtx.h>
#include <NXOpen/Body.hxx>
#include <NXOpen/BodyCollection.hxx>

// Collect the occurrence solids of the active component and all their faces (assembly space)
static void CollectActiveFaces(
    NXOpen::Assemblies::Component* comp, NXOpen::Part* proto,
    std::vector<tag_t>& bodyTags, std::vector<tag_t>& faceTags)
{
    if (proto == nullptr) return;
    BodyCollection* bodies = proto->Bodies();
    for (BodyCollection::iterator it = bodies->begin(); it != bodies->end(); ++it)
    {
        NXOpen::Body* pb = *it;
        if (pb == nullptr || !pb->IsSolidBody()) continue;

        NXOpen::Body* use = pb;
        if (comp != nullptr)                                  // map to the assembly-space occurrence
        {
            NXOpen::Body* occ = dynamic_cast<NXOpen::Body*>(comp->FindOccurrence(pb));
            if (occ) use = occ;
        }
        bodyTags.push_back(use->Tag());

        uf_list_p_t fl = nullptr;
        if (UF_MODL_ask_body_faces(use->Tag(), &fl) == 0 && fl)
        {
            int fc = 0; UF_MODL_ask_list_count(fl, &fc);
            for (int i = 0; i < fc; ++i)
            {
                tag_t ft = NULL_TAG;
                if (UF_MODL_ask_list_item(fl, i, &ft) == 0 && ft != NULL_TAG) faceTags.push_back(ft);
            }
            UF_MODL_delete_list(&fl);
        }
    }
}

std::vector<tag_t> bodyTags, faceTags;
CollectActiveFaces(activeComp, activePart, bodyTags, faceTags);

// Ray intersection along the probe line direction: starting from one end of the line, the first two distinct hit faces = the two faces passing through the sheet metal
double xform[16]; UF_MTX4_identity(xform);
tag_t face1 = NULL_TAG, face2 = NULL_TAG;
int numHits = 0;
UF_MODL_ray_hit_point_info_p_t hits = nullptr;
if (UF_MODL_trace_a_ray((int)bodyTags.size(), bodyTags.data(),
                        segStart, dir, xform, 0, &numHits, &hits) == 0 && hits)
{
    for (int i = 0; i < numHits && (face1 == NULL_TAG || face2 == NULL_TAG); ++i)
    {
        tag_t f = hits[i].hit_face;
        if (f == NULL_TAG) continue;
        if (face1 == NULL_TAG)      face1 = f;                // first hit (entry face, closest to the weld point)
        else if (f != face1)        face2 = f;               // second hit (exit face)
    }
    UF_free(hits);
}
if (face1 == NULL_TAG)
    throw NXException::Create("The probe line does not intersect this part (check that the coordinates/normal are in assembly space).");

// Key: LFO / LFO_half use only one face (chosenFace); but keep both face1/face2 for LWE_half in section 7 to exclude adjacent faces
tag_t chosenFace = face1;
std::cout << "Intersect faces: " << (face1?1:0) + (face2?1:0)
          << "  chosen=" << chosenFace << std::endl;
```

> Alternative face finding (no ray): iterate `faceTags` and use `UF_MODL_ask_minimum_dist_3(2, lineTag, face, ...)` to take the faces with `d < 1e-4`, i.e. the faces at "intersection distance 0"; again **keep only one**.

---

## 5. LFO_half (LFO/2) = minimum distance from the chosen face's edges to the probe line (see docs 03 / 05)

> **MANDATORY (no deviation) -- LFO_half (= LFO/2) may only be measured this way:**
> 1. Take all edges (`UF_MODL_ask_face_edges`) of the **chosen face `chosenFace` (the single intersecting face)**.
> 2. For each edge use `UF_MODL_ask_minimum_dist_3(2, lineTag, edge, ...)` to get the "edge <-> probe line" minimum distance; **the smallest over all edges = LFO_half**.
> 3. **Never** back-compute LFO_half with `LFO * 0.5`, the distance between two ray hits, plate thickness, or any other substitute; LFO_half must be measured independently in this section.

```cpp
#include <limits>

double lfoHalf = std::numeric_limits<double>::max();
uf_list_p_t edgeList = nullptr;
if (UF_MODL_ask_face_edges(chosenFace, &edgeList) == 0 && edgeList)  // take the edges of "this one" face only
{
    int ec = 0; UF_MODL_ask_list_count(edgeList, &ec);
    for (int i = 0; i < ec; ++i)
    {
        tag_t edgeTag = NULL_TAG;
        if (UF_MODL_ask_list_item(edgeList, i, &edgeTag) != 0 || edgeTag == NULL_TAG) continue;

        double d = 0, p1[3] = {0}, p2[3] = {0}, g[3] = {0,0,0}, acc = 0;
        if (UF_MODL_ask_minimum_dist_3(2, lineTag, edgeTag, 0, g, 0, g, &d, p1, p2, &acc) == 0)
            if (d < lfoHalf) lfoHalf = d;                    // smallest edge <-> probe line distance = LFO/2
    }
    UF_MODL_delete_list(&edgeList);
}
if (lfoHalf == std::numeric_limits<double>::max())
    throw NXException::Create("The chosen face has no usable edges; LFO_half computation failed.");
```

---

## 6. LFO = sweep a section around the probe line, intersect with **the same chosen face**, take the shortest intersection length (see docs 04 / 06)

> **MANDATORY (no deviation) -- LFO may only use the "sweep a section and take the shortest intersection" method:**
> 1. Around the probe line direction `dir`, build **every 1 degree** a **section plane through the weld point with normal perpendicular to the probe line** (`UF_MODL_create_plane` + `RotateAroundAxis`), covering 0 to 180 degrees.
> 2. Each plane intersects **only** the **chosen face `chosenFace` (the same intersecting face)** (`UF_MODL_intersect_objects`); sum the intersection arc lengths with `UF_CURVE_ask_arc_length`.
> 3. **The shortest intersection length over all angles = LFO**.
> 4. **Never** define LFO as "distance between two ray hits (plate thickness)", "edge distance x 2" or any other shortcut -- that measures plate thickness, not LFO.
>
> **The section-plane construction is fixed as follows (four steps, none may be omitted; do not replace with fixed XY/YZ planes or a bounding-box cut):**
> 1. **Seed vector `u`**: any unit vector perpendicular to `dir`. Fixed procedure: `ref=(1,0,0)`; if `|dot(ref,dir)|>0.9` use `ref=(0,1,0)` instead, then `u = normalize(cross(dir, ref))`. **This guarantees `u` is perpendicular to `dir`**.
> 2. **Rotate around the line**: for each angle `ang = deg*pi/180`, rotate `u` around `dir` with Rodrigues' formula to get the in-plane vector `inPlane = RotateAroundAxis(u, dir, ang)`.
> 3. **Plane normal**: `n = normalize(cross(dir, inPlane))`. **Because `n` is the cross product with `dir`, `n` is perpendicular to `dir`, i.e. the plane always contains the probe line (the whole line, not just one point).**
> 4. **Plane origin**: `org = weldPos` (the weld coordinate). So every section passes through the weld point and **contains the whole probe line**, just rotated by a different angle around it.
> Iterating `deg = 0..179` (1 degree step) sweeps a full half-plane turn around the probe line; the shortest intersection = LFO.

```cpp
#include <uf_curve.h>

double lfo = std::numeric_limits<double>::max();
int bestDeg = -1;

// Seed vector u perpendicular to dir
double ref[3] = { 1.0, 0.0, 0.0 };
if (std::fabs(Dot(ref, dir)) > 0.9) { ref[0]=0; ref[1]=1; ref[2]=0; }
double u[3]; Cross(dir, ref, u); Normalize(u);

const double kPi = 3.14159265358979;
for (int deg = 0; deg < 180; ++deg)                          // one section through the line per 1 degree (180 degrees covers all orientations)
{
    double ang = deg * kPi / 180.0;
    double inPlane[3]; RotateAroundAxis(u, dir, ang, inPlane);
    double n[3]; Cross(dir, inPlane, n); Normalize(n);       // plane normal perpendicular to the probe line

    tag_t planeTag = NULL_TAG;
    double org[3] = { weldPos[0], weldPos[1], weldPos[2] };  // plane passes through the weld point (i.e. the probe line)
    if (UF_MODL_create_plane(org, n, &planeTag) != 0 || planeTag == NULL_TAG) continue;

    int numInt = 0;
    UF_MODL_intersect_info_p_t* inter = nullptr;             // declare one level of pointer; &inter => double pointer
    if (UF_MODL_intersect_objects(chosenFace, planeTag, 0.001, &numInt, &inter) == 0 && inter) // intersect with this one face only
    {
        double totalLen = 0.0; bool hasCurve = false;
        for (int k = 0; k < numInt; ++k)
        {
            UF_MODL_intersect_info_p_t item = inter[k];         // the element itself is a pointer, use ->
            if (item != nullptr && item->intersect_type == UF_MODL_INTERSECT_CURVE)
            {
                tag_t c = item->intersect.curve.identifier;
                double len = 0.0;
                if (UF_CURVE_ask_arc_length(c, 0.0, 1.0, UF_MODL_MMETER, &len) == 0)
                { totalLen += len; hasCurve = true; }
                UF_OBJ_delete_object(c);
            }
        }
        for (int k = 0; k < numInt; ++k) UF_free(inter[k]);     // free each element first
        UF_free(inter);                                        // then free the pointer array

        if (hasCurve && totalLen > 1e-6 && totalLen < lfo)    // shortest intersection length = LFO
        { lfo = totalLen; bestDeg = deg; }
    }
    UF_OBJ_delete_object(planeTag);                           // delete each step to avoid piling up
}
if (bestDeg < 0)
    throw NXException::Create("The swept sections produced no valid intersection curve; LFO computation failed.");
```

---

## 7. LWE_half = minimum distance from the remaining faces to the probe line (see doc 05)

**Uses both intersecting faces** `face1` / `face2`: for every other face, first decide whether it **intersects BOTH** of them -- if so skip it; a face intersecting just one of them stays a candidate; otherwise compute its minimum distance to the probe line; the smallest over all faces is **LWE_half**.

> **MANDATORY (no deviation) -- LWE_half (= LWE/2) may only be measured this way:**
> 1. Iterate all faces `faceTags` of the activated part, **first excluding the two intersecting faces `face1`, `face2` themselves**.
> 2. Then exclude every face that **intersects BOTH** `face1` **AND** `face2`. "Intersect" = **shares an edge tag** (topological adjacency, `UF_MODL_ask_face_edges` on both faces and compare tag lists) **OR** face-to-face minimum distance `< kTol` with `kTol = 1e-3`. A face intersecting only one of them is a valid candidate (user-verified rule).
> 3. Additionally exclude the **opposite side of the same sheet**: shares an edge with one intersecting face **and** sits within `±0.05 mm` of one measured thickness from the other intersecting face. Without this the sheet's own back face wins and LWE_half collapses to the plate thickness.
> 4. For the **remaining faces** use `UF_MODL_ask_minimum_dist_3(2, lineTag, face, ...)` to get the "face <-> probe line" minimum distance; **the smallest over all remaining faces = LWE_half**.
> 5. **Never** skip the exclusions in steps 1-3 and measure directly, and **never** replace them with any other shortcut.

```cpp
// topological adjacency: two faces "share an edge" when their edge tag lists intersect
static void FaceEdges(tag_t face, std::vector<tag_t>& out)
{
    uf_list_p_t list = NULL;
    if (UF_MODL_ask_face_edges(face, &list) != 0 || list == NULL) return;
    int n = 0;
    UF_MODL_ask_list_count(list, &n);
    for (int i = 0; i < n; i++) { tag_t e = NULL_TAG; UF_MODL_ask_list_item(list, i, &e); out.push_back(e); }
    UF_MODL_delete_list(&list);
}
static bool SharesEdge(const std::vector<tag_t>& a, const std::vector<tag_t>& b)
{
    for (size_t i = 0; i < a.size(); i++)
        for (size_t j = 0; j < b.size(); j++)
            if (a[i] == b[j]) return true;
    return false;
}

const double kTol = 1e-3;                       // NOT 1e-6: JT-derived B-rep shared edges report ~1.6e-5
std::vector<tag_t> e1, e2;
FaceEdges(face1, e1);
if (face2 != NULL_TAG) FaceEdges(face2, e2);
const double thk = hasThkMeasured ? thkMeasured : 0.0;

double lweHalf = std::numeric_limits<double>::max();
double g0[3] = { 0, 0, 0 };
for (tag_t f : faceTags)
{
    if (f == face1 || f == face2) continue;                 // exclude the two intersecting faces themselves

    // cheap line-to-face distance first; the exclusion test only matters for faces closer than the current best
    double dLine = 0, q1[3] = {0}, q2[3] = {0}, acc2 = 0;
    if (UF_MODL_ask_minimum_dist_3(2, lineTag, f, 0, g0, 0, g0, &dLine, q1, q2, &acc2) != 0 || dLine >= lweHalf)
        continue;

    std::vector<tag_t> ef; FaceEdges(f, ef);
    bool sh1 = SharesEdge(ef, e1), sh2 = (face2 != NULL_TAG) && SharesEdge(ef, e2);
    double d1 = 0, d2 = 0, pa[3] = {0}, pb[3] = {0}, acc = 0;
    if (UF_MODL_ask_minimum_dist_3(2, f, face1, 0, g0, 0, g0, &d1, pa, pb, &acc) != 0) d1 = 1e9;
    if (face2 != NULL_TAG &&
        UF_MODL_ask_minimum_dist_3(2, f, face2, 0, g0, 0, g0, &d2, pa, pb, &acc) != 0) d2 = 1e9;
    bool inter1 = sh1 || d1 < kTol;
    bool inter2 = sh2 || d2 < kTol;
    if (inter1 && inter2) continue;                         // intersects BOTH -> excluded

    // opposite side of the same sheet: adjacent to one weld face, one thickness away from the other
    bool sameSheet = (sh2 && thk > 0.0 && std::fabs(d1 - thk) < 0.05) ||
                     (sh1 && thk > 0.0 && std::fabs(d2 - thk) < 0.05);
    if (sameSheet) continue;

    lweHalf = dLine;                                        // smallest distance over all faces = LWE_half
}
if (lweHalf == std::numeric_limits<double>::max())
    throw NXException::Create("No face satisfies the conditions; LWE_half computation failed.");

UF_OBJ_delete_object(lineTag);                                // clean up the probe line only after LWE_half is done
> Faces at **distance 0** from **both** intersecting faces (sharing an edge with both, e.g. the flange faces bridging the two sheets) would give a false minimum to the probe line, so they are excluded. A face touching only one of the two intersecting faces is a **valid candidate** (user-verified rule, 2026-10-21).
> The **opposite side of the same sheet** (shares an edge with one weld face and sits one measured thickness away from the other) is also excluded — otherwise LWE_half degenerates to the sheet thickness. **User confirmed 17.2 mm for `76401-01-R` / `N1WB-E02556-B_39` on 2026-10-21, so this is the final rule; do not revert.**

> Neighbor faces at **distance 0** from an intersecting face, i.e. "sharing an edge / touching" (such as the adjacent faces at a sheet-metal flange), lie against the intersecting faces and would give a false minimum to the probe line, so they are excluded first.
> LWE_half needs **both intersecting faces**, so do not discard `face2` in section 4.

---

## 8. Complete `NxMain` (chaining 1~7)

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

// Paste the helper functions of sections 2/3 here: ToLower, GetItemId, ItemIdMatchScore,
// BestMatch, FindBestLeafByItemId, Dot/Cross/Normalize/RotateAroundAxis,
// and CollectActiveFaces from section 4.

// DLL entry: argv[0] = DLL path, argv[1] = first user argument
extern "C" __declspec(dllexport) int NxMain(int argc, char* argv[])
{
    // Inputs (command line overrides, otherwise defaults)
    std::string assemblyPath = (argc >= 2) ? argv[1] : "C:\\path\\to\\assembly.prt";
    std::string targetPartNo = (argc >= 3) ? argv[2] : "V2S9-R21124-A_14";
    std::string weldName     = (argc >= 4) ? argv[3] : "WP_0001";
    double weldPos[3] = { 1000.0, 200.0, 500.0 };             // weld position (assembly space)
    double weldIjk[3] = { 0.0, 0.0, 1.0 };                    // weld normal IJK

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

        PartLoadStatus* ls = nullptr;
        Part* topPart = theSession->Parts()->OpenDisplay(assemblyPath.c_str(), &ls);
        if (ls) { delete ls; ls = nullptr; }
        if (topPart == nullptr) throw NXException::Create("Cannot open the part.");

        NXOpen::Assemblies::ComponentAssembly* ca = topPart->ComponentAssembly();
        NXOpen::Assemblies::Component* root = ca ? ca->RootComponent() : nullptr;

        // -- 2. Walk + match + activate --
        BestMatch best;
        if (root != nullptr) FindBestLeafByItemId(root, targetPartNo, best);

        NXOpen::Assemblies::Component* activeComp = nullptr;
        NXOpen::Part* activePart = nullptr;
        std::string matchedItemId;

        if (best.comp != nullptr && best.score >= 0.85)
        {
            PartLoadStatus* ws = nullptr;
            theSession->Parts()->SetWorkComponent(best.comp, &ws);
            if (ws) { delete ws; ws = nullptr; }
            activeComp = best.comp;
            activePart = dynamic_cast<NXOpen::Part*>(best.comp->Prototype());
            matchedItemId = best.itemId;
        }
        else if (root == nullptr)                              // single-part mode
        {
            activePart = topPart;
            matchedItemId = GetItemId(topPart);
        }
        else throw NXException::Create("No leaf part matching the part number was found.");

        // -- 3. Build the 10 mm probe line --
        double dir[3] = { weldIjk[0], weldIjk[1], weldIjk[2] }; Normalize(dir);
        double half = 5.0, segStart[3], segEnd[3];
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
            throw NXException::Create("Failed to create the probe line.");

        // -- 4. Extract all faces + ray finds the two intersecting faces -> pick one --
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
        if (face1 == NULL_TAG) throw NXException::Create("The probe line does not intersect the part.");
        tag_t chosenFace = face1;                              // use only one face

        // -- 5. LFO_half = minimum distance from the chosen face's edges to the line --
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
        if (lfoHalf == std::numeric_limits<double>::max())
            throw NXException::Create("LFO_half computation failed.");

        // -- 6. LFO = shortest intersection length of the swept section with the same face --
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

            int numInt = 0; UF_MODL_intersect_info_p_t* inter = nullptr;
            if (UF_MODL_intersect_objects(chosenFace, planeTag, 0.001, &numInt, &inter) == 0 && inter)
            {
                double tot = 0.0; bool has = false;
                for (int k = 0; k < numInt; ++k)
                {
                    UF_MODL_intersect_info_p_t item = inter[k];
                    if (item != nullptr && item->intersect_type == UF_MODL_INTERSECT_CURVE)
                    {
                        tag_t c = item->intersect.curve.identifier; double len = 0.0;
                        if (UF_CURVE_ask_arc_length(c, 0.0, 1.0, UF_MODL_MMETER, &len) == 0) { tot += len; has = true; }
                        UF_OBJ_delete_object(c);
                    }
                }
                for (int k = 0; k < numInt; ++k) UF_free(inter[k]);
                UF_free(inter);
                if (has && tot > 1e-6 && tot < lfo) { lfo = tot; bestDeg = deg; }
            }
            UF_OBJ_delete_object(planeTag);
        }
        if (bestDeg < 0) throw NXException::Create("LFO computation failed.");

        // -- 7. LWE_half = minimum distance from the remaining faces (adjacent faces excluded) to the probe line --
        // "Intersect" = share an edge tag (topological) or face-to-face minimum distance < kTol.
        const double kTol = 1e-3;
        std::vector<tag_t> e1, e2;
        FaceEdges(face1, e1);
        if (face2 != NULL_TAG) FaceEdges(face2, e2);
        const double thk = hasThkMeasured ? thkMeasured : 0.0;

        double lweHalf = std::numeric_limits<double>::max();
        double g0[3] = { 0, 0, 0 };
        for (tag_t f : faceTags)
        {
            if (f == face1 || f == face2) continue;
            std::vector<tag_t> ef; FaceEdges(f, ef);
            bool sh1 = SharesEdge(ef, e1), sh2 = (face2 != NULL_TAG) && SharesEdge(ef, e2);
            double d1 = 0, d2 = 0, pa[3]={0}, pb[3]={0}, acc=0;
            if (UF_MODL_ask_minimum_dist_3(2, f, face1, 0, g0, 0, g0, &d1, pa, pb, &acc) != 0) d1 = 1e9;
            if (face2 != NULL_TAG &&
                UF_MODL_ask_minimum_dist_3(2, f, face2, 0, g0, 0, g0, &d2, pa, pb, &acc) != 0) d2 = 1e9;
            bool inter1 = sh1 || d1 < kTol;
            bool inter2 = sh2 || d2 < kTol;
            if (inter1 && inter2) continue;   // intersects BOTH intersecting faces -> excluded
            bool sameSheet = (sh2 && thk > 0.0 && std::fabs(d1 - thk) < 0.05) ||
                             (sh1 && thk > 0.0 && std::fabs(d2 - thk) < 0.05);
            if (sameSheet) continue;          // opposite side of the same sheet -> excluded
            double dLine=0, q1[3]={0}, q2[3]={0}, acc2=0;
            if (UF_MODL_ask_minimum_dist_3(2, lineTag, f, 0, g0, 0, g0, &dLine, q1, q2, &acc2) == 0)
                if (dLine < lweHalf) lweHalf = dLine;
        }
        UF_OBJ_delete_object(lineTag);
        if (lweHalf == std::numeric_limits<double>::max())
            throw NXException::Create("LWE_half computation failed.");

        // -- Output --
        std::cout << "==== Weld Point LFO / LWE Result ====" << std::endl;
        std::cout << "Name       : " << weldName << std::endl;
        std::cout << "Position   : (" << weldPos[0] << ", " << weldPos[1] << ", " << weldPos[2] << ")" << std::endl;
        std::cout << "IJK        : (" << dir[0] << ", " << dir[1] << ", " << dir[2] << ")" << std::endl;
        std::cout << "PartNo(in) : " << targetPartNo << std::endl;
        std::cout << "ItemID     : " << matchedItemId << std::endl;
        std::cout << "NX Path    : " << assemblyPath << std::endl;
        std::cout << "LFO        : " << lfo << " mm (at " << bestDeg << " deg)" << std::endl;
        std::cout << "LFO_half   : " << lfoHalf << " mm" << std::endl;
        std::cout << "LWE_half   : " << lweHalf << " mm" << std::endl;
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

## 9. Output example

```
  leaf: V2S9-R21124-A_14  ItemID=V2S9-R21124-A
  ...
Activated: V2S9-R21124-A_14  (ItemID=V2S9-R21124-A, score=0.95)
Intersect faces: 2  chosen=<faceTag>
==== Weld Point LFO / LWE Result ====
Name       : WPWDPZ1B82620_01_R_00
Position   : (2999.643, 102.671, 478.413)
IJK        : (0, 0.913, 0.408)
PartNo(in) : V2S9-R21124-A_14
ItemID     : V2S9-R21124-A
NX Path    : C:\...\assembly.prt
LFO        : 12.83 mm (at 37 deg)
LFO_half   : 6.02 mm
LWE_half   : 8.44 mm
```

---

## 10. Gotchas

- **LWE_half needs both faces**: keep both `face1` / `face2` and exclude every face that **intersects BOTH** of them (shares an edge tag, or face-to-face minimum distance < 1e-3); a face intersecting only one of them is a valid candidate. Also exclude the **opposite side of the same sheet** (shares an edge with one intersecting face and sits ~one measured thickness from the other) -- otherwise the sheet's own back face wins and LWE_half collapses to the plate thickness. Dropping `face2` or excluding single-touch faces yields a falsely large value.
- **"Intersect" must be topological first**: JT-derived B-rep faces that really share an edge report a face-to-face minimum distance of ~1.6e-5 to 2.2e-5, so a `1e-6` distance test misses them. Compare **edge tag lists** (`UF_MODL_ask_face_edges` on both faces) and OR that with a relaxed `1e-3` distance test.
- **Adjacency threshold**: `kTol = 1e-3` for the geometric touch test; the topological edge-tag test is the reliable one.
- **Consistent coordinate system**: weld coordinates/normals are in assembly space; hence use `FindOccurrence` to get **occurrence faces** (assembly space). If you use the part's own geometry (the Prototype body) instead, apply the "component -> assembly" transform from doc 08, otherwise coordinates are misplaced and the ray misses.
- **All components must be loaded**: call `SetComponentsToLoad(LoadComponentsAll)` before opening the assembly, otherwise the leaf `Prototype()` / attributes are empty and the Item ID cannot be read.
- **Locate parts only by leaf Item ID (mandatory)**: recurse through the structure tree down to **leaf parts with no children** and match only the `UF_ATTR` **Item ID** at the leaves; never match by intermediate nodes, `DisplayName`, tree node names, or file names. Below threshold means "not found"; do not fall back to a non-leaf.
- **Unnormalized normal**: `Normalize` `weldIjk` first, otherwise the probe line length/direction is wrong.
- **Item ID attribute name varies**: different data sources may use `Item ID` / `ItemId` / `DB_PART_NO` etc.; `GetItemId` already does case-insensitive multi-keyword matching; add keywords if needed.
- **Clean up resources in pairs**: the loop's `planeTag`, intersection `curveTag`, `inter[k]` / `inter`, `hits`, and `lineTag` all need `UF_OBJ_delete_object` / `UF_free`, otherwise they pile up in the batch session.
- **Intersection tolerance**: pass `0.001` to `UF_MODL_intersect_objects`; relax it for very large faces / complex curvature. Use `UF_MODL_MMETER` for the arc-length unit.
- **Shortest-intersection test**: `totalLen > 1e-6` filters degenerate/empty intersections before taking the minimum; `bestDeg` records the shortest angle for review.

---

## 11. API quick reference

| Function / member | Purpose | Source |
| --- | --- | --- |
| `Parts()->LoadOptions()->SetComponentsToLoad(LoadComponentsAll)` | Load all child components before opening an assembly | 07/09 |
| `Parts()->OpenDisplay(path, &ls)` | Open the assembly / single-part `.prt` | 00 |
| `part->ComponentAssembly()->RootComponent()` | Assembly root component (null for a single part) | 07 |
| `component->GetChildren()` | Child components; empty = leaf part | 07 |
| `component->Prototype()` -> `Part*` | Component prototype part (read attributes/geometry) | 07 |
| `UF_ATTR_*` iterator | Read user attributes such as Item ID (most reliable in batch) | 10 |
| `Parts()->SetWorkComponent(comp, &ls)` | **Activate** the matched part (enter the component) | 08 |
| `component->FindOccurrence(protoBody)` | Prototype body -> assembly-space occurrence body | 08 |
| `UF_CURVE_create_line(&lineData, &lineTag)` | Build the probe line from midpoint + direction + 10 mm | 01 |
| `UF_MODL_ask_body_faces / _face_edges` | Get a body's faces / a face's edges | 03 |
| `UF_MODL_trace_a_ray(n, bodies, origin, dir, xform, 0, &numHits, &hits)` | Ray finds the intersecting faces (take two, pick one) | 02 |
| `UF_MODL_ask_minimum_dist_3(2, line, edge, ...)` | Edge <-> line minimum distance -> **LFO_half** | 05 |
| `UF_MODL_ask_minimum_dist_3(2, face, face1/face2, ...)` | Face <-> intersecting-face minimum distance; 0 = adjacent, skip | 05 |
| `UF_MODL_ask_minimum_dist_3(2, line, face, ...)` | Non-adjacent face <-> line minimum distance; global minimum = **LWE_half** | 05 |
| `UF_MODL_create_plane(origin, normal, &plane)` + `RotateAroundAxis` | Sweep section planes through the line | 04 |
| `UF_MODL_intersect_objects(face, plane, 0.001, &n, &inter)` | Section âˆ© chosen face -> curves (5th arg `..._p_t**`; declare `..._p_t* inter`, use `inter[k]->`, two-level `UF_free`: per element then the array) | 06 |
| `UF_CURVE_ask_arc_length(curve, 0,1, UF_MODL_MMETER, &len)` | Intersection length; shortest = **LFO** | 06 |
| `UF_OBJ_delete_object` / `UF_free` / `UF_MODL_delete_list` | Clean up temporary tags / pointers / lists | 00 |

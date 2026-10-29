# 05 · Minimum Distance & Measurement (Open C)

## Description
Measures the **minimum distance** between two objects (returning the closest point on each side) in a remote batch DLL, filters by "shortest edge distance / shortest face distance",
and reads mass properties (area / volume / mass / center of mass). The core is `UF_MODL_ask_minimum_dist_3`.

## Keywords
UF_MODL_ask_minimum_dist_3, minimum distance, closest point, min edge distance, LWE,
nearest face, UF_MODL_ask_mass_props_3d, area, volume, centroid, accuracy, guess

---

## 1. Minimum distance between two objects + closest points (core)

`UF_MODL_ask_minimum_dist_3` takes two object tags (point/line/edge/face/body) and outputs the minimum distance, the closest points on both objects,
and the achieved accuracy. **The first argument `2` is the calculation mode** (the verified value):

```cpp
#include <uf_modl.h>

double minDist = 0.0;
double pt1[3] = {0}, pt2[3] = {0};    // closest points on object1 / object2
double guess1[3] = {0,0,0}, guess2[3] = {0,0,0};
double accuracyOut = 0.0;

int st = UF_MODL_ask_minimum_dist_3(
    2,                 // mode
    object1Tag,        // first object (e.g. the probe line)
    object2Tag,        // second object (e.g. an edge / a face)
    0, guess1,         // no guess point for object1
    0, guess2,         // no guess point for object2
    &minDist,          // <O> minimum distance
    pt1, pt2,          // <O> closest points on both sides
    &accuracyOut);     // <O> achieved accuracy

if (st == 0)
    std::cout << "min dist = " << minDist << std::endl;
```

## 2. Shortest distance from a line to all edges of a face (LWE/2 mode)

Iterate the boundary edges of the face and take the smallest "line <-> edge" minimum distance:

```cpp
double minEdgeDist = std::numeric_limits<double>::max();
for (int i = 0; i < edgeCount; ++i)
{
    tag_t edgeTag = NULL_TAG;
    if (UF_MODL_ask_list_item(edgeList, i, &edgeTag) != 0 || edgeTag == NULL_TAG) continue;

    double d = 0, p1[3] = {0}, p2[3] = {0}, g[3] = {0,0,0}, acc = 0;
    if (UF_MODL_ask_minimum_dist_3(2, lineTag, edgeTag, 0, g, 0, g, &d, p1, p2, &acc) == 0)
    {
        if (d < minEdgeDist) minEdgeDist = d;
    }
}
if (minEdgeDist != std::numeric_limits<double>::max())
    std::cout << "min edge distance = " << minEdgeDist << std::endl;
```

## 3. Distance from a line to the "nearest non-adjacent face" (LFO/2 mode)

First exclude adjacent faces as in doc 03 section 5, then find the shortest "line <-> face" distance among the remaining faces:

```cpp
double minFaceDist = std::numeric_limits<double>::max();
tag_t nearestFace = NULL_TAG;
for (tag_t candidate : allFaces)
{
    if (isExcluded(candidate)) continue;      // skip the intersecting faces and their neighbors
    double d = 0, p1[3] = {0}, p2[3] = {0}, g[3] = {0,0,0}, acc = 0;
    if (UF_MODL_ask_minimum_dist_3(2, lineTag, candidate, 0, g, 0, g, &d, p1, p2, &acc) == 0)
    {
        if (d < minFaceDist) { minFaceDist = d; nearestFace = candidate; }
    }
}
if (nearestFace != NULL_TAG)
    std::cout << "nearest non-adjacent face distance = " << minFaceDist
              << " (face " << nearestFace << ")" << std::endl;
```

## 4. Point-to-point / point-to-face / face-to-face

The two objects of `UF_MODL_ask_minimum_dist_3` can be any combination with identical usage -- just pass the corresponding tags:

```cpp
// point to face: point object tag and face tag
UF_MODL_ask_minimum_dist_3(2, pointTag, faceTag, 0, g, 0, g, &d, p1, p2, &acc);
// face to face:
UF_MODL_ask_minimum_dist_3(2, faceTagA, faceTagB, 0, g, 0, g, &d, p1, p2, &acc);
```

## 5. Mass properties (area / volume / mass / center of mass)

```cpp
tag_t objs[1] = { bodyTag };            // or faceTag
double acc[11] = { 0.999 }, mp[47] = {0}, stats[13] = {0};
// Solid: type=1; sheet/face: type=2. units (verified): 1 = lb-in (length in inches), 4 = kg-m (length in meters)
// WARNING: NX geometry itself is in millimeters. The length unit of the center of mass mp[3..5] is decided by units (meters/inches);
// convert before using it as a geometric coordinate, and never mix it with mm.
if (UF_MODL_ask_mass_props_3d(objs, 1, 1, 4, 1.0, 1, acc, mp, stats) == 0)
{
    double area = mp[0], volume = mp[1], mass = mp[2];
    double com[3] = { mp[3], mp[4], mp[5] };
    double density = mp[46];
}
```

## 6. Output results

```cpp
std::cout << "LWE/2 = " << minEdgeDist << " mm\n";
std::cout << "LFO/2 = " << minFaceDist << " mm\n";
```

## 7. API quick reference

| Function / member | Purpose |
| --- | --- |
| `UF_MODL_ask_minimum_dist_3(2, t1, t2, 0, g1, 0, g2, &d, p1, p2, &acc)` | Minimum distance between two objects + closest points |
| `t1/t2` | Tags of point/line/edge/face/body (any combination) |
| `d` / `p1` / `p2` | Distance / closest point on object1 / closest point on object2 |
| `UF_MODL_ask_mass_props_3d(objs, n, type, units, 1.0, 1, acc, mp, st)` | Area / volume / mass / center of mass |
| `mp[0..2]` | Area / volume / mass |
| `mp[3..5]` / `mp[46]` | Center of mass / density |
| `std::numeric_limits<double>::max()` | Initial value for minimum search |
| `#include <uf_modl.h>` `<limits>` | Headers |

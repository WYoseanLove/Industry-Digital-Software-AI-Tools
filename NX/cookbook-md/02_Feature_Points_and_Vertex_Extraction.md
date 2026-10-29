# 02 · Extract Feature Points & Vertices (Open C)

## Description
Extracts **feature points** from part geometry in a remote batch DLL: face boundary vertices, circular-edge centers, face centroids,
and **ray casting** (`UF_MODL_trace_a_ray`) along a probe line to find the faces it crosses and locate the intersection points. Everything uses Open C (tag level).

## Keywords
UF_MODL_trace_a_ray, UF_MODL_ray_hit_point_info_p_t, hit_face, hit_point, UF_MTX4_identity,
UF_MODL_ask_face_edges, UF_MODL_ask_list_count, UF_MODL_ask_list_item, UF_MODL_delete_list,
UF_MODL_ask_mass_props_3d, centroid, vertex, circle center, UF_MODL_ask_body_faces

---

## 1. Find intersecting faces along a probe line with a ray (and get the hit points)

Given a line (origin + direction), intersect a set of bodies with a ray and return the hit faces and hit points:

```cpp
#include <uf_modl.h>
#include <uf_mtx.h>

// bodyTags: tag array of the target solids (see doc 03 for how to collect them)
double transform[16];
UF_MTX4_identity(transform);                     // identity transform (WCS)
double rayOrigin[3] = { start[0], start[1], start[2] };
double dir[3]       = { d[0], d[1], d[2] };      // normalized direction

int numHits = 0;
UF_MODL_ray_hit_point_info_p_t hitList = nullptr;
if (UF_MODL_trace_a_ray((int)bodyTags.size(), bodyTags.data(),
                        rayOrigin, dir, transform, 0, &numHits, &hitList) == 0)
{
    std::cout << "Ray hits: " << numHits << std::endl;
    for (int i = 0; i < numHits; ++i)
    {
        tag_t face = hitList[i].hit_face;                 // hit face
        double* hp = hitList[i].hit_point;                // hit point coordinates (usable)
        std::cout << "  hit face tag=" << face << std::endl;
    }
    if (hitList) UF_free(hitList);                        // release
}
```

> The first hit `hitList[0].hit_face` is normally the face nearest to the ray origin. The hit point is the intersection of the probe line and the face (one feature point).

## 2. Extract the boundary edges of a face and process them one by one (vertex candidates)

```cpp
uf_list_p_t edgeList = nullptr;
if (UF_MODL_ask_face_edges(faceTag, &edgeList) == 0 && edgeList != nullptr)
{
    int edgeCount = 0;
    UF_MODL_ask_list_count(edgeList, &edgeCount);
    for (int i = 0; i < edgeCount; ++i)
    {
        tag_t edgeTag = NULL_TAG;
        if (UF_MODL_ask_list_item(edgeList, i, &edgeTag) != 0 || edgeTag == NULL_TAG) continue;
        // For each edge, get its end vertices (below) or measure the minimum distance to the probe line (see doc 05)
    }
    UF_MODL_delete_list(&edgeList);
}
```

## 3. Get the two end vertices of an edge (convenient C++ way)

```cpp
#include <NXOpen/Edge.hxx>

NXOpen::Edge* edge = dynamic_cast<NXOpen::Edge*>(NXObjectManager::Get(edgeTag));
NXOpen::Point3d v1, v2;
edge->GetVertices(&v1, &v2);       // the two end vertices of the edge
std::cout << "V1=(" << v1.X << "," << v1.Y << "," << v1.Z << ")" << std::endl;
```

## 4. Extract a face's **centroid / area** (`UF_MODL_ask_mass_props_3d`)

```cpp
#include <uf_modl.h>

tag_t objs[1] = { faceTag };
double acc[11] = { 0.999 }, mp[47] = {0}, stats[13] = {0};
// type=2 means sheet/face; units=1 (mm) or 4 (kg-m)
if (UF_MODL_ask_mass_props_3d(objs, 1, 2, 1, 1.0, 1, acc, mp, stats) == 0)
{
    double area = mp[0];                                  // area
    double centroid[3] = { mp[3], mp[4], mp[5] };         // centroid
    std::cout << "Face area=" << area
              << " centroid=(" << centroid[0] << "," << centroid[1] << "," << centroid[2] << ")"
              << std::endl;
}
```

## 5. Extract the **center** of a circle/arc edge (check the type first)

```cpp
#include <NXOpen/Edge.hxx>

NXOpen::Edge* edge = dynamic_cast<NXOpen::Edge*>(NXObjectManager::Get(edgeTag));
if (edge && edge->SolidEdgeType() == NXOpen::Edge::EdgeTypeCircular)
{
    NXOpen::Point3d v1, v2;
    edge->GetVertices(&v1, &v2);
    // If the edge itself is a full circle (closed), the end points coincide; the center can be taken from the arc data:
    // or convert tag -> NXOpen::Arc and use arc->CenterPoint()/Radius()
}
```

## 6. Create a visible point from the extracted coordinates (write back to the part)

```cpp
double c[3] = { centroid[0], centroid[1], centroid[2] };
tag_t ptTag = NULL_TAG;
UF_CURVE_create_point(c, &ptTag);      // creates a point in the part for visualization / later reference
```

## 7. API quick reference

| Function / member | Purpose |
| --- | --- |
| `UF_MTX4_identity(double[16])` | Identity transform matrix (WCS for the ray) |
| `UF_MODL_trace_a_ray(n, bodies, origin, dir, xform, 0, &numHits, &hitList)` | Ray intersection to find faces |
| `hitList[i].hit_face` / `.hit_point` | Hit face / hit point |
| `UF_MODL_ask_face_edges(face, &list)` | Get the boundary edges of a face |
| `UF_MODL_ask_list_count/item(list, ...)` | Iterate a UF list |
| `UF_MODL_delete_list(&list)` | Release the list |
| `UF_MODL_ask_mass_props_3d(objs,n,type,units,1.0,1,acc,mp,st)` | Area / centroid / volume |
| `edge->GetVertices(&v1,&v2)` | Edge end vertices (C++) |
| `edge->SolidEdgeType()` | Detect circular edges |
| `UF_CURVE_create_point(c, &ptTag)` | Create a point (write back) |
| `UF_free(hitList)` | Release the hit array |

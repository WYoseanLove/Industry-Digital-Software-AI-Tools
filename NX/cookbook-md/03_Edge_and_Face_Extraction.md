# 03 · Extract Edges & Faces (Open C)

## Description
**Extracts edges and faces** in a remote batch DLL: collect all faces/edges of a solid, get the boundary edges of a face, decide on "adjacent faces"
(shared edge, distance ~ 0), and gather all faces from a set of bodies for later measurement and intersection. Everything uses the Open C list API.

## Keywords
UF_MODL_ask_body_faces, UF_MODL_ask_body_edges, UF_MODL_ask_face_edges, uf_list_p_t,
UF_MODL_ask_list_count, UF_MODL_ask_list_item, UF_MODL_delete_list, adjacent face,
IsSolidBody, BodyCollection, edge, face extraction

---

## 1. Collect the tags of all solids in the part

```cpp
#include <NXOpen/Body.hxx>
#include <NXOpen/BodyCollection.hxx>
#include <vector>

std::vector<tag_t> bodyTags;
BodyCollection* bodies = part->Bodies();
for (BodyCollection::iterator it = bodies->begin(); it != bodies->end(); ++it)
{
    Body* b = *it;
    if (b != nullptr && b->IsSolidBody())
        bodyTags.push_back(b->Tag());
}
```

## 2. Get all **faces** of a body

```cpp
#include <uf_modl.h>

std::vector<tag_t> allFaces;
for (tag_t bodyTag : bodyTags)
{
    uf_list_p_t faceList = nullptr;
    if (UF_MODL_ask_body_faces(bodyTag, &faceList) == 0 && faceList != nullptr)
    {
        int fc = 0;
        UF_MODL_ask_list_count(faceList, &fc);
        for (int i = 0; i < fc; ++i)
        {
            tag_t ft = NULL_TAG;
            if (UF_MODL_ask_list_item(faceList, i, &ft) == 0 && ft != NULL_TAG)
                allFaces.push_back(ft);
        }
        UF_MODL_delete_list(&faceList);
    }
}
std::cout << "Total faces: " << allFaces.size() << std::endl;
```

## 3. Get all **edges** of a body

```cpp
uf_list_p_t edgeList = nullptr;
if (UF_MODL_ask_body_edges(bodyTag, &edgeList) == 0 && edgeList != nullptr)
{
    int ec = 0;
    UF_MODL_ask_list_count(edgeList, &ec);
    for (int i = 0; i < ec; ++i)
    {
        tag_t et = NULL_TAG;
        if (UF_MODL_ask_list_item(edgeList, i, &et) == 0 && et != NULL_TAG)
        {
            // process edge et
        }
    }
    UF_MODL_delete_list(&edgeList);
}
```

## 4. Get the **boundary edges of a face**

```cpp
uf_list_p_t faceEdges = nullptr;
if (UF_MODL_ask_face_edges(faceTag, &faceEdges) == 0 && faceEdges != nullptr)
{
    int n = 0;
    UF_MODL_ask_list_count(faceEdges, &n);
    std::cout << "Face has " << n << " boundary edges." << std::endl;
    for (int i = 0; i < n; ++i)
    {
        tag_t edgeTag = NULL_TAG;
        UF_MODL_ask_list_item(faceEdges, i, &edgeTag);
        // ...
    }
    UF_MODL_delete_list(&faceEdges);
}
```

## 5. Decide on **adjacent faces** (shared edge / distance ~ 0) -- used for filtering

For measurements such as "nearest non-adjacent face", first exclude the faces adjacent to the target faces:

```cpp
// intersectFaces = the known set of target faces; faces at distance ~ 0 from them are marked adjacent and excluded
std::vector<tag_t> excluded = intersectFaces;
auto isExcluded = [&excluded](tag_t f) {
    for (tag_t e : excluded) if (e == f) return true;
    return false;
};

for (tag_t candidate : allFaces)
{
    if (isExcluded(candidate)) continue;
    for (tag_t iface : intersectFaces)
    {
        double d = 0, p1[3] = {0}, p2[3] = {0}, acc = 0, g[3] = {0,0,0};
        if (UF_MODL_ask_minimum_dist_3(2, iface, candidate, 0, g, 0, g,
                                       &d, p1, p2, &acc) == 0)
        {
            if (d < 1e-6) { excluded.push_back(candidate); break; }  // touching = adjacent
        }
    }
}
```

## 6. Convenient C++ iteration (use GetFaces/GetEdges after tag -> object)

If you already have an `NXOpen::Body*`, you can also use C++ directly:

```cpp
#include <NXOpen/Face.hxx>
#include <NXOpen/Edge.hxx>

std::vector<NXOpen::Face*> faces = body->GetFaces();
std::vector<NXOpen::Edge*> edges = body->GetEdges();
for (NXOpen::Face* f : faces) { /* f->SolidFaceType() gives the face type */ }
```

## 7. API quick reference

| Function / member | Purpose |
| --- | --- |
| `part->Bodies()` + `IsSolidBody()` + `Tag()` | Collect solid tags |
| `UF_MODL_ask_body_faces(body, &list)` | All faces of a body |
| `UF_MODL_ask_body_edges(body, &list)` | All edges of a body |
| `UF_MODL_ask_face_edges(face, &list)` | Boundary edges of a face |
| `UF_MODL_ask_list_count(list, &n)` | Number of list elements |
| `UF_MODL_ask_list_item(list, i, &tag)` | Get the i-th element |
| `UF_MODL_delete_list(&list)` | Release the list |
| `UF_MODL_ask_minimum_dist_3(2, f1, f2, ...)` | Adjacency test (distance ~ 0) |
| `body->GetFaces()/GetEdges()` | Convenient C++ iteration |
| `#include <uf_modl.h>` | Open C modeling header |

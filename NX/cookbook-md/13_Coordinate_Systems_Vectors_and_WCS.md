# 13 · CSYS, Vectors & WCS (Open C)

## Description
Coordinate math in a batch DLL: vectors/distances (`UF_VEC*`), building a rotation matrix from two vectors (`UF_MTX3_initialize`),
creating/querying coordinate systems (`UF_CSYS_*`), setting the work coordinate system WCS, mapping points between coordinate systems (`UF_CSYS_map_point`),
and **resetting the WCS to a known baseline before modeling** to avoid misplaced features.
> Entry point see [doc 00](00_NX_DLL_Entry_Template.md).
> For measurement / minimum distance see also [05_Distance_Measurement_and_Minimum_Distance.md](05_Distance_Measurement_and_Minimum_Distance.md).

## Keywords
UF_VEC2_add, UF_VEC3_distance, UF_MTX3_initialize, UF_CSYS_create_matrix, UF_CSYS_create_csys,
UF_CSYS_create_temp_csys, UF_CSYS_ask_csys_info, UF_CSYS_ask_matrix_values, UF_CSYS_set_origin,
UF_CSYS_set_wcs, UF_CSYS_set_wcs_display, UF_CSYS_ask_wcs, UF_CSYS_map_point,
UF_CSYS_ROOT_WCS_COORDS, UF_CSYS_WORK_COORDS, UF_CSYS_ROOT_COORDS

---

## 1. Vector math and distance between two points

```cpp
#include <uf_vec.h>

// 2D vector addition
double v1[2] = {1.0, 2.0}, v2[2] = {3.0, 4.0}, v3[2];
UF_VEC2_add(v1, v2, v3);

// 3D distance between two points
double p1[3] = {3.0, 4.0, 2.0}, p2[3] = {1.0, 1.0, 0.0};
double dist = 0.0;
UF_VEC3_distance(p1, p2, &dist);
std::cout << "distance = " << dist << std::endl;
```
> Vector families `UF_VEC2_*` / `UF_VEC3_*` (add/subtract, dot, cross, normalize, ...), matrix families `UF_MTX3_*` / `UF_MTX4_*`.
> You can also reuse the self-written `Dot/Cross/Normalize` helpers from [doc 01](01_Point_and_Line_Basic_Geometry.md).

## 2. Build a matrix from two vectors and create a coordinate system

```cpp
#include <uf_csys.h>
#include <uf_mtx.h>

double origin[3] = { 10, 20, 30 };

// X, Y reference vectors -> 3x3 matrix (orthogonalized internally)
double vecX[3] = { 2, 3, 5 };
double vecY[3] = { 0, 1, 0 };
double mtx[9];
UF_MTX3_initialize(vecX, vecY, mtx);

// Matrix -> matrix tag
tag_t mtxId = NULL_TAG;
UF_CSYS_create_matrix(mtx, &mtxId);

// Origin + matrix -> coordinate system
tag_t csysId = NULL_TAG;
UF_CSYS_create_csys(origin, mtxId, &csysId);
```

## 3. Query coordinate-system info and matrix values

```cpp
tag_t csysMtxId = NULL_TAG;
double org[3];
UF_CSYS_ask_csys_info(csysId, &csysMtxId, org);   // get the origin and matrix tag

double m[9];
UF_CSYS_ask_matrix_values(mtxId, m);              // the 9 matrix components
```

## 4. Change the origin, set the WCS, display the WCS

```cpp
double newOrg[3] = { 100, 0, 0 };
UF_CSYS_set_origin(csysId, newOrg);   // move the CSYS origin

UF_CSYS_set_wcs(csysId);              // make it the work coordinate system
UF_CSYS_set_wcs_display(1);           // show the WCS (0 hides it; can be omitted in headless batch)
```

## 5. Map points between coordinate systems `UF_CSYS_map_point`

The correct way to build geometry on the **current WCS**: first map the absolute/root coordinate point into WORK coordinates, then use the mapped result as the corner point:

```cpp
// Get the current WCS
tag_t wcsTag = NULL_TAG;
UF_CSYS_ask_wcs(&wcsTag);

// Map ROOT(WCS) coordinate (10,10,10) to WORK coordinates
double src[3] = { 10, 10, 10 };
double dst[3];
UF_CSYS_map_point(UF_CSYS_ROOT_WCS_COORDS, src, UF_CSYS_WORK_COORDS, dst);
std::cout << "mapped: " << dst[0] << ", " << dst[1] << ", " << dst[2] << std::endl;
```

Coordinate-system constants: `UF_CSYS_ROOT_WCS_COORDS` (root/absolute WCS), `UF_CSYS_WORK_COORDS` (current work coordinates),
`UF_CSYS_ROOT_COORDS` (root coordinates).

## 6. Reset the WCS to a known baseline before modeling / measuring

**Symptom**: when building two coordinate-based features in a row, if the WCS was previously rotated/translated, the second feature lands somewhere else.
**Fix**: first rebuild a temporary coordinate system at the origin aligned with the absolute system and set it as the WCS, so all coordinates share one baseline.

```cpp
// Rebuild a matrix aligned with the absolute system from unit directions
double vecX[3] = { 1.0, 0.0, 0.0 };
double vecY[3] = { 0.0, 1.0, 0.0 };
double m[9];
UF_MTX3_initialize(vecX, vecY, m);

tag_t matId = NULL_TAG;
UF_CSYS_create_matrix(m, &matId);

// Temporary coordinate system (origin at 0,0,0)
double origin[3] = { 0.0, 0.0, 0.0 };
tag_t csysId = NULL_TAG;
UF_CSYS_create_temp_csys(origin, matId, &csysId);

// Reset the WCS; coordinate-based operations afterwards will not be misplaced
UF_CSYS_set_wcs(csysId);
```

## 7. API quick reference

| Function | Purpose |
| --- | --- |
| `UF_VEC3_distance(p1,p2,&d)` | 3D distance between two points |
| `UF_MTX3_initialize(X,Y,mtx)` | Orthogonalize a 3x3 matrix from X/Y reference vectors |
| `UF_CSYS_create_matrix(mtx,&mtxId)` | Matrix array -> matrix tag |
| `UF_CSYS_create_csys(origin,mtxId,&csysId)` | Origin + matrix -> coordinate system |
| `UF_CSYS_create_temp_csys(origin,matId,&csysId)` | Temporary coordinate system (not in the navigator) |
| `UF_CSYS_ask_csys_info(csysId,&mtxId,org)` | Query CSYS origin / matrix tag |
| `UF_CSYS_ask_matrix_values(mtxId,m[9])` | Read the 9 matrix components |
| `UF_CSYS_set_origin / set_wcs / set_wcs_display` | Change origin / set WCS / show WCS |
| `UF_CSYS_ask_wcs(&wcsTag)` | Get the current WCS |
| `UF_CSYS_map_point(from,src,to,dst)` | Map a point across coordinate systems |

## Notes
- **Do not assume the WCS is at the origin** before modeling / coordinate-based measuring; for multi-step operations involving relative positions, reset/map to a known baseline first.
- `UF_MTX3_initialize(X, Y, mtx)` uses X as the primary axis, orthogonalizes the true Y from Y, then takes the cross product for Z.
- `create_temp_csys` yields a temporary CSYS that does not enter the part navigator; suitable for just "straightening" the WCS.
- In the batch DLL (`NxMain`), always output through `std::cout` / `std::cerr`.
- **Run and verified on NX2512 + assembly `FF.prt`** (vector/matrix/CSYS/WCS/map_point/temp_csys all rc=0).

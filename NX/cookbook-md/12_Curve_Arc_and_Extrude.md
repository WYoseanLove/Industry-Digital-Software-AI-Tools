# 12 · Curves: Arc & Extrude (Open C)

## Description
In a batch DLL, create wireframe geometry on an already opened `.prt` and **extrude it into a solid**: build an **arc** from a struct (angles in radians),
put several curves into a list with `UF_MODL_create_list` and extrude them with `UF_MODL_create_extruded2`, plus Open C
**memory allocation / release** (`UF_allocate_memory` / `UF_free`).
> For the basics of creating **points / lines** see [01_Point_and_Line_Basic_Geometry.md](01_Point_and_Line_Basic_Geometry.md) (not repeated here); this doc focuses on **arcs, list-based extrusion, dynamic memory**.
> Entry point see [doc 00](00_NX_DLL_Entry_Template.md).

## Keywords
UF_CURVE_create_arc, UF_CURVE_arc_t, matrix_tag, DEGRA, UF_CSYS_ask_wcs, UF_CSYS_ask_matrix_of_object,
UF_MODL_create_list, UF_MODL_put_list_item, UF_MODL_ask_list_count, UF_MODL_create_extruded2,
UF_FEATURE_SIGN, UF_allocate_memory, UF_reallocate_memory, UF_free, UF_MODL_delete_list

---

## 1. Arc `UF_CURVE_create_arc`

Arc angles are in **radians** (`degrees * DEGRA`); the arc orientation matrix is taken from the current WCS matrix tag:

```cpp
#include <uf_curve.h>
#include <uf_csys.h>

UF_CURVE_arc_t arc;
arc.start_angle   = 0.0;
arc.end_angle     = 225 * DEGRA;   // degrees -> radians
arc.arc_center[0] = 0.0; arc.arc_center[1] = 0.0; arc.arc_center[2] = 0.0;
arc.radius        = 50.0;

// Arc orientation matrix: take the matrix tag of the current WCS
tag_t wcsTag = NULL_TAG;
UF_CSYS_ask_wcs(&wcsTag);
UF_CSYS_ask_matrix_of_object(wcsTag, &arc.matrix_tag);

tag_t arcTag = NULL_TAG;
if (UF_CURVE_create_arc(&arc, &arcTag) != 0 || arcTag == NULL_TAG)
    std::cerr << "Failed to create arc." << std::endl;
else
    std::cout << "Arc tag = " << arcTag << std::endl;
```

`UF_CURVE_arc_t` members: `matrix_tag` (CSYS matrix of the arc), `start_angle`/`end_angle` (radians),
`arc_center[3]` (center), `radius`.

## 2. Chain several lines + extrude into a solid `UF_MODL_create_extruded2`

Use three end-to-end lines to form a triangle, put them in a list, then extrude (for creating points/lines see [doc 01](01_Point_and_Line_Basic_Geometry.md)):

> **MANDATORY -- verified on NX2512**: `UF_MODL_create_extruded2` is declared in **`uf_modl_sweep.h`** (not `uf_modl.h`);
> with only `#include <uf_modl.h>` you get `error C3861` (symbol not found), so `uf_modl_sweep.h` must be included explicitly.

```cpp
#include <uf_modl.h>
#include <uf_modl_sweep.h>   // UF_MODL_create_extruded2 (in this header on NX2512)
#include <uf_curve.h>

// Create three lines, store the tags in an array
tag_t lineTAG[3];
UF_CURVE_create_line(&line1, &lineTAG[0]);
UF_CURVE_create_line(&line2, &lineTAG[1]);
UF_CURVE_create_line(&line3, &lineTAG[2]);

// Create the list and fill it
uf_list_t* objects = NULL;
UF_MODL_create_list(&objects);
for (int i = 0; i < 3; i++)
    UF_MODL_put_list_item(objects, lineTAG[i]);

int count = 0;
UF_MODL_ask_list_count(objects, &count);   // verify the count
std::cout << "Section curves = " << count << std::endl;

// Extrusion parameters
char*  taper_angle = "0";                 // draft angle (expression string)
char*  limit[2]    = { "0", "10" };       // start/end distance (expression strings)
double point[3]    = { 0, 0, 0 };
double direction[3]= { 0, 0, 1 };         // extrusion direction
UF_FEATURE_SIGN sign = UF_NULLSIGN;
uf_list_t* features = NULL;
UF_MODL_create_extruded2(objects, taper_angle, limit, point, direction, sign, &features);

UF_MODL_delete_list(&objects);            // free the section list
if (features) UF_MODL_delete_list(&features);
```

## 3. Open C dynamic memory allocation / release

When you need a batch of structs such as `UF_CURVE_line_t`, allocate dynamically and `UF_free` when done:

```cpp
int err = 0;
UF_CURVE_line_t* buf =
    (UF_CURVE_line_t*)UF_allocate_memory(32 * sizeof(UF_CURVE_line_t), &err);
buf = (UF_CURVE_line_t*)UF_reallocate_memory(buf, 32 * sizeof(UF_CURVE_line_t), &err);

buf->start_point[0] = 20; buf->start_point[1] = 30; buf->start_point[2] = 40;
buf->end_point[0]   = 130; buf->end_point[1]  = 140; buf->end_point[2]  = 0;
tag_t l2 = NULL_TAG;
UF_CURVE_create_line(buf, &l2);

UF_free(buf);   // release
```

## 4. API quick reference

| Function / member | Purpose |
| --- | --- |
| `UF_CURVE_arc_t{matrix_tag,start_angle,end_angle,arc_center[3],radius}` | Arc data structure (angles in radians) |
| `UF_CURVE_create_arc(&arc, &arcTag)` | Create an arc, returns the tag |
| `DEGRA` | Degrees-to-radians conversion constant |
| `UF_CSYS_ask_wcs(&wcsTag)` / `UF_CSYS_ask_matrix_of_object(wcsTag,&mtx)` | Get the WCS and its matrix tag |
| `UF_MODL_create_list(&list)` / `UF_MODL_put_list_item(list,tag)` | Create a list and add objects |
| `UF_MODL_ask_list_count(list,&n)` | Number of list elements |
| `UF_MODL_create_extruded2(objects,taper,limit,point,dir,sign,&feats)` | Extrude curves into a solid |
| `UF_MODL_delete_list(&list)` | Free a list |
| `UF_allocate_memory / UF_reallocate_memory / UF_free` | Open C dynamic memory |

## Notes
- Dimensions of lines/points/arcs are real `double`s; only the edge lengths/diameters/heights of **modeling primitives (block/cylinder/cone)** are `char*` expression strings.
- The extrusion `taper_angle` and `limit[2]` are strings (expressions).
- The arc `end_angle` must be in radians: `degrees * DEGRA`.
- Every `UF_MODL_create_list` / `UF_allocate_memory` needs a matching `UF_MODL_delete_list` / `UF_free`.
- In the batch DLL (`NxMain`), always output through `std::cout` / `std::cerr`; do not use ListingWindow / message boxes.
- **Compiled and run successfully on NX2512 + assembly `FF.prt`** (arc / extrude / memory allocation all rc=0).

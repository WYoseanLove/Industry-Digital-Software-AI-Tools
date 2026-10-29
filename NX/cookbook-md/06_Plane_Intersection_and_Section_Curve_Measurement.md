# 06 · Plane x Face Intersection & Measuring the Curve (Open C)

## Description
In a remote batch DLL, intersects a **plane** with a **feature face** to get the **intersection curve** (section curve), then measures the curve length with the arc-length function;
also gives the complete loop "sweep cutting planes about a probe line and take the shortest section curve length" (LWE). The core is
`UF_MODL_intersect_objects` + `UF_CURVE_ask_arc_length`.

## Keywords
UF_MODL_intersect_objects, UF_MODL_intersect_info_p_t, UF_MODL_INTERSECT_CURVE, intersect.curve.identifier,
UF_CURVE_ask_arc_length, UF_MODL_MMETER, intersection curve, section length, sweep, LWE,
UF_OBJ_delete_object, UF_free

---

## 1. Plane x face -> intersection curve (core)

`UF_MODL_intersect_objects(face, plane, tol, &numInt, &intersections)` returns the intersection results.
> **WARNING - signature notes (verified on NX2512)**: the 5th parameter is a **double pointer** `UF_MODL_intersect_info_p_t**`,
> i.e. "a pointer to an **array of pointers**". So declare `UF_MODL_intersect_info_p_t* intersections` (one level of pointer)
> and pass `&intersections`. Each array element `intersections[k]` is itself a pointer, so members are accessed with `->`,
> and **each element and the array itself must be released separately with `UF_free`** (official header comment: the memory allocated for this
> array **and each element of the array** should be freed with `UF_free`).
> Writing it as a "contiguous struct array" with `UF_MODL_intersect_info_p_t intersections` + `intersections[k].field`
> **does not compile** (C2664: cannot convert `..._p_t*` to `..._p_t**`).

Check each result for the **curve** type and extract the curve tag:

```cpp
#include <uf_modl.h>

int numInt = 0;
UF_MODL_intersect_info_p_t* intersections = nullptr;   // one level of pointer; &it => double pointer
int st = UF_MODL_intersect_objects(faceTag, planeTag, 0.001, &numInt, &intersections);
if (st == 0 && intersections != nullptr)
{
    for (int k = 0; k < numInt; ++k)
    {
        UF_MODL_intersect_info_p_t item = intersections[k];   // each element is itself a pointer
        if (item != nullptr && item->intersect_type == UF_MODL_INTERSECT_CURVE)
        {
            tag_t curveTag = item->intersect.curve.identifier;   // intersection curve (use ->)
            // ... measure the length (see below) ...
            UF_OBJ_delete_object(curveTag);      // delete the temporary curve when done
        }
    }
    for (int k = 0; k < numInt; ++k) UF_free(intersections[k]);  // release each element first
    UF_free(intersections);                                      // then the array itself
}
```

## 2. Measure the intersection curve length (arc length)

```cpp
#include <uf_curve.h>

double len = 0.0;
// parameter range [0,1], unit millimeters
if (UF_CURVE_ask_arc_length(curveTag, 0.0, 1.0, UF_MODL_MMETER, &len) == 0)
{
    std::cout << "intersection curve length = " << len << " mm" << std::endl;
}
```

## 3. "Total section length" of one plane cutting one face (possibly several segments)

One intersection may produce several curve segments; add them up for the total length:

```cpp
double totalLen = 0.0;
bool hasCurve = false;
int numInt = 0;
UF_MODL_intersect_info_p_t* inter = nullptr;
if (UF_MODL_intersect_objects(faceTag, planeTag, 0.001, &numInt, &inter) == 0 && inter)
{
    for (int k = 0; k < numInt; ++k)
    {
        UF_MODL_intersect_info_p_t item = inter[k];
        if (item != nullptr && item->intersect_type == UF_MODL_INTERSECT_CURVE)
        {
            tag_t c = item->intersect.curve.identifier;
            double len = 0.0;
            if (UF_CURVE_ask_arc_length(c, 0.0, 1.0, UF_MODL_MMETER, &len) == 0)
            {
                totalLen += len; hasCurve = true;
            }
            UF_OBJ_delete_object(c);
        }
    }
    for (int k = 0; k < numInt; ++k) UF_free(inter[k]);
    UF_free(inter);
}
if (hasCurve) std::cout << "total section length = " << totalLen << " mm\n";
```

## 4. Full loop: sweep cutting planes about the probe line, take the **shortest** section length (LWE)

Connects the "sweep cutting planes" of doc 04 with the "intersect + measure length" of this document:

```cpp
double bestLen = std::numeric_limits<double>::max();
int    bestAngle = -1;

// u: seed vector perpendicular to the probe-line direction dir (see docs 01/04)
for (int deg = 0; deg < 180; ++deg)
{
    double angle = deg * 3.14159265358979 / 180.0;
    double inPlaneDir[3];
    RotateAroundAxis(u, dir, angle, inPlaneDir);

    double planeNormal[3];
    Cross(dir, inPlaneDir, planeNormal);
    Normalize(planeNormal);

    tag_t planeTag = NULL_TAG;
    double planeOrigin[3] = { point[0], point[1], point[2] };
    if (UF_MODL_create_plane(planeOrigin, planeNormal, &planeTag) != 0 || planeTag == NULL_TAG)
        continue;

    int numInt = 0;
    UF_MODL_intersect_info_p_t* inter = nullptr;
    if (UF_MODL_intersect_objects(chosenFace, planeTag, 0.001, &numInt, &inter) == 0 && inter)
    {
        double totalLen = 0.0; bool hasCurve = false;
        for (int k = 0; k < numInt; ++k)
        {
            UF_MODL_intersect_info_p_t item = inter[k];
            if (item != nullptr && item->intersect_type == UF_MODL_INTERSECT_CURVE)
            {
                tag_t c = item->intersect.curve.identifier;
                double len = 0.0;
                if (UF_CURVE_ask_arc_length(c, 0.0, 1.0, UF_MODL_MMETER, &len) == 0)
                { totalLen += len; hasCurve = true; }
                UF_OBJ_delete_object(c);
            }
        }
        for (int k = 0; k < numInt; ++k) UF_free(inter[k]);
        UF_free(inter);

        if (hasCurve && totalLen > 1e-6 && totalLen < bestLen)
        { bestLen = totalLen; bestAngle = deg; }
    }
    UF_OBJ_delete_object(planeTag);
}

if (bestAngle >= 0)
    std::cout << "Shortest section (LWE) = " << bestLen
              << " mm at " << bestAngle << " deg" << std::endl;
```

## 5. Curve end points / distance to other objects

- Minimum distance from the intersection curve to other objects: pass the curve tag to `UF_MODL_ask_minimum_dist_3` (see doc 05).
- Curve end points: `UF_CURVE_ask_arc_length` gives the length; end-point coordinates can be read with a curve evaluation API or by converting to a C++ curve object.

## 6. Notes

- **Clean up correctly**: delete the `planeTag` and the curve `curveTag` produced in each loop iteration with
    `UF_OBJ_delete_object`; `intersections` is an **array of pointers**, so first `for(k) UF_free(intersections[k])`
    to release each element, **then** `UF_free(intersections)` to release the array itself (two-level release, both required).
- Pass `0.001` for `tol` (verified); relax it when the face is very large or has complex curvature.
- Unit constant for `UF_CURVE_ask_arc_length`: use `UF_MODL_MMETER` for millimeters.

## 7. API quick reference

| Function / member | Purpose |
| --- | --- |
| `UF_MODL_create_plane(origin, normal, &planeTag)` | Create a cutting plane (see doc 04) |
| `UF_MODL_intersect_objects(face, plane, 0.001, &numInt, &inter)` | Face x plane intersection (5th arg is `..._p_t**`: declare `..._p_t* inter` and pass `&inter`) |
| `inter[k]->intersect_type == UF_MODL_INTERSECT_CURVE` | Check whether a result is a curve (`inter[k]` is a pointer, use `->`) |
| `inter[k]->intersect.curve.identifier` | Get the intersection curve tag |
| `UF_CURVE_ask_arc_length(curve, 0.0, 1.0, UF_MODL_MMETER, &len)` | Measure the curve length (mm) |
| `UF_OBJ_delete_object(tag)` | Delete a temporary plane/curve |
| `for(k) UF_free(inter[k]); UF_free(inter);` | Free each element first, then the pointer array |
| `RotateAroundAxis / Cross / Normalize` | Sweep cutting planes (see docs 01/04) |
| `#include <uf_modl.h>` `<uf_curve.h>` | Headers |

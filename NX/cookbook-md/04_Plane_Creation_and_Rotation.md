# 04 · Create & Rotate Planes (Open C)

## Description
Creates **planes** (`UF_MODL_create_plane`, from origin + normal) in a remote batch DLL and **rotates** them: the plane normal is rotated about an axis
(usually the probe-line direction) with Rodrigues' formula, "sweeping" out a series of cutting planes that all pass through the same line.
This is how cutting planes are rotated to find the shortest section (LWE).

## Keywords
UF_MODL_create_plane, plane, origin, normal, rotation, RotateAroundAxis, Rodrigues,
sweep plane, cutting plane, planeNormal, Cross, Normalize, UF_OBJ_delete_object

---

## 1. Create a plane (origin + normal)

```cpp
#include <uf_modl.h>

double planeOrigin[3] = { 0.0, 0.0, 50.0 };   // a point on the plane
double planeNormal[3] = { 0.0, 0.0, 1.0 };    // plane normal (must be normalized)

tag_t planeTag = NULL_TAG;
if (UF_MODL_create_plane(planeOrigin, planeNormal, &planeTag) != 0 || planeTag == NULL_TAG)
{
    std::cerr << "Failed to create plane." << std::endl;
}
// ... release when done: UF_OBJ_delete_object(planeTag);
```

## 2. Rotate a plane normal (about any axis, Rodrigues)

"Rotating a plane" = rotate the normal about an axis by an angle, then rebuild the plane. Use `RotateAroundAxis` (see doc 01, section 4):

```cpp
double axis[3]   = { 1.0, 0.0, 0.0 };          // rotation axis (unit vector)
double angleRad  = 30.0 * 3.14159265358979 / 180.0;
double nIn[3]    = { 0.0, 0.0, 1.0 };          // original normal
double nOut[3];
RotateAroundAxis(nIn, axis, angleRad, nOut);   // rotated normal
Normalize(nOut);

tag_t rotatedPlane = NULL_TAG;
double origin[3] = { 0, 0, 0 };
UF_MODL_create_plane(origin, nOut, &rotatedPlane);
```

## 3. Sweep cutting planes about a "probe line" (core LWE pattern)

Requirement: every cutting plane must **pass through the same line** (direction `dir`, through `point`). Method: take a vector `u` perpendicular to `dir`,
rotate it about `dir` to get the in-plane direction `inPlaneDir`; plane normal = `dir x inPlaneDir`.

```cpp
// 1) Take a seed vector u perpendicular to dir (see doc 01, section 5)
double ref[3] = { 1.0, 0.0, 0.0 };
if (std::fabs(Dot(ref, dir)) > 0.9) { ref[0]=0; ref[1]=1; ref[2]=0; }
double u[3]; Cross(dir, ref, u); Normalize(u);

// 2) Generate one cutting plane through the line every 1 degree
for (int deg = 0; deg < 180; ++deg)      // 180 degrees covers all plane orientations
{
    double angle = deg * 3.14159265358979 / 180.0;
    double inPlaneDir[3];
    RotateAroundAxis(u, dir, angle, inPlaneDir);   // rotate the seed vector about the line

    double planeNormal[3];
    Cross(dir, inPlaneDir, planeNormal);           // normal is perpendicular to the line and to the in-plane direction
    Normalize(planeNormal);

    tag_t planeTag = NULL_TAG;
    double planeOrigin[3] = { point[0], point[1], point[2] };  // plane passes through point (i.e. through the line)
    if (UF_MODL_create_plane(planeOrigin, planeNormal, &planeTag) != 0 || planeTag == NULL_TAG)
        continue;

    // ... intersect this plane with the target face and measure the section curve length (see doc 06) ...

    UF_OBJ_delete_object(planeTag);   // delete after each step to avoid accumulation
}
```

## 4. A plane at a given angle to a target face ("rotate to an angle")

Given the reference face normal `refNormal` and a rotation axis `axis`, build a plane at `angle` to the reference face:

```cpp
double outNormal[3];
RotateAroundAxis(refNormal, axis, angleRad, outNormal);
Normalize(outNormal);
tag_t anglePlane = NULL_TAG;
UF_MODL_create_plane(planeOrigin, outNormal, &anglePlane);
```

## 5. tag -> C++ Plane (when some C++ builder needs it)

```cpp
NXOpen::Plane* cppPlane = dynamic_cast<NXOpen::Plane*>(NXObjectManager::Get(planeTag));
```

> For "plane x face intersection" in batch mode, use `UF_MODL_intersect_objects` directly (see doc 06); there is no need to convert to a C++ Plane.

## 6. API quick reference

| Function / member | Purpose |
| --- | --- |
| `UF_MODL_create_plane(origin[3], normal[3], &planeTag)` | Create a plane from origin + normal |
| `RotateAroundAxis(nIn, axis, angle, nOut)` | Rotate a normal about an axis (Rodrigues) |
| `Cross(dir, inPlaneDir, planeNormal)` | Plane normal from two directions |
| `Normalize(v)` | Normalize |
| `UF_OBJ_delete_object(planeTag)` | Delete a temporary plane |
| `NXObjectManager::Get(planeTag)` | tag -> C++ Plane |
| `#include <uf_modl.h>` | Open C modeling header |

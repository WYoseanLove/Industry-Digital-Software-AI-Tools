# 01 · Points & Lines Basics (Open C)

## Description
Creates the most basic geometry in a remote batch DLL: **points** from coordinates, **lines** from two end points, plus preparation of direction vectors
and common vector math (dot product, cross product, normalize, rotate about an axis). In a batch session prefer Open C (`UF_CURVE_*`);
convert to C++ objects only when needed.

## Keywords
UF_CURVE_create_point, UF_CURVE_create_line, UF_CURVE_line_t, start_point, end_point, tag_t,
NXObjectManager, Point3d, Dot, Cross, Normalize, RotateAroundAxis, Rodrigues, direction, ijk

---

## 1. Create a point from coordinates (Open C)

```cpp
#include <uf_curve.h>

double coords[3] = { 10.0, 20.0, 30.0 };
tag_t ptTag = NULL_TAG;
UF_CURVE_create_point(coords, &ptTag);

// When a C++ object is needed:
NXOpen::Point* pt = dynamic_cast<NXOpen::Point*>(NXObjectManager::Get(ptTag));
```

## 2. Create a line from two end points (Open C, most common in this library)

Fill the start/end points in `UF_CURVE_line_t`; `UF_CURVE_create_line` returns the line tag:

```cpp
#include <uf_curve.h>

UF_CURVE_line_t lineData;
lineData.start_point[0] = 0.0;   lineData.start_point[1] = 0.0;   lineData.start_point[2] = 0.0;
lineData.end_point[0]   = 100.0; lineData.end_point[1]   = 0.0;   lineData.end_point[2]   = 0.0;

tag_t lineTag = NULL_TAG;
if (UF_CURVE_create_line(&lineData, &lineTag) != 0 || lineTag == NULL_TAG)
{
    std::cerr << "Failed to create line." << std::endl;
}
// ... release when done: UF_OBJ_delete_object(lineTag);
```

## 3. Probe line from "midpoint + direction + length" (common LWE pattern)

Given a midpoint `point`, a direction `ijk` and a total length `lineLength`, extend symmetrically into one line:

```cpp
double dir[3] = { ijk[0], ijk[1], ijk[2] };
Normalize(dir);
double half = lineLength * 0.5;

UF_CURVE_line_t lineData;
for (int i = 0; i < 3; ++i)
{
    lineData.start_point[i] = point[i] - dir[i] * half;
    lineData.end_point[i]   = point[i] + dir[i] * half;
}
tag_t lineTag = NULL_TAG;
UF_CURVE_create_line(&lineData, &lineTag);
```

## 4. Vector helpers (dot / cross / normalize / rotate about axis)

Almost every measurement, intersection and plane sweep needs these. **Copy this set of helpers as-is**:

```cpp
#include <cmath>

static double Dot(const double a[3], const double b[3])
{ return a[0]*b[0] + a[1]*b[1] + a[2]*b[2]; }

static void Cross(const double a[3], const double b[3], double out[3])
{
    out[0] = a[1]*b[2] - a[2]*b[1];
    out[1] = a[2]*b[0] - a[0]*b[2];
    out[2] = a[0]*b[1] - a[1]*b[0];
}

static double Norm(const double a[3]) { return std::sqrt(Dot(a, a)); }

static void Normalize(double a[3])
{
    double n = Norm(a);
    if (n > 1e-12) { a[0]/=n; a[1]/=n; a[2]/=n; }
}

// Rotate vector v about unit axis k by angle (radians), Rodrigues' formula
static void RotateAroundAxis(const double v[3], const double k[3], double angle, double out[3])
{
    double c = std::cos(angle), s = std::sin(angle);
    double kxv[3]; Cross(k, v, kxv);
    double kdotv = Dot(k, v);
    for (int i = 0; i < 3; ++i)
        out[i] = v[i]*c + kxv[i]*s + k[i]*kdotv*(1.0 - c);
}
```

## 5. Get a vector perpendicular to a given direction (seed for plane creation / sweeps)

```cpp
// dir is the known direction; find a unit vector u perpendicular to it
double ref[3] = { 1.0, 0.0, 0.0 };
if (std::fabs(Dot(ref, dir)) > 0.9) { ref[0]=0; ref[1]=1; ref[2]=0; } // switch the reference when dir is near the X axis
double u[3]; Cross(dir, ref, u); Normalize(u);
```

## 6. tag -> C++ curve object (when geometry must be read or passed to measurement)

```cpp
NXOpen::Line* cppLine = dynamic_cast<NXOpen::Line*>(NXObjectManager::Get(lineTag));
if (cppLine)
{
    NXOpen::Point3d s = cppLine->StartPoint();
    NXOpen::Point3d e = cppLine->EndPoint();
    double len = cppLine->GetLength();
}
```

## 7. API quick reference

| Function / member | Purpose |
| --- | --- |
| `UF_CURVE_create_point(coords[3], &ptTag)` | Create a point from coordinates |
| `UF_CURVE_line_t{start_point[3], end_point[3]}` | Line data structure |
| `UF_CURVE_create_line(&lineData, &lineTag)` | Create a line, returns the tag |
| `UF_OBJ_delete_object(tag)` | Delete a temporary line/point |
| `Dot / Cross / Norm / Normalize` | Basic vector math (write your own) |
| `RotateAroundAxis(v, k, angle, out)` | Rotate a vector about an axis (Rodrigues) |
| `NXObjectManager::Get(tag)` | tag -> C++ object |
| `line->StartPoint()/EndPoint()/GetLength()` | Read line end points / length |
| `#include <uf_curve.h>` | Open C curve header |

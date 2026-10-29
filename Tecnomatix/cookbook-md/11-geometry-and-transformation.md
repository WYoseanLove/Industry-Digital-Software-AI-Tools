# 11 · Geometry & Transformation / 几何测量与坐标变换

> **When to use / 何时使用**
> Build/compose `TxTransformation` (translation + RPY rotation, deg↔rad); measure distances,
> project points, compute bounding boxes; extract faces/edges/planes; create display geometry
> (local component, sphere, line); build swept volumes; move a location by assigning
> `AbsoluteLocation`.
>
> **Keywords / 关键词**: transformation, TxTransformation, RPY_XYZ, TxVector, rotation, translation,
> AbsoluteLocation, GetMinimalDistance, TxBoundingBoxCalculator, projection, TxLineData, TxPlaneData,
> ITxExactGeometryFace, TxLocalComponentCreationData, TxSphereCreationData, TxLineCreationData,
> TxSweptVolumeCreationData, swept volume, SetAsDisplay, 坐标变换, 几何, 包围盒, 扫掠体
>
> **Consolidated from / 归并来源**: `07_几何测量与坐标变换.md`, `11_几何体创建与显示.md`,
> `18_坐标变换组合与偏移.md`, `Location-Move.md`,
> `Macro Or Commande To Reclocate All The Locations That Have The Same Name.md`

---

## 1. Build a transformation (translation + RPY rotation)

```csharp
TxVector tran = new TxVector(x, y, z);
TxVector rot  = new TxVector(rx, ry, rz);   // RADIANS
TxTransformation t = new TxTransformation(tran, rot, TxTransformation.TxRotationType.RPY_XYZ);

// degrees -> radians
double rad = deg * Math.PI / 180.0;
```

## 2. Compose transformations (right-multiply = local frame)

```csharp
// Apply loca_Translate in the LOCAL frame of (weldFrameLocation * txTransformation):
TxTransformation result = weldFrameLocation * txTransformation * loca_Translate;
```
- Right-multiplication applies the next transform in the CURRENT (local) frame.
- Left-multiplication applies it in the world frame.

## 3. Minimal distance between two objects

```csharp
double clearance;
TxVector p1, p2;
(objA as ITxLocatableObject).GetMinimalDistance(objB as ITxLocatableObject, out clearance, out p1, out p2);
```

## 4. Move a location (assign AbsoluteLocation + refresh)

```csharp
TxVector tran = new TxVector(x, y, z);
TxVector rot  = new TxVector(rx, ry, rz);
location.AbsoluteLocation =
    new TxTransformation(tran, rot, TxTransformation.TxRotationType.RPY_XYZ);
TxApplication.RefreshDisplay();
```

### Re-locate all locations that share a name (forum macro)
```csharp
// Group locations by Name, then Locate() each group's members onto the first member's frame.
TxTransformation firstAbsLocation = group.First().AbsoluteLocation;
foreach (ITxLocatableObject loc in group)
    loc.Locate(firstAbsLocation);
```
> 来源 / Source (forum): "Macro or command to re-locate all the locations that have the same name".
> Group selected/searched locations by `Name`; use `ITxLocatableObject.Locate(firstAbsLocation)`.

## 5. Bounding box

```csharp
TxBoundingBoxCalculator calc = new TxBoundingBoxCalculator();
// add objects, then compute; read min/max corners from the result.
```

## 6. Create display geometry (local component / sphere / line)

```csharp
// Local component container
TxLocalComponentCreationData compData = new TxLocalComponentCreationData("MyMarkers");
TxLocalComponent comp = TxApplication.ActiveDocument.PhysicalRoot.CreateLocalComponent(compData);

// Sphere marker
TxSphereCreationData sphereData = new TxSphereCreationData(radius);
TxSphere sphere = comp.CreateSphere(sphereData);
sphere.SetAsDisplay();          // make it a display object
sphere.Color = new TxColor(255, 0, 0);

// Line
TxLineCreationData lineData = new TxLineCreationData(startVec, endVec);
TxLine line = comp.CreateLine(lineData);
```

## 7. Swept volume (create + sample during playback)

```csharp
TxSweptVolumeCreationData svData = new TxSweptVolumeCreationData(name);
svData.Accuracy  = 1.0;
svData.Clearance = 0.0;

TxSweptVolumeCalculationData calcData = new TxSweptVolumeCalculationData();
TxObjectSweptVolumeCalculationData objData = new TxObjectSweptVolumeCalculationData(movingObject);
// during simulation, per frame:
objData.AddTransformation(movingObject.AbsoluteLocation);
calcData.AddObjectData(objData);

TxSweptVolume sv = TxApplication.ActiveDocument.PhysicalRoot.CreateSweptVolume(svData, calcData);
// Sample poses via PlayWithoutRefresh (see 09) then Rewind.
```

## Geometry API quick reference / 几何 API 速查
| Member | Use |
| --- | --- |
| `TxTransformation(tran, rot, RPY_XYZ)` | build transform from vectors |
| `ITxLocatableObject.GetMinimalDistance(...)` | min distance/clearance |
| `TxLineData` / `TxPlaneData` | line / plane geometric data |
| `ITxExactGeometryFace` / `ITx1Dimensional` | exact face / 1-D (edge) geometry |
| `ITxGeometryCreation` | geometry creation interface |
| `TxBoundingBoxCalculator` | bounding box |
| `TxLocalComponentCreationData` / `CreateLocalComponent` | local component |
| `TxSphereCreationData` / `TxLineCreationData` / `SetAsDisplay` | display markers |
| `TxSweptVolumeCreationData` / `CreateSweptVolume` | swept volume |
| `TxObjectSweptVolumeCalculationData.AddTransformation` | accumulate poses |

## See also / 参见
- `04-robot-kinematics-and-pose.md` — poses & frames on robots.
- `06-operations-and-trajectory.md` — apply transforms to trajectory points.
- `09-simulation-and-playback.md` — per-frame sampling for swept volumes.

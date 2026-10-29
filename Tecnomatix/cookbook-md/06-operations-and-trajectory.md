# 06 · Operations & Trajectory / 操作与轨迹

> **When to use / 何时使用**
> Create robotic operations (generic / weld) and their trajectory points (via/seam/weld locations);
> set motion type (PTP/Line), external-axis data, robot configuration on a point; reorder / move /
> delete points; recursively traverse the operation tree.
>
> **Keywords / 关键词**: operation, trajectory, via point, location, TxGenericRoboticOperation,
> TxGenericRoboticOperationCreationData, TxRoboticViaLocationOperation,
> TxRoboticViaLocationOperationCreationData, CreateRoboticViaLocationOperation, RRS_MOTION_TYPE,
> TxRoboticIntParam, MoveChildAfter, TxCompoundOperation, operation tree, 操作树, 轨迹点, 运动类型
>
> **Consolidated from / 归并来源**: `03_操作与轨迹.md`, `16_操作创建与操作树管理.md`,
> `How To Create A Robotic Via Location Using Net Api.md`

---

## 1. Create a generic robotic operation

```csharp
TxGenericRoboticOperationCreationData creationData = new TxGenericRoboticOperationCreationData();
creationData.Robot = robot;                                 // TxRobot
creationData.Tool  = robServerGun as ITxLocatableObject;    // optional tool (e.g. servo gun)

TxGenericRoboticOperation op =
    TxApplication.ActiveDocument.OperationRoot.CreateGenericRoboticOperation(creationData);

// op.Delete();  // delete a temporary operation when done
```

## 2. Create a via location under an operation (minimal, forum example)

```csharp
TxWeldOperationCreationData operationCreationData = new TxWeldOperationCreationData { Name = "Test operation" };
ITxRoboticViaLocationOperationCreation operation =
    TxApplication.ActiveDocument.OperationRoot.CreateWeldOperation(operationCreationData);
if (operation == null) return;

TxRoboticViaLocationOperationCreationData viaLocationCreationData =
    new TxRoboticViaLocationOperationCreationData("Via1");
if (operation.CanCreateRoboticViaLocationOperation(viaLocationCreationData))
{
    ITxLocatableObject viaLocation = operation.CreateRoboticViaLocationOperation(viaLocationCreationData);
    if (viaLocation != null)
    {
        TxVector translation = new TxVector(-750.0, 800.0, 1300.0);
        TxVector rotation    = new TxVector(0.0, 0.0, -Math.PI / 4);   // RADIANS
        viaLocation.AbsoluteLocation =
            new TxTransformation(translation, rotation, TxTransformation.TxRotationType.RPY_XYZ);
    }
}
```
> 来源 / Source (forum): <https://community.sw.siemens.com/s/question/0D5Vb00000ZjGCeKAN/> —
> "How to create a robotic via location using .NET API" (MarkusH).

## 3. Create a via point with motion + external axis + config (full recipe)

```csharp
public static TxRoboticViaLocationOperation addrobotPathViaLoc(
    string name, point p, TxGenericRoboticOperation weldOperation,
    TxRobot robot, TxServoGun robServerGun)
{
    // (name, description, arrival time / tolerance)
    TxRoboticViaLocationOperationCreationData data =
        new TxRoboticViaLocationOperationCreationData(name, "", 2.0);

    TxVector tran = new TxVector(p.x, p.y, p.z);
    TxVector rot  = new TxVector(p.rx, p.ry, p.rz);   // RADIANS
    data.AbsoluteLocation =
        new TxTransformation(tran, rot, TxTransformation.TxRotationType.RPY_XYZ);

    TxRoboticViaLocationOperation loc = weldOperation.CreateRoboticViaLocationOperation(data);

    // External axis (servo gun opening)
    TxRobotExternalAxisData[] ext = new TxRobotExternalAxisData[1];
    ext[0] = new TxRobotExternalAxisData();
    ext[0].Device     = robServerGun as TxServoGun;
    ext[0].Joint      = (robServerGun as TxServoGun).DrivingJoints.Last() as TxJoint;
    ext[0].JointValue = p.Gun_Open;
    loc.RobotExternalAxesData = ext;

    // Motion type: 1 = PTP, 2 = LINE
    loc.SetParameter(new TxRoboticIntParam("RRS_MOTION_TYPE", 1));
    return loc;
}
```

## 4. Motion type (PTP / LINE)

```csharp
loc.SetParameter(new TxRoboticIntParam("RRS_MOTION_TYPE", 1)); // PTP
loc.SetParameter(new TxRoboticIntParam("RRS_MOTION_TYPE", 2)); // LINE
```

## 5. Robot configuration on a point

```csharp
robot.CurrentPose = startPose;
TxRobotConfigurationData cfg = robot.GetPoseConfiguration(startPose);
loc.RobotConfigurationData = cfg;

// If a point's RobotConfigurationData is null, derive a pose at that location first:
if ((allWeldPointsExist[i] as TxRoboticViaLocationOperation).RobotConfigurationData == null)
{
    TxPoseData spotPoseData =
        robot.GetPoseAtLocation(allWeldPointsExist[j + 1] as ITxRoboticLocationOperation);
}
```

## 6. Operation-tree add / move / reorder / delete

```csharp
// Reorder: move a child to sit immediately AFTER a reference child
weldTargetOperation.MoveChildAfter(refLocation, RobFramepostLocation);

// Move an object into the operation root
TxApplication.ActiveDocument.OperationRoot.AddObject(someLocation);

// Delete
someLocation.Delete();
```

## 7. Recursively collect operations (TxCompoundOperation)

```csharp
private void CollectWeldOperations(ITxObject op, List<TxWeldOperation> targetList)
{
    if (op is TxWeldOperation weldOp)
    {
        targetList.Add(weldOp);
    }
    else if (op is TxCompoundOperation compoundOp)
    {
        for (int i = 0; i < compoundOp.Count; i++)
            CollectWeldOperations(compoundOp.GetChildAt(i), targetList);   // recurse
    }
    // skip other types
}
```

## 8. Filter direct children by several types

```csharp
TxTypeFilter opFilter = new TxTypeFilter(typeof(TxWeldLocationOperation));
opFilter.AddIncludedType(typeof(TxRoboticViaLocationOperation));
TxObjectList allPoints = weldTargetOperation.GetDirectDescendants(opFilter);
```

## API quick reference / 速查
| Member | Use |
| --- | --- |
| `TxGenericRoboticOperationCreationData` (`.Robot` / `.Tool`) | generic robotic op creation data |
| `OperationRoot.CreateGenericRoboticOperation(data)` | create generic robotic op |
| `TxRoboticViaLocationOperationCreationData(name, desc, time)` | via point creation data |
| `op.CreateRoboticViaLocationOperation(data)` | create a via point under op |
| `loc.SetParameter(new TxRoboticIntParam("RRS_MOTION_TYPE", 1))` | motion type 1=PTP / 2=LINE |
| `robot.GetPoseConfiguration(pose)` / `loc.RobotConfigurationData` | config |
| `parent.MoveChildAfter(refChild, child)` | reorder children |
| `OperationRoot.AddObject(obj)` | move into operation root |
| `TxCompoundOperation.Count` / `.GetChildAt(i)` | traverse compound op children |

## See also / 参见
- `07-weld-operations.md` — weld operations & weld points specifically.
- `05-external-axes-and-joints.md` — external-axis data details.
- `08-olp-and-builtin-commands.md` — attach OLP commands to trajectory points.

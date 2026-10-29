# 05 · External Axes & Joint Values / 外部轴与关节值

> **When to use / 何时使用**
> Read or set external-axis values (rails X/Y/Z, positioner, servo gun) on a robot and on
> trajectory locations; offset external-axis values across all locations of an operation; fix
> Ext1/Ext2 order swapping between locations.
>
> **Keywords / 关键词**: external axis, external axes, ExternalAxes, TxRobotExternalAxisData,
> RobotExternalAxesData, JointValue, TxJoint, rail, 7th axis, Ext1, Ext2, servo gun, DrivingJoints,
> offset, 外部轴, 关节值, 导轨
>
> **Consolidated from / 归并来源**: `12_外部轴与关节值.md`,
> `Api How Do I Get The Value Of Operations External Axis Using Api.md`,
> `Api What Causes Ext1 Ex2 Values To Change In The Second Location.md`,
> `How To Change A Via Points Ext1 Value By Api.md`

---

## ⚠️ Key lesson: match by Joint.Name / Joint.Id, NOT by array index

`RobotExternalAxesData` element ORDER can change between locations, which makes Ext1/Ext2 (e.g. X,
Y) appear swapped. Read/write by matching the joint identity, never by a fixed index.

```csharp
// Fix for "Ext1/Ext2 values change in the second location": match by Joint.Name
foreach (ITxRoboticLocationOperation loc in locs)
{
    var axisX = loc.RobotExternalAxesData.FirstOrDefault(a => a.Joint.Name == "X2");
    var axisY = loc.RobotExternalAxesData.FirstOrDefault(a => a.Joint.Name == "Y2");
    var axisZ = loc.RobotExternalAxesData.FirstOrDefault(a => a.Joint.Name == "Z2");

    double currentX = axisX != null ? axisX.JointValue : 0;
    double currentY = axisY != null ? axisY.JointValue : 0;
    double currentZ = axisZ != null ? axisZ.JointValue : 0;
    // ...
}
```
> 来源 / Source (forum): <https://community.sw.siemens.com/s/question/0D5Vb00001LrwirKAB/> —
> "[API] What causes Ext1, Ex2 values to change in the second location?" (mindheart's fix).

## 1. Read an operation's external-axis values (and offset them)

```csharp
foreach (ITxRoboticLocationOperation loc in locs)
{
    double currentX = loc.RobotExternalAxesData[0].JointValue;
    double currentY = loc.RobotExternalAxesData[1].JointValue;
    double currentZ = loc.RobotExternalAxesData[2].JointValue;

    double newX = currentX + offsetX;
    double newY = currentY + offsetY;
    double newZ = currentZ + offsetZ;

    var ret = new TxRobotExternalAxisData[3];
    for (int i = 0; i < 3; i++)
    {
        ret[i] = new TxRobotExternalAxisData();
        ret[i].Device = ((TxJoint)robot.ExternalAxes[i]).Device;
        ret[i].Joint  = (TxJoint)robot.ExternalAxes[i];
    }
    ret[0].JointValue = newX;
    ret[1].JointValue = newY;
    ret[2].JointValue = newZ;

    loc.RobotExternalAxesData = ret;   // assign the whole array back
}
```
> 来源 / Source (forum): <https://community.sw.siemens.com/s/question/0D5Vb00001LWxBiKAL/> —
> "[API] How do I get the value of Operation's External Axis using API?".
> NOTE: prefer the Joint.Name / Joint.Id matching above over the fixed `[0]/[1]/[2]` indices.

## 2. Set a trajectory point's external-axis value (servo gun OR rail)

```csharp
TxRobotExternalAxisData[] externalAxisData = new TxRobotExternalAxisData[1];

if (robServerEx != null && robServerEx.GetType() == typeof(TxServoGun))
{
    TxServoGun servoGun = robServerEx as TxServoGun;
    externalAxisData[0] = new TxRobotExternalAxisData();
    externalAxisData[0].Device     = servoGun;
    externalAxisData[0].Joint      = servoGun.DrivingJoints.Last() as TxJoint;
    externalAxisData[0].JointValue = p.Servo_Ext;
}
else if (robot.ExternalAxes.Count > 0)   // positioner / track / rail fallback
{
    externalAxisData[0] = new TxRobotExternalAxisData();
    externalAxisData[0].Joint      = robot.ExternalAxes[0] as TxJoint;
    externalAxisData[0].Device     = (robot.ExternalAxes[0] as TxJoint).Device;
    externalAxisData[0].JointValue = p.Servo_Ext;
}

viaLocation.RobotExternalAxesData = externalAxisData;
```

## 3. Change a via point's Ext value by matching Joint.Id (robust)

```csharp
if (!(TxApplication.ActiveSelection.GetAllItems()[0] is TxRoboticViaLocationOperation)) return;
TxRoboticViaLocationOperation via = TxApplication.ActiveSelection.GetAllItems()[0] as TxRoboticViaLocationOperation;

TxRobotExternalAxisData[] extData = via.RobotExternalAxesData;
TxRobot robot = via.ParentRoboticOperation.Robot as TxRobot;

foreach (TxRobotExternalAxisData axis in extData)
{
    foreach (ITxObject ext in robot.ExternalAxes)
    {
        if (axis.Joint.Id == ext.Id)
        {
            axis.JointValue = 1000;   // your target value
            break;
        }
    }
}
via.RobotExternalAxesData = extData;   // reassign the array
```
> 来源 / Source (forum): <https://community.sw.siemens.com/s/question/0D5Vb000009f0vGKAQ/> —
> "How to change a via point's Ext1 value by API" (Henry Muschler). The thread also shows a batch
> command that ADDS any missing external axis to every location (build a new `TxRobotExternalAxisData`
> per missing `robot.ExternalAxes` joint and `Union` it into `location.RobotExternalAxesData`).
> Note: simple in-place value assignment "does not work for unknown reasons" — always rebuild and
> reassign the whole array.

## 4. Read a location's external-axis value back onto the robot

```csharp
((robot.ExternalAxes[0]) as TxJoint).CurrentValue =
    (viaLoc as TxRoboticViaLocationOperation).RobotExternalAxesData[0].JointValue;
```

## See also / 参见
- `06-operations-and-trajectory.md` — create locations that carry external-axis data.
- `04-robot-kinematics-and-pose.md` — drive a rail/7th axis via `robot.ExternalAxes` CurrentValue.

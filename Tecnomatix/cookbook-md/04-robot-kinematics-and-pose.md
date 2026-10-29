# 04 · Robot Kinematics & Pose / 机器人运动学与姿态

> **When to use / 何时使用**
> Driving a robot's kinematics: inverse kinematics (IK) & reachability, choosing a non-overhead
> pose, applying a pose, reading TCP, updating joint values (deg→rad), reading pose at a location,
> pose↔configuration, joint soft limits, and checking RCS/controller initialization.
>
> **Keywords / 关键词**: robot, pose, posture, kinematics, IK, inverse, CalcInverseSolutions,
> CalcInverseSolutions, reach, reachability, TxRobotInverseData, TxPoseData, CurrentPose, TCPF,
> GetPoseAtLocation, GetPoseConfiguration, TxRobotConfigurationData, OverheadState, soft limit,
> RCS, controller, RRS, ValidateRCSParameters, 逆解, 位姿, 配置, 软限位
>
> **Consolidated from / 归并来源**: `10_机器人运动学与姿态.md`, `17_位姿读取与机器人配置.md`,
> `Robot-Pose-And-Motion.md`, `How To Check Robot Rcs Is Initialed Ok Through Api.md`

---

## Notes / 要点
- `robot.CalcInverseSolutions(inv)` returns an `ArrayList`; each element is a `TxPoseData`.
- The Tecnomatix joint API expects **RADIANS** for revolute joints. Convert degrees:
  `deg * Math.PI / 180.0`.
- `robot.ExternalAxes` items are `TxJoint`. For prismatic/rail joints `CurrentValue` is in the
  joint's linear unit (pass a distance directly); for rotary external axes convert degrees first.
- Weld points (`TxWeldLocationOperation`) and via points (`TxRoboticViaLocationOperation`) both
  implement `ITxRoboticLocationOperation`, so pose calls work uniformly.

## 1. Inverse kinematics + reachability + apply best non-overhead pose

```csharp
TxRobotInverseData inv = new TxRobotInverseData();
inv.Destination = targetLoc;                 // TxTransformation
ArrayList solutions = robot.CalcInverseSolutions(inv);
if (solutions == null || solutions.Count == 0)
{
    message = string.Format("Robot '{0}' cannot reach the target.", robot.Name);
}
else
{
    TxPoseData chosen = solutions[0] as TxPoseData;
    for (int i = 0; i < solutions.Count; i++)
    {
        TxPoseData p = solutions[i] as TxPoseData;
        if (p == null) continue;
        TxRobotConfigurationData cfg = robot.GetPoseConfiguration(p);
        if (cfg.OverheadState != TxRobotConfigurationData.TxOverheadState.Overhead)
        { chosen = p; break; }
    }
    if (chosen != null) robot.CurrentPose = chosen;
    TxApplication.RefreshDisplay();
    message = string.Format("Robot '{0}' can reach the target. Solutions: {1}.", robot.Name, solutions.Count);
}
```

### Building the destination from XYZ + RPY
```csharp
TxRobotInverseData txRobotInverseData = new TxRobotInverseData();
TxTransformation txTransformation = new TxTransformation();
TxVector rotation = new TxVector { X = target.rx, Y = target.ry, Z = target.rz }; // radians
txTransformation.RotationRPY_XYZ = rotation;
txTransformation.Translation = new TxVector(target.x, target.y, target.z);
txRobotInverseData.Destination = txTransformation;
ArrayList solutions = robot.CalcInverseSolutions(txRobotInverseData);
```

## 2. Apply a pose / build a pose from joint values

```csharp
// From a solution:
TxPoseData poseData = (TxPoseData)solutions[0];
robot.CurrentPose = poseData;
double j1 = (double)poseData.JointValues[0];

// From an ArrayList of radian joint values:
var arr = new ArrayList(q.ToArray());   // q = joint array (radians)
var robotPosture = new TxPoseData { JointValues = arr };
robot.CurrentPose = robotPosture;
```

### Update posture from user joint values (degrees → radians)
```csharp
if (jointDegrees != null && jointDegrees.Length > 0)
{
    for (int j = 0; j < jointDegrees.Length && j < robot.Joints.Count; j++)
        robot.Joints[j].CurrentValue = jointDegrees[j] * Math.PI / 180.0;
    TxApplication.RefreshDisplay();
}
```

## 3. Read pose at a location (GetPoseAtLocation)

```csharp
TxPoseData poseData = robot.GetPoseAtLocation(location as ITxRoboticLocationOperation);
if (poseData != null)
{
    robot.CurrentPose = poseData;                 // apply
    double j1 = (double)poseData.JointValues[0];  // read a joint
}
```

## 4. Pose ↔ configuration (GetPoseConfiguration)

```csharp
TxRobotConfigurationData cfg = robot.GetPoseConfiguration(poseData);
location.RobotConfigurationData = cfg;   // write back to the location to keep teaching consistent
```

## 5. Read TCP absolute pose

```csharp
double x  = robot.TCPF.AbsoluteLocation.Translation.X;
double y  = robot.TCPF.AbsoluteLocation.Translation.Y;
double z  = robot.TCPF.AbsoluteLocation.Translation.Z;
double rx = robot.TCPF.AbsoluteLocation.RotationRPY_XYZ.X;
double ry = robot.TCPF.AbsoluteLocation.RotationRPY_XYZ.Y;
double rz = robot.TCPF.AbsoluteLocation.RotationRPY_XYZ.Z;
```

## 6. Joint soft limits (sampling / validation)

```csharp
for (int i = 0; i < 6; i++)
{
    double low  = robot.Joints[i].LowerSoftLimit;
    double high = robot.Joints[i].UpperSoftLimit;
    if (value[i] < low || value[i] > high) { /* out of range, reject this pose */ }
}
```

## 7. Controller / RCS state check

Quick heuristic (a real controller is loaded ⇒ RRS interpolation, more accurate but slower):

```csharp
bool isRCSLoaded = false;
if (robot.IsRCSTurnedOffForNonSimulationActions == false
 && robot.IsRCSTurnedOffForSimulationActions == false
 && robot.Controller.Name != "default")
{
    isRCSLoaded = true;
}
```

### Validate RCS parameters via controller services (verified pattern)
```csharp
TxOlpControllerUtilities controllerUtilities = new TxOlpControllerUtilities();
ITxRoboticControllerServices controllerServices =
    (ITxRoboticControllerServices)controllerUtilities.GetInterfaceImplementationFromController(
        robot.Controller.Name,
        typeof(ITxRoboticControllerServices),
        typeof(TxControllerAttribute), "ControllerName");
if (controllerServices != null)
{
    try
    {
        if (silent)
        {
            TxRCSParamResults res = controllerServices.ValidateRCSParametersSilently(robot);
            if (res != null) { /* res.Message -> invalid params */ }
        }
        else
        {
            bool validateRCS = controllerServices.ValidateRCSParameters(robot);
        }
    }
    catch (TxRRSCanNotInitializeRcsException initException)
    {
        // initException.StatusMessage + " (" + initException.StatusCode + ")"
    }
}
```
> 来源 / Source (forum): <https://community.sw.siemens.com/s/question/0D5Vb000012z45JKAQ/> —
> "How to check Robot RCS is initialed ok through api". Also look at `TxRobotRRSController`.

## See also / 参见
- `05-external-axes-and-joints.md` — external/rail axis values on a robot and on locations.
- `06-operations-and-trajectory.md` — write the chosen pose/config onto trajectory points.
- `12-device-and-tool.md` — servo gun opening via `ITxDevice.CurrentPose`.

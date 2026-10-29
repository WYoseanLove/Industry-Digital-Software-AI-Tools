# 12 · Device & Tool / 设备与工具

> **When to use / 何时使用**
> Switch a device (fixture/gripper/clamp) to a named posture; drive a mounted `TxServoGun`
> open/close opening value through `ITxDevice.CurrentPose`.
>
> **Keywords / 关键词**: device, tool, gun, servo gun, servogun, gripper, clamp, posture, pose, open,
> close, opening, MountedTools, CurrentPose, PoseList, ITxDevice, TxServoGun, TxDevice, 设备, 工具,
> 夹具, 焊枪, 姿态
>
> **Consolidated from / 归并来源**: `Device-And-Tool.md`

---

## 1. Switch a device posture by name

```csharp
TxDevice dev = target as TxDevice;
if (dev != null && dev.GetType() == typeof(TxDevice))
{
    for (int i = 0; i < dev.PoseList.Count; i++)
    {
        if (string.Equals(dev.PoseList[i].Name, postureName, StringComparison.OrdinalIgnoreCase))
        {
            dev.CurrentPose = dev.PoseList[i].PoseData;
            TxApplication.RefreshDisplay();
            break;
        }
    }
}
```

## 2. Drive a mounted TxServoGun (open/close opening value)

```csharp
// A servo gun is driven through ITxDevice.CurrentPose with a single JointValues entry.
// Resolve the gun from the robot's mounted tools first.
TxServoGun servoGun = null;
for (int i = 0; i < robot.MountedTools.Count; i++)
{
    if (robot.MountedTools[i].GetType() == typeof(TxServoGun))
    {
        servoGun = (TxServoGun)robot.MountedTools[i];
        break;
    }
}

if (servoGun != null)
{
    ITxDevice gunDevice = servoGun as ITxDevice;
    if (gunDevice != null)
    {
        ArrayList gunJointValues = new ArrayList();
        gunJointValues.Add(gunOpening); // linear opening value; convert deg->rad only if the axis is rotary
        TxPoseData gunPose = gunDevice.CurrentPose;
        gunPose.JointValues = gunJointValues;
        gunDevice.CurrentPose = gunPose;
    }
}
TxApplication.RefreshDisplay();
```

## 3. Read a gun's named pose (e.g. "open")

```csharp
foreach (TxPose pose in servoGun.PoseList)
    if (string.Equals(pose.Name, "open", StringComparison.OrdinalIgnoreCase))
        (servoGun as ITxDevice).CurrentPose = pose.PoseData;
```

## API quick reference / 速查
| Member | Use |
| --- | --- |
| `dev.PoseList` / `pose.Name` / `pose.PoseData` | named postures of a device |
| `dev.CurrentPose` (get/set) | current posture |
| `robot.MountedTools` | tools mounted on a robot |
| `TxServoGun` (`GetType()==typeof(TxServoGun)`) | identify the servo gun |
| `TxPoseData.JointValues` (ArrayList) | joint/opening values for a pose |

## See also / 参见
- `04-robot-kinematics-and-pose.md` — robot poses, joints, mounts.
- `05-external-axes-and-joints.md` — drive gun via external-axis data on a trajectory point.

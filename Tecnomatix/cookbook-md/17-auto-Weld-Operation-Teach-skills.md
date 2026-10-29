# 17 · Auto Weld-Operation Teach / 焊接轨迹自动示教

> **When to use / 何时使用**
> "Auto teach every weld point in a weld operation": resolve the Robot + Gun from the trajectory
> itself, shrink the gun opening, sweep each weld point's orientation about its own Z axis to find
> a reachable / collision-free pose, lock (`TeachCurrentRobotConfiguration`) the best pose per
> point, keep all taught points' robot configuration as consistent as possible, avoid singular /
> overhead poses, and report any weld point that could not be resolved for manual review.
>
> **Keywords / 关键词**: auto teach, 自动示教, weld operation, weld point, TxWeldOperation,
> TxWeldLocationOperation, DoesInverseExist, CalcInverseSolutions, TxRobotInverseData,
> IsPoseWristSingular, TeachCurrentRobotConfiguration, RobotConfigurationData, TxServoGun,
> PoseList, gun opening, TxCollisionPair, GetCollidingObjectsAndDistances, TxCollisionState.Distance,
> rotate about local Z, 碰撞检测, 奇异点, 一致性, 焊枪开口
>
> **Consolidated from / 归并来源**: new skill authored from user requirements (2026-09-08); builds
> on `04-robot-kinematics-and-pose.md`, `06-operations-and-trajectory.md`,
> `07-weld-operations.md`, `10-collision-and-interference.md`, `11-geometry-and-transformation.md`,
> `12-device-and-tool.md`.

---

## 0. Inputs / outputs / contract

**Inputs (user-provided)**
- `weldOperationName` — name of the `TxWeldOperation` to auto-teach (or leave empty and pre-select
  the operation / its weld points in the active selection instead — see §1).
- `collisionPairName` — name of an **existing** `TxCollisionPair` (created beforehand under
  `TxApplication.ActiveDocument.CollisionRoot`) that the robot/gun must stay clear of.

**Robot & gun are NOT user inputs** — both are resolved ("locked") from the weld operation itself
(§1), never asked from the user, never re-resolved per point.

**Output**
- Every weld point that found a valid pose: its `AbsoluteLocation` (orientation only — see §3),
  `RobotConfigurationData` and gun-opening external axis are updated/taught in place.
- A `List<string>` of weld point names that could **not** be resolved (unreachable or no
  collision-free orientation in the swept range) — for manual follow-up. Those points are restored
  to their original (pre-run) location, untouched.

## 1. Step 1 — resolve & "lock" Robot + Gun from the trajectory

There is no dedicated "lock" API — locking means: resolve Robot/Gun **once**, from the operation,
and reuse those exact references for the whole run (never re-resolved per weld point).

```csharp
using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using Tecnomatix.Engineering;

TxWeldOperation ResolveWeldOperation(string weldOperationName)
{
    // Prefer an explicit name; fall back to the active selection (operation or a weld point).
    if (!string.IsNullOrEmpty(weldOperationName))
    {
        TxObjectList found = TxApplication.ActiveDocument.GetObjectsByName(weldOperationName);
        foreach (ITxObject o in found)
            if (o.GetType() == typeof(TxWeldOperation)) return (TxWeldOperation)o;
        return null;
    }

    TxObjectList sel = TxApplication.ActiveSelection.GetAllItems();
    foreach (ITxObject o in sel)
    {
        if (o.GetType() == typeof(TxWeldOperation)) return (TxWeldOperation)o;
        if (o.GetType() == typeof(TxWeldLocationOperation))
            return ((TxWeldLocationOperation)o).ParentRoboticOperation as TxWeldOperation;
    }
    return null;
}

TxWeldOperation weldOp = ResolveWeldOperation(weldOperationName);
if (weldOp == null) { message = "Weld operation not found."; return; }

// Robot: from the trajectory's own assignment (ITxRoboticOrderedCompoundOperation.Robot)
TxRobot robot = weldOp.Robot as TxRobot;

// Gun: resolved from the robot's mounted tools (TxWeldOperationCreationData.Gun is create-time
// only; there is no ITxRoboticOrderedCompoundOperation.Gun getter, so read it via MountedTools).
TxServoGun gun = null;
for (int i = 0; i < robot.MountedTools.Count; i++)
    if (robot.MountedTools[i].GetType() == typeof(TxServoGun))
    { gun = (TxServoGun)robot.MountedTools[i]; break; }

if (robot == null || gun == null)
{ message = string.Format("Operation '{0}' has no Robot/ServoGun assigned.", weldOp.Name); return; }
```

## 2. Step 2 — read gun posture list, shrink opening to 25%

```csharp
double closeVal = 0, openVal = 0;
bool hasClose = false, hasOpen = false;
foreach (ITxObject o in gun.PoseList)
{
    TxPose pose = o as TxPose;
    if (pose == null) continue;
    if (string.Equals(pose.Name, "close", StringComparison.OrdinalIgnoreCase))
    { closeVal = (double)pose.PoseData.JointValues[0]; hasClose = true; }
    else if (string.Equals(pose.Name, "open", StringComparison.OrdinalIgnoreCase))
    { openVal = (double)pose.PoseData.JointValues[0]; hasOpen = true; }
}
if (!hasClose || !hasOpen)
{ message = string.Format("Gun '{0}' has no 'open'/'close' named pose.", gun.Name); return; }

// Requirement: shrink the opening to 1/4 of the way from close -> open.
double teachOpening = (openVal - closeVal) / 4.0 + closeVal;

ITxDevice gunDevice = gun as ITxDevice;
ArrayList gunJointValues = new ArrayList();
gunJointValues.Add(teachOpening);
TxPoseData gunPose = gunDevice.CurrentPose;
gunPose.JointValues = gunJointValues;
gunDevice.CurrentPose = gunPose;
TxApplication.RefreshDisplay();
```
`teachOpening` stays constant for the whole run — it is the opening value written onto every
successfully taught weld point in §4 (it is not re-optimized per point).

## 3. Step 3 — retract every weld point 10 mm along its own -Z

```csharp
const double RETREAT_MM = 10.0;
TxTransformation retreat =
    new TxTransformation(new TxVector(0, 0, -RETREAT_MM), new TxVector(0, 0, 0),
                          TxTransformation.TxRotationType.RPY_XYZ);
TxTransformation advance =
    new TxTransformation(new TxVector(0, 0, RETREAT_MM), new TxVector(0, 0, 0),
                          TxTransformation.TxRotationType.RPY_XYZ);

TxTypeFilter wpFilter = new TxTypeFilter(typeof(TxWeldLocationOperation));
TxObjectList weldPoints = weldOp.GetDirectDescendants(wpFilter);

Dictionary<string, TxTransformation> originalLocation = new Dictionary<string, TxTransformation>();
foreach (ITxObject o in weldPoints)
{
    TxWeldLocationOperation wp = (TxWeldLocationOperation)o;
    ITxLocatableObject loc = (ITxLocatableObject)wp;
    originalLocation[wp.Id] = loc.AbsoluteLocation;
    loc.AbsoluteLocation = loc.AbsoluteLocation * retreat;   // right-multiply = LOCAL frame (see 11)
}
```
> ⚠️ Why retract first: it gives the Z-axis rotation sweep in §4 clearance from the sheet metal
> before any orientation is committed. Because rotating about the point's own Z axis does not
> change where the Z axis points, advancing +10 mm along the (possibly rotated) local Z in §4
> lands EXACTLY back on the original XY/Z position — only the orientation changes. So retreat/
> advance is transparent to the final taught position.

## 4. Step 4 — sweep orientation, test reachability + singularity + collision

```csharp
const double STEP_DEG      = 1.0;
const double MAX_SWEEP_DEG = 180.0;    // 0°..180° swept on BOTH signs => full 360° coverage
TxCollisionRoot collisionRoot = TxApplication.ActiveDocument.CollisionRoot;

TxCollisionPair targetPair = null;
foreach (TxCollisionPair p in collisionRoot.PairList)
    p.Active = string.Equals(p.Name, collisionPairName, StringComparison.OrdinalIgnoreCase);
foreach (TxCollisionPair p in collisionRoot.PairList)
    if (p.Active) { targetPair = p; break; }
if (targetPair == null)
{ message = string.Format("Collision pair '{0}' not found.", collisionPairName); return; }

class Candidate
{
    public double AngleDeg;
    public TxTransformation Location;
    public TxPoseData Pose;
    public TxRobotConfigurationData Config;
    public string ConfigKey;
    public double Clearance;
}

string BuildConfigKey(TxRobotConfigurationData cfg)
{
    StringBuilder sb = new StringBuilder(cfg.OverheadState.ToString());
    foreach (TxJointConfigurationData jc in cfg.JointsConfigurations)
        sb.Append('|').Append(jc.State).Append(':').Append(jc.Turn);
    return sb.ToString();
}

// Distance-to-collision for the CURRENT robot pose, using the ONE active pair (§4, 10-collision...).
bool TryGetClearance(out double clearance)
{
    clearance = double.MaxValue;
    bool ok = true;
    using (TxCollisionQueryResults results = new TxCollisionQueryResults())
    {
        TxCollisionAndDistancesQueryParams qp = new TxCollisionAndDistancesQueryParams();
        qp.Mode = TxCollisionQueryParams.TxCollisionQueryMode.DefinedPairs;
        qp.UseNearMiss = true;
        qp.NearMissDistance = 1000.0;              // large enough to always get a Distance back
        qp.ComputeDistanceIfInNearMiss = true;
        collisionRoot.GetCollidingObjectsAndDistances(qp);   // populates the query context...
        // Simpler/robust alternative used here: explicit min-distance between gun and pair targets
        // (see 10-collision-and-interference.md §3) combined with a boolean collision check:
        foreach (ITxObject src in targetPair.FirstList)
        {
            foreach (ITxObject tar in targetPair.SecondList)
            {
                TxCollisionState state = collisionRoot.GetCollisionStateForObjects(
                    (TxObjectBase)src, (TxObjectBase)tar, qp);
                if (state == null) continue;
                if (state.Type == TxCollisionState.TxCollisionStateType.Collision) ok = false;
                if (state.Distance < clearance) clearance = state.Distance;
            }
        }
    }
    return ok;
}

Dictionary<string, List<Candidate>> candidatesByPoint = new Dictionary<string, List<Candidate>>();
foreach (ITxObject o in weldPoints)
{
    TxWeldLocationOperation wp = (TxWeldLocationOperation)o;
    ITxLocatableObject loc = (ITxLocatableObject)wp;
    TxTransformation retracted = loc.AbsoluteLocation;      // already retracted in §3
    List<Candidate> found = new List<Candidate>();

    // step goes 0..180 and each non-zero step is tried as BOTH +step and -step, so angleDeg
    // takes every value in {0, +1,-1, +2,-2, ..., +180,-180} = the closed range [-180°, +180°].
    // A rotation of +180° about Z and -180° about Z produce the IDENTICAL orientation (180° is
    // its own opposite, mod 360°), so this range already contains one representative of every
    // distinct orientation reachable by rotating the point about its own Z axis — i.e. the full
    // 360° circle — with only that single ±180° value tested twice (harmless, not a gap).
    for (double step = 0; step <= MAX_SWEEP_DEG; step += STEP_DEG)
    {
        double[] signs = step == 0 ? new double[] { 0 } : new double[] { 1, -1 };
        foreach (double sign in signs)
        {
            double angleDeg = sign * step;
            double angleRad = angleDeg * Math.PI / 180.0;
            TxTransformation rotated = retracted *
                new TxTransformation(new TxVector(0, 0, 0), new TxVector(0, 0, angleRad),
                                      TxTransformation.TxRotationType.RPY_XYZ);

            TxRobotInverseData inv = new TxRobotInverseData(rotated);
            if (!robot.DoesInverseExist(inv)) continue;          // not reachable

            ArrayList solutions = robot.CalcInverseSolutions(inv);
            if (solutions == null) continue;

            foreach (TxPoseData pose in solutions)
            {
                if (pose == null) continue;
                if (robot.IsPoseWristSingular(pose)) continue;   // reject singular poses

                TxRobotConfigurationData cfg = robot.GetPoseConfiguration(pose);
                if (cfg.OverheadState == TxRobotConfigurationData.TxOverheadState.Overhead)
                    continue;                                    // reject overhead poses

                robot.CurrentPose = pose;                         // drive robot to evaluate collision
                TxApplication.RefreshDisplay();

                double clearance;
                if (!TryGetClearance(out clearance)) continue;    // collides -> reject

                found.Add(new Candidate
                {
                    AngleDeg = angleDeg, Location = rotated, Pose = pose,
                    Config = cfg, ConfigKey = BuildConfigKey(cfg), Clearance = clearance
                });
            }
        }
    }
    candidatesByPoint[wp.Id] = found;
}
```

## 5. Step 5 — pick the most CONSISTENT, non-singular, max-clearance pose per point

```csharp
// Vote: for how many DISTINCT weld points is each config key achievable at all?
Dictionary<string, int> configVotes = new Dictionary<string, int>();
foreach (List<Candidate> list in candidatesByPoint.Values)
{
    HashSet<string> keysHere = new HashSet<string>();
    foreach (Candidate c in list) keysHere.Add(c.ConfigKey);
    foreach (string key in keysHere)
        configVotes[key] = configVotes.ContainsKey(key) ? configVotes[key] + 1 : 1;
}
string targetConfigKey = configVotes.Count == 0 ? null :
    configVotes.OrderByDescending(kv => kv.Value).First().Key;

List<string> unresolvedWeldPointNames = new List<string>();

foreach (ITxObject o in weldPoints)
{
    TxWeldLocationOperation wp = (TxWeldLocationOperation)o;
    ITxLocatableObject loc = (ITxLocatableObject)wp;
    List<Candidate> list = candidatesByPoint[wp.Id];

    if (list.Count == 0)
    {
        loc.AbsoluteLocation = originalLocation[wp.Id];    // restore, untouched (Step 6)
        unresolvedWeldPointNames.Add(wp.Name);
        continue;
    }

    // Prefer candidates matching the majority config; fall back to this point's own candidates.
    List<Candidate> matching = list.Where(c => c.ConfigKey == targetConfigKey).ToList();
    List<Candidate> pool = matching.Count > 0 ? matching : list;

    // Among the consistent pool: maximize clearance, then minimize deviation from the taught angle.
    Candidate best = pool.OrderByDescending(c => c.Clearance)
                          .ThenBy(c => Math.Abs(c.AngleDeg))
                          .First();

    loc.AbsoluteLocation = best.Location;
    robot.CurrentPose = best.Pose;
    wp.TeachCurrentRobotConfiguration();      // lock the robot pose/config onto this weld point
    wp.RobotConfigurationData = best.Config;  // explicit, keeps it consistent with the taught pose

    // Write the gun-opening external axis (Step 4 requirement: use the CURRENT (25%) opening)
    TxRobotExternalAxisData[] ext = new TxRobotExternalAxisData[1];
    ext[0] = new TxRobotExternalAxisData();
    ext[0].Device     = gun;
    ext[0].Joint      = gun.DrivingJoints.Last() as TxJoint;
    ext[0].JointValue = teachOpening;
    wp.RobotExternalAxesData = ext;

    // Step 7 — advance back 10 mm along the (now rotated) local Z; restores the true weld position.
    loc.AbsoluteLocation = loc.AbsoluteLocation * advance;
}

TxApplication.RefreshDisplay();
message = unresolvedWeldPointNames.Count == 0
    ? string.Format("Auto-taught {0} weld point(s) OK.", weldPoints.Count)
    : string.Format("Auto-taught {0}/{1} weld point(s). Needs manual review: {2}",
                     weldPoints.Count - unresolvedWeldPointNames.Count, weldPoints.Count,
                     string.Join(", ", unresolvedWeldPointNames));
```

## 6. Step 6 — manual-review list

`unresolvedWeldPointNames` (built in §5) is the deliverable for "无法保证可达/无干涉" points. Those
points are left at their **original** (pre-run) `AbsoluteLocation`/`RobotConfigurationData` — never
left retracted, and never partially taught.

## Design notes / 设计要点
- **No separate "lock" API** — §1 resolves Robot/Gun once from `weldOp.Robot` /
  `robot.MountedTools`, and every later step reuses those exact references (that IS the lock).
- **Retract → sweep → advance is transparent** to the final position: rotation about a point's own
  Z axis never moves the point, so undoing the ∓10 mm along the (rotated) local Z always lands back
  on the original XY/Z (see the note at the end of §3).
- **Consistency before per-point optimality**: §5 picks one "majority" `TxRobotConfigurationData`
  key across all weld points first, THEN maximizes clearance within that pool — this is what keeps
  the whole trajectory's arm configuration uniform instead of each point independently picking its
  own best (possibly wildly different) elbow/wrist config.
- **Singularity & overhead are hard rejects**, not scored — `IsPoseWristSingular` and
  `OverheadState == Overhead` candidates are discarded before they ever reach the collision check.
- ⚠️ `TxCollisionPair`'s activation property is **`Active`** (verified against `api-md`), NOT
  `IsActive` as one older cookbook snippet (10-collision-and-interference.md §4) shows.
- `MAX_SWEEP_DEG = 180` is intentional, NOT a shortcut: `step` runs 0°..180° and is tried on BOTH
  signs (`+step`/`-step`), so the loop covers the FULL 360° circle (`-180°..+180°`, where -180°
  and +180° are the same orientation) — this guarantees reachability/collision-free is checked at
  every 1° around the point's Z axis before it is ever reported as unresolved in §5/§6. Only
  narrow `MAX_SWEEP_DEG` below 180 if you deliberately want to cap how far a point may rotate from
  its originally taught orientation (e.g. process/quality constraints) — that trades off
  "guaranteed full-circle search" for runtime.
- Runtime scales with `weldPoints.Count * 360` IK + collision checks; the search stops finding
  MORE candidates once the full circle is swept (not early-exit), since §5 needs the FULL
  candidate set per point to pick the clearance-maximizing, config-consistent choice.
- Wrap `TxCollisionQueryResults` in `using` (`IDisposable`) — see `10-collision-and-interference.md`.

## API quick reference / 速查
| Member | Use |
| --- | --- |
| `weldOp.Robot` (`ITxRoboticOrderedCompoundOperation.Robot`) | robot assigned to the trajectory |
| `robot.MountedTools` + `typeof(TxServoGun)` | resolve the gun mounted on that robot |
| `gun.PoseList` / `TxPose.Name` / `TxPose.PoseData.JointValues[0]` | read named open/close opening |
| `(gun as ITxDevice).CurrentPose` | drive/read the gun's current opening |
| `loc.AbsoluteLocation = loc.AbsoluteLocation * T` | move/rotate in the point's LOCAL frame |
| `robot.DoesInverseExist(TxRobotInverseData)` | cheap reachability check |
| `robot.CalcInverseSolutions(TxRobotInverseData)` | full IK solution set |
| `robot.IsPoseWristSingular(TxPoseData)` | reject singular poses |
| `robot.GetPoseConfiguration(TxPoseData)` / `TxRobotConfigurationData.OverheadState` | config / overhead check |
| `collisionRoot.GetCollisionStateForObjects(a, b, params)` / `TxCollisionState.Distance` | pairwise collision + clearance |
| `wp.TeachCurrentRobotConfiguration()` | lock/teach the robot's current config onto the point |
| `wp.RobotConfigurationData` | explicit config written on the weld point |
| `wp.RobotExternalAxesData` (`Device=gun`, `Joint=gun.DrivingJoints.Last()`) | write the taught gun opening |

## See also / 参见
- `04-robot-kinematics-and-pose.md` — IK, `CalcInverseSolutions`, `GetPoseConfiguration`, overhead state.
- `06-operations-and-trajectory.md` — traversing/filtering weld points, `RobotConfigurationData` on a point.
- `07-weld-operations.md` — resolving the gun from `robot.MountedTools`, weld-op/weld-point basics.
- `10-collision-and-interference.md` — collision pairs, `GetMinimalDistance`, query params, `IDisposable`.
- `11-geometry-and-transformation.md` — local-frame composition (`a * b`), degrees→radians.
- `12-device-and-tool.md` — driving a `TxServoGun`'s opening via `ITxDevice.CurrentPose`.

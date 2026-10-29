# Tecnomatix Process Simulate .NET API — Cookbook INDEX / 目录

> **This is the ONLY file that needs to go into the prompt.** It is the authoritative catalog for
> selecting cookbook recipe files. For any user request, read this index, pick the **1–4** files
> whose *When to use* / *Keywords* best match, and inject ONLY those files.
> 这是唯一需要放进 prompt 的文件。按下方“何时使用/关键词”为用户请求挑选 1–4 个最匹配的文件并注入。

**Scope / 适用范围**: `namespace Tecnomatix.Engineering`, Process Simulate .NET add-in API.
**Code constraint / 代码约束**: target **.NET Framework 4.8 / C# 5** — **NO string interpolation**;
use `string.Format(...)`. Revolute joints & rotations are in **RADIANS** (`deg * Math.PI / 180`).

---

## How to select a file / 选型规则
1. If the task must first **find/locate** objects → **01**.
2. If you already have an object and must decide **what it is** / act on the **selection** → **02**.
3. Match the task's DOMAIN to the table below by *Keywords* + *When to use*.
4. Prefer the FEWEST files that fully cover the task (usually 01 + one or two domain files).
5. Need an exact class/member name or its version? → **16** (surface reference).

---

## Catalog / 目录

| # | File | When to use (triggers) | Key classes / 关键词 |
|---|------|------------------------|----------------------|
| 01 | [01-traversal-and-search.md](01-traversal-and-search.md) | Locate objects before acting: find robot/device/operation by name, list all of a type, iterate physical/operation tree, search a folder. **Reach for this FIRST.** | `PhysicalRoot`, `OperationRoot`, `GetAllDescendants`, `GetDirectDescendants`, `TxTypeFilter`, `GetObjectsByName` |
| 02 | [02-object-type-and-selection.md](02-object-type-and-selection.md) | You hold an `ITxObject` / the active selection and must safely type-check/cast before type-specific calls; focus/jump to an object in the tree. | `GetType`, `as`, `ActiveSelection`, `GetItems`, `GetAllItems`, `Locate` |
| 03 | [03-attachment-and-ownership.md](03-attachment-and-ownership.md) | Find devices/tools/parts attached to a robot, or which robot an object belongs to; mounted tools; add robot + attachments to a collision set. Uses id-matching, NOT tree position. | `AttachmentParent`, `MountedTools`, `ExternalAxes`, id match |
| 04 | [04-robot-kinematics-and-pose.md](04-robot-kinematics-and-pose.md) | Robot IK & reachability, choose/apply a pose, read TCP, set joint values, pose↔config, soft limits, RCS/controller init check. | `CalcInverseSolutions`, `TxPoseData`, `CurrentPose`, `GetPoseConfiguration`, `TxRobotConfigurationData` |
| 05 | [05-external-axes-and-joints.md](05-external-axes-and-joints.md) | Read/set external-axis values (rail/positioner/servo gun) on a robot or a location; offset Ext across a path; fix Ext1/Ext2 swapping. | `RobotExternalAxesData`, `TxRobotExternalAxisData`, `JointValue`, `ExternalAxes` |
| 06 | [06-operations-and-trajectory.md](06-operations-and-trajectory.md) | Create robotic operations & via/location points; motion type (PTP/Line); config on a point; reorder/move/delete points; traverse the operation tree. | `TxGenericRoboticOperation`, `TxRoboticViaLocationOperation`, `RRS_MOTION_TYPE`, `MoveChildAfter`, `TxCompoundOperation` |
| 07 | [07-weld-operations.md](07-weld-operations.md) | Create weld operations (robot + gun), create weld points, leading part, get products/parts in a weld op. Includes the `CreateWeldPoint`-not-implemented workaround. | `TxWeldOperation`, `CreateWeldOperation`, `TxWeldLocationOperation`, `CreateWeldLocationOperation`, `AssignedParts` |
| 08 | [08-olp-and-builtin-commands.md](08-olp-and-builtin-commands.md) | Add OLP commands to points (comments, enter/exit zone, `# Destination`); invoke built-in commands (Convert to Via/Weld Location); read Path-Editor params (Speed/Acc/Duration). | `TxRoboticCompositeCommand*`, `CreateCompositeCommand`, `TxCommandManager`, `ExecuteCommandByCommandProgId` |
| 09 | [09-simulation-and-playback.md](09-simulation-and-playback.md) | Play/step/jump a simulation; per-frame sampling; drive via Path Editor & stop at a location; "sim stops early under API" fix. | `TxSimulationPlayer`, `SetOperation`, `Play`, `PlayWithoutRefresh`, `JumpSimulationToTime`, `TimeIntervalReached` |
| 10 | [10-collision-and-interference.md](10-collision-and-interference.md) | Create collision pairs, run collision/near-miss queries, read states, minimal distance/clearance, reports. | `TxCollisionRoot`, `TxCollisionPairCreationData`, `TxCollisionQueryResults`, `GetCollidingObjects`, `GetMinimalDistance` |
| 11 | [11-geometry-and-transformation.md](11-geometry-and-transformation.md) | Build/compose `TxTransformation` (deg↔rad); measure/project/bounding-box; faces/edges/planes; create display geometry; swept volumes; move a location. | `TxTransformation`, `TxVector`, `RPY_XYZ`, `AbsoluteLocation`, `TxBoundingBoxCalculator`, `TxSweptVolumeCreationData` |
| 12 | [12-device-and-tool.md](12-device-and-tool.md) | Switch a device to a named posture; drive a mounted `TxServoGun` open/close opening value. | `PoseList`, `CurrentPose`, `MountedTools`, `TxServoGun`, `TxPoseData.JointValues` |
| 13 | [13-plc-logic-blocks.md](13-plc-logic-blocks.md) | Create PLC logic behaviors/blocks & expressions; fix "INVALID EXPRESSION" for complex expressions; set angular display units. | `TxPlcLogicBehaviorCreationData`, `CreateLogicBehavior`, `TxPlcExpressionBuilder`, `AddLogicBehaviorExpression` |
| 14 | [14-command-ui-and-plugin-dev.md](14-command-ui-and-plugin-dev.md) | Build a command/add-in: register `ITxCommand`, host WPF/WinForms UI & controls, custom Viewer, thread marshaling, `IDisposable` memory, ribbon bitmap fix, Python-DLL registration failure. | `ITxCommand`, `TxWindow`, `TxMessageBox`, `ITxDockingViewerControl`, `InvokeRequired`, Embedded Resource |
| 15 | [15-mfg-teamcenter-and-part-appearance.md](15-mfg-teamcenter-and-part-appearance.md) | Create `PartAppearance` (standard-study-mode workaround); Teamcenter "action not supported" on compound-part creation; map a UI MFG property to a class member. | `TxPartAppearanceCreationDataEx`, `TxOperationEx`, `TxCompoundPartCreationData`, `AssignedMfgFeatures` |
| 16 | [16-api-surface-reference.md](16-api-surface-reference.md) | Confirm the exact class/member name, its namespace area, or the version it was introduced in (v10.1–v12.1.3). | full by-topic class/method reference |
| 17 | [17-auto-Weld-Operation-Teach-skills.md](17-auto-Weld-Operation-Teach-skills.md) | Auto-teach every weld point in a weld operation: resolve Robot/Gun from the trajectory, shrink gun opening, sweep orientation about local Z for a reachable/collision-free/non-singular pose, keep configs consistent across points, report unresolved points. | `DoesInverseExist`, `IsPoseWristSingular`, `TeachCurrentRobotConfiguration`, `GetCollisionStateForObjects`, `TxRobotConfigurationData` |
| 18 | [18-Tecnomatix_Process_Simulate_Station_Analysis.md](18-Tecnomatix_Process_Simulate_Station_Analysis.md) | Analyze an OPEN Study read-only: tree/assembly/kinematics, BIW area, gripper pick/place, GEO vs re-spot station, part pairs per GEO station, sequence/cycle time; analysis workflow and report template (no API code). 分析已打开仿真的工艺流程、工位类型、GEO/补焊判断。 | `AnalyzeStudyProcess`, `AnalyzeStudyWeldParts`, `TxWeldOperation`, OLP `# Destination`, GEO, re-spot, BIW |

---

## Topic → file cheat sheet / 主题速查
- Find / list / iterate → **01**
- Selection / type-check / cast / focus in tree → **02**
- "attached to robot" / "belongs to which robot" / mounted tools → **03**
- IK / reach / pose / joints / TCP / RCS → **04**
- external axis / rail / 7th axis / Ext1/Ext2 / gun opening on a point → **05**
- create operation / via point / motion type / operation tree → **06**
- weld operation / weld point / products in weld op → **07**
- OLP command / `# Destination` / built-in command / Path-Editor Speed/Acc → **08**
- play / simulate / per-frame / stop at location → **09**
- collision / interference / near miss / min distance → **10**
- transformation / measure / bounding box / display geometry / swept volume → **11**
- device posture / servo gun open-close → **12**
- PLC logic block / expression / invalid expression / display units → **13**
- command / add-in / ribbon button / UI controls / thread / memory / Python DLL → **14**
- PartAppearance / Teamcenter error / compound part / MFG property mapping → **15**
- "what is the exact class/method/version" → **16**
- auto teach weld points / weld trajectory orientation sweep / consistent robot config across a path → **17**
- analyze station / process flow of an open study / GEO vs re-spot / BIW area / pick-place / 工位工艺分析 → **18**

---

## Common cross-cutting rules / 通用规则
- Always **type-check before cast** (`x.GetType() == typeof(T)` or `x as T` + null-check) — see **02**.
- Rotations/joints are **radians**; convert `deg * Math.PI / 180`.
- Reassign whole arrays for external-axis / collision-pair lists (don't mutate in place) — **05**, **10**.
- Dispose `IDisposable` API objects (`TxCollisionQueryResults`, `TxPoseData`) via `using` — **14**.
- Call `TxApplication.RefreshDisplay()` after geometry/pose/appearance changes.
- Model access must be on the **UI thread** — **14**.

> Forum-sourced recipes keep their original discussion URL as `来源 / Source (forum): <url>` inside
> each file. Official .NET API support: `txapi_support.plm@siemens.com`.

# 16 · API Surface Reference / API 类与方法索引

> **When to use / 何时使用**
> A by-topic quick-reference of the most-used classes/methods for API selection. Use when you need to
> confirm the exact class/member name, the namespace area, or the version a member was introduced in
> (v10.1 – v12.1.3). Always confirm against your target installation's API docs before calling.
>
> **Keywords / 关键词**: surface, reference, index, TxApplication, TxNoTypeFilter, TxTypeFilter,
> TxRobot, TxDevice, TxServoGun, TxGripper, ITxRoboticControllerServices, TxRobotConfigurationData,
> TxPoseData, TxRobotExternalAxisData, TxWeldOperation, TxWeldOperationCreationData,
> TxWeldLocationOperation, TxRoboticViaLocationOperation, TxRoboticSeamLocationOperation,
> TxRoboticIntParam, TxMfgCreationDataFactory, TxTcDiscreteOperation, TxTcContinuousOperation,
> TxSimulationPlayer, TxInterferenceSet, TxCollisionQuery, TxSectionVolume, TxTransformation,
> TxVector, TxFrame, TxLineData, TxPlaneData, ITxExactGeometryFace, TxBoundingBoxCalculator,
> TxLocationCalculation, TxWindow, TxViewersManager, ITxDockingViewerControl, TxHuman,
> ITxHumanOperationCreation, ITxPlcGenericConveyor, ITxKinematicsModellable
>
> **Consolidated from / 归并来源**: `09_API类与方法索引.md`
> (source: official "Tecnomatix .NET API New Features (as of 10.1)", covering v10.1 – v12.1.3;
> the version noted is the member's introduction version)

---

## Application & document entry / 应用与文档入口
| Member | Use |
| --- | --- |
| `TxApplication.ActiveDocument` | current document |
| `TxApplication.ActiveSelection.GetItems()` | current selection |
| `TxApplication.RefreshDisplay()` | refresh display |
| `TxApplication.ViewersManager` | viewers manager |
| `TxApplication.RegistryPath` | registry path (v11.1TR2) |
| `ActiveDocument.PhysicalRoot` / `OperationRoot` | physical / operation tree roots |
| `ActiveDocument.MainFolders` | main folders collection |

## Search / filter / 搜索过滤
| Member | Use |
| --- | --- |
| `GetDirectDescendants(filter)` | direct children |
| `GetAllDescendants(filter)` | all descendants |
| `TxNoTypeFilter` / `TxTypeFilter(typeof(T))` | no filter / type filter |

## Robot / device / tool / 机器人·设备·工具
| Member | Use |
| --- | --- |
| `TxRobot` / `TxDevice` / `TxServoGun` / `TxGripper` | robot / device / servo gun / gripper |
| `robot.MountedTools` / `robot.ExternalAxes` | mounted tools / external axes |
| `robot.GetPoseAtLocation(loc)` | pose at a location |
| `robot.GetPoseConfiguration(posture)` | config from posture |
| `robot.SetConveyorTriggerSignal` / `SetConveyorPositionSignal` | conveyor trigger/position (v11.1TR1) |
| `robot.GetPlcConveyorByNumber` | PLC conveyor by number (v11) |
| `ITxRoboticControllerServices` | `CheckInverse`, `CalculateInverseSolutions`, `GetActiveGun`, `GetActiveGripper`, `JumpExternals`, `MirrorSystemFrames` |
| `TxRobotConfigurationData` / `TxPoseData` / `TxRobotExternalAxisData` | config / pose / external-axis data |

## Operation / trajectory / weld / 操作·轨迹·焊接
| Member | Use |
| --- | --- |
| `TxWeldOperation` / `ITxWeldOperation` | weld operation (interface preferred since v10.1) |
| `TxWeldOperationCreationData` | weld operation creation data |
| `OperationRoot.CreateWeldOperation(data)` | create weld operation |
| `TxWeldLocationOperation` / `...CreationData` | weld point operation |
| `TxWeldLocationOperation.GetTranslationLimit` | weld point translation limit (v12.1.2) |
| `TxRoboticViaLocationOperation` / `...CreationData` | via point |
| `TxRoboticSeamLocationOperation` | seam point |
| `TxRoboticIntParam("RRS_MOTION_TYPE", n)` | motion type (1=PTP, 2=LINE) |
| `TxMfgCreationDataFactory` | MFG / weld-point creation data factory (v11) |
| `TxTcDiscreteOperation` / `TxTcContinuousOperation` | Teamcenter discrete/continuous ops (v10.1) |
| `ITxSeamMfgFeature.ProjectWithEqualDistanceSpacing` | equal-distance seam projection (v10.1) |

## Simulation / 仿真
| Member | Use |
| --- | --- |
| `TxSimulationPlayer` | simulation player |
| `SetOperation` / `Play` / `JumpSimulationToTime` | bind / play / jump |
| `TxSimulationPlayerSource.TaskSimulationPlayer` | play source |

## Collision / interference / 碰撞·干涉
| Member | Use |
| --- | --- |
| `TxInterferenceSet` | interference set |
| `TxCollisionQuery` / `TxCollisionInquiryData` / `TxCollisionsSet` | query / input / results |
| `TxPlacementCollisionControl` | collision control while moving (`MovementTypeChanged`, v11.1TR3) |
| `TxSectionVolume.GetIntersection` | section-volume intersection (v11) |

## Geometry / coordinates / 几何·坐标
| Member | Use |
| --- | --- |
| `TxTransformation` / `TxVector` / `TxFrame` | transform / vector / frame |
| `TxLineData` / `TxPlaneData` | line / plane geometric calc |
| `ITxExactGeometryFace` | exact face (U,V params) |
| `ITx1Dimensional` / `ITxGeometryCreation` | curve ops / geometry creation |
| `TxBoundingBoxCalculator` | bounding box |
| `TxLocationCalculation` | location calculation (v12.0TR1) |
| `ITxComponent.CreateCurvesByOffsetOnBody` | offset curves on body |
| `TxRectangleCreationData` / `TxSlotCreationData` | rectangle / slot (v11) |

## UI / Viewer
| Member | Use |
| --- | --- |
| `TxWindow` | WPF window base (v11) |
| `TxObjectComboBoxControl` / `TxObjEditBoxControl` | object select/edit controls |
| `TxFrameComboBoxCtrl` / `TxFrameEditBoxCtrl` | frame controls |
| `TxNumericEditBoxControl` | numeric input |
| `TxMessageBar` / `TxMessageBox.ShowModal` | message bar / modal box |
| `TxViewersManager` | multi-viewer manager |
| `ITxDockingViewerControl` / `ITxTreeViewerControl` | docking viewer / tree command support |
| `ITxPathEditorViewer` | Path Editor viewer (v12.0TR1) |

## Human / 人机
| Member | Use |
| --- | --- |
| `TxHuman.GetPostureAngle` | posture angle |
| `GetSiteLocation` / `GetSiteLoad` / `GetSiteForce` | site location / load / force |
| `GetJointAngles` / `SetJointAngles` / `GetJointLocation` | joint angles / location |
| `ITxHumanOperationCreation` | create human operation (v11.1) |

## PLC / signals / modeling / PLC·信号·建模
| Member | Use |
| --- | --- |
| `ITxPlcRobotSignal` / `TxPlcRobotPoseSensorSignal` | robot signal / pose-sensor signal |
| `ITxPlcGenericConveyor` (`AddPosition`/`RemovePosition`/`UpdatePosition`) | generic conveyor positions |
| `ITxKinematicsModellable` (`CreateLink`/`CreateJoint`/`CoupleJoints`) | kinematics modeling (v12.1.1) |
| `ITxComponent` (modeling scope / end modeling / create device) | component modeling |

> More detail: official "Tecnomatix .NET API New Features (as of 10.1)" and per-version Developer
> Updates. Official .NET API support email: `txapi_support.plm@siemens.com`.

## See also / 参见
- Every other file in this cookbook expands one of the rows above with runnable recipes.
- `README`/`INDEX.md` — how to pick the right file.

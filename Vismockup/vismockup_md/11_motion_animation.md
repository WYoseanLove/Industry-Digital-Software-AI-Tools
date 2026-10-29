# 功能块 11：运动与动画（Motion / Path Planning / Turntable / Swept Volume）

> 对象：`VisDispMotionMngr`、`VisDispPathPlanningMngr`、`VisDispTurntableMngr`、`VisDispSweptVolMngr`
> 入口：`VisDisp3DView` 的 `MotionManager` / `PathPlanningManager` / `TurntableManager`（扫掠体由路径规划或独立管理器生成）
> 能力：播放 .vfm 动画、自动路径规划避障、转台自动旋转、生成扫掠体（swept volume）。

## VisDispMotionMngr（`VisDisp3DView.MotionManager`）

| 成员 | 签名 | 说明 |
| --- | --- | --- |
| `NumFrames` | Long (R) | 动画帧数 |
| `OpenVFM(String strVFMFile)` | void | 打开 .vfm 动画文件 |
| `Play()` | void | 播放当前动画 |

## VisDispPathPlanningMngr（`VisDisp3DView.PathPlanningManager`）

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `SetTargetParts(VisDispNodeList)` | void | 设置移动的目标零件 |
| `SetBackgroundParts(VisDispNodeList)` | void | 设置需避让的背景零件 |
| `SetInputMotionFile(String strMotionFilePath)` | void | 设置关键位姿输入（*.vfm 或 *.plmxml） |
| `SetStaticClearance(Single)` | void | 每帧最小间隙距离 |
| `SetStepSize(Single)` | void | 帧间移动步长 |
| `SetOptimizationIterations(Long)` | void | 优化迭代次数（0 关闭） |
| `SetTimeLimit(Single)` | void | 计算时间上限（分钟，0 关闭） |
| `GeneratePath()` | String | 生成路径，返回运动文件全路径 |
| `GeneratePathAndSweptVolume()` | String | 生成路径与扫掠体，返回运动文件全路径 |

## VisDispTurntableMngr（`VisDisp3DView.TurntableManager`）

属性（R/W）：`AutomaticMotionMode`(TURNTABLE_MOTION_TYPE)、`ImmediateRotation`(Bool)、`PerformFitAll`(Bool)、`AutomaticMotion`(Bool)、`RotationDirection`(TURNTABLE_ROTATION_DIRECTION)。
方法：`StartRotation()`、`StopRotation()`、`FitAll()`。

## VisDispSweptVolMngr

| 方法 | 说明 |
| --- | --- |
| `SetInputMotionFile(String)` | 生成动态扫掠体的输入运动文件（*.vfm/*.plmxml） |
| `SetStaticParts(VisDispNodeList)` | 生成静态“shrink wrap”扫掠体的输入零件（传 0 清空） |
| `SetChordal(Single)` | 输出质量：0.050 低 / 0.025 中 / 0.001 高 |
| `SetOutputSweptVolumeName(String)` | 输出扫掠体名称 |
| `SetOutputTransparency(Single)` | 透明度：1.0 不透明，0.0 全透 |
| `SetColorType(SV_COLOR_TYPE)` | `COLORTYPE_SPECIFIED`（默认，自定色）/ `COLORTYPE_ARBITRARY`（自动色） |
| `SetColor(Single R, G, B)` | 设置颜色（ARBITRARY 时忽略） |
| `GenerateSweptVolume()` | 生成扫掠体并插入产品结构树 |

## C# 示例

### 播放 VFM 动画

```csharp
dynamic view = app.Documents.ActiveView;
dynamic motion = view.MotionManager;
motion.OpenVFM(@"C:\motion\open_door.vfm");
Console.WriteLine($"帧数：{motion.NumFrames}");
motion.Play();
```

### 转台自动旋转

```csharp
dynamic tt = view.TurntableManager;
tt.PerformFitAll = true;
tt.AutomaticMotion = true;
tt.StartRotation();
// ... 展示一段时间后
tt.StopRotation();
```

### 路径规划生成运动文件

```csharp
dynamic pp = view.PathPlanningManager;
pp.SetTargetParts(targetNodeList);       // VisDispNodeList
pp.SetBackgroundParts(bgNodeList);
pp.SetInputMotionFile(@"C:\motion\keyposes.plmxml");
pp.SetStaticClearance(2.0f);
pp.SetStepSize(5.0f);
pp.SetOptimizationIterations(50);
string outFile = pp.GeneratePath();
Console.WriteLine($"生成运动文件：{outFile}");
```

### 生成扫掠体

```csharp
dynamic sv = view.PathPlanningManager; // 若有独立 SweptVolMngr 入口则用之
dynamic svm = /* VisDispSweptVolMngr */ null;
svm.SetInputMotionFile(@"C:\motion\open_door.vfm");
svm.SetChordal(0.025f);                 // 中等质量
svm.SetOutputSweptVolumeName("DoorSweep");
svm.SetColorType(VISAUTOMATIONLib.SV_COLOR_TYPE.COLORTYPE_SPECIFIED);
svm.SetColor(1.0f, 0.5f, 0.0f);
svm.SetOutputTransparency(0.5f);
svm.GenerateSweptVolume();
```

## 给代码生成模型的提示

- 步长/间隙/透明度/颜色分量均为 `Single`（`float`）。
- 路径规划：`SetOptimizationIterations(0)` 关闭优化、`SetTimeLimit(0)` 关闭时限。
- 扫掠体质量 `SetChordal` 越小越精细（0.001 高、0.050 低）。
- 转台旋转需 `AutomaticMotion=true` 后再 `StartRotation()`。
- 运动输入文件支持 `*.vfm` 与 `*.plmxml`。

## 官方 Samples 转写（C#）

### SweptVolumeExample / SweptVolumeMultiExample —— 生成扫掠体

用途：指定静态零件、弦高精度、输出名，由运动生成扫掠体并导出。

```csharp
dynamic svMgr = view.SweptVolumeManager;
svMgr.SetStaticParts(staticNodeList);          // 静态零件
svMgr.SetChordal(0.010f);                       // 弦高，越小越精细
svMgr.SetInputMotionFile(@"C:\motion\path.vfm");
svMgr.SetOutputSweptVolumeName("Swept_1");
svMgr.GenerateSweptVolume();

// 导出生成的扫掠体
dynamic doc = visApp.Documents.ActiveDocument();
int last = doc.NumHierarchies - 1;
doc.ExportEx(0 /*SAVE_TYPE.DIRECTMODEL*/, @"C:\out\swept.jt", null, last);
```

### PathPlanningExample —— 自动路径规划

用途：设置目标/背景零件、静态间隙、步长与优化参数，生成无碰撞路径（可同时生成扫掠体）。

```csharp
dynamic ppMgr = view.PathPlanningManager;
ppMgr.SetTargetParts(targetNodeList);      // 被移动件
ppMgr.SetBackgroundParts(bgNodeList);      // 障碍物
ppMgr.SetInputMotionFile(@"C:\motion\start.vfm");
ppMgr.SetStaticClearance(2.0f);            // 静态安全间隙
ppMgr.SetStepSize(5.0f);
ppMgr.SetOptimizationIterations(0);        // 0=关闭优化
ppMgr.SetTimeLimit(0);                      // 0=无时限
ppMgr.GeneratePath();                      // 仅路径
// 或 ppMgr.GeneratePathAndSweptVolume();  // 路径 + 扫掠体
```

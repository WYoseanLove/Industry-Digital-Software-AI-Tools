# 功能块 06：剖切（Cross Sections）

> 对象：`VisDispSectionMngr`、`VisDispSection`、`VisDispSectionSeries`、`VisDispSectionGridSettings`
> 入口：`VisDisp3DView.SectionManager`（官方链路中经 3D 视图取剖切管理器）
> 能力：创建单个截面/系列、裁剪状态、封盖、剖面线、网格、发送到 2D/3D。

## VisDispSectionMngr — 常用方法

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `CreateSection(Single Offset, Single NormalX, Single NormalY, Single NormalZ)` | VisDispSection | 按偏移和法向量创建截面 |
| `CreateSeries(p1x,p1y,p1z, p2x,p2y,p2z, Single Spacing, Long NumSections)` | VisDispSectionSeries | 在两点连线上创建截面系列。Spacing=0 由 NumSections 决定；NumSections=0 由 Spacing 决定 |
| `DeleteAllSections()` | void | 删除活动视图所有截面 |
| `SendAllSectionsTo3D()` | VisDisp3DView | 生成仅含全部截面的新 3D 视图 |

### VisDispSectionMngr — 常用属性（均 R/W）

`ShowBorders`、`DrawSectionLines`、`SectionLineColor`(VisDispColor)、`SectionLineWidth`(Long)、`ActiveSectionColor`、`InactiveSectionColor`、`EnableCapping`、`CapSolidsOnly`、`CappingDefaultColor`、`CapUsingPartColors`、`EnableHatching`、`HatchSpacing`(Single)、`HatchColor`、`ShowClippedAsSolid/Tessellated/Transparent`、`EnableMaterialThickness`、`MTDefaultThickness`(Single)、`GridSettings`(VisDispSectionGridSettings)。

## VisDispSection — 单截面

| 成员 | 类型/签名 | 说明 |
| --- | --- | --- |
| `Offset` | Single (R/W) | 沿法向到原点距离 |
| `Name` | String (R/W) | 名称 |
| `Clipping` | CLIP_STATE (R/W) | 裁剪状态：`CS_CLIP_NONE/NEAR/FAR/BOTH` |
| `SectionLineColor` / `SectionLineWidth` | VisDispColor / Long | 剖面线颜色/宽度 |
| `SendTo2D` / `SendTo3D` | VisDisp2DView / VisDisp3DView (R) | 生成仅含此截面的新视图 |
| `Select()` | void | 选中此截面 |
| `SetCameraToNormal()` | void | 相机对准法向并选中 |
| `Delete()` | void | 删除此截面 |
| `GetNormal(out NX, out NY, out NZ)` | void | 读法向量（3 个 Single） |
| `SetNormal(Single NX, NY, NZ)` | void | 设法向量 |
| `GetRange(out MinOffset, out MaxOffset)` | void | 有效偏移范围（基于可见部分 BBox） |

## VisDispSectionSeries — 截面系列

属性：`Spacing`(Single)、`NumSections`(Long)、`Name`(String)。
方法：`Delete()`、`SetCameraToNormal()`、`SendTo2D()`、`SendTo3D()`、`Select()`、`GetPointOne/SetPointOne`、`GetPointTwo/SetPointTwo`（[out] 或 Single 参数）。

## VisDispSectionGridSettings

属性（R/W）：`ShowGrid`(Bool)、`GridSpacing`(Single)、`GridlineWidth`(Long)、`GridlineColor`(VisDispColor)、`ShowLabels`(Bool)、`LabelSize`(Long)、`LabelColor`(VisDispColor)。

## C# 示例

### 创建一个沿 X 轴的截面并对准相机

```csharp
dynamic view = app.Documents.ActiveView;
dynamic secMgr = view.SectionManager;

dynamic sec = secMgr.CreateSection(0.0f, 1.0f, 0.0f, 0.0f); // Offset=0, 法向=(1,0,0)
sec.Name = "X-Cut";
sec.Clipping = VISAUTOMATIONLib.CLIP_STATE.CS_CLIP_NEAR;    // 裁掉近侧
sec.SetCameraToNormal();
```

### 读取截面有效偏移范围（[out]）

```csharp
using System.Reflection;
object minOff = null, maxOff = null;
object[] args = { minOff, maxOff };
var pm = new ParameterModifier(2); pm[0] = pm[1] = true;
((object)sec).GetType().InvokeMember("GetRange", BindingFlags.InvokeMethod,
    null, sec, args, new[] { pm }, null, null);
Console.WriteLine($"Offset 范围: {args[0]} ~ {args[1]}");
```

### 创建截面系列

```csharp
dynamic series = secMgr.CreateSeries(
    0f,0f,0f,  100f,0f,0f,   // 两点连线（沿 X）
    10f,       0);           // 间距 10，NumSections=0 表示由间距决定
series.Name = "X-Series";
```

### 打开封盖并设置剖面线

```csharp
secMgr.EnableCapping = true;
secMgr.CapUsingPartColors = true;
secMgr.EnableHatching = true;
secMgr.HatchSpacing = 2.0f;
```

## 给代码生成模型的提示

- 法向量分量与 `Offset`、`Spacing` 均为 `Single`（`float`），写成 `1.0f`。
- `CreateSeries` 的 `Spacing` 与 `NumSections` 二选一置 0，让另一个自动决定。
- 裁剪状态用 `CLIP_STATE`：`CS_CLIP_NONE/NEAR/FAR/BOTH`。
- `GetNormal`/`GetRange`/`GetPointOne`/`GetPointTwo` 是 `[out]`，后期绑定用反射。
- 删除全部截面用管理器 `DeleteAllSections()`，删除单个用 `section.Delete()`。

## 官方 Samples 转写（C#）

### 3DCrossSection —— 创建截面、读法向、切换显示选项

用途：由原点偏移与法向 (nx,ny,nz) 创建截面，并读取/设置网格、截面线、材料厚度、封盖、剖面线。

```csharp
dynamic secMgr = view.SectionManager;

// 创建截面：offset=0, 法向 (1,0,0)
dynamic section = secMgr.CreateSection(0.0f, 1.0f, 0.0f, 0.0f);
section.Select();

// 切换全局/单截面显示选项
secMgr.GridSettings.ShowGrid = true;
secMgr.DrawSectionLines = true;
secMgr.EnableMaterialThickness = true;
secMgr.EnableCapping = true;
secMgr.EnableHatching = true;

// 读取法向（[out] 3 个 float，后期绑定用反射）
using System.Reflection;
object[] nrm = new object[3];
var mods = new ParameterModifier(3);
mods[0] = mods[1] = mods[2] = true;
section.GetType().InvokeMember("GetNormal",
    BindingFlags.InvokeMethod, null, section, nrm,
    new[] { mods }, null, null);

// 删除全部
secMgr.DeleteAllSections();
```

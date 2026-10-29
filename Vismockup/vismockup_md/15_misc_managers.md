# 功能块 15：其他管理器（轮廓捕获 / CAE / 3D 对比 / 技术插图与组合 / 资产）

> 对象：`VisDispOutlineMngr`、`VisDispCAEMngr`(+`VisDispCAEAnnotation(List)`)、`VisDisp3DCompareMngr`、
> `VisDispTechIllustrationView(2)`、`VisDispTechPortfolioView(2)`、`VisDispAsset(2)(List)`、`VisDispStringContainer`
> 说明：技术插图/组合/资产相关能力**主要面向 Teamcenter Publish 集成**，独立 Vismockup 一般用不到；此处仅列关键接口供需要时参考。

## VisDispOutlineMngr（`DispVisApp.OutlineManager` / `VisDisp3DView.OutlineManager`）

轮廓/线条图捕获。

| 方法 | 说明 |
| --- | --- |
| `CaptureAll3DViews()` | 为所有 3D 视图创建轮廓图 |
| `CaptureCurrent3DView()` | 为当前 3D 视图创建轮廓图（新建 2D 文档） |
| `CaptureCurrent3DViewToFile(String strFileName)` | 轮廓输出到 CGM 文件 |
| `SetFeatureAngle(Single 0~180)` | 相邻面法向夹角超过该值才画边 |
| `SetLineThickness(Single, PAGE_EXTENTS_UNITS)` | 线宽 |
| `SetShowRoundedEdges(Boolean)` | 是否画圆角边 |
| `SetRemoveHiddenLines(Boolean)` | 是否去隐藏线 |
| `SetPreserveColors(Boolean)` | 是否保留零件颜色 |
| `SetUseParasolidBRep(Boolean)` | 用 Parasolid BRep 生成更精确轮廓 |
| `SetHalos(Boolean, Single, PAGE_EXTENTS_UNITS)` | 引线与零件线交叉处加光晕断开 |
| `SetBackgroundColorOverride(Boolean, R, G, B)` | 覆盖 2D 背景色 |

## VisDispCAEMngr（`VisDisp3DView.CAEManager`）

| 成员 | 返回 | 说明 |
| --- | --- | --- |
| `VisibleAnnotations()` | VisDispCAEAnnotationList | 活动视图可见的 CAE 注释 |

- `VisDispCAEAnnotation`：`Title`(R)、`Identifier`(R)、`Result`(R)。
- `VisDispCAEAnnotationList`：`NumAnnotations`(R)、`Annotation(Long Index)`(R)。

## VisDisp3DCompareMngr（`VisDisp3DView.CompareManager`）

3D 对比与并排（SxS）对比。

属性：`CompareType`(COMPARE_3D_TYPE, W)、`SxSViewCount`(Long,R)、`SxSSynchronizedViewing`(Bool,R/W)、`SxSTileAttribute`(Bool,R/W)、`Alpha`(Single,R/W 0~1)。
方法：`Compare(VisDispNodeList NodeList1, VisDispNodeList NodeList2)`、`SxSAddView(Long ViewHandle)`、`SxSRepositionWindows()`、`SxSCompare(Boolean Start)`。

## 技术插图 / 组合 / 资产（Teamcenter Publish，简述）

- `VisDispTechIllustrationView`：`InsertStencil`、`InsertPicture`、`InsertCADDocument`、`ExportAsImage(Location)`、`SaveDocument(Location)`、`AssetList`、`ActivePage`、`NumPages`。
- `VisDispTechPortfolioView`：`AddIllustration(TECHDOCTYPE, name, id)`、`DeleteIllustration(id)`、`PublishToHTML(Location, DisplayErrors)`、`PublishToPDF(Location, PUBTYPE, DisplayErrors)`、`SavePortfolio(Location)`。
  - `PUBTYPE`：`PUBTYPE_PACKAGE` / `PUBTYPE_SINGLE` / `PUBTYPE_ZIPFILE`。
  - `TECHDOCTYPE`：`TECHDOC_GENERIC` / `TECHDOC_HEADERFOOTER` / `TECHDOC_CONTAINER` / `TECHDOC_PLACEHOLDER`。
- `VisDispAsset` / `VisDispAsset2` / `VisDispAssetList`：资产属性、绑定/提交（`Commit(COMMIT_TYPE)`）、`Populate*`（Teamcenter 专用）。
- `VisDispStringContainer`：字符串容器工具（`AddString`、`GetString(out)`、`GetStringCount(out)`）。

## C# 示例

### 当前 3D 视图生成轮廓图

```csharp
dynamic view = app.Documents.ActiveView;
dynamic outline = view.OutlineManager;
outline.SetFeatureAngle(30.0f);
outline.SetRemoveHiddenLines(true);
outline.SetPreserveColors(true);
outline.CaptureCurrent3DViewToFile(@"C:\out\outline.cgm");
```

### 两组零件做 3D 对比

```csharp
dynamic cmp = view.CompareManager;
cmp.CompareType = VISAUTOMATIONLib.COMPARE_3D_TYPE.TRICOLOR /*示例*/;
cmp.Alpha = 0.5f;
cmp.Compare(nodeListA, nodeListB);
```

### 读取可见 CAE 注释

```csharp
dynamic cae = view.CAEManager;
dynamic anns = cae.VisibleAnnotations();
for (int i = 0; i < anns.NumAnnotations; i++)
{
    dynamic a = anns.Annotation(i);
    Console.WriteLine($"{a.Title}: {a.Result}");
}
```

## 给代码生成模型的提示

- 轮廓 `SetFeatureAngle` 取值 0~180 度；线宽/光晕带 `PAGE_EXTENTS_UNITS` 单位参数。
- 3D 对比 `Compare` 的效果取决于先设的 `CompareType`；并排对比用 `SxSAddView` + `SxSCompare(true)`。
- 技术插图/组合/资产多为 Teamcenter Publish 场景，独立 Vismockup 自动化一般不用；如需使用，`PublishToPDF` 用 `PUBTYPE` 控制输出形态。
- 具体枚举值（`COMPARE_3D_TYPE`、`PAGE_EXTENTS_UNITS` 等）见 `ENUMS.INC`。

## 官方 Samples 转写（C#）

### OutlineExample —— 为当前/全部视图生成轮廓

用途：配置特征角、线宽、圆角边、隐藏线、保留颜色，对当前或全部 3D 视图捕获轮廓。轮廓管理器为应用级 `DispVisApp.OutlineManager`。

```csharp
dynamic outMgr = visApp.OutlineManager;
outMgr.SetFeatureAngle(15.0);       // 特征角 0~180
outMgr.SetLineThickness(0.0, 0);    // 线宽 + PAGE_EXTENTS_UNITS
outMgr.SetShowRoundedEdges(1);
outMgr.SetRemoveHiddenLines(1);
outMgr.SetPreserveColors(1);

outMgr.CaptureCurrent3DView();      // 仅当前视图
// outMgr.CaptureAll3DViews();       // 所有视图
```

### CAETests —— CAE 管理器基本操作

用途：加载/遍历 CAE 结果。

```csharp
dynamic caeMgr = view.CAEManager;
caeMgr.LoadResults(@"C:\cae\result.set");
int num = caeMgr.NumResultSets;
for (int i = 0; i < num; i++)
{
    dynamic rs = caeMgr.ResultSet(i);
    string name = rs.Name;
}
```

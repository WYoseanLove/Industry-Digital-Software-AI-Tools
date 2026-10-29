# 功能块 03：视图与相机（Views / Camera）

> 对象：`VisDispViewList`、`VisDisp3DView`、`VisDisp2DView`
> 能力：相机读写、显示/隐藏节点、适合视图、截图、按属性查找节点、各类子管理器入口。

## 对象链路

```text
VisDispDoc.ViewList → VisDispViewList
    └── .ViewByIndex(i) → VisDisp3DView / VisDisp2DView
VisDisp3DView
├── .RootNode / .AllNodes / .VisibleNodes / .SelectedNodes / .LoadedNodes → 节点
├── .SnapShotManager / .PMIManager / .Section...（见各功能块）
├── .MeasurementManager / .ClearanceManager / .GroupManager
├── .TurntableManager / .PathPlanningManager / .CompareManager
├── .Markup3DManager / .AppearanceSysManager / .CAEManager
└── .LayerFilterMngr / .MotionManager / .OutlineManager
```

## VisDispViewList

| 成员 | 类型 | 说明 |
| --- | --- | --- |
| `NumViews` | Long (R) | 视图数 |
| `ViewByIndex(Long Index)` | Object (R) | 按索引取视图 |
| `ViewByHandle(Long viewHandle)` | Object (R) | 按句柄取视图 |
| `DocType` | DOC_TYPE (R) | 文档类型 |

## VisDisp3DView — 关键属性

| 属性 | 类型 | 读写 | 说明 |
| --- | --- | --- | --- |
| `ViewHandle` | Long | R | 视图句柄 |
| `Title` | String | R/W | 视图标题 |
| `RootNode` | VisDisp3DNode | R | 根节点 |
| `AllNodes` / `VisibleNodes` / `LoadedNodes` | VisDispNodeList | R | 全部/可见/已加载节点 |
| `SelectedNodes` | VisDispNodeList | R/W | 选中节点（可读可设置选中） |
| `NumVisibleNodes` / `NumLoadedNodes` / `NumSelectedNodes` | Long | R | 计数 |
| `BackGroundColor` / `SelectionColor` | VisDispColor | R/W | 背景/选择色 |
| `ModelUnits` | MODEL_UNITS | R | 当前单位 |
| `SelectionFilter` | PickFilterState | R/W | 选择过滤器 |
| `StillLODQuality` | Single | R/W | LOD 质量 |
| `DrawTrihedron` | Boolean | R/W | 三维坐标轴显示 |
| `Document` | VisDispDoc | R | 反向取所属文档 |

各子管理器属性：`SnapShotManager`、`PMIManager`、`MotionManager`、`MeasurementManager`、`ClearanceManager`、`PathPlanningManager`、`GroupManager`、`TurntableManager`、`CompareManager`、`AppearanceSysManager`、`CAEManager`、`Markup3DManager`、`LayerFilterMngr`、`OutlineManager`。

## VisDisp3DView — 关键方法

| 方法 | 说明 |
| --- | --- |
| `AllNodesOn()` / `AllNodesOff()` | 全部显示 / 全部隐藏 |
| `SetNodesVisible(VisDispNodeList)` / `SetNodesInVisible(VisDispNodeList)` | 批量显示 / 隐藏 |
| `SelectVisibleNodes()` / `DeSelectAllNodes()` | 选中所有可见 / 取消全部选择 |
| `FitAll()` | 适合全部可见节点 |
| `GetCameraPosition(out UpVec, out LookAtVec, out LookFromPt)` | 读相机（各为 3 个 float 数组） |
| `SetCameraPosition(UpVec, LookAtVec, LookFromPt)` | 设相机 |
| `CaptureImage(String strLocation)` | 截图到文件（.jpg/.bmp/.png/.ps） |
| `CaptureImage2(String strLocation, Boolean bTransparent)` | 截图，PNG 可透明背景 |
| `CaptureImageTo2D()` | 截图并新建 2D 视图 |
| `GetNodeFromCADID(String strCADID, out VisDisp3DNode)` | 按 CADID 取节点 |
| `GetVisibleBBox(out Min, out Max)` | 可见部分包围盒（各 3 个 float） |
| `Find(INPUT_TYPE, FIND_NODE_TYPE, strPropName, COMPARE_OP, PropValue1, PropValue2, out OutNodeList)` | 按属性查找节点 |
| `FindInList(InNodeList, FIND_NODE_TYPE, strPropName, COMPARE_OP, PropValue1, PropValue2, out OutNodeList)` | 在给定列表内查找 |
| `UpdateView()` / `SetActive()` | 刷新 / 设为活动视图 |
| `SaveViewingPrefs(String vprFilePathName)` | 保存 .vpr 视图偏好 |

### Find 相关枚举

- `INPUT_TYPE`：`ALL_PARTS`, `VISIBLE_PARTS`, `LOADED_PARTS`, `SELECTED_PARTS`
- `FIND_NODE_TYPE`：`PARTS`, `ASSEMBLIES`, `PARTS_AND_ASSEMBLIES`
- `COMPARE_OP`：`LESS_THAN`, `LESS_THAN_EQUAL`, `EQUAL`, `GREATER_THAN`, `GREATER_THAN_EQUAL`, `NOT_EQUAL`, `RANGE`

## VisDisp2DView（简要）

属性：`ViewHandle`、`Document`、`NumLayers`、`ActiveLayer`、`LayerVisibility`、`BackGroundColor`、`Title`、`PageNumber`、`NumPages`、`Monocolor`。
方法：`Pan(dx,dy)`、`Zoom(IsAbsolute,dz)`、`Rotate(IsAbsolute,deg)`、`FitAll()`、`UpdateView()`、`SetActive()`。

## C# 示例

### 适合视图 + 截图

```csharp
dynamic view = app.Documents.ActiveView;   // VisDisp3DView
view.AllNodesOn();
view.FitAll();
view.CaptureImage2(@"C:\out\snap.png", true); // PNG 透明背景
```

### 读写相机（[out] 参数，后期绑定用反射）

```csharp
using System.Reflection;

object up = null, lookAt = null, lookFrom = null;
object[] args = { up, lookAt, lookFrom };
var pm = new ParameterModifier(3); pm[0] = pm[1] = pm[2] = true;

((object)view).GetType().InvokeMember("GetCameraPosition",
    BindingFlags.InvokeMethod, null, view, args, new[] { pm }, null, null);

// args[0]=UpVec, args[1]=LookAtVec, args[2]=LookFromPt（各为 3 元素数组）
double[] lookFromPt = ((object[])args[2]).Select(Convert.ToDouble).ToArray();

// 回写相机
view.SetCameraPosition(args[0], args[1], args[2]);
```

> 若使用早期绑定（引用 `VISAUTOMATIONLib`），可直接 `view.GetCameraPosition(out up, out lookAt, out lookFrom);`。

### 按属性查找节点

```csharp
using System.Reflection;
object outList = null;
object[] a = {
    VISAUTOMATIONLib.INPUT_TYPE.VISIBLE_PARTS,
    VISAUTOMATIONLib.FIND_NODE_TYPE.PARTS,
    "PartNumber",
    VISAUTOMATIONLib.COMPARE_OP.EQUAL,
    "12345", null, outList
};
var pm = new ParameterModifier(7); pm[6] = true;
((object)view).GetType().InvokeMember("Find", BindingFlags.InvokeMethod,
    null, view, a, new[] { pm }, null, null);
dynamic found = a[6];  // VisDispNodeList
Console.WriteLine($"匹配 {found.NumNodes} 个节点");
```

## 给代码生成模型的提示

- 相机三要素：`UpVec`、`LookAtVec` 为方向向量，`LookFromPt` 为眼点坐标，均 3 元素。
- `[out]` 方法（`GetCameraPosition`/`GetVisibleBBox`/`GetNodeFromCADID`/`Find`）后期绑定需反射 `ParameterModifier`，早期绑定用 `out`。
- 截图优先 `CaptureImage2`（可控透明）；文件类型由扩展名决定。
- 修改可见性后调用 `FitAll()` 再截图，效果更稳定。

## 官方 Samples 转写（C#）

### ExactCamera —— 用眼点/目标点/上向量精确设置相机

用途：由眼点 `E`、注视点 `F`、上向量 `U` 计算相机。注意 `LookAtVec = F - E`（方向向量，非坐标）。

```csharp
dynamic view = docs.ActiveView;

double ex = 0.0, ey = -7353.5, ez = 1320.08;   // 眼点
double fx = 0.0, fy = 0.0,     fz = 1320.8;     // 注视点
double ux = 0.0, uy = 0.0,     uz = 1.0;        // 上向量

var eyePt     = new object[] { ex, ey, ez };
var lookAtVec = new object[] { fx - ex, fy - ey, fz - ez };
var upVec     = new object[] { ux, uy, uz };

view.SetCameraPosition(upVec, lookAtVec, eyePt);
view.UpdateView();
```

### IsometricView —— 切换等轴测视角

```csharp
view.SetStandardView(7);   // 标准视枚举，7=Isometric（值见 ENUMS.INC）
view.FitAll();
view.UpdateView();
```

### FindExample —— 按属性查找节点并隔离显示

用途：`Find(inputType, nodeType, propName, compOp, val1, val2)` 返回匹配的 `VisDispNodeList`；再用 `GetNodeFromCADID` 定位单个节点。inputType: 0=全部/1=已载入/2=可见/3=选中；nodeType: 0=仅零件/1=仅装配/2=两者；compOp: 0=`<`/1=`>`/2=`=`/3=`!=`/4=`<=`/5=`>=`/6=范围。

```csharp
// 查找 Name 匹配 "*" 的所有零件
dynamic nodeList = view.Find(0, 0, "Name", 2, "*", "");
int n = nodeList.NumNodes;
for (int i = 0; i < n; i++)
{
    dynamic node = nodeList.Node(i);
    string cadid = node.CADID;
    // 隔离显示某个节点
    dynamic hit = view.GetNodeFromCADID(cadid);
    view.AllNodesOff();
    hit.Visible = 1;
    view.FitAll();
}
```

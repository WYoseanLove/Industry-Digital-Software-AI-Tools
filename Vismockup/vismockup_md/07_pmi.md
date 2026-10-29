# 功能块 07：PMI（产品制造信息）

> 对象：`VisDispPMIMngr`、`VisDispPMIQuery`、`VisDispPMIEntity`、`VisDispPMIList`
> 入口：`VisDisp3DView.PMIManager`
> 能力：查询模型/零件/选中/可见 PMI、按类型或属性筛选、显示/隐藏/选中、着色、Model View 相关。

## VisDispPMIMngr

| 成员 | 类型/签名 | 说明 |
| --- | --- | --- |
| `PMIQuery` | VisDispPMIQuery (R) | 查询对象 |
| `PMIDisplayMode` | PMIGUIState (W) | 设置 PMI 显示状态 |
| `PMIGUIState` | Long (R) | 读取 PMI GUI 状态 |
| `ExportDisclosureAsPLMXML(String strFilePath)` | void | 导出调色板中的 Model View 到 PLMXML |

## VisDispPMIQuery（结果为 VisDispPMIList）

> **绑定形态（务必遵守）**：下表方法在 IDL 里把结果声明为最后一个 `[out] VisDispPMIList` 参数，但它同时是
> `retval`——**用 late-bound(dynamic) 调用时，结果是方法的【直接返回值】**（已实测 `GetAllPMIOnPart`/`GetAllPMIInModel`
> 均如此）。因此**首选**：`dynamic list = query.方法(...);`。**只用反射 `[out]`+`ParameterModifier` 读 `args[..]` 会拿到
> `null`**（args 不被回填，结果在返回值里），这正是“选中却 0 个 PMI / PMI 显示不出来”的根因。稳健写法见下方 `TryGetPmiList`。

| 方法 | 说明 |
| --- | --- |
| `GetAllPMIInModel(out VisDispPMIList List)` | 模型中全部 PMI |
| `GetAllPMIOnPart(VisDisp3DNode Node, out List)` | 指定节点上的 PMI |
| `GetSelectedPMI(out List)` / `GetVisiblePMI(out List)` | 选中 / 可见 PMI |
| `GetAssociatedPMI(String strCADID, Long FaceID, out List)` | 指定 CADID+面 的关联 PMI |
| `GetPMIOfType(PMI_TYPES pmiType, out List)` | 按类型筛选 |
| `GetPMIByMatchingAttribute(strAttrName, PMI_ATTR_TESTS, VARIANT testValue, out List)` | 按属性匹配 |
| `PopulateModelViewGallery(bool bGetPublished, bool bGetNonPublished)` | 填充 Model View 画廊 |
| `GenerateMissingModelViewImages(bool bIncludeHiDef)` | 为缺图的 Model View 生成图 |
| `SaveGeneratedImagesForPublishedModelViews()` | 将生成图保存回 Teamcenter |

- `PMI_ATTR_TESTS`：`PMI_ATTR_EXISTS`, `PMI_ATTR_IS_DEFINED`, `PMI_ATTR_EQUALS`, `PMI_ATTR_GREATER_THAN`, `PMI_ATTR_LESS_THAN`, `PMI_ATTR_BETWEEN`（BETWEEN 时 testValue 为 2 元素数组）。

## VisDispPMIEntity

属性：`Name`(R)、`Property(strPropName)`(R)、`NumProperties`(R)、`PropName(Index)`(R)、`PropValue(Index)`(R)、`Visible`(R/W)、`Selected`(R/W，源文档拼写为 `Selectede`)、`CADID`(R)、`NumFaces`(R)、`FaceID(Index)`(R)、`ContainerNode`(VisDisp3DNode,R)、`AssociatedPMI`(VisDispPMIList,R)、`Type`(PMITypes,R)、`State`(PMI_MODEL_VIEW_STATE,R)。

方法：`ColorizeGeometry(BYTE R, G, B)`、`UncolorizeGeometry()`、`Select()`、`Activate()`、`Unselect()`。

## VisDispPMIList

属性：`NumPMIEntities`(R)、`PMIEntity(Index)`(R)。
方法：`Remove(Index)`、`Show()`、`Hide()`、`Select()`、`Deselect()`、`Sort(strAttrName)`、`AppendList(list)`、`AppendEntity(entity)`、`IntersectList(list)`、`ComplementList(list)`、`GetContainingModelViews(out PMIOutList)`。

## C# 示例

### 获取全部 PMI 并打印名称（首选直接返回值）

```csharp
dynamic view  = app.Documents.ActiveView;
dynamic query = view.PMIManager.PMIQuery;

// late-bound 下结果就是方法的直接返回值；不要只用 [out] 反射读 args（会得到 null）。
dynamic pmiList = query.GetAllPMIInModel();
for (int i = 0; i < (int)pmiList.NumPMIEntities; i++)
{
    dynamic e = pmiList.PMIEntity(i);
    Console.WriteLine($"{e.Name} (type={e.Type}, faces={e.NumFaces})");
}
```

### 稳健取列表：先直接返回值，为 null 再退回 [out]（任意 Get*PMI* 通用）

```csharp
using System.Reflection;

// 适用于 GetAllPMIInModel / GetAllPMIOnPart(node) / GetSelectedPMI / GetVisiblePMI / GetPMIOfType(type) 等。
static dynamic TryGetPmiList(dynamic query, string method, params object[] leadingArgs)
{
    // 形态 A：直接返回值（late-bound 首选，已实测有效）。
    try
    {
        object ret = ((object)query).GetType().InvokeMember(method,
            BindingFlags.InvokeMethod, null, query, leadingArgs, null, null, null);
        if (ret != null) return ret;
    }
    catch { }

    // 形态 B：最后一个 [out] 参数 + ParameterModifier；结果落在 args[last] 或返回值里。
    try
    {
        object[] args = new object[leadingArgs.Length + 1];
        System.Array.Copy(leadingArgs, args, leadingArgs.Length);
        var pm = new ParameterModifier(args.Length); pm[args.Length - 1] = true;
        object ret = ((object)query).GetType().InvokeMember(method,
            BindingFlags.InvokeMethod, null, query, args, new[] { pm }, null, null);
        return args[args.Length - 1] ?? ret;
    }
    catch { return null; }
}
```

### 显示选中零件的 PMI（最常见；选中装配/分组时递归下钻）

```csharp
dynamic view  = app.Documents.ActiveView;
dynamic query = view.PMIManager.PMIQuery;
dynamic sel   = view.SelectedNodes;
int selCount  = (sel == null) ? 0 : (int)sel.NumNodes;   // 0 => 提示先选零件，不要放大到整模型

int total = 0;
for (int i = 0; i < selCount; i++)
    total += ShowPmiOnNode(query, sel.Node(i));          // 递归收集并显示
view.UpdateView();                                        // 刷新，Show() 才可见

// 当前节点取到 PMI 就显示并停止下钻；否则递归子节点（用户常选装配/分组）。
static int ShowPmiOnNode(dynamic query, dynamic node)
{
    if (node == null) return 0;
    dynamic list = TryGetPmiList(query, "GetAllPMIOnPart", node);
    int cnt = 0; try { cnt = (list == null) ? 0 : (int)list.NumPMIEntities; } catch { cnt = 0; }
    if (cnt > 0) { list.Show(); return cnt; }             // 收集并 STOP

    dynamic children = null; try { children = node.Children; } catch { }
    int n = 0; try { if (children != null) n = (int)children.NumNodes; } catch { }
    int sum = 0;
    for (int c = 0; c < n; c++) sum += ShowPmiOnNode(query, children.Node(c));
    return sum;
}
```

> 若查到 PMI 数量 > 0 但画面看不到，是视图的 PMI 显示总开关关闭：设置 `view.PMIManager.PMIDisplayMode`
> （`PMIGUIState`，枚举见 ENUMS.INC）打开显示，或提示用户在 UI 中开启 PMI 显示。

### 按类型筛选并全部显示

```csharp
object list = null;
object[] args = { VISAUTOMATIONLib.PMI_TYPES.DIMENSION /*示例*/, list };
var pm = new ParameterModifier(2); pm[1] = true;
((object)query).GetType().InvokeMember("GetPMIOfType",
    BindingFlags.InvokeMethod, null, query, args, new[] { pm }, null, null);
dynamic dims = args[1] ?? query.GetPMIOfType(VISAUTOMATIONLib.PMI_TYPES.DIMENSION);  // 直接返回值兜底
dims.Show();        // 显示这批 PMI
```

### 给一个 PMI 实体着色

```csharp
dynamic e = pmiList.PMIEntity(0);
e.ColorizeGeometry((byte)255, (byte)0, (byte)0);  // 关联几何标红
e.Select();
```


## 给代码生成模型的提示

- **关键（务必遵守）**：所有 `Get*PMI*` 方法的结果在 late-bound(dynamic) 下是方法的**直接返回值**
  （`dynamic list = query.GetAllPMIOnPart(node);`），因为 IDL 里那个 `[out] VisDispPMIList` 同时是 `retval`。
  **只用反射 `[out]`+`ParameterModifier` 读 `args[..]` 会得到 `null`**（结果不在 args 里，在返回值里），
  这会造成“选中却 0 个 PMI / PMI 显示不出来”。稳健写法：先直接返回值，为 null 再退回 `[out]` 反射并读
  `args[last] ?? 返回值`（见 `TryGetPmiList`）。
- **范围要对齐**：选中零件用 `GetAllPMIOnPart(node)`；已选中的 PMI 用 `GetSelectedPMI()`；可见用 `GetVisiblePMI()`；
  整模型才用 `GetAllPMIInModel()`。**不要**把“选中零件”悄悄放大成整模型；`SelectedNodes.NumNodes==0` 时提示先选零件。
- 用户常选**装配/分组**节点，PMI 挂在其下叶子零件上：需递归 `node.Children`，“当前节点取到 PMI 就显示并 STOP，
  否则下钻子节点”。显示后调用 `view.UpdateView()` 刷新。
- 集合索引 `PMIEntity(i)` 为方法式索引器。
- `ColorizeGeometry` 参数是 `BYTE`（0~255），与 `VisDispColor` 的 0.0~1.0 不同。
- 实体“选中”属性源文档拼写为 `Selectede`；用方法 `Select()/Unselect()` 更稳妥。
- `PMI_TYPES`/`PMITypes` 具体值见 ENUMS.INC。

## 官方 Samples 转写（C#）

### PMIExample1 —— 列举/显示/隐藏模型中的全部 PMI

用途：`GetAllPMIInModel()` 取回 `VisDispPMIList`，遍历 `PMIEntity(i).Name`，并整体 `Show()/Hide()` 或单个 `.Visible`。

```csharp
dynamic pmiMgr   = view.PMIManager;
dynamic pmiQuery = pmiMgr.PMIQuery;
dynamic pmiList  = pmiQuery.GetAllPMIInModel();

int count = pmiList.NumPMIEntities;
for (int i = 0; i < count; i++)
{
    dynamic e = pmiList.PMIEntity(i);
    string name = e.Name;
}

pmiList.Show();   // 显示全部
pmiList.Hide();   // 隐藏全部
pmiList.PMIEntity(0).Visible = true;  // 单个显示
```

### PMIOfType —— 按类型查询 PMI

用途：`GetPMIOfType(pmiType)` 只取指定类型（如 17=MODEL_VIEW，0=DIMENSION，1=NOTE）。类型常量完整列表见 ENUMS.INC。

```csharp
const int PMI_TYPE_MODEL_VIEW = 17;
dynamic mvList = pmiQuery.GetPMIOfType(PMI_TYPE_MODEL_VIEW);
for (int i = 0; i < mvList.NumPMIEntities; i++)
{
    dynamic mv = mvList.PMIEntity(i);
    string name = mv.Name;
}
```

### PMItoProductView —— 将模型视图转为产品视图（快照）

用途：遍历模型视图 PMI，逐个添加快照并另存为产品视图。参见 `10_snapshot`。

```csharp
dynamic snapMgr = view.SnapShotManager;
snapMgr.AddSnapShot(0);                 // 添加快照
int idx = snapMgr.NumSnapShots - 1;
snapMgr.SaveAsProductView(idx);         // 另存为产品视图
view.UpdateView();
```

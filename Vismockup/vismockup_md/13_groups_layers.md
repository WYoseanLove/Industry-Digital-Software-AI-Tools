# 功能块 13：分组与图层过滤（Groups / Layer Filters）

> 对象：`VisDispGroupMngr`、`VisDispGroup`、`VisDispLayerFilterMngr`
> 入口：`VisDisp3DView.GroupManager` / `VisDisp3DView.LayerFilterMngr`
> 能力：创建/删除零件分组、给分组指派材质、应用图层过滤（含 PMI）。

## VisDispGroupMngr

| 成员 | 签名/类型 | 说明 |
| --- | --- | --- |
| `NumGroups` | Long (R) | 分组数 |
| `GroupByIndex(Long Index)` | VisDispGroup (R) | 按索引取分组（0 基） |
| `CreateGroup(String Name, VisDispNodeList NodeList)` | → VisDispGroup | 创建分组（Name 可空串，NodeList 可 Nothing） |
| `Delete(Long Index)` | void | 删除指定分组 |

## VisDispGroup

| 成员 | 类型/签名 | 说明 |
| --- | --- | --- |
| `Name` | String (R/W) | 分组名 |
| `Enabled` | Boolean (R/W) | 是否启用 |
| `NodeList` | VisDispNodeList (R/W) | 成员节点（设 Nothing 清空） |
| `Material` | VisDispMaterial (R/W) | 分组材质（设 Nothing 清除） |
| `AddNodes(VisDispNodeList)` | void | 追加成员节点 |

## VisDispLayerFilterMngr

| 成员 | 签名 | 说明 |
| --- | --- | --- |
| `GetAvailableLayerFilters(VisDispNodeList pVisDispNodeList)` | SAFEARRAY(String) | 返回可用图层过滤器数组（传 NULL 返回全部） |
| `ApplyDefaultLayerFilter(Boolean bShowPMI, Boolean bTurnAllEnabledLeafsOn)` | void | 应用默认图层过滤器 |
| `ApplyLayerFilters(SAFEARRAY pStrArray, Boolean bShowPMI, Boolean bTurnAllEnabledLeafsOn, Boolean bUseDefaultFilterAsBackupOption)` | void | 应用指定图层过滤器 |

## C# 示例

### 创建分组并指派材质

```csharp
dynamic view = app.Documents.ActiveView;
dynamic gMgr = view.GroupManager;

// 收集要分组的节点
dynamic nodes = view.SelectedNodes;             // VisDispNodeList
dynamic grp = gMgr.CreateGroup("MyGroup", nodes);

dynamic mat = grp.Material ?? view.RootNode.Children.Node(0).BasicMaterial;
dynamic diff = mat.Diffuse; diff.Red = 0f; diff.Green = 1f; diff.Blue = 0f; mat.Diffuse = diff;
grp.Material = mat;
grp.Enabled = true;
```

### 遍历现有分组

```csharp
for (int i = 0; i < gMgr.NumGroups; i++)
{
    dynamic g = gMgr.GroupByIndex(i);
    Console.WriteLine($"{g.Name} 成员数={g.NodeList.NumNodes} 启用={g.Enabled}");
}
```

### 应用图层过滤器

```csharp
dynamic lfm = view.LayerFilterMngr;
object[] filters = (object[])lfm.GetAvailableLayerFilters(null); // 全部可用过滤器
foreach (string f in filters) Console.WriteLine(f);

// 应用默认过滤器，显示 PMI，打开所有启用叶子
lfm.ApplyDefaultLayerFilter(true, true);
```

## 给代码生成模型的提示

- `CreateGroup` 的 `Name` 可传 `""`，`NodeList` 可传 `null`（Nothing）。
- 清空分组成员/材质：把 `NodeList`/`Material` 设为 `null`。
- `GetAvailableLayerFilters(null)` 返回全部；传节点列表则只返回相关过滤器。
- `ApplyLayerFilters` 的 `pStrArray` 需传字符串数组（SAFEARRAY），可先用 `GetAvailableLayerFilters` 取名。

## 官方 Samples 转写（C#）

### Toolbox —— 获取/应用层过滤器

用途：按搜索范围（全部/选中/可见）取可用层过滤器，应用默认或多个过滤器。

```csharp
dynamic lfMgr = view.LayerFilterMngr;

// 取可用过滤器（null=全部；传 SelectedNodes/VisibleNodes 可限定范围）
Array filters = lfMgr.GetAvailableLayerFilters(null);

// 应用默认过滤器（showPMI, showAllComponents）
lfMgr.ApplyDefaultLayerFilter(true, true);

// 应用多个过滤器（传字符串 SAFEARRAY）
var names = new object[] { "Layer_A", "Layer_B" };
lfMgr.ApplyLayerFilters(names, true, true, false /*useDefaultAsBackup*/);
view.UpdateView();
```

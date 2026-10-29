# 功能块 12：间隙分析（Clearance / Interference）

> 对象：`VisDispClearanceMngr`、`VisDispClearanceResult`、`VisDispClearanceResultList`
> 入口：`VisDisp3DView.ClearanceManager`
> 能力：矩阵/选中/分组间隙分析、接触与穿透检测、结果查找、保存/加载结果、动态间隙。

## VisDispClearanceMngr — 属性（R/W）

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `ResultList` | VisDispClearanceResultList (R) | 当前结果列表 |
| `ClearanceRequirement` | Single | 可显示结果的最大距离 |
| `PenetrationCheck` | Boolean | 启用接触/穿透检测 |
| `UsePrecise` | Boolean | 使用精确几何 |
| `ContactTolerance` | Single | 0 附近判为“接触”的距离范围 |
| `ElementType` | CLEARANCE_ELEMENT_TYPE | 元素类型设置 |
| `UseLeafComponentForEndItem` | Boolean | 找不到 End Item 时用叶子组件 |
| `GenerateImages` | Boolean | 为结果生成图片 |
| `GenerateClearanceDBResults` | Boolean | 生成 ClearanceDB 结果文件 |

## VisDispClearanceMngr — 方法

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `MatrixClearance(INPUT_TYPE Scope)` | ResultList | 矩阵间隙分析 |
| `SelectedClearance(INPUT_TYPE Scope)` | ResultList | 选中间隙分析 |
| `GroupClearance(VisDispNodeList GroupOne, VisDispNodeList GroupTwo)` | ResultList | 组对组分析 |
| `SaveResultsToFile(String strFilePath)` | void | 保存结果摘要到文本 |
| `LoadResults(String FilePath)` | ResultList | 从文本加载结果 |
| `DisplayPrecision(MODEL_UNITS Units, Long DecimalPlaces)` | void | 设置显示精度 |
| `Find(Long ColumnIndex, VARIANT PropValue)` | ResultList | 按列值查找 |
| `FindByElement(VisDisp3DNode Node)` | ResultList | 查找含指定节点的结果 |
| `FindByValue(Single LowerBound, Single UpperBound)` | ResultList | 按距离范围查找 |
| `EnableDynamicClearance(Boolean)` | void | 启用/禁用动态间隙 |
| `Analyze(Long ResultIndex)` | void | 分析指定结果对 |

- `INPUT_TYPE`：`ALL_PARTS`, `VISIBLE_PARTS`, `LOADED_PARTS`, `SELECTED_PARTS`。

## VisDispClearanceResult / VisDispClearanceResultList

- `VisDispClearanceResult`：`Data`(VARIANT，字符串数组)、`NodeOne`(VisDisp3DNode)、`NodeTwo`(VisDisp3DNode)。
- `VisDispClearanceResultList`：`NumResults`(Single,R)、`Result(Single Index)`(R)、`ColumnNames`(VARIANT，字符串数组,R)。

## C# 示例

### 对可见零件做矩阵间隙分析

```csharp
dynamic view = app.Documents.ActiveView;
dynamic cMgr = view.ClearanceManager;
cMgr.UsePrecise = true;
cMgr.PenetrationCheck = true;
cMgr.ClearanceRequirement = 5.0f;      // 只显示 <=5mm 的结果
cMgr.ContactTolerance = 0.1f;

dynamic results = cMgr.MatrixClearance(VISAUTOMATIONLib.INPUT_TYPE.VISIBLE_PARTS);
Console.WriteLine($"结果数：{(int)results.NumResults}");
```

### 遍历结果与列名

```csharp
object[] cols = (object[])results.ColumnNames;
for (int i = 0; i < (int)results.NumResults; i++)
{
    dynamic r = results.Result((float)i);
    object[] data = (object[])r.Data;   // 与 ColumnNames 对应的一行字符串
    Console.WriteLine($"{r.NodeOne.PrintableName} <-> {r.NodeTwo.PrintableName}: " +
                      string.Join(", ", data));
}
```

### 保存结果并按距离范围查找

```csharp
cMgr.SaveResultsToFile(@"C:\out\clearance.txt");
dynamic tight = cMgr.FindByValue(0.0f, 1.0f);  // 0~1mm 的紧密结果
```

## 给代码生成模型的提示

- `NumResults` 与 `Result(index)` 的索引类型是 `Single`，遍历时注意 `(float)i` / `(int)NumResults` 转换。
- `Data` 与 `ColumnNames` 都是字符串 SAFEARRAY，按列对齐解析。
- 距离阈值、容差为 `Single`（`float`）。
- 分析范围用 `INPUT_TYPE`；组对组用 `GroupClearance` 传两个 `VisDispNodeList`。
- 生成图片/DB 前先设 `GenerateImages`/`GenerateClearanceDBResults`。

## 官方 Samples 转写（C#）

### GenClearanceResultsImages —— 运行间隙分析并生成结果图片

用途：设置阀值与图片选项，对选中集合跑间隙，遍历结果并导出图片。

```csharp
dynamic clrMgr = view.ClearanceManager;
clrMgr.ClearanceDistance = 5.0f;      // 间隙阀值
clrMgr.GenerateImages = true;         // 同时生成结果图片

// 对选中零件跑分析（INPUT_TYPE 3=SELECTED）
clrMgr.Compute(3);

dynamic results = clrMgr.Results;     // VisDispClearanceResultList
int num = (int)results.NumResults;
for (int i = 0; i < num; i++)
{
    dynamic r = results.Result(i);
    double d = r.Distance;
    // 图片已随分析生成，可由结果对象取图路径/导出
}
```

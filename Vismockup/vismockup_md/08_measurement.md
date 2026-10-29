# 功能块 08：测量（Measurement）

> 对象：`VisDispMeasurementMngr`、`VisDispMeasurementEntity`、`VisDispMeasurementEntity2`、`VisDispMeasurementEntityList`
> 入口：`VisDisp3DView.MeasurementManager`
> 能力：单体测量（面积/体积/质心）、两组距离、组测量、查找、最小包围盒、惯性矩。

## VisDispMeasurementMngr

| 成员 | 签名/类型 | 说明 |
| --- | --- | --- |
| `MinMax` | MEASURE_MINMAX (R/W) | 测最小或最大距离 |
| `UsePrecise` | Boolean (R/W) | 使用精确几何 |
| `DefaultDensity` | Single (R/W) | 默认密度 |
| `MassUnits` | MASS_UNITS (R/W) | 质量单位 |
| `MeasureObject(VisDisp3DNode)` | → Entity | 单个零件测量 |
| `MeasureObjectSet(VisDispNodeList)` | → Entity | 一组零件的组测量 |
| `MeasureDistance(NodeOne, NodeTwo)` | → Entity | 两零件距离 |
| `MeasureSetDistance(NodeListOne, NodeListTwo)` | → Entity | 两组零件距离 |
| `EntityByKey(Long Key)` | → Entity | 按 key 取测量 |
| `GetAllMeasurements()` | → EntityList | 全部测量 |
| `DeleteAllMeasurements()` | void | 删除全部 |
| `Find(MEASURE_TYPE, FIND_MEASURE_TYPE, COMPARE_OP, PropValue1, PropValue2)` | → EntityList | 查找 |
| `FindInList(InList, MEASURE_TYPE, FIND_MEASURE_TYPE, COMPARE_OP, PropValue1, PropValue2)` | → EntityList | 列表内查找 |

- `MEASURE_TYPE`：`MEASURE_SINGLE`, `MEASURE_DOUBLE`, `MEASURE_GROUP`, `MEASURE_PARTSETS`, `MEASURE_SINGLE_AND_GROUP`, `MEASURE_DOUBLE_AND_PARTSETS`, `MEASURE_ALL`。
- `FIND_MEASURE_TYPE`：`KEY`, `PART_NAME`, `AREA`, `VOLUME`, `DISTANCE`。
- `COMPARE_OP`：`LESS_THAN`, `LESS_THAN_EQUAL`, `EQUAL`, `GREATER_THAN`, `GREATER_THAN_EQUAL`, `NOT_EQUAL`, `RANGE`。

## VisDispMeasurementEntity（只读属性）

`Type`(MEASURE_TYPE)、`Key`(Long)、`PartName`(String)、`Area`(Single)、`Volume`(Single)、`Centroid`(VARIANT，3 个 float)、`Distance`(Single)、`MinMax`、`UsePrecise`、`NodeListOne`、`NodeListTwo`。

### VisDispMeasurementEntity2（扩展，[out] 方法）

- `GetMinBBox(out p1..p8)`：最小包围盒 8 个角点。
- `GetMinBBoxSize(out Length, out Width, out Height)`：尺寸。
- `GetMomentOfIntertia(out pPnt)`：惯性矩（XYZ）。
- `GetPrincipalAxisOfInertia(out v1, out v2, out v3)`：主惯性轴（3 个 IJK 向量）。

## VisDispMeasurementEntityList

属性：`NumEntities`(Single,R)、`EntityByIndex(Long)`(R)、`EntityByKey(Long)`(R)。
方法：`Append(entity)`、`RemoveByIndex(index)`、`RemoveByKey(key)`、`Clear()`。

## C# 示例

### 单体测量并读取面积/体积/质心

```csharp
dynamic view = app.Documents.ActiveView;
dynamic mMgr = view.MeasurementManager;
mMgr.UsePrecise = true;

dynamic node = view.RootNode.Children.Node(0);
dynamic ent = mMgr.MeasureObject(node);

Console.WriteLine($"Area={ent.Area}, Volume={ent.Volume}");
double[] c = ((object[])ent.Centroid).Select(Convert.ToDouble).ToArray(); // [x,y,z]
Console.WriteLine($"Centroid=({c[0]},{c[1]},{c[2]})");
```

### 两零件间距离

```csharp
dynamic a = view.RootNode.Children.Node(0);
dynamic b = view.RootNode.Children.Node(1);
dynamic d = mMgr.MeasureDistance(a, b);
Console.WriteLine($"Distance={d.Distance}");
```

### 查找体积大于阈值的测量

```csharp
dynamic list = mMgr.Find(
    VISAUTOMATIONLib.MEASURE_TYPE.MEASURE_ALL,
    VISAUTOMATIONLib.FIND_MEASURE_TYPE.VOLUME,
    VISAUTOMATIONLib.COMPARE_OP.GREATER_THAN,
    1000.0, null);
for (int i = 0; i < (int)list.NumEntities; i++)
    Console.WriteLine(list.EntityByIndex(i).PartName);
```

### 读取最小包围盒尺寸（Entity2，[out]）

```csharp
using System.Reflection;
object len = null, wid = null, hgt = null;
object[] args = { len, wid, hgt };
var pm = new ParameterModifier(3); pm[0] = pm[1] = pm[2] = true;
((object)ent).GetType().InvokeMember("GetMinBBoxSize",
    BindingFlags.InvokeMethod, null, ent, args, new[] { pm }, null, null);
Console.WriteLine($"L={args[0]}, W={args[1]}, H={args[2]}");
```

## 给代码生成模型的提示

- `NumEntities` 类型是 `Single`，遍历索引前转 `int`。
- 距离比较值 `PropValue1/2` 是 `VARIANT`，直接传数字即可；`RANGE` 时用两个值。
- `Centroid` 是 3 个 float 的数组；`GetMinBBox*`、`GetMomentOfIntertia` 等为 `[out]`，后期绑定用反射。
- 单体测量的 `NodeListOne` 在非 Automation 创建时可能靠 `PartName` 猜测零件。

## 官方 Samples 转写（C#）

### GetMinBBox —— 求选中零件的最小包围盒

用途：对选中节点求最小（定向）包围盒，结果为 `[out]` 参数。

```csharp
using System.Reflection;

dynamic measMgr = view.MeasurementManager;
dynamic sel = view.SelectedNodes;

object[] args = new object[] { sel, null, null, null, null, null, null };
var mods = new ParameterModifier(7);
for (int k = 1; k < 7; k++) mods[k] = true;  // 后 6 个为 min/max [out]
measMgr.GetType().InvokeMember("GetMinBBox",
    BindingFlags.InvokeMethod, null, measMgr, args,
    new[] { mods }, null, null);
// args[1..6] = minX,minY,minZ,maxX,maxY,maxZ
```

### GetMomentOfIntertia —— 计算转动惯量

```csharp
object[] args = new object[] { sel, null };
var mods = new ParameterModifier(2);
mods[1] = true;   // [out] 惯量张量/数组
measMgr.GetType().InvokeMember("GetMomentOfIntertia",
    BindingFlags.InvokeMethod, null, measMgr, args,
    new[] { mods }, null, null);
```

### MeasurementExample —— 创建两点/两体间距离测量

用途：用测量管理器创建测量实体，读取结果值。

```csharp
dynamic measMgr = view.MeasurementManager;
dynamic entity  = measMgr.CreateMeasurement();  // 创建测量实体
entity.NodeListOne = someNodeListA;
entity.NodeListTwo = someNodeListB;
entity.Compute();                               // 执行测量
double dist = entity.Distance;
```

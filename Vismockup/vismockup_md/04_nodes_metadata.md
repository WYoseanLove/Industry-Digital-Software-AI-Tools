# 功能块 04：节点与元数据（Nodes / MetaData）
# 功能块 04：节点与元数据（含焊点 Weld Point 位置/法向、连接钣金件、钣金厚度/材料）

> 对象：`VisDisp3DNode`、`VisDispNodeList`、`VisDispMetaDataList`
> 能力：遍历模型树、显示/隐藏/选择、读写变换矩阵、包围盒、物理属性、读取元数据、CADID。
> 领域：焊点位置(`Connector Location`)/法向(`Connector Normal`)、连接钣金号(`Connected Part-1..3`)、
> 钣金厚度(`MCI Gauge/Thickness [mm]`)/材料(`MCI Material Specification`)。

## VisDisp3DNode — 属性

| 属性 | 类型 | 读写 | 说明 |
| --- | --- | --- | --- |
| `IsPart` | Boolean | R | 是否为零件 |
| `IsLoaded` | Boolean | R | 是否已加载 |
| `NumChildren` | Long | R | 子节点数 |
| `NumParents` | Long | R | 父节点数（0 或 1） |
| `DataStoreLocation` | String | R | 加载来源文件路径 |
| `DataStoreName` | String | R | 加载来源文件名 |
| `PrintableName` | String | R | 友好显示名 |
| `FullName` | String | R | 全名 |
| `Visible` | Boolean | R/W | 可见性 |
| `Selected` | Boolean | R/W | 选中状态 |
| `DynamicHighlight` | Boolean | R/W | 动态高亮 |
| `Children` | VisDispNodeList | R | 子节点集合 |
| `Parent` | VisDisp3DNode | R | 父节点 |
| `MetaDataProperties` | VisDispMetaDataList | R | 元数据集合 |
| `Material` / `BasicMaterial` | VisDispMaterial | R/W | 材质（`BasicMaterial` 随会话保存） |
| `CADID` | String | R | CAD 标识 |
| `Transform` | VARIANT | R | 局部变换（16 个 double，4×4 齐次矩阵） |
| `GlobalTransformation` | VARIANT | R | 全局变换（16 个 double） |
| `BBox` | VARIANT | R | 包围盒 6 个 float：[xmin,ymin,zmin,xmax,ymax,zmax] |

## VisDisp3DNode — 方法

| 方法 | 说明 |
| --- | --- |
| `RelativeTransform(Boolean Relative, VARIANT Transform)` | 设置变换。Relative=True 相对当前位置，False 相对原始位置。Transform 为 16 个 double |
| `GetPhysicalProperties(out Area, out Volume, out Centroid)` | 面积/体积/质心（质心为 3 个 float） |
| `AllChildrenVisible(out Boolean FullVis)` | 子节点是否全部可见 |
| `RestoreDefaultMaterial()` / `RestoreDefaultBasicMaterial()` | 恢复默认材质 |

## VisDispNodeList

| 成员 | 签名/类型 | 说明 |
| --- | --- | --- |
| `NumNodes` | Long (R) | 节点数 |
| `Node(Long Index)` | VisDisp3DNode (R) | 按索引取节点 |
| `NodeType(Long Index)` | NODE_TYPE (R) | 节点类型 |
| `AppendNode(VisDisp3DNode)` | void | 追加节点 |

## VisDispMetaDataList

| 成员 | 签名 | 说明 |
| --- | --- | --- |
| `NumProperties` | Long (R) | 属性数量 |
| `GetProperty(Long Index, out strPropName, out varPropValue)` | void | 按索引取属性名和值（均 [out]） |
| `GetPropertyByName(String strPropName, out varPropValue)` | void | 按名取值（不存在返回空串） |

## C# 示例

### 递归遍历模型树

```csharp
static void Walk(dynamic node, int depth)
{
    Console.WriteLine($"{new string(' ', depth * 2)}{node.PrintableName} " +
                      $"(part={node.IsPart}, visible={node.Visible})");
    dynamic children = node.Children;
    for (int i = 0; i < children.NumNodes; i++)
        Walk(children.Node(i), depth + 1);
}

dynamic view = app.Documents.ActiveView;
Walk(view.RootNode, 0);
```

### 切换可见性 / 选择

```csharp
dynamic root = view.RootNode;
dynamic first = root.Children.Node(0);
first.Visible = false;      // 隐藏
first.Selected = true;      // 选中
```

### 读取元数据（[out] 参数，反射 + VariantWrapper）✅ 正确做法

> 这是读取焊点/零件“全部自定义属性”的正确写法。经过实测（`inspectSelectedNode` 成功、
> 旧 `Vismockup_GetSelectedWeldPointInfo` 失败）验证：`GetProperty` 的两个 `[out]` 参数是
> **VARIANT**，后期绑定时**必须用 `VariantWrapper(null)` 包装**，否则读不到任何元数据。

```csharp
using System.Reflection;
using System.Runtime.InteropServices;   // VariantWrapper

dynamic node = view.RootNode.Children.Node(0);
object metaObj = node.MetaDataProperties;
if (metaObj != null)
{
    int count = ((dynamic)metaObj).NumProperties;
    for (int i = 0; i < count; i++)
    {
        // ⚠️ 关键：两个 [out] VARIANT 必须用 VariantWrapper(null) 包装（强制 VT_BYREF|VT_VARIANT）。
        object[] args = { i, null, null };
        var pm = new ParameterModifier(3); pm[1] = true; pm[2] = true;
        metaObj.GetType().InvokeMember("GetProperty", BindingFlags.InvokeMethod,
            null, metaObj, args, new[] { pm }, null, null);

        object pname = Unwrap(args[1]);
        object pvalue = Unwrap(args[2]);
        Console.WriteLine($"{pname} = {pvalue}");
    }
}

// 解开 VariantWrapper，取出真正的返回值。
static object Unwrap(object o)
{
    VariantWrapper w = o as VariantWrapper;
    return w != null ? w.WrappedObject : o;
}
```

#### ❌ 反例（旧代码为什么读不到元数据）

```csharp
// 错误：直接传 string.Empty / null 作为 [out] VARIANT
object[] args = { i, string.Empty, null };
var pm = new ParameterModifier(3); pm[1] = true; pm[2] = true;
metaObj.GetType().InvokeMember("GetProperty", BindingFlags.InvokeMethod,
    null, metaObj, args, new[] { pm }, null, null);
Console.WriteLine($"{args[1]} = {args[2]}");   // 抛 DISP_E_BADCALLEE，进入 catch
```

原因：`null`/`string.Empty` 会被 CLR 按 `VT_BYREF|VT_EMPTY`（或固定 BSTR）封送，而 COM 被调方
要求 `VT_BYREF|VT_VARIANT`，类型不匹配 → 抛 `DISP_E_BADCALLEE`（"Invalid callee"）。若每项都套了
`try/catch`，就表现为“每个元数据项都失败、一个属性都读不到”。用 `VariantWrapper(null)` 包装即可修复。


### 读取变换矩阵与包围盒

```csharp
dynamic node = view.RootNode.Children.Node(0);
double[] m = ((object[])node.Transform).Select(Convert.ToDouble).ToArray(); // 16 个
float[] bbox = ((object[])node.BBox).Select(Convert.ToSingle).ToArray();    // 6 个
// bbox = [xmin,ymin,zmin,xmax,ymax,zmax]
```

### 读取物理属性（[out]）

```csharp
using System.Reflection;
object area = null, vol = null, centroid = null;
object[] args = { area, vol, centroid };
var pm = new ParameterModifier(3); pm[0] = pm[1] = pm[2] = true;
((object)node).GetType().InvokeMember("GetPhysicalProperties",
    BindingFlags.InvokeMethod, null, node, args, new[] { pm }, null, null);
Console.WriteLine($"Area={args[0]}, Volume={args[1]}");
```

## 给代码生成模型的提示

- `Node(index)` 是**方法式索引器**（`Node(0)`），不是 `Node[0]`（早期绑定 Interop 里可能是 `Node[i]`，后期绑定用 `Node(i)`）。
- `Transform`/`GlobalTransformation` 是 16 个 double 的 4×4 **行主**齐次矩阵；`BBox` 是 6 个 float。
- 物理属性用 `[out]`，后期绑定必须用反射 `ParameterModifier`。
- **元数据 `GetProperty` 的两个 `[out]` 参数是 VARIANT，必须用 `VariantWrapper(null)` 包装 + `Unwrap` 取值**；直接传 `string.Empty`/`null` 会抛 `DISP_E_BADCALLEE`，导致一个元数据都读不到（这是“读不全焊点属性”的根因）。
- 要读焊点/零件的**全部自定义属性**，遍历 `MetaDataProperties`（`NumProperties` + `GetProperty(i, out name, out value)`）即可，属性都在这里。
- 每个属性单独 `try/catch`，某个属性读取失败不影响其它属性。
- `DataStoreName` 常带 `_序号` 后缀，按需 `Substring(0, LastIndexOf('_'))` 清洗。
- 修改 `BasicMaterial` 会随会话保存，`Material` 将被弃用。

## 官方 Samples 转写（C#）

### BBoxTest —— 读取选中节点的包围盒

用途：遍历选中节点，读取其 `BBox`（6 个 float：minX,minY,minZ,maxX,maxY,maxZ）。`BBox` 为 `[out]`，后期绑定用反射。

```csharp
using System.Reflection;

dynamic sel = view.SelectedNodes;
for (int i = 0; i < sel.NumNodes; i++)
{
    dynamic node = sel.Node(i);
    object[] args = new object[6];
    var mods = new ParameterModifier(6);
    for (int k = 0; k < 6; k++) mods[k] = true;
    node.GetType().InvokeMember("BBox",
        BindingFlags.InvokeMethod, null, node, args,
        new[] { mods }, null, null);
    float minX = Convert.ToSingle(args[0]);
    float maxX = Convert.ToSingle(args[3]);
    // ...
}
```

### GetPropertyByName —— 按属性名读取节点元数据

```csharp
dynamic node = view.SelectedNodes.Node(0);
dynamic meta = node.MetaData;                 // VisDispMetaDataList
string value = meta.GetProperty("PartNumber"); // 按键名取值
```

### PlaceVehicle —— 用 4×4 矩阵变换节点

用途：构造 4×4 行主齐次矩阵（16 个 double），用 `RelativeTransform(bAbsolute, matrix)` 施加到节点；`GlobalTransformation` 读取当前全局变换。

```csharp
// 单位阵 + 平移 (tx,ty,tz)，行主 4x4
double tx = 0, ty = -7353.3, tz = 0;
object[] m = new object[]
{
    1,0,0,0,
    0,1,0,0,
    0,0,1,0,
    tx,ty,tz,1
};
dynamic node = view.SelectedNodes.Node(0);
node.RelativeTransform(true, m);   // true=绝对/替换
view.UpdateView();
```

### InspectSelectedNode —— 读取选中焊点的“全部属性”（实测通过）

用途：连接运行中的 Vismockup，遍历当前视图选中节点，打印基本信息、局部/全局变换、包围盒，
以及**全部元数据键值对**（焊点自定义属性都在元数据里）。关键点在于元数据 `[out]` 用 `VariantWrapper`。

```csharp
using System;
using System.Reflection;
using System.Runtime.InteropServices;   // VariantWrapper

dynamic view = app.Documents.ActiveView;   // VisDisp3DView
dynamic selected = view.SelectedNodes;      // VisDispNodeList
int count = selected.NumNodes;
for (int i = 0; i < count; i++)
{
    dynamic node = selected.Node(i);        // VisDisp3DNode（方法式索引器）

    // 基本信息（每个属性单独容错）
    PrintProp("PrintableName",      () => node.PrintableName);
    PrintProp("FullName",           () => node.FullName);
    PrintProp("DataStoreName",      () => node.DataStoreName);
    PrintProp("DataStoreLocation",  () => node.DataStoreLocation);
    PrintProp("CADID",              () => node.CADID);
    PrintProp("IsPart",             () => node.IsPart);
    PrintProp("IsLoaded",           () => node.IsLoaded);
    PrintProp("Visible",            () => node.Visible);
    PrintProp("NumChildren",        () => node.NumChildren);

    // 变换与包围盒（VARIANT 数组直接格式化）
    PrintProp("Transform",             () => FormatArray(node.Transform));
    PrintProp("GlobalTransformation",  () => FormatArray(node.GlobalTransformation));
    PrintProp("BBox",                  () => FormatArray(node.BBox));

    // 全部元数据
    DumpMetaData(node);
}

static void PrintProp(string label, Func<object> getter)
{
    object value;
    try { value = getter(); }
    catch (Exception ex) { value = "<不可用: " + ex.Message + ">"; }
    Console.WriteLine(string.Format("  {0,-20}: {1}", label, value));
}

static string FormatArray(object variant)
{
    object[] arr = variant as object[];
    if (arr != null)
        return "[" + string.Join(", ", Array.ConvertAll(arr, x => Convert.ToString(x))) + "]";
    return Convert.ToString(variant);
}

static object Unwrap(object o)
{
    VariantWrapper w = o as VariantWrapper;
    return w != null ? w.WrappedObject : o;
}

static void DumpMetaData(dynamic node)
{
    object metaObj;
    try { metaObj = node.MetaDataProperties; }
    catch (Exception ex) { Console.WriteLine("    <读取元数据失败: " + ex.Message + ">"); return; }
    if (metaObj == null) { Console.WriteLine("    (无元数据)"); return; }

    int num = ((dynamic)metaObj).NumProperties;
    for (int i = 0; i < num; i++)
    {
        try
        {
            // 两个 [out] VARIANT 必须用 VariantWrapper(null) 包装，否则 DISP_E_BADCALLEE。
            object[] args = { i, null, null };
            ParameterModifier pm = new ParameterModifier(3);
            pm[1] = true; pm[2] = true;
            metaObj.GetType().InvokeMember("GetProperty", BindingFlags.InvokeMethod,
                null, metaObj, args, new[] { pm }, null, null);
            Console.WriteLine("    " + Unwrap(args[1]) + " = " + Unwrap(args[2]));
        }
        catch (Exception ex)
        {
            Console.WriteLine("    <第 " + i + " 项读取失败: " + ex.Message + ">");
        }
    }
}
```

## 焊点（Weld Point）与钣金（Sheet-Metal）领域知识（重要，读取焊点/钣金属性时必须加载）

这些属性都保存在节点的**元数据（MetaDataProperties）**里，按上面的 `GetProperty`（`[out] VARIANT` 用
`VariantWrapper(null)` 包装）逐条读取；属性名**大小写与空格必须完全一致**。

### 1. 读取指定属性（按属性名）

- 当用户只需要**读取节点的属性信息**（例如某个指定的元数据键值）时，直接用下面的
  `GetMetaDataValue(node, "属性名")` 按名读取即可，**不需要**做任何 Connector Location /
  Connector Normal 的矩阵→位姿转换。
- ⚠️ **读取必须成功**：属性经常**不在选中节点"自身"**，而挂在其**子节点**上；键名也可能带
  多余空格或大小写差异。因此按名读取时**必须**：
  1. **先查节点自身，找不到再递归查所有子节点**（`node.Children.Node(c)`）；
  2. **键名匹配用 `Trim()` + `StringComparison.OrdinalIgnoreCase`**（去空格 + 忽略大小写），
     严格相等会导致"选中 N 个节点但 0 个成功提取"。
  3. 若 0 个成功，**递归打印首个选中节点及其子节点的全部元数据键值对**（限深 2 层），暴露真实键名。

> 说明：焊点的**位置坐标与法向**请改用节点的 `Transform`（16 元素 4×4 矩阵）直接转换，
> 见 `skill_get_weld_point_location_and_normal.md`；本功能块只负责**按名读取属性信息**，不做矩阵→位姿转换。

#### 按名读取焊点元数据（自身找不到则递归查子节点 + 键名容错）✅ 保证读取成功

```csharp
using System;
using System.Reflection;
using System.Runtime.InteropServices;   // VariantWrapper

// 先查节点自身，找不到再递归查子节点；键名 Trim + 忽略大小写。
static object GetMetaDataValue(dynamic node, string propertyName)
{
    object direct = GetMetaDataValueOnNode(node, propertyName);
    if (direct != null) return direct;

    try
    {
        dynamic children = node.Children;
        int childCount = 0;
        try { childCount = (int)children.NumNodes; } catch { childCount = 0; }
        for (int c = 0; c < childCount; c++)
        {
            object fromChild = GetMetaDataValue(children.Node(c), propertyName);
            if (fromChild != null) return fromChild;
        }
    }
    catch { /* 无子节点 */ }
    return null;
}

static object GetMetaDataValueOnNode(dynamic node, string propertyName)
{
    object metaObj;
    try { metaObj = node.MetaDataProperties; } catch { return null; }
    if (metaObj == null) return null;

    int count;
    try { count = (int)((dynamic)metaObj).NumProperties; } catch { return null; }

    int failures = 0;
    string firstError = null;
    for (int i = 0; i < count; i++)
    {
        try
        {
            object[] args = { i, null, null };
            ParameterModifier pm = new ParameterModifier(3);
            pm[1] = true; pm[2] = true;
            metaObj.GetType().InvokeMember("GetProperty", BindingFlags.InvokeMethod,
                null, metaObj, args, new[] { pm }, null, null);

            object pname = Unwrap(args[1]);
            if (pname != null)
            {
                string key = Convert.ToString(pname).Trim();  // 去空格
                if (string.Equals(key, propertyName, StringComparison.OrdinalIgnoreCase)) // 忽略大小写
                    return Unwrap(args[2]);
            }
        }
        catch (Exception ex)
        {
            // 单项失败不影响其它项，但要记录首个异常，供上层在“全部失败”时抛出真实错误信号。
            failures++;
            if (firstError == null) firstError = ex.Message;
        }
    }
    // 一项都没读到、且每一项都异常 => 静默失败，必须让上层看到，否则 auto-fix 无法触发。
    if (count > 0 && failures == count)
        throw new InvalidOperationException(
            "MetaData GetProperty failed for all " + count + " properties; first error: " + firstError);
    return null;
}
```

> ⚠️ 若不递归查子节点或用严格大小写/空格相等，就会出现"选中 N 个节点、0 个成功提取"的报错。
> 0 个成功时应递归打印首个选中节点及其子节点的全部键值对，暴露真实键名。

> 强制返回值契约（务必遵守，否则 auto-fix 永远无法触发）：
> 绝不允许用 catch 块把每一项 COM 调用的异常静默吞掉。当出现选中 N 项、但 0 项成功提取
> （即 count 大于 0 且每一项都异常或为空）时，skill 必须返回 SkillExecutionResult.Success = false，
> 并把首个被捕获的异常消息写入 Message 与 RawResult。
> 只有把真实失败信号暴露出来，执行期 auto-fix 才能读到失败并自动修复；
> 若 Success = true 且无失败文本，系统会误判为成功但空结果，修复循环会被直接跳过。
>
> 参考：上面的 GetMetaDataValueOnNode 已用 failures 与 firstError 计数并在全部失败时 throw，
> 生成的 skill 顶层应捕获该异常并转成 Success = false 的结果。

### 2. 焊点连接的钣金零件号

- 焊点对应的钣金零件号保存在元数据键 **`Connected Part-1`、`Connected Part-2`、`Connected Part-3`** 中，
  分别对应第 1/2/3 块被连接的钣金件号（一个焊点可连接 2~3 块钣金；对应键不存在时表示没有该层）。

> 当用户需求是**输出选中焊点的全部属性**并提取**板材搭接（钣金搭接）的钣金号码**时，
> 直接参考 `skill_get_weld_point_properties_and_connected_parts.md`（含递归下钻焊点组、
> `VariantWrapper(null)` 读取全部元数据、`Connected Part-1..3` 提取的完整样板），不要另行拼装。

### 3. 钣金（被连接零件）自身的属性

在对应钣金节点的元数据里读取：

- **`MCI Gauge/Thickness [mm]`** = 钣金的**厚度**（毫米）。
- **`MCI Material Specification`** = 钣金的**材料规格 / 材料属性**。

> 使用约定：按名读取属性信息时读取 `Connected Part-1..3`（连接钣金号）等元数据键；
> 当需要这些钣金的厚度/材料时，再定位到对应钣金节点读取
> `MCI Gauge/Thickness [mm]` 与 `MCI Material Specification`。焊点的位置坐标/法向请用节点 `Transform` 转换（见 `skill_get_weld_point_location_and_normal.md`）。

### 4. 导出 JT 数据

当用户需要导出 JT 数据时，直接参考 `skill_export_cad_to_path.md` 中的 **`ExportActiveDocumentToJt`**
命令（`SAVE_TYPE.DIRECTMODEL`），不要另行拼装导出逻辑。

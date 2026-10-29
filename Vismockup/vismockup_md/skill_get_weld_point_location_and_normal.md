
> 技能类型：Vismockup COM 自动化
> 适用场景：读取当前视图中被选中的焊点（Weld Point）或焊点组，直接从（叶子）焊点节点的 Transform（16 元素 4x4
>          列主序变换矩阵）解析出位置坐标 (X,Y,Z) 与法向/姿态 (RX,RY,RZ)，转换为 Tecnomatix 可识别的 TxTransformation
>          （Translation + RotationRPY_XYZ），用于导入 Tecnomatix。
> 触发关键词：焊点位置坐标、焊点法向、焊点坐标、选中焊点、焊点组、焊点位置和法向、导入 Tecnomatix、RotationRPY_XYZ、焊点方向

## 目标

连接正在运行的 Vismockup，获取当前活动视图的选中项集合。选中项既可能是单个焊点，也可能是一个焊点组（内部节点）。对每个选中项递归向下遍历，找到所有叶子焊点节点后，逐个读取：

- 读取名称（DataStoreName，并去掉末尾的 _序号 后缀）。
- 直接读取（叶子）焊点节点的 Transform（visDispNode.Transform）得到 16 元素 4x4 列主序变换矩阵。
- 用 TryGetXyzRxyz 把该矩阵一次性转换为 位置 (X,Y,Z) + 姿态/法向 (RX,RY,RZ)（弧度，ZYX 顺序）。
- 写入 TxTransformation（Translation + RotationRPY_XYZ），即可导入 Tecnomatix。

> 重要：位置坐标与法向都来自同一个 Transform 矩阵，不需要读取元数据键 Connector Location / Connector Normal，也不需要用元数据键名匹配。
> 但当选中的是焊点组（内部节点，含子节点）时，必须递归向下遍历子节点，直到叶子焊点节点，再读取其 Transform。
>
> 关键判据（VisView_NG 实测）：焊点组是【未命名/空白 DataStoreName】的结构节点，其 Transform 是原点处的单位阵，
> 直接读它会得到 (0,0,0) 的假焊点；焊点节点的 DataStoreName【非空】（通常以 .jt 结尾）。因此判定焊点必须用
> “DataStoreName 非空 = 焊点”，**不能**用“有 Transform = 焊点”——否则选中焊点组时会把组的单位阵读成一个 (0,0,0)
> 假焊点并停止下钻，这正是之前“选中焊点组总是提取错误、不稳定”的根因。

## 关键接口与参数

- gDocs.ActiveView.SelectedNodes -> 选中节点集合 VisDispNodeList。
- visDispNodeList.NumNodes -> 选中项数量，为 0 时直接返回空结果。
- visDispNodeList.Node[i] -> 第 i 个选中节点 VisDisp3DNode（可能是单个焊点，也可能是焊点组）。
- visDispNode.DataStoreName -> 焊点名称（可能带 _序号 后缀）。
- node.Children / children.NumNodes / children.Node(c) -> 子节点集合；当选中项是焊点组时，用它递归向下遍历到叶子焊点。
- visDispNode.Transform -> 叶子焊点节点的 16 元素 4x4 列主序变换矩阵（SAFEARRAY/VARIANT），位置和姿态都从这里解析，无需读取元数据。
- TryGetXyzRxyz(matrix, out x, out y, out z, out rx, out ry, out rz) -> 把 16 元素列主序矩阵解析为平移 (x,y,z) + 欧拉角 (rx,ry,rz)（弧度，ZYX）。

## C# 代码

```csharp
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;   // Marshal.GetActiveObject
using VISAUTOMATIONLib;

private List<VismockupPointInfo> GetWeldPointsFromVismockupSelection()
{
    var results = new List<VismockupPointInfo>();

    // 关键：必须“附着”到正在运行、且已经选中焊点的 Vismockup 实例。
    // 直接用 Activator.CreateInstance 会新建一个全新的空白实例，
    // 其 ActiveView.SelectedNodes 为空（NumNodes == 0），导致取不到选中的焊点。
    VISAUTOMATIONLib.DispVisApp gDispVisApp = null;
    try
    {
        // 优先附着到正在运行的实例（用户已在其中选好焊点）。
        dynamic running = Marshal.GetActiveObject("VFFrame.Application");
        gDispVisApp = running.VisAppAutomation();
    }
    catch
    {
        // 没有正在运行的实例才新建（新实例没有选中项，通常不是想要的）。
        Type oType = Type.GetTypeFromProgID("VFFrame.Application");
        if (oType == null)
        {
            // 未找到 COM ProgID VFFrame.Application。
            return results;
        }
        dynamic oOTCVis = Activator.CreateInstance(oType);
        gDispVisApp = oOTCVis.VisAppAutomation();
    }

    VisDispDocList gDocs = gDispVisApp.Documents;

    if (gDocs == null || gDocs.ActiveDocument == null)
    {
        // 未找到当前打开的 Vismockup 文档。
        return results;
    }

    // 从当前活动视图获取选中的节点（可能是焊点或焊点组）
    VisDispNodeList visDispNodeList = gDocs.ActiveView.SelectedNodes;
    if (visDispNodeList.NumNodes == 0) return results;

    // 选中项可能是单个焊点，也可能是焊点组（内部节点）。对每个选中项递归向下遍历，
    // 找到所有叶子焊点节点再读取位置/法向。
    for (int i = 0; i < visDispNodeList.NumNodes; i++)
    {
        CollectWeldPoints(visDispNodeList.Node[i], results);
    }

    return results;
}

// 递归向下遍历：命名节点当焊点读取（成功即收集并 STOP），空名结构节点（焊点组）向下钻。
private void CollectWeldPoints(dynamic node, List<VismockupPointInfo> results)
{
    if (node == null) return;

    // 关键判据（VisView_NG 实测）：焊点节点的 DataStoreName【非空】（通常以 .jt 结尾）；
    // 焊点组是【未命名/空白】结构节点，其 Transform 是原点处的单位阵——直接读它会得到 (0,0,0)
    // 的假焊点并提前 return，永远钻不到真正的焊点，这正是“选中焊点组就提取错误/不稳定”的根因。
    // 因此必须用“命名=焊点”而不是“有 Transform=焊点”来判定：
    //   命名节点 => 焊点：读取并 STOP（不再下钻其几何子节点，子节点只是重复同一变换）；
    //   空名节点 => 焊点组/结构节点：向下钻。
    string name = null;
    try { name = (string)node.DataStoreName; } catch { name = null; }

    if (name != null && name.Trim().Length > 0)
    {
        VismockupPointInfo point;
        if (TryReadWeldPoint(node, out point))
        {
            results.Add(point);
            return;   // 已收集该焊点，绝不下钻其几何子节点
        }
        // 命名但读不出 Transform：继续尝试子节点以防万一。
    }

    // 未命名 / 结构节点（焊点组 / 装配层级）：递归向下遍历子节点。
    int childCount = 0;
    dynamic children = null;
    try
    {
        children = node.Children;
        if (children != null) childCount = (int)children.NumNodes;
    }
    catch
    {
        childCount = 0;
    }
    for (int c = 0; c < childCount; c++)
    {
        CollectWeldPoints(children.Node(c), results);
    }
}

// 从单个（叶子）节点读取名称 + Transform，转换为 VismockupPointInfo。
private bool TryReadWeldPoint(dynamic visDispNode, out VismockupPointInfo point)
{
    point = null;

    // 名称：去掉末尾的 _序号 后缀
    string name;
    try { name = visDispNode.DataStoreName; }
    catch { return false; }
    name = name.Contains("_") ? name.Substring(0, name.LastIndexOf('_')) : name;

    // 优先读取全局(绝对)变换 GlobalTransformation；叶子焊点的局部 Transform
    // 常是相对父节点的单位阵，读它会得到全 0 坐标或转换失败。
    // 两者都尝试，任一能转成 16 元素矩阵即可。
    double x, y, z, rx, ry, rz;
    bool ok = false;

    dynamic globalT = null;
    try { globalT = visDispNode.GlobalTransformation; } catch { globalT = null; }
    if (globalT != null)
        ok = TryGetXyzRxyz((object)globalT, out x, out y, out z, out rx, out ry, out rz);
    else { x = y = z = rx = ry = rz = 0; }

    if (!ok)
    {
        dynamic localT = null;
        try { localT = visDispNode.Transform; } catch { localT = null; }
        if (localT != null)
            ok = TryGetXyzRxyz((object)localT, out x, out y, out z, out rx, out ry, out rz);
    }

    if (!ok)
    {
        // 既没有 GlobalTransformation 也没有可用的 16 元素 Transform，
        // 说明该节点不是可读的焊点节点。
        return false;
    }

    var transformation = new TxTransformation();
    transformation.Translation = new TxVector(x, y, z);
    // RotationRPY_XYZ 必须是【弧度】——这是 Tecnomatix 的内部单位，导入位姿时用它，不能改成角度。
    transformation.RotationRPY_XYZ = new TxVector(rx, ry, rz);

    point = new VismockupPointInfo();
    point.Transformation = transformation;
    point.Name = name;
    // 另存一份【角度】值，仅用于显示/打印给用户查看（1 rad = 180/π 度）。
    const double RadToDeg = 180.0 / Math.PI;
    point.RXDeg = rx * RadToDeg;
    point.RYDeg = ry * RadToDeg;
    point.RZDeg = rz * RadToDeg;
    return true;
}

// 把 16 元素列主序 4x4 变换矩阵转换为 x,y,z + rx,ry,rz（弧度，ZYX 顺序）。
private static bool TryGetXyzRxyz(object transformObj, out double x, out double y, out double z,
    out double rx, out double ry, out double rz)
{
    x = 0; y = 0; z = 0; rx = 0; ry = 0; rz = 0;

    // COM 返回的 Transform 可能是 object[]、被 VariantWrapper 包裹、
    // 或元素类型不统一。统一展平成 double[]，避免因形态差异整体失败。
    double[] m = FlattenToDoubles(transformObj);
    if (m == null || m.Length != 16)
    {
        return false;
    }

    // 列主序 4x4 矩阵：
    // | m0  m4  m8  m12 |
    // | m1  m5  m9  m13 |
    // | m2  m6  m10 m14 |
    // | m3  m7  m11 m15 |

    // 平移
    x = m[12];
    y = m[13];
    z = m[14];

    // 旋转矩阵元素
    double r00 = m[0];
    double r10 = m[1];
    double r20 = m[2];
    double r11 = m[5];
    double r12 = m[9];
    double r21 = m[6];
    double r22 = m[10];

    // 按常见 ZYX 顺序提取欧拉角（ry=pitch, rx=roll, rz=yaw）
    if (Math.Abs(r20) < 0.999999)
    {
        ry = Math.Asin(-r20);
        rx = Math.Atan2(r21, r22);
        rz = Math.Atan2(r10, r00);
    }
    else
    {
        // 万向锁
        ry = r20 <= -1.0 ? Math.PI / 2.0 : -Math.PI / 2.0;
        rx = Math.Atan2(-r12, r11);
        rz = 0;
    }

    return true;
}

// 把 COM 返回的 Transform（object[] / VariantWrapper / 嵌套数组 / 各种数值类型）
// 稳健地展平为 double[]，再由调用方判断长度是否为 16。
private static double[] FlattenToDoubles(object transformObj)
{
    transformObj = Unwrap(transformObj);
    if (transformObj == null) return null;

    var arr = transformObj as System.Collections.IEnumerable;
    if (arr == null) return null;

    var list = new List<double>(16);
    foreach (var raw in arr)
    {
        object o = Unwrap(raw);
        try { list.Add(Convert.ToDouble(o)); }
        catch { return null; }   // 元素不是数值，说明不是变换矩阵
    }
    return list.ToArray();
}

// 解开 VariantWrapper（[out] VARIANT 常被包一层）。
private static object Unwrap(object o)
{
    var w = o as System.Runtime.InteropServices.VariantWrapper;
    return w != null ? w.WrappedObject : o;
}
```

## 给代码生成模型的提示

- 连接 Vismockup 必须“附着”到正在运行的实例：优先 Marshal.GetActiveObject("VFFrame.Application")，
  失败再退回 Activator.CreateInstance。切勿直接用 Activator.CreateInstance 新建实例——那会得到一个
  全新的空白 Vismockup，ActiveView.SelectedNodes 为空（NumNodes == 0），导致取不到用户选中的焊点。
- 选中项来自 ActiveView.SelectedNodes，先判断 NumNodes == 0 再遍历；集合索引用 Node[i]。
- 选中项可能是单个焊点，也可能是焊点组（内部节点）。区分焊点与焊点组的**唯一可靠判据**是 DataStoreName：
  【命名节点（DataStoreName 非空，通常 .jt 结尾）= 焊点】，读取其 Transform 后收集并 return，绝不下钻其
  几何子节点（它们只是重复同一变换）；【未命名/空白节点 = 焊点组/结构节点】，向下钻子节点。
  切勿用“有 Transform = 焊点”判定——焊点组本身有一个原点处的单位阵 Transform，用该判据会把焊点组读成
  一个 (0,0,0) 假焊点并提前 return，永远钻不到真正的焊点。这就是选中焊点组时提取错误/不稳定的根因。
  也切勿一发现有 Children 就无脑下钻——焊点节点自身常带几何子节点，命中命名焊点后必须 STOP。
- 位置坐标与法向/姿态优先取叶子焊点的 GlobalTransformation（绝对变换），失败再退回 Transform；
  局部 Transform 常是相对父节点的单位阵，直接读会得到全 0 坐标或转换失败。
- Transform / GlobalTransformation 取回的是 VARIANT，形态可能是 object[]、被 VariantWrapper 包裹、
  或元素类型不统一。必须先用 FlattenToDoubles 解包(Unwrap)并逐元素 Convert.ToDouble 展平成 double[]，
  再判断长度==16，最后用 TryGetXyzRxyz 转换。不能直接 `as Array` 强转，否则形态稍有差异就整体失败。
- 不要读取元数据键 Connector Location / Connector Normal，也不要用元数据键名匹配；
  本技能只用 Transform，元数据属性读取请参考 04_nodes_metadata.md。
- 结果写入 TxTransformation：Translation = new TxVector(x,y,z)，RotationRPY_XYZ = new TxVector(rx,ry,rz)；
  这是 Tecnomatix 能识别的位姿格式。
- TryGetXyzRxyz 返回的 rx/ry/rz 是弧度。RotationRPY_XYZ 写入时必须保持【弧度】（Tecnomatix 内部单位），
  绝不能在这里乘 180/π，否则导入 Tecnomatix 的位姿会错。
- 但【输出/打印给用户看】的方向/法向必须是【角度】：VismockupPointInfo 需额外提供 RXDeg/RYDeg/RZDeg
  三个字段（= rx/ry/rz * 180.0 / Math.PI），在 TryReadWeldPoint 里一并填好。
- 最终打印每个焊点时：名称、位置 (X,Y,Z)、法向/方向用【角度】(RXDeg,RYDeg,RZDeg) 单位标注为“度/deg”，
  供用户查看；导入 Tecnomatix 仍用 Transformation（内部弧度）。
- 递归遍历时用 try/catch 保护 node.Children 访问；叶子节点访问 Children 可能抛异常，视为无子节点即可。
- Vismockup 必须已运行且有活动文档，否则返回空结果。

# Vismockup C# 自动化开发手册

## 1. 教材定位

这是一份面向 C#（.NET）开发者的 Teamcenter Visualization（Vismockup）自动化开发手册。

官方 API 文档本质上是对象参考手册，主要面向 Visual Basic .NET 和 VBScript 用户，并不直接教你如何用 C# 从零开始调用这些 COM 接口，也没有说明如何把这些调用封装成一个可复用的 .NET 类库（DLL）。本文在不改变官方接口定义的前提下，把官方内容整理成一条适合 C# 学习和工程化的路径，最终目标是：

- 让开发者能用 C# 通过 COM 操控 Vismockup。
- 让开发者能把这些能力封装成一个可复用的 **DLL（类库）**。
- 让代码生成模型（LLM）能够根据本手册的对象定义与调用范式，自动生成可编译的 C# COM 互操作代码。

本文严格遵循以下边界：

- 官方内容：来自 API Documentation 中的对象说明、属性、方法、参数定义。
- C# 写法：是在官方 COM 调用模型基础上的 C#（.NET / COM Interop）表达方式。
- 补充说明：官方没有明确写出，但项目已验证、对 C# 实战有帮助的内容，会显式写成“补充说明”。

> **给代码生成模型的提示**：本手册中所有对象名、属性名、方法名均与官方 COM 对象一一对应。生成 C# 代码时，请优先使用后期绑定（`dynamic`），除非明确要求早期绑定（Interop 强类型）。COM 成员名区分大小写敏感，请严格按本文书写。

---

## 2. 官方资料来源

本手册主要依据以下官方文档编写（与 Python 手册同源）：

- API Documentation/ref_files/prereq.md
- API Documentation/ref_files/autointro.md
- API Documentation/ref_files/starting_session.htm
- API Documentation/ref_files/deref.md
- API Documentation/ref_files/errorhandling.md
- API Documentation/ref_files/visappobject.md
- API Documentation/ref_files/visappobject2.md
- API Documentation/ref_files/visappobject3.md
- API Documentation/ref_files/visappobject4.md
- API Documentation/ref_files/visdispdoclist.md
- API Documentation/ref_files/visdispdoc.md
- API Documentation/ref_files/visdispviewlist.md
- API Documentation/ref_files/visdisp3dview.md
- API Documentation/ref_files/visdisp3dnode.md
- API Documentation/ref_files/visdispnodelist.md
- API Documentation/ref_files/visdispmetadatalist.md
- API Documentation/ref_files/visdispsnapshotmngr.md
- API Documentation/ref_files/visdispsectionmngr.md
- API Documentation/ref_files/visdispsection.md
- API Documentation/ref_files/visdisppmimngr.md
- API Documentation/ref_files/visdisppmiquery.md
- API Documentation/ref_files/visdisppmilist.md
- API Documentation/ref_files/visdisppmientity.md

如果你在开发过程中发现本文与官方对象定义冲突，应以官方文档为准。

---

## 3. 官方对象链路（完整版）

官方文档是 COM Automation 参考手册。无论用哪种语言，对象链路都是同一棵树。C# 访问这些对象时，路径与 Python/VB 完全一致，只是语法不同。

```text
VFFrame.Application
└── .VisAppAutomation                        ← 所有操作的起点
    ├── .Documents                           ← 文档集合
    │   ├── .NumDocuments                    ← 当前打开的文档数
    │   ├── .ActiveDocument                  ← 当前活动文档
    │   ├── .ActiveView                      ← 当前活动视图（3D）
    │   ├── .OpenDocument(path)              ← 打开文件，返回 VisDispDoc
    │   └── .CloseAllDocuments()             ← 关闭全部文档
    │
    └── .OpenDocument(path) → VisDispDoc
        ├── .Path / .DocType                 ← 文件路径 / 文档类型
        ├── .Export(saveType, path, "")      ← 导出为 JT/STEP 等格式
        ├── .ExportEnhanced(path, w, h, dpi) ← 导出为图片
        ├── .CloseDocument()                 ← 关闭此文档
        └── .ViewList
            └── .ViewByIndex(1) → ActiveView（3D 视图）
                ├── .Title                   ← 视图标题
                ├── .NumLoadedNodes          ← 已加载节点数
                ├── .Document                ← 反向取得所属文档
                ├── .FitAll()                ← 全部适合视图
                ├── .AllNodesOn/Off()        ← 全部显示 / 全部隐藏
                ├── .GetCameraPosition()     ← 读取相机位置
                ├── .SetCameraPosition()     ← 设置相机位置
                ├── .ExportEnhanced(path, w, h, dpi)  ← 导出截图
                │
                ├── .RootNode → VisDisp3DNode
                │   ├── .PrintableName       ← 节点显示名称
                │   ├── .Visible             ← 是否可见（可读写）
                │   ├── .IsPart              ← 是否是零件
                │   ├── .NumChildren         ← 子节点数量
                │   ├── .Children            ← 子节点列表
                │   ├── .Parent              ← 父节点
                │   └── .MetaDataProperties  ← 元数据（零件号等）
                │
                ├── .VisibleNodes / .AllNodes / .SelectedNodes → VisDispNodeList
                │   ├── .NumNodes            ← 节点数量
                │   └── .Node(index)         ← 按索引取节点
                │
                ├── .SnapShotManager
                │   ├── .NumSnapShots        ← 快照数量
                │   ├── .Name(index)         ← 快照名称
                │   ├── .AddSnapShot()       ← 新建快照
                │   └── .Activate(index)     ← 激活快照
                │
                ├── .PMIManager
                │   └── .PMIQuery
                │       ├── .GetAllPMIInModel(list)   ← 获取全部 PMI
                │       └── .GetPMIOfType(type, list) ← 按类型筛选
                │
                └── .SectionManager
                    ├── .CreateSection(offset, nx, ny, nz)  ← 创建截面
                    └── .DeleteAllSections()                ← 删除所有截面
```

你只要先按这个树去定位对象，再按对象页查参数，就能快速写出稳定的 C# 代码。

---

## 4. 什么是 OLE Automation（从 C# 的角度）

根据官方文档 API Documentation/ref_files/autointro.md，OLE Automation 是基于 COM 的一套脚本化技术。它把一个应用程序暴露成“可被外部程序调用的对象”。

对 C# 开发者来说，这句话可以翻译成：

- Vismockup 不通过 HTTP API 对外提供能力。
- 它通过 Windows COM 对象暴露能力。
  - COM（Component Object Model，组件对象模型）是微软在 Windows 平台上定义的一套 **二进制组件规范和跨进程/跨语言调用机制**。
  - 在 Windows 上，不同语言写的程序（C/C++、C#、VB、脚本等）可以通过 COM 这个统一接口标准，像“调用本地对象”一样互相调用对方提供的功能。
- C# 通过 **.NET COM Interop** 调用这些 COM 对象。
  - .NET 运行时内置了 COM 互操作层（RCW，Runtime Callable Wrapper）。
  - C# 有两种典型调用方式：**后期绑定**（`dynamic` + `Type.GetTypeFromProgID`）和 **早期绑定**（引用 COM 类型库生成 Interop 程序集）。

这也是为什么本项目只能在 Windows 上工作，并且需要以 x86/x64 与 Vismockup 进程位数一致的方式编译。

> **补充说明（位数一致性）**：COM 进程外/进程内调用要求调用方与被调用方位数匹配。若 Vismockup 是 64 位，则 C# 工程的“平台目标”应设为 `x64`（不要用 `AnyCPU` 的默认 32 位偏好）。

---

## 5. 开发环境准备

### 5.1 系统与软件

- Windows 10 或 Windows 11
- 已安装 Teamcenter Visualization（Vismockup），并已注册其 COM 组件
- Visual Studio 2019/2022 或 .NET SDK（`dotnet` CLI）
- .NET Framework 4.7.2+ 或 .NET 6/8（Windows 平台）

> **补充说明**：进程外 COM 自动化对 .NET Framework 与现代 .NET（`net6.0-windows` 等）都可用。若使用现代 .NET，需在项目里启用 `<UseWindowsForms>` 无关的 COM 支持即可，关键是目标框架带 `-windows`（如 `net8.0-windows`）以获得 `Marshal`、`dynamic` COM 能力。

### 5.2 新建一个类库（DLL）工程

用命令行创建一个类库工程（本手册最终目标就是产出这个 DLL）：

```cmd
dotnet new classlib -n VismockupAutomation -f net8.0-windows
cd VismockupAutomation
```

或在 Visual Studio 中选择“类库（Class Library）”模板。

工程文件（`VismockupAutomation.csproj`）关键配置：

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0-windows</TargetFramework>
    <Platforms>x64</Platforms>
    <PlatformTarget>x64</PlatformTarget>
    <AllowUnsafeBlocks>false</AllowUnsafeBlocks>
    <!-- 后期绑定 dynamic 需要 Microsoft.CSharp（.NET Framework 需显式引用） -->
  </PropertyGroup>
</Project>
```

### 5.3 先启动 Vismockup

初学/联调阶段最稳妥的做法：

1. 手动启动 Vismockup。
2. 手动打开一个 3D 文件。
3. 再运行 C# 程序（连接到已运行实例）。

---

## 6. 两种调用方式：后期绑定 vs 早期绑定

C# 调用 COM 有两条路线，本手册两者都给出，**默认推荐后期绑定**。

### 6.1 后期绑定（Late Binding，推荐用于生成代码）

- 不需要引用任何 Interop 程序集。
- 用 `Type.GetTypeFromProgID` 拿到类型，用 `Activator.CreateInstance` 创建对象。
- 用 `dynamic` 关键字访问所有属性和方法，写法几乎和脚本一样。
- 优点：无需类型库、跨 Vismockup 版本更兼容、代码生成最简单。
- 缺点：无编译期检查，成员名写错要到运行期才报错。

```csharp
using System;

Type t = Type.GetTypeFromProgID("VFFrame.Application");
dynamic vmu = Activator.CreateInstance(t);
dynamic visApp = vmu.VisAppAutomation;   // 等价于 VB 的 VMU.VisAppAutomation()
```

### 6.2 早期绑定（Early Binding，强类型 Interop）

- 需要 Vismockup 提供的 COM 类型库（`.tlb` / `.dll`），或用 `tlbimp` 生成 Interop 程序集。
- 在 Visual Studio 中：右键项目 → 添加 → COM 引用 → 勾选 Vismockup 类型库。
- 或命令行：`tlbimp Vismockup.tlb /out:Interop.Vismockup.dll`
- 优点：编译期类型检查、IntelliSense 智能提示。
- 缺点：依赖具体版本的类型库，跨版本可能不兼容。

```csharp
using Interop.Vismockup; // tlbimp 生成的命名空间（示例名，具体以类型库为准）

var vmu = new ApplicationClass();
var visApp = vmu.VisAppAutomation();
```

> **补充说明**：由于不同环境的类型库名称、CoClass 名、命名空间不固定，本手册后续示例统一采用 **后期绑定 `dynamic`**，以保证代码生成的通用性。若你已有确定的类型库，可将 `dynamic` 替换为对应强类型接口。

---

## 7. 官方会话启动方式，如何翻译成 C#

官方文档 API Documentation/ref_files/starting_session.htm 给出的 Visual Basic 示例核心是：

```vb
Set VMU = CreateObject("VFFrame.Application")
Set VisApp = VMU.VisAppAutomation()
```

翻译成 C#（后期绑定）：

```csharp
using System;

// 方式 A：创建新的应用实例
Type t = Type.GetTypeFromProgID("VFFrame.Application");
dynamic vmu = Activator.CreateInstance(t);
dynamic visApp = vmu.VisAppAutomation;

// 方式 B：连接到已经在运行的 Vismockup 实例（推荐联调时使用）
dynamic running = System.Runtime.InteropServices.Marshal.GetActiveObject("VFFrame.Application");
dynamic visApp2 = running.VisAppAutomation;
```

要点：

- 官方入口对象是 `VFFrame.Application`。
- 真正的自动化应用对象是 `VisAppAutomation`。
- VB 里 `VisAppAutomation()` 是方法调用形式；在 C# 后期绑定中通常以属性访问表现，本手册统一写作 `vmu.VisAppAutomation`。这属于绑定层差异，不是对象模型差异。

> **补充说明（GetActiveObject）**：在现代 .NET 中，`Marshal.GetActiveObject` 在部分目标框架下未直接暴露，可用 `Type.GetTypeFromProgID` + `Activator.CreateInstance` 作为等价入口，或通过 P/Invoke 调用 `GetActiveObject`。若目标是 .NET Framework，`Marshal.GetActiveObject` 直接可用。

---

## 8. 第一个可运行的 C# 程序

建议先跑通下面这段最小程序，验证 COM 链路：

```csharp
using System;

class Program
{
    static void Main()
    {
        Type t = Type.GetTypeFromProgID("VFFrame.Application");
        dynamic vmu = Activator.CreateInstance(t);
        dynamic visApp = vmu.VisAppAutomation;

        Console.WriteLine($"应用程序名称  : {visApp.Name}");
        Console.WriteLine($"应用程序路径  : {visApp.Fullname}");
        Console.WriteLine($"版本          : {visApp.VersionString}");
        Console.WriteLine($"构建号        : {visApp.BuildString}");
        Console.WriteLine($"当前语言环境  : {visApp.LocaleString}");
        Console.WriteLine($"窗口宽度      : {visApp.Width} px");
        Console.WriteLine($"窗口高度      : {visApp.Height} px");
    }
}
```

如果这段代码能成功输出，说明：

- C# 可以创建或连接 COM 对象。
- Vismockup 自动化对象可访问。
- 你已经拿到应用级入口对象 `visApp`。

> **补充说明（COM 线程模型）**：COM 自动化通常要求 STA（单线程套间）。控制台 `Main` 建议加 `[STAThread]` 特性；WinForms/WPF 的 UI 线程默认就是 STA。

```csharp
[STAThread]
static void Main() { /* ... */ }
```

---

## 9. 认识核心对象链路

### 9.1 应用对象 DispVisApp

官方文档 API Documentation/ref_files/visappobject.md 将主应用对象命名为 `DispVisApp`。

在 C# 中，`dynamic visApp = vmu.VisAppAutomation;` 拿到的 `visApp`，就是主应用自动化对象 `DispVisApp`。它是所有自动化对象的起点。你能从它拿到：

- `Documents`：文档集合
- `ActiveDocument`：当前活动文档
- `ActiveView`：当前活动视图
- `SnapShotManager`：应用级快照管理器
- `PrintManager`：打印管理器
- `OutlineManager`：轮廓捕获管理器

常用属性示例：

```csharp
Console.WriteLine(visApp.Name);
Console.WriteLine(visApp.Fullname);
Console.WriteLine(visApp.VersionString);
Console.WriteLine(visApp.BuildString);
Console.WriteLine(visApp.LocaleString);
```

### 9.2 文档集合 Documents

官方文档 API Documentation/ref_files/visdispdoclist.md 说明：`visApp.Documents` 返回文档集合对象。

```csharp
dynamic documents = visApp.Documents;
Console.WriteLine($"当前文档数: {documents.NumDocuments}");

dynamic doc = documents.OpenDocument(@"C:\models\engine.jt");
Console.WriteLine(doc.Path);
```

### 9.3 文档对象 VisDispDoc（OpenDocument 的返回值）

官方文档 API Documentation/ref_files/visdispdoc.md 中，`VisDispDoc` 最常用成员包括 `Path`、`DocType`、`ViewList`、`CloseDocument()`、`Export()`、`ExportEnhanced()`。

```csharp
dynamic doc = documents.OpenDocument(@"C:\models\assembly.jt");

Console.WriteLine($"文档路径: {doc.Path}");
Console.WriteLine($"文档类型: {doc.DocType}");
Console.WriteLine($"视图数量: {doc.ViewList.NumViews}");
```

#### 9.3.1 如何关闭当前文档

写法 A（推荐）：关闭你手里明确引用的 `doc`

```csharp
dynamic doc = documents.OpenDocument(@"C:\models\assembly.jt");
Console.WriteLine($"打开后文档数: {documents.NumDocuments}");

doc.CloseDocument();
Console.WriteLine($"关闭后文档数: {documents.NumDocuments}");
```

写法 B：关闭当前活动文档

```csharp
dynamic doc = documents.ActiveDocument;
if (doc != null)
{
    Console.WriteLine($"准备关闭: {doc.Path}");
    doc.CloseDocument();
}
```

### 9.4 视图集合 ViewList

官方文档 API Documentation/ref_files/visdispviewlist.md 说明：`doc.ViewList` 是视图集合。

```csharp
dynamic viewList = doc.ViewList;
Console.WriteLine($"视图数量: {viewList.NumViews}");

for (int index = 0; index < viewList.NumViews; index++)
{
    dynamic view = viewList.ViewByIndex(index);
    Console.WriteLine($"视图索引: {index}");
}
```

> **补充说明（索引基准）**：官方对象链路示例中出现过 `ViewByIndex(1)`。不同集合的索引起点（0 基或 1 基）可能不一致。生成代码时应先做一次探测（打印首尾索引），确认基准后再固定循环边界。

### 9.5 三维视图 ActiveView

官方文档 API Documentation/ref_files/visdisp3dview.md 说明：3D 视图对象是真正做三维操作的核心。常访问的对象基本都挂在它下面：`RootNode`、`AllNodes`、`VisibleNodes`、`SelectedNodes`、`SnapShotManager`、`PMIManager`、`SectionManager`、`MeasurementManager`、`ClearanceManager`。

```csharp
dynamic view3d = documents.ActiveView;

Console.WriteLine($"视图标题: {view3d.Title}");
Console.WriteLine($"加载节点数: {view3d.NumLoadedNodes}");
Console.WriteLine($"可见节点数: {view3d.NumVisibleNodes}");
```

---

## 10. 第一个完整链路：打开文件并读取 3D 视图

```csharp
using System;

class Program
{
    [STAThread]
    static void Main()
    {
        Type t = Type.GetTypeFromProgID("VFFrame.Application");
        dynamic vmu = Activator.CreateInstance(t);
        dynamic visApp = vmu.VisAppAutomation;

        dynamic documents = visApp.Documents;
        dynamic doc = documents.OpenDocument(@"C:\models\assembly.jt");
        dynamic view3d = documents.ActiveView;

        Console.WriteLine($"应用名: {visApp.Name}");
        Console.WriteLine($"文档: {doc.Path}");
        Console.WriteLine($"视图标题: {view3d.Title}");
        Console.WriteLine($"加载节点数: {view3d.NumLoadedNodes}");
    }
}
```

开发建议：

1. 先确认这段代码可以运行。
2. 再在每一步单独输出对象属性观察行为。
3. 不要一开始就写复杂递归或批处理逻辑。

---

## 11. 节点 Node

官方文档 API Documentation/ref_files/visdisp3dnode.md 说明：`VisDisp3DNode` 表示 3D 视图中的零件或装配节点。模型树里的每个“零件/组件”，在自动化里都对应一个节点对象。

常用属性：`PrintableName`、`FullName`、`IsPart`、`IsLoaded`、`Visible`、`Selected`、`NumChildren`、`Children`、`Parent`、`DataStoreLocation`、`CADID`、`MetaDataProperties`、`BBox`。

### 11.1 根节点与子节点

```csharp
dynamic rootNode = view3d.RootNode;

Console.WriteLine(rootNode.PrintableName);
Console.WriteLine(rootNode.NumChildren);
```

### 11.2 节点列表 VisDispNodeList

官方文档 API Documentation/ref_files/visdispnodelist.md 说明：节点集合对象提供 `NumNodes`、`Node(index)`、`AppendNode(node)`。

```csharp
dynamic children = rootNode.Children;

for (int index = 0; index < children.NumNodes; index++)
{
    dynamic node = children.Node(index);
    Console.WriteLine(node.PrintableName);
}
```

---

## 12. 递归遍历节点树

学会递归遍历节点树，是进入 Vismockup 自动化开发的第一道门槛。下面是适合封装进 DLL 的树遍历模板：

```csharp
static void WalkNode(dynamic node, int depth = 0)
{
    string indent = new string(' ', depth * 2);
    string kind = node.IsPart ? "零件" : "装配";
    string state = node.Visible ? "显示" : "隐藏";
    Console.WriteLine($"{indent}[{kind}] {node.PrintableName} ({state})");

    dynamic children = node.Children;
    for (int index = 0; index < children.NumNodes; index++)
    {
        dynamic childNode = children.Node(index);
        WalkNode(childNode, depth + 1);
    }
}

// 调用
dynamic rootNode = view3d.RootNode;
WalkNode(rootNode);
```

这段代码稳定运行后，你就具备了以下几类任务的基础：

- 按名称搜索零件
- 批量隐藏/显示零件
- 统计零件数量
- 读取零件属性

---

## 13. 控制节点显示与隐藏

官方文档 API Documentation/ref_files/visdisp3dnode.md 明确说明：`Visible` 是可读写属性。

```csharp
dynamic node = view3d.RootNode.Children.Node(0);
node.Visible = false;
Console.WriteLine($"已隐藏: {node.PrintableName}");

node.Visible = true;
Console.WriteLine($"已显示: {node.PrintableName}");
```

官方文档 API Documentation/ref_files/visdisp3dview.md 还提供了视图级方法：`AllNodesOn()`、`AllNodesOff()`、`SetNodesVisible(node_list)`、`SetNodesInVisible(node_list)`。

```csharp
view3d.AllNodesOff();
view3d.AllNodesOn();
```

入门阶段先掌握节点 `Visible` 和视图 `AllNodesOn/AllNodesOff` 就够了。

---

## 14. 读取节点元数据

官方文档 API Documentation/ref_files/visdisp3dnode.md 指出：每个节点可以通过 `MetaDataProperties` 拿到元数据集合。该集合的官方对象是 `VisDispMetaDataList`（见 API Documentation/ref_files/visdispmetadatalist.md）。

官方接口：

- `NumProperties`
- `GetProperty(index, name, value)`
- `GetPropertyByName(prop_name, value)`

### 14.1 为什么元数据读取在 C# 需要特别处理

`GetProperty` / `GetPropertyByName` 使用的是 COM **输出参数**（`[out]`）。在 C# 后期绑定中，需要用 `object` 变量按引用传入。因为 `dynamic` 无法直接对 `ref` 做重载解析，通常改用 `Type.InvokeMember` 并配合 `ParameterModifier` 传出参数。

按官方接口思路的 C# 示例：

```csharp
using System;
using System.Reflection;

dynamic node = view3d.RootNode.Children.Node(0);
object metaObj = node.MetaDataProperties;
if (metaObj != null)
{
    dynamic meta = metaObj;
    int count = meta.NumProperties;

    for (int index = 0; index < count; index++)
    {
        object[] args = new object[] { index, string.Empty, null };
        // 声明第 2、3 个参数为按引用传出
        ParameterModifier pm = new ParameterModifier(3);
        pm[1] = true; // name  为 out
        pm[2] = true; // value 为 out
        ParameterModifier[] mods = new[] { pm };

        metaObj.GetType().InvokeMember(
            "GetProperty",
            BindingFlags.InvokeMethod,
            binder: null,
            target: metaObj,
            args: args,
            modifiers: mods,
            culture: null,
            namedParameters: null);

        Console.WriteLine($"{args[1]} = {args[2]}");
    }
}
```

### 14.2 按名称读取元数据

```csharp
using System.Reflection;

object metaObj = node.MetaDataProperties;
object[] args = new object[] { "Part Number", null };
ParameterModifier pm = new ParameterModifier(2);
pm[1] = true; // value 为 out
metaObj.GetType().InvokeMember(
    "GetPropertyByName",
    BindingFlags.InvokeMethod,
    null, metaObj, args, new[] { pm }, null, null);

Console.WriteLine(args[1]);
```

> **补充说明**：不同 CAD 数据源的元数据字段名可能不同，例如同样是“零件号”，字段名未必都叫 `Part Number`。这是业务数据差异，不是 API 差异。生成代码时应先枚举全部属性名，再决定按名读取。

---

## 15. 认识 3D 视图上的常用管理器

拿到 `view3d` 之后，真正的功能对象大多从这里继续获取。最重要的几个管理器：

- `SnapShotManager`
- `SectionManager`
- `PMIManager`
- `MeasurementManager`
- `ClearanceManager`

初学阶段最常用的前三个分别对应：快照、截面、PMI。

---

## 16. 快照管理

官方文档 API Documentation/ref_files/visdispsnapshotmngr.md 说明，快照管理器提供：`Name(index)`、`NumSnapShots`、`AddSnapShot(index)`、`Activate(index)`、`ReCapture(index)`、`Replace(index)`、`Delete(index)`、`SetVisibility(index)`、`SetNavigation(index)`、`SetTranslation(index)`、`Cycle()`。

### 16.1 获取快照管理器

```csharp
dynamic snapMgr = view3d.SnapShotManager;
Console.WriteLine($"快照数量: {snapMgr.NumSnapShots}");
```

### 16.2 列出所有快照

```csharp
for (int index = 0; index < snapMgr.NumSnapShots; index++)
{
    Console.WriteLine($"{index} {snapMgr.Name(index)}");
}
```

### 16.3 新建快照并激活

```csharp
object newIndex = snapMgr.AddSnapShot(null);
Console.WriteLine($"新增快照索引: {newIndex}");

snapMgr.Activate(newIndex);
```

### 16.4 将当前视图切到某个快照

```csharp
int targetIndex = 0;
snapMgr.Activate(targetIndex);
Console.WriteLine($"已激活快照: {snapMgr.Name(targetIndex)}");
```

---

## 17. 导出文件与导出图片

官方文档 API Documentation/ref_files/visdispdoc.md 给了两套导出能力：`Export()` 和 `ExportEnhanced()`。

### 17.1 Export()

`Export(SaveType, path, config)` 用于按导出类型输出文件。官方文档列出的 SaveType 包括：`DIRECTMODEL`、`VRML`、`ROBFACE`、`PLMXML`、`STEP`、`BLK`。

```csharp
doc.Export("DIRECTMODEL", @"C:\output\export.jt", "");
```

### 17.2 ExportEnhanced()

官方参数说明：

- `path`：输出文件路径
- `Width`：导出图像宽度，单位英寸，范围 1 到 66.2
- `Height`：导出图像高度，单位英寸，范围 1 到 93.6
- `DPI`：每英寸点数，范围 72 到 1200

“导出一张宽 8 英寸、高 6 英寸、200 DPI 的图片”：

```csharp
doc.ExportEnhanced(@"C:\output\render.jpg", 8.0, 6.0, 200);
```

像素尺寸约等于：

$$
宽像素 = 8 \times 200 = 1600
$$

$$
高像素 = 6 \times 200 = 1200
$$

即大约生成一张 1600 x 1200 的图片。

### 17.3 导出图片示例

```csharp
doc.ExportEnhanced(@"C:\output\snapshot.jpg", 8.0, 6.0, 150);
doc.ExportEnhanced(@"C:\output\snapshot.png", 10.0, 7.5, 300);
```

> **补充说明**：官方文档同时提供了 `VisDisp3DView.CaptureImage()` 和 `CaptureImage2()`。本项目在当前环境验证时，发现它们可能抛出 COM 异常甚至导致 Vismockup 退出，因此项目代码默认优先使用 `doc.ExportEnhanced()` 做图片输出。这条结论属于项目验证结果，不属于官方文档承诺。

---

## 18. 截面管理

官方文档 API Documentation/ref_files/visdispsectionmngr.md 说明：`VisDispSectionMngr` 负责截面管理。常用方法：

- `CreateSection(offset, nx, ny, nz)`
- `CreateSeries(p1x, p1y, p1z, p2x, p2y, p2z, spacing, num_sections)`
- `DeleteAllSections()`

### 18.1 CreateSection 的参数要非常注意

官方文档明确说明：

- 第 1 个参数 `Offset`：截面距离原点的偏移量
- 第 2 到第 4 个参数：法向量 `NormalX`、`NormalY`、`NormalZ`

所以这行代码：

```csharp
dynamic section = view3d.SectionManager.CreateSection(0.0, 0.0, 0.0, 1.0);
```

不能理解成“在 Z=0 创建截面”，而应理解成：偏移量 0.0、截面法向量 (0, 0, 1)，即“创建一个法向量沿 Z 轴的截面”。

### 18.2 创建单个截面

```csharp
dynamic sectionMgr = view3d.SectionManager;
dynamic section = sectionMgr.CreateSection(0.0, 0.0, 0.0, 1.0);

sectionMgr.ShowBorders = true;
sectionMgr.EnableCapping = true;

Console.WriteLine("截面已创建");
```

### 18.3 调整截面偏移量

官方文档 API Documentation/ref_files/visdispsection.md 说明，`VisDispSection` 对象提供 `Offset` 属性。

```csharp
section.Offset = 50.0;
Console.WriteLine("截面偏移已设为 50.0");
```

### 18.4 删除所有截面

```csharp
sectionMgr.DeleteAllSections();
Console.WriteLine("所有截面已删除");
```

### 18.5 创建截面序列

```csharp
dynamic series = sectionMgr.CreateSeries(
    0.0, 0.0, -500.0,
    0.0, 0.0, 500.0,
    0.0,
    5);
Console.WriteLine(series);
```

---

## 19. PMI 基础操作

官方文档 API Documentation/ref_files/visdisppmimngr.md 说明：3D 视图通过 `PMIManager` 提供 PMI 功能。它下面最重要的对象是 `PMIQuery`（见 API Documentation/ref_files/visdisppmiquery.md）。

### 19.1 获取 PMI 管理器和查询器

```csharp
dynamic pmiMgr = view3d.PMIManager;
dynamic pmiQuery = pmiMgr.PMIQuery;
```

### 19.2 获取所有 PMI

根据官方文档，`GetAllPMIInModel()` 通过 **输出参数** 返回一个 `VisDispPMIList`。C# 中需要先准备一个可接收结果的对象再传入。若能创建结果对象，可用 `Activator.CreateInstance`：

```csharp
Type listType = Type.GetTypeFromProgID("VisDispPMIList");
dynamic pmiList = Activator.CreateInstance(listType);
pmiQuery.GetAllPMIInModel(pmiList);
```

> **补充说明**：这类“先创建结果对象再传入”的写法，在不同 COM 绑定环境中表现可能不一致（ProgID 是否可创建取决于注册情况）。官方文档只定义了输出参数语义，没有提供 C# 示例。因此项目里更常用的方式是通过现有封装函数或在运行时做对象探测。若 `GetAllPMIInModel` 声明为 `[out]` 且需 RCW 回填，可改用第 14 节的 `InvokeMember` + `ParameterModifier` 方式传出。这个差异属于 C# 实战补充，不属于官方文档直接给出的调用模板。

### 19.3 PMI 列表对象可以做什么

官方文档 API Documentation/ref_files/visdisppmilist.md 说明，PMI 列表对象支持：`NumPMIEntities`、`PMIEntity(index)`、`Show()`、`Hide()`、`Select()`、`Deselect()`、`Sort(attr_name)`。

```csharp
for (int index = 0; index < pmiList.NumPMIEntities; index++)
{
    dynamic entity = pmiList.PMIEntity(index);
    Console.WriteLine(entity.Name);
}
```

### 19.4 PMI 单个实体对象

官方文档 API Documentation/ref_files/visdisppmientity.md 说明，单个 PMI 实体常用属性包括：`Name`、`Type`、`Visible`、`Selected`、`NumProperties`、`PropName(index)`、`PropValue(index)`、`CADID`、`ContainerNode`。

```csharp
dynamic entity = pmiList.PMIEntity(0);

Console.WriteLine(entity.Name);
Console.WriteLine(entity.Type);
Console.WriteLine(entity.Visible);

for (int index = 0; index < entity.NumProperties; index++)
{
    Console.WriteLine($"{entity.PropName(index)} {entity.PropValue(index)}");
}
```

### 19.5 显示和隐藏 PMI

```csharp
pmiList.Show();
pmiList.Hide();
```

---

## 20. 视图导航与相机

官方文档 API Documentation/ref_files/visdisp3dview.md 提供了两个非常重要的方法：

- `GetCameraPosition(up_vec, look_at_vec, look_from_pt)`
- `SetCameraPosition(up_vec, look_at_vec, look_from_pt)`

这说明 Vismockup 的相机可以通过向量和坐标直接控制。此外还提供 `FitAll()`、`GetVisibleBBox(min, max)`。

```csharp
view3d.FitAll();
```

`GetCameraPosition` / `SetCameraPosition` / `GetVisibleBBox` 使用 `[out]` 向量参数，C# 中需按第 14 节的 `InvokeMember` + `ParameterModifier` 方式传出，或使用早期绑定的强类型 `ref` 签名。

> **补充说明**：官方文档没有提供“正视图、俯视图、右视图、等轴测视图”的完整高层 API 教程。项目中的标准视角切换，是基于相机向量和模型边界框计算实现的。这属于项目补充实现，不属于官方直接示例。

---

## 21. 错误处理

官方文档 API Documentation/ref_files/errorhandling.md 重点讨论 VBScript 的错误处理，但核心原则对 C# 同样成立：不需要每一行都包错误处理，在容易失败的地方做检查，读取错误信息并尽量输出上下文。

C# 中，COM 错误通常表现为 `COMException`（HRESULT），后期绑定失败会抛 `RuntimeBinderException`：

```csharp
using System;
using System.Runtime.InteropServices;

try
{
    Type t = Type.GetTypeFromProgID("VFFrame.Application");
    dynamic vmu = Activator.CreateInstance(t);
    dynamic visApp = vmu.VisAppAutomation;
    dynamic docs = visApp.Documents;
    dynamic doc = docs.OpenDocument(@"C:\models\not_exists.jt");
    Console.WriteLine(doc.Path);
}
catch (COMException ex)
{
    Console.WriteLine($"COM 调用失败 (HRESULT=0x{ex.HResult:X8}): {ex.Message}");
}
catch (Exception ex)
{
    Console.WriteLine($"自动化调用失败: {ex.Message}");
}
```

入门阶段最常见的错误来源：

- Vismockup 未启动
- COM 未正确注册
- 位数（x86/x64）不匹配
- 文件路径不存在
- 当前活动视图不是 3D 视图
- 对象为空却继续访问属性

---

## 22. 对象释放（COM 生命周期管理）

官方文档 API Documentation/ref_files/deref.md 强调：对象变量使用结束后应被释放。VB/VBScript 里官方建议 `Set objX = Nothing`。

在 C# / .NET 中，COM 对象由 RCW 包装，垃圾回收会最终释放它们，但对于进程外 COM（Vismockup 是独立进程），**建议显式释放**以避免 Vismockup 进程被长期占用：

```csharp
using System.Runtime.InteropServices;

if (doc != null) Marshal.ReleaseComObject(doc);
if (documents != null) Marshal.ReleaseComObject(documents);
if (visApp != null) Marshal.ReleaseComObject(visApp);

doc = null;
documents = null;
visApp = null;

// 需要彻底回收时
GC.Collect();
GC.WaitForPendingFinalizers();
```

原则：

- 不要长期保留无用 COM 对象引用。
- 每个从 COM 拿到的对象，理论上都应有对应的 `ReleaseComObject`。
- 在 GUI、多线程或长生命周期进程里，释放比一次性程序更重要。

> **补充说明**：过度、错误地调用 `ReleaseComObject`（比如释放了仍在使用的对象）会导致 `InvalidComObjectException`。工程上更稳妥的做法是用包装类在 `Dispose()` 中集中释放，见第 24 节。

---

## 23. 多线程与 COM 套间（STA/MTA）

官方文档没有对 .NET 的多线程 COM 使用给出指导。工程实践建议：

- 自动化 COM 一般运行在 **STA**。UI 线程默认 STA；后台 `Thread` 需显式设置。

```csharp
using System.Threading;

var thread = new Thread(() =>
{
    // 在这个线程里再获取 COM 对象
    Type t = Type.GetTypeFromProgID("VFFrame.Application");
    dynamic vmu = Activator.CreateInstance(t);
    dynamic visApp = vmu.VisAppAutomation;
    // ... 使用 ...
});
thread.SetApartmentState(ApartmentState.STA);
thread.Start();
thread.Join();
```

- 避免跨线程共享同一个 COM 对象；若必须跨线程，需要 COM 封送（marshaling）。项目中的做法是尽量在每个线程内重新连接。这属于工程化补充，不是官方文档原文。

---

## 24. 把能力封装成 DLL（工程化目标）

本手册的最终目标是产出一个可复用的 .NET 类库（DLL）。下面给出一个最小可用的封装骨架，代码生成模型可以在此基础上扩展。

```csharp
using System;
using System.Runtime.InteropServices;

namespace VismockupAutomation
{
    /// <summary>
    /// Vismockup COM 自动化封装。通过后期绑定操作 VFFrame.Application。
    /// 实现 IDisposable 以确保 COM 对象被显式释放。
    /// </summary>
    public sealed class VismockupSession : IDisposable
    {
        private dynamic _vmu;
        private dynamic _visApp;
        private bool _disposed;

        /// <summary>连接到（或创建）Vismockup 应用对象。</summary>
        public void Connect()
        {
            Type t = Type.GetTypeFromProgID("VFFrame.Application")
                     ?? throw new InvalidOperationException("未找到 VFFrame.Application，请确认 Vismockup 已安装并注册 COM。");
            _vmu = Activator.CreateInstance(t);
            _visApp = _vmu.VisAppAutomation;
        }

        public string ApplicationName => (string)_visApp.Name;
        public string Version => (string)_visApp.VersionString;

        /// <summary>打开一个文档并返回其 3D 活动视图。</summary>
        public dynamic OpenDocument(string path)
        {
            dynamic documents = _visApp.Documents;
            dynamic doc = documents.OpenDocument(path);
            return doc;
        }

        /// <summary>导出当前文档为图片（英寸 + DPI）。</summary>
        public void ExportImage(dynamic doc, string outputPath, double widthInch, double heightInch, int dpi)
        {
            doc.ExportEnhanced(outputPath, widthInch, heightInch, dpi);
        }

        public void Dispose()
        {
            if (_disposed) return;
            try
            {
                if (_visApp != null) Marshal.ReleaseComObject(_visApp);
                if (_vmu != null) Marshal.ReleaseComObject(_vmu);
            }
            catch { /* 忽略释放期异常 */ }
            finally
            {
                _visApp = null;
                _vmu = null;
                _disposed = true;
            }
        }
    }
}
```

编译成 DLL：

```cmd
dotnet build -c Release
```

生成的 `bin\Release\net8.0-windows\VismockupAutomation.dll` 即可被其它 .NET 程序引用。

使用示例（消费方）：

```csharp
using VismockupAutomation;

using (var session = new VismockupSession())
{
    session.Connect();
    Console.WriteLine(session.ApplicationName);

    dynamic doc = session.OpenDocument(@"C:\models\assembly.jt");
    session.ExportImage(doc, @"C:\output\snapshot.png", 8.0, 6.0, 150);
}
```

> **补充说明（把该 DLL 反向暴露为 COM）**：如果你还希望这个 DLL 本身被非 .NET 程序当作 COM 组件调用（`[ComVisible(true)]` + `regasm`），那是另一个方向的需求。本手册聚焦“C# 作为客户端通过 COM 调用 Vismockup”，如需反向 COM 暴露可另行扩展。

---

## 25. 从零开始的学习顺序

建议按下面的顺序开发，不要跳步：

1. **只连接应用**：能成功拿到 `visApp` 并输出版本信息。
2. **打开文档**：能拿到 `doc` 并输出 `doc.Path`。
3. **拿到 3D 视图**：能读取 `view3d.Title` 和 `view3d.NumLoadedNodes`。
4. **遍历节点树**：能打印节点名称和层级关系。
5. **隐藏一个节点**：能把一个零件隐藏后再显示回来。
6. **导出一张图片**：能调用 `ExportEnhanced()` 成功导出 JPG 或 PNG。
7. **创建一个截面**：能创建截面并修改偏移量。
8. **读取一个 PMI 或元数据**：能打印属性名和值。
9. **封装成 DLL**：把上述能力放进 `VismockupSession`，编译输出 DLL。

完成这 9 步，你就具备了独立阅读大多数官方对象文档并构建 C# 自动化 DLL 的能力。

---

## 26. 官方文档缺失点清单（C# 视角）

以下内容在官方文档中定义不完整，或没有给出 C# 可直接照抄的示例。本文虽给出补充建议，但必须当作“补充说明”，不能误认为官方承诺：

- C# 多线程/套间（STA/MTA）下的 COM 使用方式
- C# 中 `[out]` 输出参数的封装方式（`InvokeMember` + `ParameterModifier` vs 早期绑定 `ref`）
- 某些成员在后期绑定下应按属性还是方法访问
- 版本差异导致的 `Count/Item` 与 `NumNodes/Node` 并存
- 图片捕获接口在特定环境下的稳定性差异
- PMI 业务字段的实际命名规则
- 标准视角切换的高层封装策略
- COM 对象的显式释放策略（`Marshal.ReleaseComObject`）

结论主线：

- 对象定义，以官方为准。
- C# 工程实践，以运行环境验证为准。

---

## 27. 给代码生成模型（LLM）的生成约定

当你（LLM）根据本手册生成用于操作 Vismockup 的 C# / DLL 代码时，请遵守：

1. **默认后期绑定**：用 `Type.GetTypeFromProgID("VFFrame.Application")` + `Activator.CreateInstance` + `dynamic`，除非用户提供了确定的 COM 类型库。
2. **入口固定**：应用对象入口为 `VFFrame.Application` → `.VisAppAutomation`。
3. **成员名严格一致**：属性/方法名严格按本手册（区分大小写），如 `PrintableName`、`NumNodes`、`Node(index)`、`ExportEnhanced`、`CreateSection`、`PMIQuery`。
4. **[out] 参数**：`GetProperty`、`GetPropertyByName`、`GetCameraPosition`、`SetCameraPosition`、`GetVisibleBBox`、`GetAllPMIInModel` 等带输出参数的方法，后期绑定时用 `InvokeMember` + `ParameterModifier`；早期绑定时用 `ref`。
5. **平台目标**：默认 `x64`，与 Vismockup 位数一致；控制台入口加 `[STAThread]`。
6. **生命周期**：封装类实现 `IDisposable`，在 `Dispose` 中 `Marshal.ReleaseComObject`。
7. **异常**：区分 `COMException`（运行时 COM 错误）与 `RuntimeBinderException`（成员不存在/绑定失败）。
8. **不要臆造成员**：本手册未列出的成员，除非用户明确提供，否则不要凭空生成。

---

## 28. 一句话总结

先拿到 `visApp`（`VFFrame.Application.VisAppAutomation`），再拿到 `doc`，再拿到 `view3d`，然后围绕 `node`、`snapshot`、`section`、`pmi` 这些对象去做操作，最后用 `IDisposable` 封装类把它们打包成 DLL。

这就是 Vismockup C# 自动化开发的最小核心模型。

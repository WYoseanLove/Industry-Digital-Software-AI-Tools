# 功能块 01：应用与会话（Application / Session）

> 对象：`DispVisApp`、`DispVisApp2/3/4`、`VisDispAttachmentMngr`
> 入口：`VFFrame.Application` → `.VisAppAutomation()` → `DispVisApp`
> 能力：启动/退出应用、窗口排列、背景/选择颜色默认值、保存会话（.vf/.vfz）、附件管理、全屏、工具栏/菜单裁剪。

## 对象链路

```text
VFFrame.Application
└── .VisAppAutomation() → DispVisApp
    ├── .Documents              → VisDispDocList
    ├── .ActiveDocument         → VisDispDoc
    ├── .ActiveView             → VisDisp3DView / VisDisp2DView
    ├── .SnapShotManager        → VisDispSnapShotMngr
    ├── .PrintManager           → VisDispPrintManager
    ├── .OutlineManager         → VisDispOutlineMngr
    └── .AttachmentManager      → VisDispAttachmentMngr
```

## DispVisApp — 属性

| 属性 | 类型 | 读写 | 说明 |
| --- | --- | --- | --- |
| `Documents` | VisDispDocList | R | 文档集合 |
| `ActiveDocument` | VisDispDoc | R | 当前活动文档 |
| `ActiveView` | Object | R | 当前活动视图（2D/3D） |
| `Fullname` / `Name` | String | R | 应用完整路径 / 名称 |
| `Width` / `Height` | Long | R/W | 主窗口宽 / 高 |
| `Left` / `Top` | Long | R/W | 主窗口左上角屏幕坐标 |
| `ShowState` | Long | R/W | 窗口显示状态（见 ENUMS.INC） |
| `Default3DBKColor` | VisDispColor | R/W | 3D 默认背景色 |
| `Default3DSelColor` | VisDispColor | R/W | 3D 默认选择色 |
| `Default3DSelStyle` | SELECTION_STYLE | R/W | 3D 默认选择样式 |
| `SnapShotManager` | VisDispSnapShotMngr | R | 快照管理器 |
| `PrintManager` | VisDispPrintManager | R | 打印管理器 |
| `OutlineManager` | VisDispOutlineMngr | R | 轮廓捕获管理器 |
| `AttachmentManager` | VisDispAttachmentMngr | R | 会话附件管理器 |
| `VersionString` / `BuildString` | String | R | 版本 / 构建号 |
| `LocaleString` | String | R | 当前区域设置 |
| `FullScreen` | Bool | R/W | 全屏状态 |

## DispVisApp — 方法

| 方法 | 说明 |
| --- | --- |
| `Quit()` | 关闭所有文档并退出应用 |
| `Sleep(Long MilliSeconds)` | 暂停当前线程指定毫秒 |
| `NewWindow()` | 新建一个视图窗口 |
| `Cascade()` / `TileVertically()` / `TileHorizontally()` | 层叠 / 垂直平铺 / 水平平铺窗口 |
| `SaveSession(Long viewNumber, String strPath)` | 保存会话到 `.vf`。viewNumber：-1 全部视图、0 当前、>0 指定视图 |
| `SaveSessionPackage(String strPath, String strPassword)` | 保存会话包 `.vfz`，密码可空串 |
| `Alert(String strMsgText)` | 弹出应用模态消息框 |
| `ActivateView(Object pDispToActivate)` | 激活传入视图（2D/3D） |
| `ExcludeToolbar(String strName)` | 隐藏指定工具栏（名称需完全匹配） |
| `ExcludeMenuItem(String strName)` | 隐藏指定菜单项（路径需完全匹配） |
| `ToolbarVisibility(String strToolbarName, Long Visibilitystate)` | 1 显示 / 0 隐藏指定工具栏 |

### DispVisApp2/3/4（扩展，多用于 Teamcenter 集成）

- `DispVisApp2`：`ClientProcessId`、`ServerProcessId`（进程存活检测）；`SetTeamcenterPublishMode()`。
- `DispVisApp3`：`MMVAutoUpdate`（分钟，≥15，0 关闭）；`MMVUpdate()` 强制检查更新。
- `DispVisApp4`：`SaveSessionToTeamcenter(TC_ATTACHMENT_TYPE eAttachment, String strName)`。

## VisDispAttachmentMngr — 会话附件

| 成员 | 类型/签名 | 说明 |
| --- | --- | --- |
| `NumAttachments` | Long (R) | 附件数量 |
| `Attachment(Long Index)` | String (R) | 指定索引附件文件名（0 基） |
| `AddAttachment(String strFileName)` | void | 添加附件 |
| `RemoveAttachmentByIndex(Long Index)` | void | 按索引移除 |
| `RemoveAttachmentByName(String strFileName)` | void | 按文件名移除 |
| `RemoveAllAttachments()` | void | 移除全部附件 |

## C# 示例

### 连接并读取版本、排列窗口

```csharp
Type t = Type.GetTypeFromProgID("VFFrame.Application");
dynamic app = ((dynamic)Activator.CreateInstance(t)).VisAppAutomation();

Console.WriteLine($"Version: {app.VersionString}, Build: {app.BuildString}");
app.TileHorizontally();          // 水平平铺所有窗口
```

### 保存会话与会话包

```csharp
app.SaveSession(-1, @"C:\out\review.vf");           // 保存全部视图为 .vf
app.SaveSessionPackage(@"C:\out\review.vfz", "");   // 保存为会话包 .vfz（无密码）
```

### 添加会话附件

```csharp
dynamic att = app.AttachmentManager;
att.AddAttachment(@"C:\out\notes.txt");
Console.WriteLine($"附件数：{att.NumAttachments}");
```

### 设置默认 3D 背景色

```csharp
dynamic bk = app.Default3DBKColor;   // VisDispColor
bk.Red = 0.1f; bk.Green = 0.1f; bk.Blue = 0.15f;
app.Default3DBKColor = bk;
```

## 给代码生成模型的提示

- `SaveSession` 路径必须 `.vf`；`SaveSessionPackage` 必须 `.vfz`。
- 退出用 `Quit()`（会关闭所有文档）；不要直接杀进程。
- `ActiveDocument` / `ActiveView` 在无打开文档时为 `null`，调用前判空。
- 工具栏/菜单裁剪名称需与 UI 完全一致，否则无效。

## 官方 Samples 转写（C#）

### PyScriptClient / attachApp —— 连接（或附着到运行中的实例）

用途：创建或获取正在运行的 VisMockup 应用，拿到 `DispVisApp`。

```csharp
using System;
using System.Runtime.InteropServices;

// 优先附着到已运行实例，失败则新建
public static dynamic InitVisApp()
{
    try
    {
        dynamic app = Marshal.GetActiveObject("VFFrame.Application");
        return app.VisAppAutomation();
    }
    catch
    {
        Type t = Type.GetTypeFromProgID("VFFrame.Application");
        dynamic app = Activator.CreateInstance(t);
        return app.VisAppAutomation();  // DispVisApp
    }
}
```

### detachApp / QuitApp —— 优雅退出并释放

用途：关闭所有文档、退出应用、释放 COM 引用。

```csharp
public static void QuitVisApp(dynamic visApp)
{
    if (visApp == null) return;
    dynamic docs = visApp.Documents;
    if (docs != null) docs.CloseAllDocuments();
    visApp.Quit();            // 会关闭所有文档
    visApp = null;
    GC.Collect();
    GC.WaitForPendingFinalizers();
}
```

### KioskDemo / OutlineExample —— 窗口平铺

```csharp
visApp.TileHorizontally();   // 亦有 TileVertically / Cascade
```

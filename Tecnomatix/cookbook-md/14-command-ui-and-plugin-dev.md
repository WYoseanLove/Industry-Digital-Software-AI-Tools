# 14 · Command, UI & Plugin Development / 命令、UI 与插件开发

> **When to use / 何时使用**
> Build a Process Simulate command/add-in: register an `ITxCommand`, host WPF/WinForms UI
> (`TxWindow`, object/frame/numeric controls, message bar/box), add a custom Viewer, run Script
> Viewer C#/Python snippets, marshal work to the UI thread, manage `IDisposable` memory, fix a
> ribbon-button bitmap not showing, and understand why Python-generated DLLs fail to register.
>
> **Keywords / 关键词**: command, ITxCommand, add-in, plugin, ribbon, button, bitmap, TxWindow, WPF,
> WinForms, TxObjectComboBoxControl, TxObjComboBoxCtrl, TxObjEditBoxControl, TxFrameComboBoxCtrl,
> TxNumericEditBoxControl, TxMessageBar, TxMessageBox, ITxDockingViewerControl, ITxTreeViewerControl,
> ControlBarId, Script Viewer, InvokeRequired, Invoke, thread, IDisposable, Dispose, using,
> Embedded Resource, Python DLL, IronPython, 命令, 界面, 插件, 线程, 内存
>
> **Consolidated from / 归并来源**: `08_命令UI与脚本.md`, `13_UI线程与内存管理.md`,
> `Bitmap Is Not Shown On Newly Created Custom Button Command In Ribbon.md`,
> `Problem Registering Command For Dlls Generated From Python Script.md`

---

## 1. Command basics
A Process Simulate command is a class implementing `ITxCommand`. Register it so it appears on the
ribbon/menu; the command's `Execute` runs your logic. Access the model on the UI thread only.

## 2. Host a WPF window (TxWindow)
Use `TxWindow` to host a WPF `UserControl`. Bind to the active document/selection, and marshal any
background results back to the UI thread (see §5).

## 3. UI controls quick reference / 控件速查
| Control | Use |
| --- | --- |
| `TxObjectComboBoxControl` / `TxObjComboBoxCtrl` | pick a model object from a combo box |
| `TxObjEditBoxControl` | object edit box (drag/pick an object) |
| `TxFrameComboBoxCtrl` | pick a frame |
| `TxNumericEditBoxControl` | numeric input with validation |
| `TxMessageBar` | non-modal status/info bar |
| `TxMessageBox.ShowModal(...)` | modal message box |

## 4. Custom Viewer
Implement `ITxDockingViewerControl` (dockable panel) or `ITxTreeViewerControl` (tree). Assign a
UNIQUE `ControlBarId` per viewer, otherwise viewers collide/replace each other.

## 5. ⚠️ Thread marshaling — Tecnomatix is NOT multi-threaded

All model access must happen on the UI thread. From a worker thread, marshal via `Invoke`.

```csharp
if (control.InvokeRequired)
    control.Invoke(new Action(() => { /* touch the model here */ }));
else
    { /* touch the model here */ }

// Returning a value from the UI thread:
var result = control.Invoke(new Func<string>(() => someModelObject.Name)) as string;
```

## 6. ⚠️ Memory — dispose `IDisposable` objects explicitly

Several API objects are `IDisposable` and leak/misbehave if not disposed (e.g.
`TxCollisionQueryResults`, `TxPoseData`). Wrap in `using` or call `Dispose()`.

```csharp
using (TxCollisionQueryResults results = new TxCollisionQueryResults())
{
    // ...
}
using (TxPoseData pose = robot.CurrentPose)
{
    double j0 = (double)pose.JointValues[0];
}
```

## 7. ⚠️ Ribbon button bitmap not showing — fix the image format

A custom ribbon button shows no icon when the bitmap format is wrong.

- Format: **BMP**, **16×16**, background color **#c0c0c0** (silver), **no transparency/alpha**.
- Build Action = **Embedded Resource** (and reference it by the correct resource name).
- 来源 / Source (forum): <https://community.sw.siemens.com/s/question/0D54O00006E9Z50SAF/> —
  "Bitmap is not shown on newly created custom button command in ribbon".

## 8. ⚠️ Python-generated DLLs cannot register as commands

The .NET API for commands is **C#/VB.NET only**. DLLs produced from Python (IronPython `ipyc.exe`)
fail with: *"dll does not contain classes implementing ITxCommand."*

- A command class MUST inherit/implement `ITxCommand` in a CLR-compliant way that Process Simulate's
  loader recognizes — IronPython-compiled assemblies are not supported for command registration.
- Use C#/VB.NET for commands. (Python can still be used inside the Script Viewer for scripting, not
  for registered ribbon commands.)
- 来源 / Source (forum): <https://community.sw.siemens.com/s/question/0D5Vb00000jx4boKAA/> —
  "Problem registering command for DLLs generated from Python script".

## 9. Script Viewer snippets
The Script Viewer runs ad-hoc C# (and Python) against the active document — good for prototyping the
recipes in this cookbook before packaging them into a registered command.

## See also / 参见
- `08-olp-and-builtin-commands.md` — invoking BUILT-IN commands (vs. authoring your own here).
- `15-mfg-teamcenter-and-part-appearance.md` — internal-extension APIs used from commands.
- `16-api-surface-reference.md` — UI/Viewer API surface and version notes.

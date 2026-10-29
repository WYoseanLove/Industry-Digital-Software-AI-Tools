# 08 · OLP & Built-in Commands / OLP 命令、复合命令与内置命令

> **When to use / 何时使用**
> Add OLP (offline programming) commands to trajectory points (via/weld): comment strings, enter/
> exit interference-zone markers, and `# Destination`-style commands that bind a device; invoke
> built-in Process Simulate commands from code (`TxCommandManager`, e.g. "Convert to Via/Weld
> Location"); read Path-Editor / OLP controller parameters (Speed, Acc, Duration).
>
> **Keywords / 关键词**: OLP, composite command, TxRoboticCompositeCommandStringElement,
> TxRoboticCompositeCommandTxObjectElement, TxRoboticCompositeCommandCreationData,
> CreateCompositeCommand, # Destination, empty command, TxCommandManager,
> ExecuteCommandByCommandProgId, CCoConvertToViaLocation, CCoConvertToWeldLocation, Path Editor,
> TxOlpControllerUtilities, ITxOlpRobotControllerParametersHandler, Speed, Acc, Duration, 复合命令,
> 内置命令, 轨迹编辑器
>
> **Consolidated from / 归并来源**: `15_OLP命令与复合命令.md`,
> `19_内置命令调用TxCommandManager.md`, `20_轨迹编辑器参数读取.md`,
> `Problem Creating Olp Destination Commands Via C Api Command Appears Empty.md`

---

## 1. Create a single OLP command string element

```csharp
private TxRoboticCompositeCommandStringElement CreateOLPCommandElement(
    string command, TxRoboticViaLocationOperation location)
{
    var commandElement = new TxRoboticCompositeCommandStringElement(command);
    commandElement.Value = command;
    return commandElement;
}
// A TxWeldLocationOperation overload is identical (only the parameter type changes).
```

## 2. Attach a command to a trajectory point (CreateCompositeCommand)

```csharp
ArrayList elements = new ArrayList();
elements.Add(CreateOLPCommandElement(
    "Enter " + robotName + " inteference Zone",
    allPointsExist[k] as TxRoboticViaLocationOperation));

TxRoboticCompositeCommandCreationData ccData = new TxRoboticCompositeCommandCreationData(elements);
(allPointsExist[k] as TxRoboticViaLocationOperation).CreateCompositeCommand(ccData);
// TxWeldLocationOperation works identically.
```

## 3. Enter/Exit interference-zone auto-comments (typical scenario)

```csharp
bool collision_test = false;
for (int k = 0; k < allPointsExist.Count; k++)
{
    // ... drive robot to this point's pose (see 04-robot-kinematics-and-pose.md) ...
    bool clear = TxRobotAPIClass.Collision_Check(mainTxControl, cd, queryParams, root, collisionSrc, collisionTar, 3.0);

    if (!clear && !collision_test)        // first entry into interference
    {
        collision_test = true;
        AddOlp(allPointsExist[k], "Enter " + otherRobot + " inteference Zone");
    }
    else if (collision_test && clear)     // leaving interference
    {
        collision_test = false;
        AddOlp(allPointsExist[k], "Exit " + otherRobot + " inteference Zone");
    }
}
// AddOlp dispatches by the point's concrete type and calls CreateCompositeCommand (see §1–2).
```

## 4. `# Destination`-style commands that BIND a device (avoid the "empty command" bug)

A standard OLP command like `# Destination` is not just text — internally it binds a target device.
If you create it from text only, the tree shows the text but the properties dialog is EMPTY.

### ❌ Wrong (looks right, is internally empty)
```csharp
var cd = new TxRoboticCommandCreationData { Text = line };
TxRoboticCommand cmd = loc.CreateCommand(cd);   // no device binding -> empty command
```
`TxRoboticCommand.CreateCommand(TxRoboticCommandCreationData)` builds a plain text line only; it
does NOT parse the device binding `# Destination` needs.

### ✅ Correct (element list + CreateCompositeCommand)
```csharp
// currentLoc: any TxRoboticViaLocationOperation (weld point -> TxWeldLocationOperation)
TxRoboticViaLocationOperation currentLoc =
    TxApplication.ActiveDocument.Selection.GetAllItems()[0] as TxRoboticViaLocationOperation;

// destinationDevice: any ITxObject device (robot/fixture/...); TxRobot here is just an example
ITxObject destinationDevice =
    TxApplication.ActiveDocument.PhysicalRoot.GetAllDescendants(new TxTypeFilter(typeof(TxRobot)))[0];

TxRoboticCompositeCommandStringElement e0 = new TxRoboticCompositeCommandStringElement("# Destination");
TxRoboticCompositeCommandTxObjectElement e1 = new TxRoboticCompositeCommandTxObjectElement(destinationDevice);

ArrayList newCommandElements = new ArrayList();
newCommandElements.Add(e0);
newCommandElements.Add(e1);

TxRoboticCompositeCommandCreationData newCommandData = new TxRoboticCompositeCommandCreationData();
newCommandData.Name = "";                  // ⚠️ Name MUST be an empty string
newCommandData.Elements = newCommandElements;

currentLoc.CreateCompositeCommand(newCommandData);
```
> ⚠️ `Name` must be `""` (empty). The `# Destination` text is the string element; the device is the
> object element. Steps to obtain `currentLoc` / `destinationDevice` are examples — any valid
> location / device works.
> 来源 / Source (forum): <https://community.sw.siemens.com/s/question/0D5Vb00000vjFgVKAU/> —
> "Problem creating OLP # Destination commands via C# API – command appears empty".

## 5. Invoke a built-in PS command (TxCommandManager)

`ExecuteCommandByCommandProgId(progId, TxObjectList)` runs a built-in command on the ACTIVE
SELECTION; it does NOT accept parameters, so pass an empty `TxObjectList()`.

```csharp
using Tecnomatix.Engineering;

// Select the target location(s) first (the command acts on the active selection).
TxCommandManager executer = new TxCommandManager();
executer.ExecuteCommandByCommandProgId("CCoConvertToViaLocation",  new TxObjectList()); // Convert to Via Location
executer.ExecuteCommandByCommandProgId("CCoConvertToWeldLocation", new TxObjectList()); // Convert to Weld Location
```
- Second argument MUST be `new TxObjectList()` (empty) — parameters are not supported.
- ⚠️ Deleting a weld location: `TxWeldLocationOperation.Delete()` also deletes its `TxWeldPoint`.
  Workaround: cache the `TxWeldPoint` info → `Delete()` the location → recreate the weld point from
  the cached info.
- 来源 / Source (forum): thread on `TxCommandsManager` "Convert to weld/via location" (best answer
  by GillesVelay).

## 6. Read Path-Editor / OLP controller parameters (Speed, Acc)

Columns that vary with the controller (Speed, Acc) are OLP controller parameters — read them via
`TxOlpControllerUtilities` → `ITxOlpRobotControllerParametersHandler`.

```csharp
public string GetDynamicParameter(string controllername, string columnName, ITxOperation op)
{
    string paramValue = string.Empty;
    TxOlpControllerUtilities utils = new TxOlpControllerUtilities();
    ITxOlpRobotControllerParametersHandler paramHandler =
        (ITxOlpRobotControllerParametersHandler)utils.GetInterfaceImplementationFromController(
            controllername,
            typeof(ITxOlpRobotControllerParametersHandler),
            typeof(TxRobotSimulationControllerAttribute),
            "ControllerName");

    if (paramHandler != null &&
        paramHandler.HasComplexRepresentation(columnName, op, TxOlpCommandLayerRepresentation.UI))
    {
        paramValue = paramHandler.GetComplexRepresentation(columnName, op, TxOlpCommandLayerRepresentation.UI);
    }
    return paramValue;
}

// controller name comes from the location's owning robotic operation:
// ((op.Collection as ITxRoboticOrderedCompoundOperation).Robot.Controller.Name)
// columnName: "Speed" (joint speed) or "Acc" (acceleration).
```

### Duration is a generic operation property (do NOT use GetDynamicParameter)
```csharp
double duration = op.Duration;   // op = ITxOperation / ITxRoboticLocationOperation
```

### Get the robot name from a location operation
```csharp
ITxRoboticLocationOperation robLoc = TxApplication.ActiveSelection.GetItems()[0] as ITxRoboticLocationOperation;
if (robLoc != null)
{
    ITxRoboticOrderedCompoundOperation roboticOperation = robLoc.ParentRoboticOperation;
    string robotName = roboticOperation.Robot.Name;
}
```
> 来源 / Source (forum): <https://community.sw.siemens.com/s/question/...> — "Getting parameters
> from patheditor" (answer by DianaG, verified by Düren).

## See also / 参见
- `06-operations-and-trajectory.md` — create the trajectory points these commands attach to.
- `10-collision-and-interference.md` — the interference-zone check driving §3.
- `14-command-ui-and-plugin-dev.md` — writing your OWN commands (not built-in ones).

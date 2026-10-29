# 02 · Object Type & Selection / 对象类型与选择

> **When to use / 何时使用**
> Whenever you hold an `ITxObject` (from a search or the active selection) and must safely decide
> WHAT it is before calling type-specific members; whenever the request mentions "the selected
> object(s)", "current selection", casting, `Locate`, or "jump/focus to an object in the tree".
>
> **Keywords / 关键词**: object, type, concrete type, GetType, cast, as, selection,
> ActiveSelection, GetItems, GetAllItems, Locate, focus, jump to tree, TxRobot, TxDevice,
> TxServoGun, TxComponent, TxGripper, TxCompoundPart, TxPartAppearance, 类型判定, 选择, 定位
>
> **Consolidated from / 归并来源**: `02_对象类型与选择.md`,
> `How To Focus On A Component When I Click It On Txwinformim...md`

---

## 1. Mandatory type-handling rule / 强制类型处理规则

Before touching ANY Tecnomatix object you MUST, in order:
1. Null-check `target != null`
2. Exact type check `target.GetType() == typeof(TxXxx)`
3. Cast with `as`
4. Null-check the cast result
5. Only then access that type's specific members

```csharp
if (target != null && target.GetType() == typeof(TxDevice))
{
    var device = target as TxDevice;
    if (device != null) { /* ... */ }
}
```

> ⚠️ Do NOT assume a robot casts safely to `TxDevice`. A robot must cast to `TxRobot`.

### Cast target reference / 转型对照
| Runtime object / 运行时类型 | Cast target / 转型目标 |
| --- | --- |
| Robot 机器人 | `TxRobot` |
| Servo gun 伺服焊枪 | `TxServoGun` |
| Device 设备 | `TxDevice` |
| Component 组件 | `TxComponent` |
| Gripper 抓手 | `TxGripper` |
| Compound part 复合零件 | `TxCompoundPart` |
| Part appearance 零件外观 | `TxPartAppearance` |
| Weld location op 焊点操作 | `TxWeldLocationOperation` |
| Via location op | `TxRoboticViaLocationOperation` |
| Seam location op 缝焊点操作 | `TxRoboticSeamLocationOperation` |
| Weld operation 焊接操作 | `TxWeldOperation` |
| Frame 坐标系 | `TxFrame` |

## 2. Read the current selection / 读取当前选择

```csharp
TxObjectList pickObjlist = TxApplication.ActiveSelection.GetItems();
// or GetAllItems() — returns whatever is currently selected: parts, devices, robots,
// components, tools, guns, frames, operations, path points, ...
```

### Recommended dispatch loop
```csharp
TxObjectList pickObjlist = TxApplication.ActiveSelection.GetItems();
foreach (ITxObject item in pickObjlist)
{
    if (item.GetType() == typeof(TxRobot))
    {
        var robot = item as TxRobot;
        if (robot != null) { /* ... */ }
    }
    else if (item.GetType() == typeof(TxDevice))
    {
        var device = item as TxDevice;
        if (device != null) { /* ... */ }
    }
    else if (item.GetType() == typeof(TxServoGun))
    {
        var gun = item as TxServoGun;
        if (gun != null) { /* ... */ }
    }
    else if (item.GetType() == typeof(TxComponent))
    {
        var component = item as TxComponent;
        if (component != null) { /* ... */ }
    }
    else if (item.GetType() == typeof(TxCompoundPart))
    {
        var compoundPart = item as TxCompoundPart;
        if (compoundPart != null) { /* ... */ }
    }
    else if (item.GetType() == typeof(TxPartAppearance))
    {
        var partAppearance = item as TxPartAppearance;
        if (partAppearance != null) { /* ... */ }
    }
}
```

## 3. Locate an object to a target point / 定位对象到目标点

Resolve the concrete type first, then call `Locate(point)` where `point` is a `TxTransformation`:

```csharp
if (target != null && target.GetType() == typeof(TxDevice))
{
    var device = target as TxDevice;
    if (device != null) device.Locate(point);
}
if (target != null && target.GetType() == typeof(TxRobot))
{
    var robot = target as TxRobot;
    if (robot != null) robot.Locate(point);
}
if (target != null && target.GetType() == typeof(TxCompoundPart))
{
    var compoundPart = target as TxCompoundPart;
    if (compoundPart != null) compoundPart.Locate(point);
}
if (target != null && target.GetType() == typeof(TxPartAppearance))
{
    var partAppearance = target as TxPartAppearance;
    if (partAppearance != null) partAppearance.Locate(point);
}
```

> For location objects (via/frame) that expose `AbsoluteLocation`, assign that instead of
> `Locate`. See `11-geometry-and-transformation.md` (Location move).

## 4. Operation-type rules / 操作类型判定

For operation / path logic, resolve the exact operation type first. Common types:
`TxWeldLocationOperation`, `TxRoboticViaLocationOperation`, `TxRoboticSeamLocationOperation`,
`TxWeldOperation`, `TxFrame`.

## 5. Focus / select an object in the Resource tree / 在资源树中聚焦对象

Setting the active selection makes the tree jump to and highlight the object — useful for
"click in my WinForm → jump to the component in the tree" (PDPS).

```csharp
TxSelection Selection = TxApplication.ActiveSelection;
Selection.Clear();
TxObjectList SelObjectList = new TxObjectList() { yourObject }; // one or more ITxObject
Selection.AddItems(SelObjectList);
```

> 来源 / Source (forum): <https://community.sw.siemens.com/s/question/0D5Vb00000aPN88KAG/> —
> "how to focus on a component when I click it on TxWinForm" (answer by Henry Muschler).

## See also / 参见
- `01-traversal-and-search.md` — find the object before resolving its type.
- `03-attachment-and-ownership.md` — resolve attachment/ownership by id, not by type alone.

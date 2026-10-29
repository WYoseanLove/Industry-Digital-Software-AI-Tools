# 01 · Traversal & Search / 搜索与遍历

> **When to use / 何时使用**
> ANY request that must first *locate* objects in the Tecnomatix tree before acting on them:
> "find robot X", "list all weld operations", "get everything under station Y", "iterate the
> physical/operation tree", "search a folder", "get the object by name". Reach for this FIRST,
> before writing any robot / device / operation logic.
>
> **Keywords / 关键词**: traversal, search, find, list, tree, descendants, PhysicalRoot,
> OperationRoot, MainFolders, GetAllDescendants, GetDirectDescendants, TxTypeFilter,
> TxNoTypeFilter, GetObjectsByName, ITxObjectCollection, ITxMainFolder, FindByName,
> 搜索, 遍历, 按名称查找
>
> **Consolidated from / 归并来源**: `01_搜索与遍历.md`, `Traversal-And-Search.md`

---

## Generalization rules / 泛化规则
- A helper like `FindRobotByName` (uses `TxTypeFilter(typeof(TxRobot))`) generalizes to
  `FindDeviceByName`, `FindServoGunByName`, `FindComponentByName`, etc., by swapping the type.
  For mixed/unknown types use `new TxNoTypeFilter()` then check the concrete type per item.
- Keep the SAME structure (exact match first, partial fallback; null-checks; type-check before
  cast) when you generalize. Only the type and member names change.
- Do NOT invent API members. Generalize ONLY across types that share the member.
- `GetDirectDescendants` → only the immediate children of that node (one level down).
  `GetAllDescendants` → every node beneath it, recursively (all levels).

## 1. Global search — PhysicalRoot / OperationRoot

```csharp
// --- Physical tree (resources: robots, devices, components, frames ...) ---

// No type filter — every DIRECT child of the physical root:
TxObjectList rootList = TxApplication.ActiveDocument.PhysicalRoot
    .GetDirectDescendants(new TxNoTypeFilter());

// Filtered by a concrete PHYSICAL type. TxRobot is only an example — substitute any
// physical-tree type (TxDevice, TxServoGun, TxComponent, TxGripper, TxFrame, ...).
// Do NOT pass operation types (TxWeldOperation, ...) here; those live under OperationRoot.
TxObjectList robotList = TxApplication.ActiveDocument.PhysicalRoot
    .GetDirectDescendants(new TxTypeFilter(typeof(TxRobot)));

// Every descendant at ALL levels (recursive), unfiltered:
TxObjectList allList = TxApplication.ActiveDocument.PhysicalRoot
    .GetAllDescendants(new TxNoTypeFilter());

// --- Operation tree (operations, weld operations, location operations ...) ---
// Same calls, but swap PhysicalRoot -> OperationRoot:
TxObjectList allOps = TxApplication.ActiveDocument.OperationRoot
    .GetAllDescendants(new TxNoTypeFilter());
TxObjectList weldOps = TxApplication.ActiveDocument.OperationRoot
    .GetAllDescendants(new TxTypeFilter(typeof(TxWeldOperation)));
```

### Filter by several types at once (multi-type filter)
```csharp
// Get all weld-spot Locations AND via Locations under one operation:
TxTypeFilter opFilter = new TxTypeFilter(typeof(TxWeldLocationOperation));
opFilter.AddIncludedType(typeof(TxRoboticViaLocationOperation));
TxObjectList allWeldPointsExist = weldTargetOperation.GetDirectDescendants(opFilter);

// Or via the array constructor (included types, excluded types):
Type[] locationTypes =
{
    typeof(TxGenericRoboticLocationOperation),
    typeof(TxRoboticSeamLocationOperation),
    typeof(TxRoboticViaLocationOperation),
    typeof(TxWeldLocationOperation)
};
TxTypeFilter locationFilter = new TxTypeFilter(locationTypes, new Type[0]);
```

## 2. Search the levels under a named node (e.g. a Station "testname")

Strategy: use a global search to reach candidate nodes, then treat the matched node as an
`ITxObjectCollection` and recurse downward.

```csharp
foreach (ITxObject obj in objList)
{
    if (obj is ITxMainFolder) continue;

    if (obj.Name.ToLower() == testname.ToLower())
    {
        // Found the target node — collect its children downward.
        ITxObjectCollection container = obj as ITxObjectCollection;
        if (container != null)
        {
            TxObjectList children = container.GetDirectDescendants(new TxNoTypeFilter());
            // ... process / recurse into children ...
        }
        continue;
    }

    // Not a match — keep searching deeper.
    ITxObjectCollection subContainer = obj as ITxObjectCollection;
    if (subContainer != null)
    {
        TxObjectList children = subContainer.GetDirectDescendants(new TxNoTypeFilter());
        // ... recurse into children ...
    }
}
```

## 3. Folder traversal (MainFolders)

```csharp
TxObjectList<ITxMainFolder> mainFolderList = TxApplication.ActiveDocument.MainFolders;

foreach (ITxObject obj in mainFolderList)
{
    ITxMainFolder mainFolder = obj as ITxMainFolder;
    if (mainFolder == null) continue;

    TxObjectList mainFolderChildren =
        mainFolder.GetDirectDescendants(new TxNoTypeFilter());

    SearchForFolder(mainFolderChildren, targetName); // your recursive method
}
```

## 4. Find an object by name (exact, then partial)

```csharp
TxRobot FindRobotByName(string robName)
{
    TxObjectList robots = TxApplication.ActiveDocument.PhysicalRoot
        .GetAllDescendants(new TxTypeFilter(typeof(TxRobot)));
    TxRobot partial = null;
    foreach (ITxObject item in robots)
    {
        TxRobot r = item as TxRobot;
        if (r == null) continue;
        if (string.Equals(r.Name, robName, StringComparison.OrdinalIgnoreCase)) return r;
        if (partial == null && r.Name.IndexOf(robName, StringComparison.OrdinalIgnoreCase) >= 0)
            partial = r;
    }
    return partial;
}
```

### Direct name lookup (GetObjectsByName)
`TxApplication.ActiveDocument.GetObjectsByName(name)` returns all same-named objects; combine
with a generic helper to filter by type:

```csharp
public static T GetObjectByName<T>(string objectName) where T : class, ITxObject
{
    TxObjectList foundObjects = TxApplication.ActiveDocument.GetObjectsByName(objectName);
    T foundObj = null;
    foreach (ITxObject o in foundObjects)
    {
        foundObj = o as T;
        if (foundObj != null) break;
    }
    return foundObj;
}
```

## See also / 参见
- `02-object-type-and-selection.md` — resolve the concrete type after finding an object, and read
  the active selection.
- `03-attachment-and-ownership.md` — for "attached devices/parts" or "which robot owns X", do NOT
  rely on tree nesting; use `AttachmentParent` id matching.

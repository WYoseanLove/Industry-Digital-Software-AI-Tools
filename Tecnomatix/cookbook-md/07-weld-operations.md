# 07 · Weld Operations / 焊接操作

> **When to use / 何时使用**
> Create weld operations for a robot (with a mounted gun), create weld points
> (`TxWeldLocationOperation`), bind a leading part, and enumerate the products/parts assigned to a
> weld operation.
>
> **Keywords / 关键词**: weld, weld operation, weld point, spot, TxWeldOperation,
> TxWeldOperationCreationData, CreateWeldOperation, TxWeldLocationOperation,
> TxWeldLocationOperationCreationData, TxMfgCreationDataFactory, CreateWeldPointCreationData,
> LeadingPart, WeldPointCreationData, ProjectedLocation, AssignedParts, products, 焊接, 焊点, 主导零件
>
> **Consolidated from / 归并来源**: `04_焊接操作.md`, `Weld-Operation-Creation.md`,
> `How To Get The Products In A Weld Operation Through The Api.md`

---

## 1. Create a weld operation for a robot (with mounted gun)

```csharp
TxWeldOperationCreationData data = new TxWeldOperationCreationData(operationName);
data.Robot = robot;

TxServoGun gun = null;
for (int i = 0; i < robot.MountedTools.Count; i++)
    if (robot.MountedTools[i].GetType() == typeof(TxServoGun))
        gun = (TxServoGun)robot.MountedTools[i];
if (gun != null) data.Gun = gun;

TxApplication.ActiveDocument.OperationRoot.CreateWeldOperation(data);
TxApplication.RefreshDisplay();
message = string.Format("Operation '{0}' created for robot '{1}'.", operationName, robot.Name);
```

## 2. Create a weld point under a weld operation

```csharp
ITxWeldPointCreationData wpcd =
    TxMfgCreationDataFactory.CreateWeldPointCreationData(pointName, location);   // location = TxTransformation

TxWeldLocationOperationCreationData wld = new TxWeldLocationOperationCreationData(pointName);
wld.WeldPointCreationData = wpcd;
wld.ProjectedLocation     = location;

TxWeldLocationOperation wl = weldOp.CreateWeldLocationOperation(wld);
```

### With a leading part
```csharp
private void AddRobotWeldSpotProcess(string weldName, TxTransformation location,
                                     TxWeldOperation op, TxComponent selectedPart)
{
    ITxWeldPointCreationData wpcd =
        TxMfgCreationDataFactory.CreateWeldPointCreationData(weldName, location);
    wpcd.LeadingPart = selectedPart;   // designate the Leading Part

    TxWeldLocationOperationCreationData weldLocData =
        new TxWeldLocationOperationCreationData(weldName) { WeldPointCreationData = wpcd };

    op.CreateWeldLocationOperation(weldLocData);
}
```

## 3. ⚠️ Common error: `MfgRoot.CreateWeldPoint` is NOT implemented

Do NOT create a weld point directly on `MfgRoot` — it throws:

```csharp
// ❌ Throws TargetInvocationException ---> TxNotImplementedException
ITxWeldPointCreationData wpcd =
    TxMfgCreationDataFactory.CreateWeldPointCreationData("test", new TxVector(100, 200, 300));
TxMfgRoot mfgRoot = TxApplication.ActiveDocument.MfgRoot;
ITxWeldPoint wp = mfgRoot.CreateWeldPoint(wpcd);   // ITxMfgFeatureCreation.CreateWeldPoint unimplemented
```

- Conclusion (forum, confirmed by Xplore/Osean): `ITxMfgFeatureCreation.CreateWeldPoint` is **not
  implemented**. Use `ITxWeldLocationOperationCreation.CreateWeldLocationOperation` instead
  (e.g. `TxOperationRoot.CreateWeldLocationOperation` or the weld operation's
  `CreateWeldLocationOperation`, as in §2).
- 来源 / Source (forum): thread "CreateWeldPoint" (Q: Xplore, A: Osean).

## 4. Get the products/parts assigned to a weld operation

```csharp
using Tecnomatix.Engineering;
using Tecnomatix.Planning;

ITxObject selected = TxApplication.ActiveSelection.GetAllItems()[0];
ITxProcessModelObject pmo = selected as ITxProcessModelObject;
if (pmo != null)
{
    TxPlanningOperation po = pmo.PlanningRepresentation as TxPlanningOperation;
    if (po != null)
    {
        var parts = po.AssignedParts;          // the assigned products/parts
        foreach (ITxObject part in parts)
            output.WriteLine(string.Format("Part '{0}' [{1}]", part.Name, part.GetType()));
    }
}
```
> 来源 / Source (forum): <https://community.sw.siemens.com/s/question/0D5Vb00000zqORLKA2/> —
> "How to get the products in a Weld Operation through the API" (Nikolay Hristov). Note the MFG
> planning representation lives under `Tecnomatix.Planning` (`TxPlanningOperation.AssignedParts`).

## API quick reference / 速查
| Member | Use |
| --- | --- |
| `TxWeldOperationCreationData` (`.Robot` / `.Gun`) | weld operation creation data |
| `OperationRoot.CreateWeldOperation(data)` | create weld operation |
| `TxMfgCreationDataFactory.CreateWeldPointCreationData(...)` | weld point creation data factory |
| `TxWeldLocationOperationCreationData` | weld point op creation data |
| `weldOp.CreateWeldLocationOperation(wld)` | create weld point under weld op |
| `TxWeldLocationOperation.GetTranslationLimit` | weld point translation limit (v12.1.2+) |
| `TxPlanningOperation.AssignedParts` | products/parts assigned to the operation |

## See also / 参见
- `06-operations-and-trajectory.md` — via/generic operations & trajectory management.
- `15-mfg-teamcenter-and-part-appearance.md` — MFG features, planning representation, Teamcenter.
- `19-内置命令调用TxCommandManager` → see `08-olp-and-builtin-commands.md` for "Convert to Weld/Via
  Location" and weld-point deletion caveats.

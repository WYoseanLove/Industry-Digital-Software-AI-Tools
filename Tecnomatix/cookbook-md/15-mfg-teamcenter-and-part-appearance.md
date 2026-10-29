# 15 · MFG, Teamcenter & Part Appearance / MFG、Teamcenter 与零件外观

> **When to use / 何时使用**
> Create `PartAppearance` objects (and work around the "not supported in standard study mode"
> exception), handle Teamcenter-environment "action not supported" errors on compound-part creation,
> and map a UI MFG property to its .NET class member.
>
> **Keywords / 关键词**: PartAppearance, TxPartAppearanceCreationDataEx, CreatePartAppearance,
> TxOperationEx, EngineeringInternalExtension, standard study mode, TxNotSupportedInStandardStudyMode,
> Teamcenter, TxCompoundPart, TxCompoundPartCreationData, CanCreateCompoundPart, MFG feature,
> AssignedMfgFeatures, ITxRoboticOrderedCompoundOperation, PlanningRepresentation, 零件外观, 复合零件
>
> **Consolidated from / 归并来源**:
> `How To Correctly Create Partappearances Using The Process Simulate Api.md`,
> `Keep Getting This Error This Action Is Not Supported In Teamcenter Environment.md`,
> `Api Please Tell Me The Corresponding Classmember Using Net Api.md`

---

## 1. ⚠️ Create a PartAppearance (standard study mode workaround)

Directly creating a `PartAppearance` in **standard** study mode throws
`TxNotSupportedInStandardStudyModeException`. Use the internal-extension API instead.

```csharp
using EngineeringInternalExtension;   // internal-extension namespace

// operation: the TxOperation you want the appearance under
TxPartAppearanceCreationDataEx dataEx = new TxPartAppearanceCreationDataEx(/* part, ... */);
TxOperationEx opEx = new TxOperationEx(operation);
var appearance = opEx.CreatePartAppearance(dataEx);
```
- The standard `CreatePartAppearance` path is blocked in standard study mode; `TxOperationEx` +
  `TxPartAppearanceCreationDataEx` (from `EngineeringInternalExtension`) is the working route.
- 来源 / Source (forum): <https://community.sw.siemens.com/s/question/0D5Vb0000173FxFKAU/> —
  "How to correctly create PartAppearances using the Process Simulate API".

## 2. ⚠️ Teamcenter: "This action is not supported in Teamcenter environment"

Some creation calls (e.g. `CreateCompoundPart`) are blocked in a Teamcenter (managed) environment.
Guard with the `CanCreate...` check before creating.

```csharp
TxCompoundPartCreationData data = new TxCompoundPartCreationData(name);
ITxCompoundPartCreation creator = owner as ITxCompoundPartCreation;
if (creator != null && creator.CanCreateCompoundPart(data))
{
    TxCompoundPart cp = creator.CreateCompoundPart(data);
}
else
{
    // Not permitted in this (Teamcenter) environment — handle gracefully / inform the user.
}
```
- 来源 / Source (forum): <https://community.sw.siemens.com/s/question/0D5Vb00001CluROKAZ/> —
  "Keep getting this error: This action is not supported in Teamcenter environment".

## 3. Map a UI MFG property to its .NET class member

To find which class member backs a property shown in the MFG UI, go through the operation's
planning/robotic-compound representation and its assigned MFG features.

```csharp
ITxRoboticOrderedCompoundOperation roboticCompound = op as ITxRoboticOrderedCompoundOperation;
TxPlanningOperation planningOp = (op as ITxProcessModelObject).PlanningRepresentation as TxPlanningOperation;

var mfgFeatures = planningOp.AssignedMfgFeatures;   // the MFG features behind UI properties
foreach (ITxObject f in mfgFeatures)
{
    // inspect f's members to locate the property shown in the UI
}
```
- 来源 / Source (forum): <https://community.sw.siemens.com/s/question/0D5Vb00000abiYoKAI/> —
  "[API] Please tell me the corresponding class member using .NET API".

## API quick reference / 速查
| Member | Use |
| --- | --- |
| `TxPartAppearanceCreationDataEx` (EngineeringInternalExtension) | part appearance creation data (ext) |
| `TxOperationEx(operation).CreatePartAppearance(...)` | create appearance in standard mode |
| `TxCompoundPartCreationData` / `CanCreateCompoundPart` / `CreateCompoundPart` | compound part (TC guard) |
| `ITxRoboticOrderedCompoundOperation` | robotic compound op representation |
| `TxPlanningOperation.AssignedMfgFeatures` | MFG features behind UI properties |
| `(ITxProcessModelObject).PlanningRepresentation` | planning representation of an operation |

## See also / 参见
- `07-weld-operations.md` — `TxPlanningOperation.AssignedParts` for products in a weld op.
- `14-command-ui-and-plugin-dev.md` — internal-extension usage from a command.

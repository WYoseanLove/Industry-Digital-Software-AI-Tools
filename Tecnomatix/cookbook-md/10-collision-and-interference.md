# 10 · Collision & Interference / 碰撞检测与干涉

> **When to use / 何时使用**
> Create collision pairs, run collision/near-miss queries between object lists, read collision
> states, compute minimal distance/clearance between two objects, and generate collision reports.
>
> **Keywords / 关键词**: collision, interference, near miss, clearance, TxCollisionRoot, PairList,
> TxCollisionPairCreationData, CreateCollisionPair, TxCollisionQueryResults, TxCollisionQueryParams,
> DefinedPairs, NearMissDistance, GetCollidingObjects, TxCollisionState, GetMinimalDistance,
> 碰撞, 干涉, 最小距离, 近距离
>
> **Consolidated from / 归并来源**: `06_碰撞检测.md`, collision half of `Simulation-And-Collision.md`
> (open-source origin: WYoseanLove / Industry-Robot-Auto-Path-Planner)

---

## 1. Create a collision pair

```csharp
TxCollisionRoot collisionRoot = TxApplication.ActiveDocument.CollisionRoot;

TxObjectList srcList = new TxObjectList(); srcList.Add(tool);
TxObjectList tarList = new TxObjectList(); tarList.Add(part);

TxCollisionPairCreationData pairData =
    new TxCollisionPairCreationData("Pair_Tool_Part", srcList, tarList, nearMissDistance /*e.g. 3.0*/);
TxCollisionPair pair = collisionRoot.CreateCollisionPair(pairData);
```

## 2. Query collisions (defined pairs + near-miss)

```csharp
public static bool Collision_Check(
    TxApplication mainTxControl, TxCollisionQueryData cd, TxCollisionQueryParams queryParams,
    TxCollisionRoot root, TxObjectList collisionSrc, TxObjectList collisionTar, double nearMiss)
{
    bool clear = true;
    using (TxCollisionQueryResults results = new TxCollisionQueryResults())
    {
        queryParams.Mode             = TxCollisionQueryParams.TxCollisionInquiryMode.DefinedPairs;
        queryParams.NearMissDistance = nearMiss;

        root.GetCollidingObjects(queryParams, results);
        foreach (TxCollisionState state in results.States)
        {
            if (state.Type == TxCollisionState.TxCollisionStateType.Collision)
            {
                clear = false;
                break;
            }
        }
    }
    return clear;
}
```
> ⚠️ Always wrap `TxCollisionQueryResults` in a `using` (it is `IDisposable`).

## 3. Minimal distance / clearance between two objects

```csharp
double clearance;
TxVector pointOnTool, pointOnCollision;
(tool as ITxLocatableObject).GetMinimalDistance(
    otherObject as ITxLocatableObject,
    out clearance, out pointOnTool, out pointOnCollision);
```

## 4. Activate ONE named pair and generate a report

```csharp
foreach (TxCollisionPair p in collisionRoot.PairList)
    p.IsActive = (p.Name == "Pair_Tool_Part");   // activate just the one you want

// ... run the query (see §2) ...
// Then write the offending pairs / states to your report/output.
```

## 5. Add/remove objects in a pair (clone the lists — never mutate in place)

`FirstList` / `SecondList` must be replaced with a rebuilt list; mutating the returned list in
place does not persist.

```csharp
// Remove an object by Id
TxObjectList newFirst = new TxObjectList();
foreach (ITxObject o in pair.FirstList)
    if (o.Id != objectToRemove.Id) newFirst.Add(o);
pair.FirstList = newFirst;      // reassign

// Add an object
TxObjectList newSecond = new TxObjectList();
foreach (ITxObject o in pair.SecondList) newSecond.Add(o);
newSecond.Add(objectToAdd);
pair.SecondList = newSecond;    // reassign
```

## API quick reference / 速查
| Member | Use |
| --- | --- |
| `TxApplication.ActiveDocument.CollisionRoot` | collision root |
| `TxCollisionPairCreationData(name, src, tar, nearMiss)` | pair creation data |
| `collisionRoot.CreateCollisionPair(data)` | create a pair |
| `collisionRoot.PairList` / `pair.IsActive` | enumerate / activate pairs |
| `TxCollisionQueryParams.Mode = DefinedPairs` | query only defined pairs |
| `TxCollisionQueryParams.NearMissDistance` | near-miss threshold |
| `root.GetCollidingObjects(params, results)` | run the query |
| `TxCollisionQueryResults.States` / `TxCollisionState.Type` | inspect results |
| `(ITxLocatableObject).GetMinimalDistance(other, out clr, out p1, out p2)` | min distance |

## See also / 参见
- `09-simulation-and-playback.md` — run per-frame collision checks during playback.
- `11-geometry-and-transformation.md` — geometry-based distance & measurement.
- `08-olp-and-builtin-commands.md` — auto-insert Enter/Exit interference-zone OLP comments.

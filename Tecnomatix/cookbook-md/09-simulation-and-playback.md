# 09 · Simulation & Playback / 仿真与播放

> **When to use / 何时使用**
> Play/step/jump a simulation of an operation or weld trajectory with `TxSimulationPlayer`; sample
> every frame (per-frame collision, swept-volume sampling); drive playback via the Path Editor and
> stop at a specific location; understand why API-driven playback stops early.
>
> **Keywords / 关键词**: simulation, playback, play, TxSimulationPlayer, SetOperation, Play,
> PlayWithoutRefresh, JumpSimulationToTime, TimeInterval, TimeIntervalReached, Rewind, Stop,
> SimulationPlayer, PathEditorViewer, OperationReachedDestination, OperationEndedProcessingLocation,
> 仿真, 播放, 逐帧采样
>
> **Consolidated from / 归并来源**: `05_仿真与播放.md`, simulation half of `Simulation-And-Collision.md`,
> `Why Is My Simulation Run Stopping When I Use The Api But Not When I Use The Play.md`

---

## 1. Play a weld operation

```csharp
TxWeldOperation weldOp = target as TxWeldOperation;
if (weldOp != null && target.GetType() == typeof(TxWeldOperation))
{
    TxSimulationPlayer player = new TxSimulationPlayer();
    player.SetOperation(weldOp);
    player.JumpSimulationToTime(0.00, true,  TxSimulationPlayerSource.TaskSimulationPlayer);
    player.Play();
    player.JumpSimulationToTime(0.00, false, TxSimulationPlayerSource.TaskSimulationPlayer);
}
```

### Recommended flow
1. Resolve the target operation object and verify its type.
2. Create `TxSimulationPlayer`.
3. `SetOperation(...)` to bind the operation.
4. `JumpSimulationToTime(0.00, ...)` to the start.
5. `Play()`, then jump again if needed.

## 2. Event-driven per-frame sampling + speed/step control

Use this to sample every frame (per-frame collision, swept-volume accumulation). Verified pattern.

```csharp
TxSimulationPlayer mSimulationPlayer = new TxSimulationPlayer();
mSimulationPlayer.TimeInterval = 0.01;                    // sampling step (seconds)
TxApplication.Options.Simulation.SimulationSpeed = 100;   // simulation speed

ITxOperation op = someOperation as ITxOperation;
mSimulationPlayer.TimeIntervalReached += player_TimeIntervalReached;
mSimulationPlayer.SetOperation(op);
mSimulationPlayer.PlayWithoutRefresh();                   // no display refresh -> fast
mSimulationPlayer.TimeIntervalReached -= player_TimeIntervalReached;
mSimulationPlayer.JumpSimulationToTime(0.00, false, TxSimulationPlayerSource.TaskSimulationPlayer);

private static void player_TimeIntervalReached(object sender,
    TxSimulationPlayer_TimeIntervalReachedEventArgs args)
{
    using (var pose = robot.CurrentPose)
    {
        double j0 = (double)pose.JointValues[0];
        // ... per-frame processing ...
        // if (problemFound) mSimulationPlayer.Stop();
    }
}
```
> Global sim step: `TxApplication.ActiveDocument.SimulationPlayer.TimeInterval`.

## 3. Drive via Path Editor and stop at a specific location

The document's shared `SimulationPlayer` + `PathEditorViewer.Play()` runs the current path; use
the reached/ended events to detect a specific location and `Stop()`.

```csharp
public static LocationSimulationResult SimulatePathUntilLocation(ITxOperation location)
{
    var simPlayer  = TxApplication.ActiveDocument.SimulationPlayer;
    var pathViewer = TxApplication.ViewersManager.PathEditorViewer;
    LocationSimulationResult result = LocationSimulationResult.NotReached;

    void OnReachedDestination(object sender, TxSimulationPlayer_OperationReachedDestinationEventArgs args)
    {
        if (args.Operation.Id == location.Id)
            result |= LocationSimulationResult.ReachedDestination;
    }
    void OnEndedProcessingLocation(object sender, TxSimulationPlayer_OperationEndedProcessingLocationEventArgs args)
    {
        if (args.FinishedTarget.Id == location.Id)
        {
            result |= LocationSimulationResult.EndedProcessingLocation;
            (sender as TxSimulationPlayer).Stop();
        }
    }

    simPlayer.OperationReachedDestination        += OnReachedDestination;
    simPlayer.OperationEndedProcessingLocation   += OnEndedProcessingLocation;
    pathViewer.Play();
    simPlayer.OperationReachedDestination        -= OnReachedDestination;
    simPlayer.OperationEndedProcessingLocation   -= OnEndedProcessingLocation;
    return result;
}
```
> ⚠️ Why API playback "stops" where the Play button doesn't: your own handler calls `Stop()` when a
> location is reached. `pathViewer.Play()` is asynchronous — subscribe BEFORE playing and keep the
> handlers alive for the run. Remove `Stop()` (or gate it) if you want the run to continue.
> 来源 / Source (forum): <https://community.sw.siemens.com/s/question/0D5Vb00000v8OFyKAM/> —
> "Why is my simulation run stopping when I use the API but not when I use the play button?".

## API quick reference / 速查
| Member | Use |
| --- | --- |
| `TxSimulationPlayer` | simulation player |
| `SetOperation` / `Play` / `PlayWithoutRefresh` / `Rewind` / `Stop` | bind / play / rewind / stop |
| `JumpSimulationToTime(t, refresh, source)` | jump to a time |
| `TimeInterval` / `TimeIntervalReached` | sampling step & per-frame event |
| `TxApplication.ActiveDocument.SimulationPlayer` | document's shared player |
| `TxApplication.ViewersManager.PathEditorViewer.Play()` | play the Path Editor path |
| `TxApplication.Options.Simulation.SimulationSpeed` | simulation speed |

## See also / 参见
- `10-collision-and-interference.md` — collision checks per frame / per pair.
- `11-geometry-and-transformation.md` — swept-volume creation samples during playback.

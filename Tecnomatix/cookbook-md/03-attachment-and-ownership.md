# Cookbook: Attachment-Chain Resolution

## Description
Given a target robot, find every device / tool / part attached to it — and, in reverse, resolve
each resource's top-level owner (its robot) — WITHOUT relying on tree nesting. The link between a
child and its parent is the child's `AttachmentParent.Id`. Match that id against the `Id` of every
candidate resource by LONGEST-COMMON-PREFIX (>= 4 chars, never exact equality), walk the chain
upward, and stop when you reach the robot.

Why id matching (not tree position): attached tools frequently live in a different folder / branch
than the robot they are mounted on, so nesting alone is unreliable. The only dependable cross-branch
link is `AttachmentParent`. Because ids of related objects share a common leading substring, the
parent is found by the LONGEST-COMMON-PREFIX id match, not by exact string equality.

## Keywords
attachment, AttachmentParent, mounted, MountedTools, ExternalAxes, owner, parent, chain, id match,
longest common prefix, TxRobot, TxDevice, TxServoGun, TxGun, TxGripper, TxComponent, end-effector,
附属设备, 附属部件, 挂载工具, 归属机器人, 按ID匹配, 最长公共前缀

---

## When to use this cookbook (trigger)
Use this WHENEVER a request concerns attachment / ownership relations. Typical triggers (EN / 中文):
- "find the devices / tools / parts attached to robot X" / “获取机器人 X 的附属设备/工具/部件”
- "which robot does this device / part belong to" / “这个设备/部件属于哪个机器人（归属机器人是谁）”
- "list a robot's mounted tools / end-effectors / grippers / guns" / “列出机器人挂载的工具/夹爪/焊枪”
- "add a robot and all its attachments to a collision set" / “把机器人及其附属设备和部件都加入碰撞集”

Do NOT answer these by tree nesting or folder position — attached resources often live in a different
branch. ALWAYS resolve the link through `AttachmentParent` id-matching described below.

## Algorithm at a glance (5 steps)
1. Collect every resource into a `NodeRef`: `Name`, `ID = obj.Id.ToString()`, `Type`,
   `AttachParentID = GetAttachParentId(obj)` (§8.1). Keep robots in the same list so a chain can end on one.
2. For any child, its parent = the node whose `Id` shares the LONGEST COMMON PREFIX (>= 4 chars,
   NEVER exact equality) with the child's `AttachParentID`; always skip the child itself (§8.2).
3. Walk parent → parent upward with a visited-set cycle guard; stop at the first `TxRobot` = the
   owning robot, else return the top ancestor (§8.3).
4. Owner of every non-robot resource = the result of step 3 (§8.3 loop).
5. A robot's attachments = resources whose resolved owner == `robot.Name`; prefer `robot.MountedTools`
   / `robot.ExternalAxes` when non-empty; count a plain `TxDevice` as a mounted tool ONLY if it has an
   OPEN / CLOSE pose (§8.4).

## Invocation contract (inputs / outputs / constants)
- INPUT: a target robot name (→ list its attachments) OR a target resource (→ find its owner robot);
  fall back to the active selection when no name is supplied.
- OUTPUT: attachments-of-robot → list of `Name (Type: ..., ID: ...)`; owner-of-resource → robot name.
- CONSTANTS: minimum common-prefix length = **4**. Handled types: `TxRobot`, `TxDevice`, `TxGun`,
  `TxServoGun`, `TxComponent`, `TxGripper`.
- The four building blocks are `GetAttachParentId` (§8.1), `GetCommonPrefixLength` +
  `FindBestMatchedParentNode` (§8.2), `FindTopParentNameByAttachParentId` (§8.3), and the invert step (§8.4).

---

## Prerequisite
First collect the station's resources (see the Traversal & Search cookbook) into typed lists
(robots, devices, servo guns, guns, components, grippers), each item carrying `Name`,
`ID = obj.Id.ToString()`, `Type`, and `AttachParentID = GetAttachParentId(obj)`.

### 8.1 Read a child's AttachmentParent Id (per concrete type)
`AttachmentParent` is exposed by each concrete physical type, so resolve the concrete type first,
then read `.AttachmentParent.Id`:

```csharp
private string GetAttachParentId(ITxObject obj)
{
    if (obj == null) return string.Empty;
    try
    {
        if (obj.GetType() == typeof(TxRobot))
            return (obj as TxRobot).AttachmentParent != null ? (obj as TxRobot).AttachmentParent.Id : string.Empty;
        if (obj.GetType() == typeof(TxDevice))
            return (obj as TxDevice).AttachmentParent != null ? (obj as TxDevice).AttachmentParent.Id : string.Empty;
        if (obj.GetType() == typeof(TxGun))
            return (obj as TxGun).AttachmentParent != null ? (obj as TxGun).AttachmentParent.Id : string.Empty;
        if (obj.GetType() == typeof(TxServoGun))
            return (obj as TxServoGun).AttachmentParent != null ? (obj as TxServoGun).AttachmentParent.Id : string.Empty;
        if (obj.GetType() == typeof(TxComponent))
            return (obj as TxComponent).AttachmentParent != null ? (obj as TxComponent).AttachmentParent.Id : string.Empty;
        if (obj.GetType() == typeof(TxGripper))
            return (obj as TxGripper).AttachmentParent != null ? (obj as TxGripper).AttachmentParent.Id : string.Empty;
        return string.Empty;
    }
    catch { return string.Empty; }
}
```

Build a flat lookup of every collected resource so ids can be cross-referenced:

```csharp
private class NodeRef { public string Name; public string ID; public string Type; public string AttachParentID; }

// Emit one NodeRef per collected resource (robots + devices + servo guns + guns + components + grippers).
//   ID             = obj.Id.ToString()
//   AttachParentID = GetAttachParentId(obj)   // from 8.1
// Keep robots in the same list: an attached tool's chain must be able to terminate on a TxRobot.
```

### 8.2 Match an AttachParentId to a node by longest-common-prefix Id
Exact id equality is NOT used. Score each candidate by how many leading id characters it shares with
the child's `AttachParentId`; require at least 4 matching chars, and pick the longest match. Always
skip the child itself (same Name + Id) so a node never becomes its own parent.

```csharp
private int GetCommonPrefixLength(string left, string right)
{
    if (string.IsNullOrWhiteSpace(left) || string.IsNullOrWhiteSpace(right)) return 0;
    int max = Math.Min(left.Length, right.Length), n = 0;
    for (int i = 0; i < max; i++)
    {
        if (char.ToUpperInvariant(left[i]) != char.ToUpperInvariant(right[i])) break;
        n++;
    }
    return n;
}

private NodeRef FindBestMatchedParentNode(string attachParentId, string currentId, string currentName, List<NodeRef> allNodes)
{
    if (string.IsNullOrWhiteSpace(attachParentId)) return null;
    NodeRef best = null; int bestLen = -1;
    foreach (var c in allNodes)
    {
        if (c == null || string.IsNullOrWhiteSpace(c.ID)) continue;
        // never match self
        if (string.Equals(c.Name, currentName, StringComparison.OrdinalIgnoreCase) &&
            string.Equals(c.ID, currentId, StringComparison.OrdinalIgnoreCase)) continue;
        int len = GetCommonPrefixLength(attachParentId, c.ID);
        if (len < 4) continue;                       // ignore weak / coincidental matches
        if (len > bestLen) { bestLen = len; best = c; }
    }
    return best;
}
```

### 8.3 Walk the attachment chain up to the owning robot
From a resource, follow AttachParentID -> best-matched parent (8.2) -> that parent's AttachParentID,
and repeat. Keep a visited set to avoid cycles. Return the robot name as soon as a `TxRobot` is
reached; otherwise return the highest ancestor found.

```csharp
private string FindTopParentNameByAttachParentId(string attachParentId, string currentId, string currentName, List<NodeRef> allNodes)
{
    if (string.IsNullOrWhiteSpace(attachParentId)) return string.Empty;
    var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    string parentId = attachParentId;
    NodeRef top = null;
    while (!string.IsNullOrWhiteSpace(parentId))
    {
        if (visited.Contains(parentId)) break;       // cycle guard
        visited.Add(parentId);
        var parent = FindBestMatchedParentNode(parentId, currentId, currentName, allNodes);
        if (parent == null) break;
        top = parent;
        if (string.Equals(parent.Type, typeof(TxRobot).Name, StringComparison.OrdinalIgnoreCase))
            return parent.Name;                      // reached the owning robot -> done
        parentId = parent.AttachParentID;            // climb one level
    }
    return top == null ? string.Empty : top.Name;
}
```

Populate every non-robot resource's owner in one pass:

```csharp
var allNodes = BuildAllNodeRefs();   // 8.1
foreach (var d in DeviceList)    d.ParentName = FindTopParentNameByAttachParentId(d.AttachParentID, d.ID, d.Name, allNodes);
foreach (var s in ServoGunList)  s.ParentName = FindTopParentNameByAttachParentId(s.AttachParentID, s.ID, s.Name, allNodes);
foreach (var g in GunList)       g.ParentName = FindTopParentNameByAttachParentId(g.AttachParentID, g.ID, g.Name, allNodes);
foreach (var c in ComponentList) c.ParentName = FindTopParentNameByAttachParentId(c.AttachParentID, c.ID, c.Name, allNodes);
foreach (var r in GripperList)   r.ParentName = FindTopParentNameByAttachParentId(r.AttachParentID, r.ID, r.Name, allNodes);
```

### 8.4 List one robot's attached tools / devices (invert the result)
Once every resource knows its owning robot (8.3), a given robot's tools are simply the resources whose
resolved `ParentName == robot.Name`. Prefer the robot's own `MountedTools` when present; only fall back
to id-chain resolution when it is empty. A plain `TxDevice` counts as a mounted tool ONLY if it exposes
an OPEN / CLOSE pose (otherwise it is stationary equipment, not an end-effector).

```csharp
foreach (var servoGun in ServoGunList)
    if (string.Equals(servoGun.ParentName, robot.Name, StringComparison.OrdinalIgnoreCase))
        AddMountedToolIfMissing(robot.MountedTools, servoGun.Name, servoGun.Type);

foreach (var gun in GunList)
    if (string.Equals(gun.ParentName, robot.Name, StringComparison.OrdinalIgnoreCase))
        AddMountedToolIfMissing(robot.MountedTools, gun.Name, gun.Type);

foreach (var gripper in GripperList)
    if (string.Equals(gripper.ParentName, robot.Name, StringComparison.OrdinalIgnoreCase))
        AddMountedToolIfMissing(robot.MountedTools, gripper.Name, gripper.Type);

foreach (var device in DeviceList)
    if (string.Equals(device.ParentName, robot.Name, StringComparison.OrdinalIgnoreCase) &&
        HasOpenClosePose(device.PoseList))            // gate: end-effector devices only
        AddMountedToolIfMissing(robot.MountedTools, device.Name, device.Type);

// HasOpenClosePose(list): true if any pose name contains "OPEN" or "CLOSE" (OrdinalIgnoreCase).
// AddMountedToolIfMissing(list, name, type): append "name(type)" unless that exact text already exists.
```

An alternative fast path when the robot object is in hand: `robot.ExternalAxes` items are `TxJoint`;
`(joint as TxJoint).Device` is the attached device (skip `TxServoGun` when you only want the carrier),
and `robot.MountedTools` directly lists mounted `TxGun` / `TxServoGun` / `TxGripper` / `TxDevice`.
Use id-chain resolution (8.1–8.3) as the reliable fallback whenever those direct links are empty.

### 8.5 Key points (ID matching)
- The parent link is `child.AttachmentParent.Id`, matched to a node's `Id` by LONGEST COMMON PREFIX
  (>= 4 chars), NEVER by exact equality.
- Always exclude the node itself (same Name + Id) before scoring, so nothing parents itself.
- Climb `AttachParentID` iteratively with a visited-set; stop at the first `TxRobot`
  (`Type == typeof(TxRobot).Name`) to get the owning robot, else return the top ancestor.
- To list a robot's attachments, invert the mapping: select resources whose resolved `ParentName`
  equals the robot name; gate plain `TxDevice` items on an OPEN / CLOSE pose.

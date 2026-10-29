# 功能块 10：快照（Snapshots）

> 对象：`VisDispSnapShotMngr`
> 入口：`DispVisApp.SnapShotManager`（应用级）或 `VisDisp3DView.SnapShotManager` / `VisDisp2DView.SnapShotManager`（视图级）
> 能力：新建/重捕/删除/替换快照、激活并还原可见性/相机/变换、循环播放、保存为 Product View。

## VisDispSnapShotMngr

| 成员 | 签名/类型 | 说明 |
| --- | --- | --- |
| `NumSnapShots` | Long (R) | 快照数量 |
| `Name(Long Index)` | String (R/W) | 指定快照名称 |
| `AddSnapShot(VARIANT Index)` | → Long | 新建快照，返回其索引 |
| `ReCapture(Long Index)` | void | 重捕指定快照 |
| `Delete(Long Index)` | void | 删除指定快照 |
| `Replace(Long Index)` | void | 用当前视图状态替换指定快照 |
| `Activate(Long Index)` | void | 激活快照并把视图还原为该快照 |
| `SetVisibility(Long Index)` | void | 仅还原该快照的节点可见性（3D） |
| `SetNavigation(Long Index)` | void | 仅还原该快照的相机（3D） |
| `SetTranslation(Long Index)` | void | 仅还原该快照的变换（3D） |
| `Cycle()` | void | 循环播放所有快照 |
| `SaveAsProductView(Long Index)` | void | 保存为 Product View |
| `SaveAsNamedProductView(Long Index, String PVName)` | void | 以指定名保存为 Product View |

## C# 示例

### 新建快照并命名

```csharp
dynamic view = app.Documents.ActiveView;
dynamic snap = view.SnapShotManager;

int idx = (int)snap.AddSnapShot(System.Reflection.Missing.Value); // 新建，返回索引
snap.Name(idx) = "初始状态";
Console.WriteLine($"当前快照数：{snap.NumSnapShots}");
```

### 激活/还原某个快照

```csharp
snap.Activate(0);          // 完整还原（可见性+相机+变换）
// 或分项还原：
snap.SetVisibility(0);
snap.SetNavigation(0);
```

### 保存快照为命名 Product View

```csharp
snap.SaveAsNamedProductView(0, "Review-Front");
```

## 给代码生成模型的提示

- `AddSnapShot` 需要一个 `VARIANT` 参数，后期绑定可传 `System.Reflection.Missing.Value` 或省略位置；返回新快照索引。
- `Name(index)` 既可读也可写（写入即重命名）。
- `Activate` = 可见性 + 相机 + 变换全部还原；需要精细控制时用 `SetVisibility`/`SetNavigation`/`SetTranslation`。
- 应用级 `DispVisApp.SnapShotManager` 管 2D+3D；视图级管理器只针对该视图。

## 官方 Samples 转写（C#）

### PMItoProductView —— 添加快照并另存为产品视图

用途：当前视图新增一个快照，再把它另存为产品视图。

```csharp
dynamic snapMgr = view.SnapShotManager;
snapMgr.AddSnapShot(System.Reflection.Missing.Value);  // 新增快照
int idx = snapMgr.NumSnapShots - 1;
snapMgr.SaveAsProductView(idx);                        // 另存为产品视图
view.UpdateView();
```

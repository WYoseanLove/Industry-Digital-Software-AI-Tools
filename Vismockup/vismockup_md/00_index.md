# Vismockup C# 自动化功能块索引（供大模型调用）

> 数据来源：`Automation/Documentation/ref_files/*.htm`（Teamcenter Visualization COM Automation 对象参考）
> 目标：把官方对象参考按**功能块**拆分成独立 `.md`，每个文件包含对象链路、属性表、方法表、枚举、可编译的 C# 调用示例。
> 语言：**C#（.NET COM Interop，后期绑定 `dynamic` 为主）**。

## 如何使用本套文档（给 LLM 的总则）

1. 先读本索引确定功能块，再打开对应功能块文件查属性/方法签名。
2. 所有对象名、属性名、方法名**大小写敏感**，必须与官方一致。
3. 统一入口：`VFFrame.Application` → `.VisAppAutomation()` → `DispVisApp`。
4. 优先后期绑定（`dynamic`）；需要强类型枚举时引用 `VISAUTOMATIONLib`。
5. COM 的 `[out]` 参数（如相机、法向量、元数据、包围盒）在 C# 中用反射 `InvokeMember` + `ParameterModifier`，或用早期绑定的 `out` 形参。
6. 变换矩阵是 16 个 `double` 的 4×4 行主齐次矩阵（SAFEARRAY/VARIANT）。

## 统一连接样板（所有示例的前置）

```csharp
using System;

Type t = Type.GetTypeFromProgID("VFFrame.Application");
if (t == null) throw new InvalidOperationException("未找到 COM ProgID 'VFFrame.Application'，请确认 Vismockup 已安装并注册。");

dynamic oOTCVis = Activator.CreateInstance(t);
dynamic app = oOTCVis.VisAppAutomation();      // DispVisApp：所有操作的起点
dynamic docs = app.Documents;                  // VisDispDocList
dynamic doc = docs.ActiveDocument;             // VisDispDoc（可能为 null）
dynamic view = docs.ActiveView;                // 当前活动视图（3D 时为 VisDisp3DView）
```

> 提示：进程外 COM 要求 C# 工程平台位数与 Vismockup 进程一致（通常 x64），目标框架建议 `net8.0-windows` 或 .NET Framework 4.7.2+，并加 `[STAThread]`。

## 功能块清单

| 文件 | 功能块 | 关键对象 |
| --- | --- | --- |
| [01_application_session.md](01_application_session.md) | 应用与会话：启动/退出、窗口、保存会话、附件、快照管理器入口 | `DispVisApp`(1-4), `VisDispAttachmentMngr` |
| [02_documents.md](02_documents.md) | 文档：打开/关闭/插入、导出 JT/STEP/图片 | `VisDispDocList`, `VisDispDoc` |
| [03_views_camera.md](03_views_camera.md) | 视图与相机：3D/2D 视图、相机、截图、Find 查找 | `VisDisp3DView`, `VisDisp2DView`, `VisDispViewList` |
| [04_nodes_metadata.md](04_nodes_metadata.md) | 节点与元数据：可见性、选择、变换、包围盒、物理属性、元数据；**焊点位置/法向(`Connector Location`/`Connector Normal`)、连接钣金号(`Connected Part-1..3`)、钣金厚度/材料(`MCI Gauge/Thickness [mm]`/`MCI Material Specification`)** | `VisDisp3DNode`, `VisDispNodeList`, `VisDispMetaDataList` |
| [skill_get_weld_point_properties_and_connected_parts.md](skill_get_weld_point_properties_and_connected_parts.md) | 输出选中**焊点全部属性**并提取**板材搭接（钣金搭接）钣金号码**(`Connected Part-1..3`)；选中项可为单个焊点或焊点组，递归下钻叶子焊点 | `VisDispNodeList`, `VisDispMetaDataList` |
| [05_appearance_color_material.md](05_appearance_color_material.md) | 外观：颜色、材质、外观系统调色板 | `VisDispColor`, `VisDispMaterial`, `VisDispAppearanceSysMngr` |
| [06_sections.md](06_sections.md) | 剖切：截面、截面系列、网格设置 | `VisDispSectionMngr`, `VisDispSection`, `VisDispSectionSeries` |
| [07_pmi.md](07_pmi.md) | PMI：查询、实体、集合、显示 | `VisDispPMIMngr`, `VisDispPMIQuery`, `VisDispPMIEntity`, `VisDispPMIList` |
| [08_measurement.md](08_measurement.md) | 测量：单体/距离/组测量、查找 | `VisDispMeasurementMngr`, `VisDispMeasurementEntity(2)` |
| [09_markup3d.md](09_markup3d.md) | 3D 批注：锚定文本自动创建、偏好、文本配方 | `VisDisp3DMarkupMngr`, `VisDisp3DMarkupPreferences`, `VisDisp3DMarkupTextRecipe` |
| [10_snapshot.md](10_snapshot.md) | 快照：新建/激活/循环、导出为 Product View | `VisDispSnapShotMngr` |
| [11_motion_animation.md](11_motion_animation.md) | 运动与动画：VFM 播放、路径规划、转台、扫掠体 | `VisDispMotionMngr`, `VisDispPathPlanningMngr`, `VisDispTurntableMngr`, `VisDispSweptVolMngr` |
| [12_clearance.md](12_clearance.md) | 间隙分析：矩阵/选中/分组、结果 | `VisDispClearanceMngr`, `VisDispClearanceResult(List)` |
| [13_groups_layers.md](13_groups_layers.md) | 分组与图层过滤 | `VisDispGroupMngr`, `VisDispGroup`, `VisDispLayerFilterMngr` |
| [14_print.md](14_print.md) | 打印：打印管理器与打印属性 | `VisDispPrintManager`, `VisDispPrintProperties` |
| [15_misc_managers.md](15_misc_managers.md) | 其他：轮廓捕获、CAE 注释、3D 对比、技术插图/组合（多为 Teamcenter Publish） | `VisDispOutlineMngr`, `VisDispCAEMngr`, `VisDisp3DCompareMngr` 等 |

## 枚举速查（跨功能块）

| 枚举 | 值 | 用途 |
| --- | --- | --- |
| `SAVE_TYPE` | `DIRECTMODEL`(JT), `VRML`, `ROBFACE`, `PLMXML`, `STEP`, `BLK` | `VisDispDoc.Export` |
| `INPUT_TYPE` | `ALL_PARTS`, `VISIBLE_PARTS`, `LOADED_PARTS`, `SELECTED_PARTS` | `Find` / 间隙范围 |
| `FIND_NODE_TYPE` | `PARTS`, `ASSEMBLIES`, `PARTS_AND_ASSEMBLIES` | `VisDisp3DView.Find` |
| `COMPARE_OP` | `LESS_THAN`,`LESS_THAN_EQUAL`,`EQUAL`,`GREATER_THAN`,`GREATER_THAN_EQUAL`,`NOT_EQUAL`,`RANGE` | 查找比较 |
| `TC_ATTACHMENT_TYPE` | `TCAT_Newstuff`, `TCAT_BaseDocument`, `TCAT_SelectedBOMLine` | Teamcenter 保存位置 |

> 具体枚举整数值参见 `Automation/Samples` 目录下的 `ENUMS.INC`。

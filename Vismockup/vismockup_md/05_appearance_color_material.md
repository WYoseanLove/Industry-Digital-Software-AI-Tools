# 功能块 05：外观（颜色 / 材质 / 外观系统）

> 对象：`VisDispColor`、`VisDispMaterial`、`VisDispAppearanceSysMngr`、`VisDispStringContainer`
> 能力：设置零件/视图颜色与透明度、材质分量、导入 PLMXML 调色板并把外观实体指派到节点。

## VisDispColor

| 属性 | 类型 | 读写 | 说明 |
| --- | --- | --- | --- |
| `RGB` | Long | R/W | 三个字节整型打包的 RGB |
| `Red` / `Green` / `Blue` | Single | R/W | 分量强度 0.0~1.0 |
| `Alpha` | Single | R/W | 透明度 0.0~1.0 |

## VisDispMaterial

| 属性 | 类型 | 读写 | 说明 |
| --- | --- | --- | --- |
| `Ambient` | VisDispColor | R/W | 环境光颜色 |
| `Diffuse` | VisDispColor | R/W | 漫反射颜色 |
| `Emission` | VisDispColor | R/W | 自发光颜色 |
| `Specular` | VisDispColor | R/W | 高光颜色 |
| `Shininess` | Single | R/W | 光泽度 0.0~1.0 |

## VisDispAppearanceSysMngr（`VisDisp3DView.AppearanceSysManager`）

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `LoadAppearanceEntity(strFilePath, APPEAR_NAMED_POLICY, APPEAR_UNNAMED_POLICY)` | String(GUID) | 从 PLMXML 调色板加载实体，返回唯一标识 |
| `MergeAppearancePalette(strFilePath, bMaterials, bImages, bTextures, bLights)` | void | 合并调色板到当前调色板 |
| `GetAppearanceEntityGUIDsByType(APPEAR_DB_TYPES)` | SAFEARRAY(String) | 按类型取实体 GUID 数组 |
| `AssignAppearanceEntity(VisDisp3DNode Node, String strGUID, Boolean bAssignToProto)` | void | 把实体指派到节点。bAssignToProto=True 指派到所有实例，False 仅本实例 |
| `GetMaterialNameByGUID(String strGUID)` | String | 由 GUID 取材质名 |
| `GetMaterialGUIDByName(String strName)` | String | 由名取材质 GUID |

### 枚举

- `APPEAR_NAMED_POLICY`：`AS_ANP_EXISTING`(保留已有)、`AS_ANP_NEW`(替换)、`AS_ANP_RENAME`(改名加载)。
- `APPEAR_UNNAMED_POLICY`：`AS_AUP_NONE`、`AS_AUP_EXISTING`。
- `APPEAR_DB_TYPES`：`AS_ADBT_UNKNOWN`(全部)、`AS_ADBT_MATERIAL`、`AS_ADBT_LIGHT`、`AS_ADBT_IMAGE`、`AS_ADBT_TEXCOORD`。

## C# 示例

### 设置节点颜色与透明度（通过 BasicMaterial）

```csharp
dynamic node = view.RootNode.Children.Node(0);
dynamic mat = node.BasicMaterial;        // VisDispMaterial
dynamic diff = mat.Diffuse;              // VisDispColor
diff.Red = 1.0f; diff.Green = 0.0f; diff.Blue = 0.0f; diff.Alpha = 0.5f;
mat.Diffuse = diff;
node.BasicMaterial = mat;                // 回写
```

### 设置视图背景色

```csharp
dynamic bg = view.BackGroundColor;
bg.Red = 0.9f; bg.Green = 0.9f; bg.Blue = 0.9f;
view.BackGroundColor = bg;
```

### 导入调色板并把材质指派到节点

```csharp
dynamic appMgr = view.AppearanceSysManager;
string guid = appMgr.LoadAppearanceEntity(
    @"C:\palettes\metal.plmxml",
    VISAUTOMATIONLib.APPEAR_NAMED_POLICY.AS_ANP_EXISTING,
    VISAUTOMATIONLib.APPEAR_UNNAMED_POLICY.AS_AUP_EXISTING);

dynamic node = view.RootNode.Children.Node(0);
appMgr.AssignAppearanceEntity(node, guid, true); // 指派到所有实例
```

### 按类型列出材质 GUID

```csharp
dynamic appMgr = view.AppearanceSysManager;
object[] guids = (object[])appMgr.GetAppearanceEntityGUIDsByType(
    VISAUTOMATIONLib.APPEAR_DB_TYPES.AS_ADBT_MATERIAL);
foreach (string g in guids)
    Console.WriteLine($"{g} => {appMgr.GetMaterialNameByGUID(g)}");
```

## 给代码生成模型的提示

- 颜色/材质分量都是 `Single`（`float`），范围 0.0~1.0，注意写成 `1.0f`。
- 修改颜色要**取出对象→改分量→回写**（COM 值语义），直接改属性可能不生效。
- 持久化外观用 `BasicMaterial`（随会话保存），`Material` 将弃用。
- `GetAppearanceEntityGUIDsByType` 返回字符串 SAFEARRAY，遍历前转 `object[]`。

## 官方 Samples 转写（C#）

### PLMXMLPrefExample —— 设置 PLMXML 导出首选项

用途：导出 PLMXML 前配置外观/单位等首选项（通过应用级首选项对象）。

```csharp
dynamic pref = visApp.PLMXMLPreferences;   // 首选项对象
pref.ExportAppearances = true;             // 导出外观
pref.ExportPMI = true;                     // 导出 PMI
pref.ExportMetaData = true;                // 导出元数据
// 随后由文档导出 PLMXML
dynamic doc = visApp.Documents.ActiveDocument();
doc.Export(6 /*SAVE_TYPE.PLMXML*/, @"C:\out\model.plmxml", null);
```

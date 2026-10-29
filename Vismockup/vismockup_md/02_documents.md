# 功能块 02：文档（Documents）

> 对象：`VisDispDocList`、`VisDispDocList2`、`VisDispDoc`
> 能力：打开/关闭/插入文档、导出为 JT/STEP/PLMXML/VRML、导出图片、打印水印。

## 对象链路

```text
DispVisApp
└── .Documents → VisDispDocList
    ├── .NumDocuments
    ├── .ActiveDocument → VisDispDoc
    ├── .ActiveView
    ├── .OpenDocument(path) → VisDispDoc
    └── .CloseAllDocuments()
```

## VisDispDocList / VisDispDocList2

| 成员 | 签名/类型 | 说明 |
| --- | --- | --- |
| `NumDocuments` | Long (R) | 打开的文档总数 |
| `ActiveDocument` | VisDispDoc (R) | 活动文档 |
| `ActiveView` | Object (R) | 活动视图（2D/3D） |
| `OpenDocument(String strPath)` | → VisDispDoc | 打开文档并返回 |
| `CloseAllDocuments()` | void | 关闭全部文档 |
| `OpenDocumentByFMS(String FMSReadTicket, VisDispDoc Doc)` | → VisDispDoc | （DocList2）从 Teamcenter FMS 打开，仅 Publish 集成用 |

## VisDispDoc — 属性

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `ViewList` | VisDispViewList (R) | 视图集合 |
| `ViewByHandle(Long viewHandle)` | Object (R) | 按句柄取视图 |
| `DocType` | DOC_TYPE (R) | 文档类型（见 ENUMS.INC） |
| `DocHandle` | Long (R) | 文档句柄 |
| `NumInsertedDocuments` | Long (R) | 已插入的文档数（仅 3D） |
| `Path` | String (R) | 文档完整路径 |
| `InsertedDocumentPath(Long documentIndex)` | String (R) | 指定插入文档路径（0 基，仅 3D） |

## VisDispDoc — 方法

| 方法 | 说明 |
| --- | --- |
| `InsertDocument(String strPath)` | 插入文档（仅 3D） |
| `DeleteInsertedDocument(Long documentIndex)` | 移除指定插入文档（0 基，仅 3D） |
| `CloseDocument()` | 关闭本文档并释放资源 |
| `Export(SAVE_TYPE SaveType, String strPath, String strConfigFile)` | 导出（JT/STEP/…）。`strConfigFile` 可为 NULL（默认用 Windows 目录 EXPORT.INI） |
| `ExportEnhanced(String strPath, Double Width, Double Height, Double DPI)` | 导出图片。Width 英寸 1~66.2；Height 英寸 1~93.6；DPI 72~1200 |
| `SetPrintStamp(String strPrintStamp)` | 添加打印水印（MDS 命令列表） |
| `GenerateTcLoadFailureReport(String filePath)` | 生成 Teamcenter 加载失败报告（XML） |
| `FixTcLoadFailures(String filePath)` | 修正加载失败报告 |

### SAVE_TYPE 枚举

| 值 | 导出格式 |
| --- | --- |
| `DIRECTMODEL` | JT 文件 |
| `VRML` | VRML |
| `ROBFACE` | ROBFACE 3D |
| `PLMXML` | PLMXML 层级结构 |
| `STEP` | STEP |
| `BLK` | NASTRAN BULK |

> 2D 文件的导出格式由 `strPath` 扩展名决定（如 `.jpg`）。

## C# 示例

### 打开、导出 JT、关闭

```csharp
dynamic docs = app.Documents;
dynamic doc = docs.OpenDocument(@"C:\models\assembly.vf");

// 导出为 JT：SAVE_TYPE.DIRECTMODEL = 需引用 VISAUTOMATIONLib 或用整数值
doc.Export(VISAUTOMATIONLib.SAVE_TYPE.DIRECTMODEL, @"C:\out\assembly.jt",
           @"C:\config\EXPORT.ini");

doc.CloseDocument();
```

### 后期绑定导出（无强类型枚举时）

```csharp
// 若不便引用 VISAUTOMATIONLib，可传枚举整数值（数值请查 ENUMS.INC）
// 推荐仍引用类型库以避免魔法数字
doc.Export((int)VISAUTOMATIONLib.SAVE_TYPE.DIRECTMODEL, path, iniPath);
```

### 导出图片（英寸 × DPI = 像素）

```csharp
dynamic doc = app.Documents.ActiveDocument;
doc.ExportEnhanced(@"C:\out\view.png", 8.0, 6.0, 150); // 1200×900 像素
```

### 插入子文档

```csharp
dynamic doc = app.Documents.ActiveDocument;
doc.InsertDocument(@"C:\models\bracket.jt");
Console.WriteLine($"已插入数：{doc.NumInsertedDocuments}");
```

## 给代码生成模型的提示

- 导出 JT 用 `Export(SAVE_TYPE.DIRECTMODEL, path, ini)`；导出图片用 `ExportEnhanced`（英寸+DPI，非像素）。
- `ExportEnhanced` 宽高为 `double`，DPI 官方范围 72~1200。
- `strConfigFile` 传 `null` 时用默认 EXPORT.INI；建议显式提供以稳定导出选项。
- 关闭单个文档用 `CloseDocument()`，全部用 `CloseAllDocuments()`。
- `InsertDocument`/`DeleteInsertedDocument` 仅对 3D 文档有效。

## 官方 Samples 转写（C#）

### openFile / insert / close —— 打开、插入、关闭文档

用途：打开主模型、把另一模型插入当前文档、关闭全部。对应多个官方示例（OutlineExample、PMIExample1 等）。

```csharp
dynamic docs = visApp.Documents;

// 打开
docs.OpenDocument(@"C:\models\assembly.jt");
dynamic doc = docs.ActiveDocument();

// 向当前文档插入另一个模型
dynamic active = docs.ActiveDocument();
active.InsertDocument(@"C:\models\part.jt");

// 关闭全部
docs.CloseAllDocuments();
```

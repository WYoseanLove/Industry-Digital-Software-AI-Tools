# 功能块 14：打印（Print）

> 对象：`VisDispPrintManager`、`VisDispPrintProperties`
> 入口：`DispVisApp.PrintManager`
> 能力：把视图加入打印列表、配置打印属性（份数、方向、页眉页脚、水印、缩放）、预览、提交并打印。

## VisDispPrintManager

| 成员 | 签名/类型 | 说明 |
| --- | --- | --- |
| `Properties` | VisDispPrintProperties (R) | 当前打印属性对象 |
| `AddView(Long ViewHandle)` | void | 把活动视图加入打印列表 |
| `EnableTabs(PRNTAB printTabs)` | void | 启用/禁用打印对话框标签页 |
| `Print()` | void | 使用当前设置发起打印 |
| `PrintPreview()` | void | 打开打印预览 |
| `Commit()` | void | 把设置提交到注册表（**打印前必须调用才生效**） |
| `OutputPVL(String strFilePath, Boolean bCorrectViewport)` | void | 保存 2D 视图及图层为 .pvl |

## VisDispPrintProperties — 常用属性（多为 R/W）

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `PrinterName` | String | 打印机名 |
| `Copies` | Long | 份数 |
| `Collate` | Boolean | 是否逐份 |
| `PaperOrientation` | PRINT_ORIENT | 纸张方向 |
| `PageSize` | Long(DMPAPER) | 纸张大小 |
| `ImageAlignment` | PRINT_IMAGE_ALIGNMENT | 图像对齐（默认居中） |
| `ScaleSetting` | PRINTSCALE | 缩放模式 |
| `ScaleFactor` | Single | 可变缩放系数（1.0=100%，0.5=50%） |
| `PrintFullView` | Boolean | 打印整幅（忽略视口裁剪） |
| `PrintAsMonocolor` | Boolean | 转黑白打印 |
| `PrintQuality` / `PreviewQuality` | Single | 光栅/预览质量 0.0~1.0 |
| `PrintToFile` | Boolean (R) | 是否打印到文件 |
| `HeaderEnabled` / `FooterEnabled` | Boolean | 页眉/页脚开关 |
| `LeftHeader`/`CenterHeader`/`RightHeader` | String | 页眉三段 |
| `LeftFooter`/`CenterFooter`/`RightFooter` | String | 页脚三段 |
| `HeaderFooterColor` | VisDispColor | 页眉页脚颜色 |
| `HeaderFooterFont` | FontDisp | 页眉页脚字体 |
| `WatermarkEnabled` | Boolean | 水印开关 |
| `WatermarkText` | String | 水印文本 |
| `WatermarkFont` / `WatermarkFontColor` / `WatermarkFontSize` | FontDisp/VisDispColor/Long | 水印字体/色/字号（0 自动） |
| `WatermarkTextDirection` | TEXTDIRECTION | 水印文字方向 |
| `WatermarkTransparency` | Boolean | 水印透明 |
| `SetPageRange` | String (W) | 页范围字符串 |

## C# 示例

### 打印当前 3D 视图（2 份，横向，带水印）

```csharp
dynamic view = app.Documents.ActiveView;
dynamic pm = app.PrintManager;

pm.AddView(view.ViewHandle);

dynamic props = pm.Properties;
props.PrinterName = "Microsoft Print to PDF";
props.Copies = 2;
props.PaperOrientation = VISAUTOMATIONLib.PRINT_ORIENT.LANDSCAPE /*示例*/;
props.CenterHeader = "Design Review";
props.HeaderEnabled = true;
props.WatermarkEnabled = true;
props.WatermarkText = "CONFIDENTIAL";

pm.Commit();     // 关键：提交设置
pm.Print();
```

### 打印预览

```csharp
pm.AddView(view.ViewHandle);
pm.Commit();
pm.PrintPreview();
```

## 给代码生成模型的提示

- **打印前必须 `Commit()`**，否则属性改动不生效。
- 先 `AddView(view.ViewHandle)` 把要打印的视图加入列表，再设属性、`Commit`、`Print`。
- 质量类属性（`PrintQuality`/`PreviewQuality`/`ScaleFactor`）为 `Single` 0.0~1.0。
- `PageSize` 取 Windows `DMPAPER` 值；自定义尺寸时读 `CustomWidth/CustomLength`（HIMETRIC，1/10 mm）。
- 页眉页脚分左/中/右三段，需 `HeaderEnabled`/`FooterEnabled` 打开。

## 官方 Samples 转写（C#）

### PrintingSample1 —— 设置页眉页脚并打印/预览

用途：把当前视图加入打印列表，启用并填写左/中/右页眉页脚，然后打印或预览。

```csharp
dynamic printMgr = visApp.PrintManager;
dynamic prop     = printMgr.Properties;
dynamic view     = visApp.ActiveView;

printMgr.AddView(view.ViewHandle);   // 把视图加入打印列表

prop.HeaderEnabled = true;
prop.LeftHeader   = "Project X";
prop.CenterHeader = "Assembly";
prop.RightHeader  = System.DateTime.Now.ToShortDateString();

prop.FooterEnabled = true;
prop.LeftFooter   = "Confidential";
prop.CenterFooter = "";
prop.RightFooter  = "Page 1";

prop.Commit();          // 必须提交，否则不生效
printMgr.PrintPreview();  // 预览
// printMgr.Print();      // 直接打印
```

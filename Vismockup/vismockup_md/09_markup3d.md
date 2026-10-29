# 功能块 09：3D 批注（3D Markup / 锚定文本）

> 对象：`VisDisp3DMarkupMngr`、`VisDisp3DMarkup`、`VisDisp3DMarkupList`、`VisDisp3DMarkupPreferences`、`VisDisp3DMarkupTextRecipe`
> 入口：`VisDisp3DView.Markup3DManager`
> 能力：在可见/选中零件上自动创建锚定文本批注、配置批注外观偏好、用“文本配方”组合属性/自由文本。

## VisDisp3DMarkupMngr

| 成员 | 类型/签名 | 说明 |
| --- | --- | --- |
| `MarkupsInView` | VisDisp3DMarkupList (R) | 活动视图中的 3D 批注 |
| `Markup3DPreferences` | VisDisp3DMarkupPreferences (R) | 批注偏好 |
| `AutocreateMarkups(MARKUP3D_AUTOCREATE_ON_TYPES, VisDisp3DMarkupTextRecipe)` | void | 在选中/可见零件上按配方自动创建锚定文本 |

- `MARKUP3D_AUTOCREATE_ON_TYPES`：指定在“选中”或“可见”零件上创建。

## VisDisp3DMarkup / VisDisp3DMarkupList

- `VisDisp3DMarkup.TextString`(R)：批注显示文本。
- `VisDisp3DMarkupList.NumMarkups`(R)、`Markup(Long Index)`(R)。

## VisDisp3DMarkupPreferences（全部 R/W）

线：`LineColor`(VisDispColor)、`LineStyle`(MARKUP3D_LINE_STYLES)、`LineWidth`(Single)。
边：`EdgeColor`、`EdgeStyle`、`EdgeWidth`。
填充：`FillColor`、`FillStyle`(MARKUP3D_FILL_STYLES)、`FillTransparency`(0~1)、`FillModeOn`(Bool)。
文本/字体：`TextColor`、`FontName`、`FontBold`、`FontItalic`、`FontStrikeout`、`FontUnderline`、`FontSize`(Long)、`TextBoundingShape`。
线端/引线/标注：`LineEndPointsBeginStyle/Size`、`LineEndPointsEndStyle/Size`、`LeaderLineAttachType`、`CalloutIdentifierType`、`CalloutNumericIdStartValue`(Long)、`CalloutAlphaIdStartValue`(String)。
配方：`PredefinedTextRecipe`(VisDisp3DMarkupTextRecipe)。

## VisDisp3DMarkupTextRecipe

| 成员 | 签名 | 说明 |
| --- | --- | --- |
| `NumElements` | Long (R) | 元素数 |
| `TextString` | String (R) | 组合后显示文本 |
| `IncludeLabels` | Boolean (R/W) | 是否包含标签 |
| `Element(Index, out ElementType, out PartAttribute, out Value)` | | 读取指定元素 |
| `AddElement(Long Index, MARKUP3D_TEXTRECIPE_ELEMENT_TYPES, String PartAttribute, String Value)` | void | 添加元素。Index=-1 追加末尾 |
| `RemoveElement(Long Index)` | void | 移除元素 |
| `RemoveAllElements()` | void | 清空 |

- `MARKUP3D_TEXTRECIPE_ELEMENT_TYPES`：含 `MTRE_PART_ATTRIBUTE`（用 PartAttribute 指定属性名）、`MTRE_FREE_TEXT`（用 Value 指定自由文本）。

## C# 示例

### 在选中零件上自动创建“零件号”批注

```csharp
dynamic view = app.Documents.ActiveView;
dynamic mkMgr = view.Markup3DManager;

// 构造文本配方：自由文本 "PN: " + 零件属性 PartNumber
dynamic recipe = mkMgr.Markup3DPreferences.PredefinedTextRecipe;
recipe.RemoveAllElements();
recipe.AddElement(-1, VISAUTOMATIONLib.MARKUP3D_TEXTRECIPE_ELEMENT_TYPES.MTRE_FREE_TEXT, "", "PN: ");
recipe.AddElement(-1, VISAUTOMATIONLib.MARKUP3D_TEXTRECIPE_ELEMENT_TYPES.MTRE_PART_ATTRIBUTE, "PartNumber", "");

mkMgr.AutocreateMarkups(
    VISAUTOMATIONLib.MARKUP3D_AUTOCREATE_ON_TYPES.MARKUP3D_ON_SELECTED /*示例值*/,
    recipe);
```

### 配置批注外观偏好

```csharp
dynamic prefs = mkMgr.Markup3DPreferences;
prefs.FontSize = 14;
prefs.FontBold = true;
dynamic tc = prefs.TextColor; tc.Red = 0f; tc.Green = 0f; tc.Blue = 0f; prefs.TextColor = tc;
prefs.FillModeOn = true;
prefs.FillTransparency = 0.3f;
```

### 遍历视图中的批注文本

```csharp
dynamic list = mkMgr.MarkupsInView;
for (int i = 0; i < list.NumMarkups; i++)
    Console.WriteLine(list.Markup(i).TextString);
```

## 给代码生成模型的提示

- 文本配方由“元素序列”组成：`MTRE_FREE_TEXT`（填 Value）与 `MTRE_PART_ATTRIBUTE`（填 PartAttribute 属性名）。
- `AddElement` 用 `Index=-1` 追加到末尾。
- 自动创建目标（选中/可见）由 `MARKUP3D_AUTOCREATE_ON_TYPES` 决定，具体枚举值见 ENUMS.INC。
- 偏好中的颜色对象需“取出→改→回写”。
- `Element(...)` 读取为 `[out]` 参数，后期绑定用反射。

## 官方 Samples 转写（C#）

### Markup3DAutocreateOnSelectedTest / OnVisibleTest —— 自动创建 3D 标注

用途：配置自动创建目标（选中或可见节点），设置文本配方，并批量创建标注。`MARKUP3D_AUTOCREATE_ON_TYPES` 值见 ENUMS.INC。

```csharp
dynamic mkMgr = view.Markup3DManager;
dynamic pref  = mkMgr.Preferences;

// 1=选中节点, 2=可见节点（具体值见 ENUMS.INC）
pref.AutoCreateOnType = 1;

// 文本配方：自由文本 + 零件属性
dynamic recipe = pref.TextRecipe;
recipe.AddElement(-1, 0 /*MTRE_FREE_TEXT*/, "PN: ", "");
recipe.AddElement(-1, 1 /*MTRE_PART_ATTRIBUTE*/, "", "PartNumber");

// 对目标集合批量自动创建
mkMgr.AutoCreate();
view.UpdateView();
```

# 15 · Object Set/Ask & Display (Open C)

## Description
In a batch DLL, set **color / linetype / line width / layer / name / translucency** on objects of an already opened `.prt`, **traverse** objects by name or by type and read
their type/subtype, and use the NXOpen `DisplayModification` to change color/line width in bulk.
> Entry point see [doc 00](00_NX_DLL_Entry_Template.md).
> For traversing faces/edges and extracting geometry see also [03_Edge_and_Face_Extraction.md](03_Edge_and_Face_Extraction.md).

## Keywords
UF_OBJ_set_color, UF_OBJ_set_font, UF_OBJ_set_line_width, UF_OBJ_set_layer, UF_OBJ_set_name,
UF_OBJ_set_translucency, UF_OBJ_set_cre_color, UF_OBJ_ask_name, UF_OBJ_cycle_by_name,
UF_OBJ_cycle_objs_in_part1, UF_OBJ_ask_type_and_subtype, UF_ASSEM_ask_work_part,
DisplayModification, SetNewColor, SetNewWidth, NXObjectManager

---

## 1. Set object appearance

```cpp
#include <uf_obj.h>
#include <uf_modl.h>

// Get the body from a block feature (fTAG is the tag of some feature)
tag_t bodyTag = NULL_TAG;
UF_MODL_ask_feat_body(fTAG, &bodyTag);

UF_OBJ_set_color(bodyTag, 11);                       // color number
UF_OBJ_set_font(bodyTag, UF_OBJ_FONT_DASHED);        // linetype (see below)
UF_OBJ_set_line_width(bodyTag, UF_OBJ_WIDTH_9);      // line width 1~9
UF_OBJ_set_layer(bodyTag, 1);                        // move to layer 1
UF_OBJ_set_name(fTAG, "FeatureName");                // name the feature
UF_OBJ_set_name(bodyTag, "BodyName");                // name the body
double origin[3] = { 0.0, 0.0, 0.0 };
UF_OBJ_set_name_origin(bodyTag, origin);             // name display position
UF_OBJ_set_translucency(bodyTag, 50);                // translucency 0~100

// Set the default creation color for a type of object
UF_OBJ_set_cre_color(UF_solid_type, UF_all_subtype, UF_OBJ_solid_body_property, 30);
```

Linetype constants: `UF_OBJ_FONT_SOLID / _DASHED / _PHANTOM / _CENTERLINE / _DOTTED / _LONG_DASHED /
_DOTTED_DASHED / _INVISIBLE`.
Line-width constants: `UF_OBJ_WIDTH_1` ... `UF_OBJ_WIDTH_9`.

## 2. Name an object and read the name

```cpp
tag_t lineTag = NULL_TAG;
UF_CURVE_create_line(&line, &lineTag);

UF_OBJ_set_name(lineTag, "LineName");

char name[256];
UF_OBJ_ask_name(lineTag, name);   // read the name back
std::cout << "name = " << name << std::endl;
```

## 3. Traverse objects by name `UF_OBJ_cycle_by_name`

Give several objects the same name, then traverse them by that name (`NULL_TAG` ends):

```cpp
tag_t objTag = NULL_TAG;
int i = -1;
do {
    UF_OBJ_cycle_by_name("LineName", &objTag);
    if (objTag != NULL_TAG) {
        ++i;
        std::cout << "object #" << i << " tag = " << objTag << std::endl;
    }
} while (objTag != NULL_TAG);
```

## 4. Traverse objects in a part by type + read type/subtype

```cpp
#include <uf_assem.h>

tag_t workPart = UF_ASSEM_ask_work_part();   // current work part (in the batch DLL, the part opened by OpenDisplay)

tag_t objTag = NULL_TAG;
int type = 0, subType = 0;
do {
    UF_OBJ_cycle_objs_in_part1(workPart, UF_solid_type, &objTag);  // traverse solid-class objects
    if (objTag != NULL_TAG) {
        UF_OBJ_ask_type_and_subtype(objTag, &type, &subType);      // type / subtype
        std::cout << "tag=" << objTag << " type=" << type
                  << " subType=" << subType << std::endl;
    }
} while (objTag != NULL_TAG);
```

Solid subtypes (`UF_solid_type = 70`):
`UF_solid_body_subtype(0)` body, `UF_solid_face_subtype(2)` face, `UF_solid_edge_subtype(3)` edge ...

## 5. NXOpen `DisplayModification` bulk color/line-width change

A record-style interface that can act on a batch of displayable objects at once; used together with UF <-> NXOpen object conversion:

```cpp
#include <NXOpen/DisplayManager.hxx>
#include <NXOpen/DisplayModification.hxx>
#include <NXOpen/DisplayableObject.hxx>
#include <NXOpen/Body.hxx>
#include <NXOpen/NXObjectManager.hxx>

// Get the body tag from a block feature
tag_t bodyTag = NULL_TAG;
UF_MODL_ask_feat_body(fTAG, &bodyTag);

NXOpen::DisplayModification* dm = theSession->DisplayManager()->NewDisplayModification();
dm->SetNewColor(186);                                              // color number
dm->SetNewWidth(NXOpen::DisplayableObject::ObjectWidthFour);       // line width

// UF tag -> NXOpen object
NXOpen::Body* body = dynamic_cast<NXOpen::Body*>(NXOpen::NXObjectManager::Get(bodyTag));
std::vector<NXOpen::DisplayableObject*> objs(1);
objs[0] = body;

dm->Apply(objs);
delete dm;    // delete when done
```

## 6. API quick reference

| Function / member | Purpose |
| --- | --- |
| `UF_OBJ_set_color/_font/_line_width/_layer/_translucency` | Change object appearance |
| `UF_OBJ_set_name(tag,str)` / `UF_OBJ_ask_name(tag,buf)` | Set / read the object name |
| `UF_OBJ_set_cre_color(type,subtype,prop,color)` | Set the default creation color of a class of objects |
| `UF_OBJ_cycle_by_name(name,&tag)` | Traverse objects by name (`NULL_TAG` ends) |
| `UF_OBJ_cycle_objs_in_part1(part,type,&tag)` | Traverse part objects by type |
| `UF_OBJ_ask_type_and_subtype(tag,&t,&s)` | Read the object type / subtype |
| `UF_ASSEM_ask_work_part()` | Current work part tag |
| `DisplayModification::SetNewColor/SetNewWidth/Apply` | Bulk change of display attributes |
| `NXObjectManager::Get(tag)` | tag -> C++ object |

## Notes
- **UF <-> NXOpen conversion**: `NXObjectManager::Get(tag)` gives the C++ object; `->Tag()` on a C++ object gives the tag.
- `set_name` works on **features** or **bodies**; when traversing by name, objects with the same name are cycled together.
- Both `cycle_by_name` and `cycle_objs_in_part1` use a returned `NULL_TAG` as the end marker; check it inside the loop before processing.
- A `DisplayModification` must be `delete`d after use, otherwise it leaks.
- In the batch DLL (`NxMain`), always output through `std::cout` / `std::cerr`.
- **Run and verified on NX2512 + assembly `FF.prt`** (naming/color/line width/layer, traversal by name and by type,
  `DisplayModification` create/set/release all OK; 216 solid-class objects in the work part).

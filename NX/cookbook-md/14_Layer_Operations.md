# 14 · Layer Operations (Open C)

## Description
Layer operations on an already opened `.prt` in a batch DLL: query and set layer status, query/create/edit layer categories,
and **traverse all objects on a layer and delete them** (collect first, delete afterwards, so the cycle cursor is not disturbed).
> Entry point see [doc 00](00_NX_DLL_Entry_Template.md).

## Keywords
UF_LAYER_ask_work_layer, UF_LAYER_ask_status, UF_LAYER_set_status, UF_LAYER_ask_category_tag,
UF_LAYER_ask_category_info, UF_LAYER_category_info_t, UF_LAYER_create_category,
UF_LAYER_edit_category_name, UF_LAYER_edit_category_descr, UF_LAYER_cycle_by_layer,
UF_MODL_create_list, UF_OBJ_delete_object, layer_mask

---

## 0. Layer status constants

```cpp
#define UF_LAYER_WORK_LAYER      1   // work layer
#define UF_LAYER_ACTIVE_LAYER    2   // selectable layer
#define UF_LAYER_REFERENCE_LAYER 3   // reference only (not selectable)
#define UF_LAYER_INACTIVE_LAYER  4   // invisible
```

## 1. Query / set the work layer and layer status

```cpp
#include <uf_layer.h>

int work = 0;
UF_LAYER_ask_work_layer(&work);         // current work layer number
std::cout << "work layer = " << work << std::endl;

int status = 0;
UF_LAYER_ask_status(61, &status);                // query the status of layer 61
UF_LAYER_set_status(61, UF_LAYER_WORK_LAYER);    // make layer 61 the work layer
```

## 2. Layer category info `UF_LAYER_category_info_t`

```cpp
// Get the category tag from the category name
tag_t catTag = NULL_TAG;
UF_LAYER_ask_category_tag("00_FINAL_DATA", &catTag);

// Get the category info (name, description, which layers it contains)
UF_LAYER_category_info_t info;
UF_LAYER_ask_category_info(catTag, &info);
// info.name / info.descr / info.layer_mask[256] (0/1 per layer: whether it belongs to this category)
```

## 3. Create / edit a layer category

```cpp
UF_LAYER_category_info_t cat;
strcpy(cat.name,  "LayerCategoryName");
strcpy(cat.descr, "LayerCategoryDescription");
for (int i = 0; i < 256; i++)
    cat.layer_mask[i] = (i <= 5) ? 1 : 0;   // put layers 0~5 into this category

tag_t newTag = NULL_TAG;
UF_LAYER_create_category(&cat, &newTag);

// Rename / change the description
UF_LAYER_edit_category_descr(newTag, "New category description");
UF_LAYER_edit_category_name (newTag, "New category name");
```

## 4. Traverse all objects on a layer

Each call to `UF_LAYER_cycle_by_layer` returns the next object tag; `NULL_TAG` means the traversal has ended:

```cpp
tag_t objTag = NULL_TAG;
do {
    UF_LAYER_cycle_by_layer(61, &objTag);   // fetch the objects of layer 61 one by one
    if (objTag != NULL_TAG) {
        std::cout << "obj on layer 61: tag = " << objTag << std::endl;
    }
} while (objTag != NULL_TAG);
```

## 5. Delete all objects on a layer (collect first, then delete)

**MANDATORY**: do not delete while cycling (deletion disturbs the cursor); collect into a list first, then delete in one pass:

```cpp
#include <uf_modl.h>
#include <uf_obj.h>

// 1) Collect the objects of this layer into a list
uf_list_t* objs = NULL;
UF_MODL_create_list(&objs);
tag_t objTag = NULL_TAG;
do {
    UF_LAYER_cycle_by_layer(61, &objTag);
    if (objTag != NULL_TAG)
        UF_MODL_put_list_item(objs, objTag);
} while (objTag != NULL_TAG);

// 2) Then traverse the list and delete
int count = 0;
UF_MODL_ask_list_count(objs, &count);
for (int i = 0; i < count; i++) {
    UF_MODL_ask_list_item(objs, i, &objTag);
    if (objTag != 0)
        UF_OBJ_delete_object(objTag);
}
std::cout << "deleted " << count << " objects on layer 61" << std::endl;

// 3) Free the list
UF_MODL_delete_list(&objs);
```

## 6. API quick reference

| Function / member | Purpose |
| --- | --- |
| `UF_LAYER_ask_work_layer(&n)` | Current work layer number |
| `UF_LAYER_ask_status(layer,&s)` / `UF_LAYER_set_status(layer,state)` | Query / set layer status |
| `UF_LAYER_ask_category_tag(name,&tag)` | Category name -> category tag |
| `UF_LAYER_ask_category_info(tag,&info)` | Read category name / description / `layer_mask[256]` |
| `UF_LAYER_create_category(&cat,&tag)` | Create a layer category |
| `UF_LAYER_edit_category_name/_descr(tag,str)` | Change category name / description |
| `UF_LAYER_cycle_by_layer(layer,&objTag)` | Traverse the objects of a layer (`NULL_TAG` ends) |
| `UF_OBJ_delete_object(tag)` | Delete an object |

## Notes
- `layer_mask` is of type `logical[UF_LAYER_MAX_LAYER]` (verified on NX2512); **index 0 corresponds to layer 1**,
  index `i` corresponds to layer `i+1` (it is NOT "index equals layer number"); a non-zero value means the layer belongs to this category.
  Example: to put layers 1~6 into a category write `for(i=0;i<UF_LAYER_MAX_LAYER;i++) cat.layer_mask[i]=(i<=5);`.
- **Do not delete objects directly inside the `cycle_by_layer` loop**, otherwise objects are missed / it crashes; collect first, then delete.
- `UF_LAYER_set_status` can make the target layer the work layer before operating, or make helper layers invisible.
- In the batch DLL (`NxMain`), always output through `std::cout` / `std::cerr`.
- **Run and verified on NX2512 + assembly `FF.prt`** (work layer = 1, 421 objects on that layer; category create/edit/read-back rc=0).

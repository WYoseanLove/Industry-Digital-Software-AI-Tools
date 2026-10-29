# 16 · Expressions & Attribute Write (Open C)

## Description
In a batch DLL, create/query/import/export/traverse **expressions** of an already opened `.prt` (`UF_MODL_*_exp`), and **delete/assign user attributes**
(`UF_ATTR_*`, including the differences and stability notes between the old and new NX11 write APIs).
> For **read-only attributes** (enumerating all user attributes, case-insensitive name matching of `Item ID`, etc.) see
> [10_Part_Attributes_and_Name_Matching.md](10_Part_Attributes_and_Name_Matching.md) (not repeated here; this doc focuses on **expressions** and **attribute write/delete**).
> Entry point see [doc 00](00_NX_DLL_Entry_Template.md).

## Keywords
UF_MODL_create_exp, UF_MODL_create_exp_tag, UF_MODL_ask_exp, UF_MODL_ask_exps_of_part,
UF_MODL_ask_exp_tag_string, UF_MODL_import_exp, UF_MODL_export_exp, UF_MODL_update,
UF_ATTR_delete, UF_ATTR_delete_all, UF_ATTR_assign, UF_ATTR_value_t, UF_ATTR_ask_part_attribute,
UF_ATTR_find_attribute, UF_ATTR_cycle, UF_ATTR_set_user_attribute, UF_ATTR_info_s,
UF_ATTR_init_user_attribute_info, UF_ASSEM_ask_work_part

---

## 1. Create expressions

> **MANDATORY -- header verified on NX2512**: `UF_MODL_create_exp` / `create_exp_tag` / `ask_exp` / `ask_exps_of_part` /
> `ask_exp_tag_string` are all **retiring APIs**, declared in **`uf_modl_expressions_retiring.h`**;
> with only `#include <uf_modl.h>` you get `C3861` (symbol not found). They still work, but new projects should prefer the non-retiring interfaces.

```cpp
#include <uf_modl.h>
#include <uf_modl_expressions_retiring.h>   // UF_MODL_*_exp (retiring header on NX2512)

UF_MODL_create_exp("name=80.00");            // create an expression directly

tag_t expTag = NULL_TAG;
UF_MODL_create_exp_tag("length=100", &expTag); // create and return the tag
```

## 2. Query an expression by name, list all expressions of a part

```cpp
#include <uf_assem.h>

// Get the expression string by name
char exp[UF_MAX_EXP_BUFSIZE + 1];
UF_MODL_ask_exp("name", exp);
std::cout << "name = " << exp << std::endl;

// Get the tags of all expressions of the current work part
tag_t work = UF_ASSEM_ask_work_part();
int num = 0;
tag_t* expTags = NULL;
UF_MODL_ask_exps_of_part(work, &num, &expTags);

// Get the expression string one by one
for (int i = 0; i < num; i++) {
    char* s = NULL;
    UF_MODL_ask_exp_tag_string(expTags[i], &s);
    std::cout << s << std::endl;
    UF_free(s);        // every string must be freed
}
UF_free(expTags);      // free the tag array
```

## 3. Import / export an expression file

```cpp
UF_MODL_import_exp("D:\\path\\1.exp", 0);  // import from .exp
UF_MODL_update();                          // trigger an update
UF_MODL_export_exp("D:\\path\\2.exp");     // export to .exp
```

## 4. Delete attributes

```cpp
#include <uf_attr.h>

tag_t work = UF_ASSEM_ask_work_part();

UF_ATTR_delete(work, UF_ATTR_any, "REMARK");   // delete the attribute with the given title
UF_MODL_update();

UF_ATTR_delete_all(work, UF_ATTR_any);          // delete all (some template attributes may not be deletable)
```

## 5. Assign attributes (old API `UF_ATTR_assign`, most stable in batch)

> **MANDATORY -- header verified on NX2512**: `UF_ATTR_assign` / `UF_ATTR_cycle` / `UF_ATTR_ask_part_attribute`
> are all **retiring APIs**, declared in **`uf_retiring.h`** (not in `uf_attr.h`); they still compile and run.
> For new projects, prefer `UF_ATTR_set_user_attribute` of section 5.1 + the iterator of [doc 10](10_Part_Attributes_and_Name_Matching.md) (both in `uf_attr.h`).

```cpp
#include <uf_attr.h>
#include <uf_retiring.h>   // UF_ATTR_assign / _cycle / _ask_part_attribute (retiring header on NX2512)

// Get the part-attribute host tag
tag_t attrTag = NULL_TAG;
UF_ATTR_ask_part_attribute(&attrTag);

UF_ATTR_value_t val;
val.type = UF_ATTR_string;             // can also be UF_ATTR_bool / _integer / _real ...
val.value.string = (char*)"2A14";
UF_ATTR_assign(attrTag, (char*)"REMARK", val);

UF_MODL_update();
```

### 5.1 New API `UF_ATTR_set_user_attribute` (NX11+)
The new interface uses the `UF_ATTR_info_s` struct with more fields (category, unit, etc.):

```cpp
UF_ATTR_info_s info;
UF_ATTR_init_user_attribute_info(&info);   // must initialize first
info.type         = UF_ATTR_string;
info.string_value = "2A14";
info.title        = "REMARK";
int num = UF_ATTR_set_user_attribute(attrTag, &info, 0);
UF_ATTR_free_user_attribute_info_strings(&info);  // free
```
> Observed: **in batch / some scenarios the new interface occasionally has no effect; the old `UF_ATTR_assign` is more stable**; keep both as a fallback.

## 6. Find and traverse attributes (locate before writing)

Attribute type constants: `UF_ATTR_integer(1) _real(2) _time(3) _null(4) _string(5) _any(6) _reference(7) _bool(8)`.

```cpp
tag_t attrTag = NULL_TAG;
UF_ATTR_ask_part_attribute(&attrTag);

// Query the type by title
int titleType = 0;
UF_ATTR_find_attribute(attrTag, UF_ATTR_any, "Title", &titleType);

// Traverse all attributes: i is the cursor, i returning to 0 means the end
int i = 0;
char title[256];
UF_ATTR_value_t val;
UF_ATTR_cycle(attrTag, &i, UF_ATTR_any, title, &val);
while (i) {
    if (val.type == UF_ATTR_string)
        std::cout << title << " = " << val.value.string << std::endl;
    UF_ATTR_cycle(attrTag, &i, UF_ATTR_any, title, &val);  // next one
}
```
> If you only need to **read and match by name** the part user attributes (e.g. working around `GetUserAttributes()` returning 0 entries in batch),
> the `UF_ATTR_*_user_attribute_iterator` iterator of [doc 10](10_Part_Attributes_and_Name_Matching.md) is more complete.

## 7. API quick reference

| Function | Purpose |
| --- | --- |
| `UF_MODL_create_exp(str)` / `UF_MODL_create_exp_tag(str,&tag)` | Create an expression / create and return the tag |
| `UF_MODL_ask_exp(name,buf)` | Get the expression string by name |
| `UF_MODL_ask_exps_of_part(part,&n,&tags)` | Get the tags of all expressions of a part |
| `UF_MODL_ask_exp_tag_string(tag,&s)` | tag -> expression string (needs `UF_free`) |
| `UF_MODL_import_exp/export_exp` | Import/export an `.exp` file |
| `UF_MODL_update()` | Trigger an update after changing expressions/attributes |
| `UF_ATTR_ask_part_attribute(&tag)` | Get the part-attribute host tag |
| `UF_ATTR_assign(tag,title,val)` | Old API assignment (more stable in batch) |
| `UF_ATTR_set_user_attribute(tag,&info,0)` | New API assignment (NX11+) |
| `UF_ATTR_delete/_delete_all` | Delete attributes |
| `UF_ATTR_find_attribute / UF_ATTR_cycle` | Find / traverse attributes |

## Notes
- Expression names may contain non-ASCII characters; use `UF_MAX_EXP_BUFSIZE + 1` for the value buffer.
- The `tag_t*` returned by `UF_MODL_ask_exps_of_part` and the `char*` of `ask_exp_tag_string` must both be `UF_free`d.
- After changing attributes/expressions call `UF_MODL_update()` to update the part; to persist after writing, call `part->Save()`.
- `UF_ATTR_cycle` uses an integer cursor `i`; **`i==0` means the traversal ended**; check it before use inside the loop.
- In the batch DLL (`NxMain`), always output through `std::cout` / `std::cerr`.
- **Verified on NX2512 + assembly `FF.prt`**: expression add/query (4 expressions in the part),
  `UF_ATTR_assign` (retiring) and `UF_ATTR_set_user_attribute` (new) writes, and `UF_ATTR_cycle` read-back all rc=0.

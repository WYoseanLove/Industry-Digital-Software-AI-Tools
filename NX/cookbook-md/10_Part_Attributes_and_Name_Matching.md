# 10 · Part Attributes & Name Matching (UF_ATTR)

## Description
Reads the **user attributes** on the part object of an opened `.prt`, getting each
title (attribute name) and value, and **matches by name, case-insensitively** to locate `Item ID`.
When `NXObject::GetUserAttributes()` returns 0 entries, **switch to the NX
Open C `UF_ATTR` iteration API** and read directly by object tag (the most reliable in batch mode).

## Keywords
Attribute, attributes, user attribute, UF_ATTR, iterator, GetUserAttributes, Item ID, ItemId,
title, value, name matching, case-insensitive, batch, tag

---

## 1. Why UF_ATTR instead of NXObject::GetUserAttributes()

In an **external standalone batch session (after `UF_initialize`)**, `part->GetUserAttributes()` often returns
**0 entries**; in that case use the Open C API `UF_ATTR_*` and iterate by object tag -- it is the **most reliable** and most complete.

```cpp
#include <uf.h>
#include <uf_attr.h>       // UF_ATTR_* attribute iteration API
#include <NXOpen/Part.hxx>

#include <string>
#include <cctype>          // std::tolower
#include <iostream>
```

## 2. Iterate all user attributes + match the target attribute

```cpp
// Iterate all user attributes on the part and match the value of "Item ID" by name
static void ReportItemId(Part* part)
{
    if (part == nullptr)
    {
        std::cout << "No part is available." << std::endl;
        return;
    }

    std::cout << "=== Item ID ===" << std::endl;

    // When NXObject::GetUserAttributes() returns 0 entries in batch mode,
    // use the UF_ATTR C API below and iterate by object tag.
    const tag_t objTag = part->Tag();
    std::string itemId;

    UF_ATTR_iterator_t iter;
    if (UF_ATTR_init_user_attribute_iterator(&iter) != 0)
    {
        std::cout << "Failed to initialize the attribute iterator." << std::endl;
        return;
    }

    int count = 0;
    if (UF_ATTR_count_user_attributes(objTag, &iter, &count) == 0)
    {
        std::cout << "User attribute count: " << count << std::endl;
    }

    // Iterate the attributes one by one
    for (;;)
    {
        UF_ATTR_info_t info;
        UF_ATTR_init_user_attribute_info(&info);

        logical hasAttribute = false;
        int irc = UF_ATTR_get_next_user_attribute(objTag, &iter, &info, &hasAttribute);
        if (irc != 0 || !hasAttribute)
        {
            UF_ATTR_free_user_attribute_info_strings(&info);
            break;
        }

        std::string titleStr = (info.title != nullptr) ? info.title : "";
        std::string valueStr = (info.string_value != nullptr) ? info.string_value : "";

        std::cout << "  Attr: \"" << titleStr << "\" = \"" << valueStr << "\"" << std::endl;

        // Case-insensitive match of "item id":
        // cast to unsigned char before passing to std::tolower, otherwise a negative value may trigger a Debug assertion/UB.
        std::string lower;
        lower.reserve(titleStr.size());
        for (char c : titleStr)
        {
            lower.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(c))));
        }
        if (itemId.empty() && lower.find("item id") != std::string::npos)
        {
            itemId = valueStr;
        }

        UF_ATTR_free_user_attribute_info_strings(&info);
    }

    UF_ATTR_release_user_attribute_iterator(&iter);

    if (!itemId.empty())
    {
        std::cout << "Item ID: " << itemId << std::endl;
        return;
    }

    std::cout << "Item ID not found among the part attributes." << std::endl;
}
```

## 3. Call it from the DLL entry (`NxMain`)

```cpp
Session* theSession = Session::GetSession();
PartLoadStatus* ls = nullptr;
Part* part = theSession->Parts()->OpenDisplay(partPath.c_str(), &ls);
if (ls) { delete ls; ls = nullptr; }

ReportItemId(part);
```

## 4. Generic: get any attribute value by name keyword / reuse

Extract the matching logic into a generic function; pass a keyword to reuse it for other attributes.

```cpp
// Get an attribute value by name keyword (case-insensitive)
static std::string GetAttrByName(Part* part, const std::string& keyword)
{
    std::string result;
    if (part == nullptr) return result;

    std::string key;
    key.reserve(keyword.size());
    for (char c : keyword)
        key.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(c))));

    const tag_t objTag = part->Tag();
    UF_ATTR_iterator_t iter;
    if (UF_ATTR_init_user_attribute_iterator(&iter) != 0) return result;

    for (;;)
    {
        UF_ATTR_info_t info;
        UF_ATTR_init_user_attribute_info(&info);

        logical has = false;
        int irc = UF_ATTR_get_next_user_attribute(objTag, &iter, &info, &has);
        if (irc != 0 || !has)
        {
            UF_ATTR_free_user_attribute_info_strings(&info);
            break;
        }

        std::string title = (info.title != nullptr) ? info.title : "";
        std::string value = (info.string_value != nullptr) ? info.string_value : "";

        std::string lower;
        lower.reserve(title.size());
        for (char c : title)
            lower.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(c))));

        if (result.empty() && lower.find(key) != std::string::npos)
            result = value;

        UF_ATTR_free_user_attribute_info_strings(&info);
    }

    UF_ATTR_release_user_attribute_iterator(&iter);
    return result;
}

// Usage
std::string itemId  = GetAttrByName(part, "item id");
std::string drawing = GetAttrByName(part, "drawing number");
```

## 5. Headers and dependencies

```cpp
#include <NXOpen/Session.hxx>
#include <NXOpen/Part.hxx>
#include <NXOpen/PartCollection.hxx>
#include <NXOpen/BasePart.hxx>
#include <NXOpen/PartLoadStatus.hxx>
#include <NXOpen/NXException.hxx>

// NX Open C (UF) API -- required to start an external session
#include <uf.h>
#include <uf_part.h>
#include <uf_attr.h>   // read user attributes
```

## Gotchas

- **Clean up in pairs**: after every `UF_ATTR_get_next_user_attribute` (including before a break) call
  `UF_ATTR_free_user_attribute_info_strings(&info)`; when the iteration ends call `UF_ATTR_release_user_attribute_iterator(&iter)` to release the iterator.
- **Cast to `unsigned char` before `std::tolower`**: passing a possibly negative char directly triggers UB / a Debug assertion.
- `info.string_value` is only valid for string-type attributes; for numeric/date types check `info.type` first.
- When `GetUserAttributes()` returns 0 entries in **batch mode**, always switch to `UF_ATTR_*` iteration.

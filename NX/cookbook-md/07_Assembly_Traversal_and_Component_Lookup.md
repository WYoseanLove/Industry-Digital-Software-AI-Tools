# 07 · Traverse Assembly & Find a Component (.prt)

## Description
In a remote batch DLL, opens a **product/assembly** `.prt`, **recursively traverses the component tree**, and **locates a component (child `.prt`)** by name / part name / attribute.
This is the first step of "enter a component, measure/edit, then return" (see doc 08).
API: `Part::ComponentAssembly()` -> `RootComponent()` -> `Component::GetChildren()`.

## Keywords
Assembly, product, ComponentAssembly, RootComponent, Component, GetChildren, DisplayName,
Prototype, OwningPart, GetPosition, traverse, find, subassembly, recursion

---

## 1. Open the assembly and get the root component

```cpp
#include <NXOpen/Part.hxx>
#include <NXOpen/Assemblies_ComponentAssembly.hxx>
#include <NXOpen/Assemblies_Component.hxx>

Session* theSession = Session::GetSession();
PartLoadStatus* ls = nullptr;
Part* assembly = theSession->Parts()->OpenDisplay(assemblyPath.c_str(), &ls);
if (ls) { delete ls; ls = nullptr; }

NXOpen::Assemblies::ComponentAssembly* ca = assembly->ComponentAssembly();
NXOpen::Assemblies::Component* root = ca->RootComponent();
if (root == nullptr) { std::cout << "This part is not an assembly (no components)." << std::endl; }
```

## 2. Recursively traverse the whole component tree (print the hierarchy)

```cpp
static void Traverse(NXOpen::Assemblies::Component* comp, int depth)
{
    if (comp == nullptr) return;
    std::string indent(depth * 2, ' ');
    std::cout << indent << "- " << comp->DisplayName().GetText() << std::endl;

    std::vector<NXOpen::Assemblies::Component*> children = comp->GetChildren();
    for (NXOpen::Assemblies::Component* child : children)
        Traverse(child, depth + 1);   // recurse into the subassembly
}

// Call:
Traverse(root, 0);
```

> A leaf component's `GetChildren()` returns empty; a subassembly returns its next-level components. Depth-first covers the whole tree.

## 3. Find a component by "component display name"

```cpp
static NXOpen::Assemblies::Component* FindByName(
    NXOpen::Assemblies::Component* comp, const std::string& target)
{
    if (comp == nullptr) return nullptr;
    if (comp->DisplayName().GetText() == target) return comp;

    for (NXOpen::Assemblies::Component* child : comp->GetChildren())
    {
        NXOpen::Assemblies::Component* found = FindByName(child, target);
        if (found) return found;
    }
    return nullptr;
}

// Call:
NXOpen::Assemblies::Component* target = FindByName(root, "BRACKET_LH");
if (target) std::cout << "Found: " << target->DisplayName().GetText() << std::endl;
```

## 4. Find by "part file name (.prt name)"

A component's prototype is the `Part` it references; use it to match the part name / path:

```cpp
#include <NXOpen/NXObject.hxx>

static NXOpen::Assemblies::Component* FindByPartLeaf(
    NXOpen::Assemblies::Component* comp, const std::string& leaf)
{
    if (comp == nullptr) return nullptr;

    // component prototype -> Part (may not be fully loaded, check for null)
    NXOpen::Part* proto = dynamic_cast<NXOpen::Part*>(comp->Prototype());
    if (proto != nullptr && std::string(proto->Leaf().GetText()) == leaf)
        return comp;

    for (NXOpen::Assemblies::Component* child : comp->GetChildren())
    {
        NXOpen::Assemblies::Component* found = FindByPartLeaf(child, leaf);
        if (found) return found;
    }
    return nullptr;
}

// Call (with or without extension, depending on what Leaf() returns):
NXOpen::Assemblies::Component* comp = FindByPartLeaf(root, "bracket_lh");
```

## 5. Collect all matching components (the same .prt may be referenced in several places)

The same part may appear several times in an assembly (multiple occurrences). Collect them all:

```cpp
static void CollectByPartLeaf(NXOpen::Assemblies::Component* comp,
    const std::string& leaf, std::vector<NXOpen::Assemblies::Component*>& out)
{
    if (comp == nullptr) return;
    NXOpen::Part* proto = dynamic_cast<NXOpen::Part*>(comp->Prototype());
    if (proto && std::string(proto->Leaf().GetText()) == leaf) out.push_back(comp);
    for (NXOpen::Assemblies::Component* c : comp->GetChildren())
        CollectByPartLeaf(c, leaf, out);
}

std::vector<NXOpen::Assemblies::Component*> hits;
CollectByPartLeaf(root, "bolt_m8", hits);
std::cout << "matches: " << hits.size() << std::endl;
```

## 6. Get the component's position/orientation in the assembly (needed for later coordinate transforms)

```cpp
#include <NXOpen/Matrix3x3.hxx>

NXOpen::Point3d   position;      // component origin in the assembly (WCS)
NXOpen::Matrix3x3 orientation;   // rotation of the component frame relative to the assembly
target->GetPosition(&position, &orientation);
std::cout << "component origin @ (" << position.X << "," << position.Y << "," << position.Z << ")\n";
```

> Component geometry is defined in its **own coordinate system**; `GetPosition` gives the "component -> assembly" rigid transform. For cross-frame measurement see doc 08.

## 7. API quick reference

| Class / member | Purpose |
| --- | --- |
| `part->ComponentAssembly()` | Get the assembly object |
| `ca->RootComponent()` | Root component (top level of the assembly) |
| `component->GetChildren()` | Direct child components (for recursive traversal) |
| `component->DisplayName()` | Component display name |
| `component->Prototype()` -> `Part*` | Prototype part referenced by the component |
| `proto->Leaf()` / `FullPath()` | Part name / path (to match a .prt) |
| `component->GetPosition(&pos, &ori)` | Position/orientation in the assembly |
| `component->Parent()` | Parent component (walk upward) |
| `component->IsSuppressed()` | Whether suppressed (can be skipped) |
| `#include <NXOpen/Assemblies_ComponentAssembly.hxx>` `<NXOpen/Assemblies_Component.hxx>` | Headers |

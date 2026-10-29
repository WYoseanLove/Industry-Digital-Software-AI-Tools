# 09 · Import JT & Convert to PRT

## Description
In a remote batch DLL, reads a **`.jt` file** from a given path into NX (a single part or a whole assembly), then **saves it as a `.prt`** into a given directory.
Two core steps: `theSession->Parts()->OpenBaseDisplay(jtPath, &loadStatus)` opens non-`.prt` files (JT goes through this, **not** `OpenDisplay`),
and on success call `SaveAs(prtPath)` on the returned `BasePart*` to produce a `.prt` copy. For an assembly JT, set `LoadOptions` first to load all components, then `SaveAll` / save each one.
It reuses the `NxMain` + `UF_initialize/terminate` skeleton of [00_NX_DLL_Entry_Template.md](00_NX_DLL_Entry_Template.md).

## Keywords
JT, jt2prt, OpenBaseDisplay, OpenBase, SaveAs, BasePart, PartSaveStatus, PartLoadStatus,
LoadOptions, SetComponentsToLoad, LoadComponentsAll, ComponentAssembly, RootComponent,
Save, SaveAll, batch convert, assembly, single part, convert, import, save as

---

## 1. How it works

| Goal | API | Notes |
| --- | --- | --- |
| Open a `.prt` | `Parts()->OpenDisplay(path, &st)` | Opens **only** `.prt` |
| Open a `.jt` (and other non-prt) | `Parts()->OpenBaseDisplay(path, &st)` | Returns `BasePart*` and makes it the display part |
| Open without making it the display part | `Parts()->OpenBase(path, &st)` | Same as above but does not switch the display |
| Save as `.prt` | `basePart->SaveAs("D:\\out\\x.prt")` | Creates a copy, returns `PartSaveStatus*` |
| Save including all components | `basePart->Save(SaveComponentsTrue, CloseAfterSaveFalse)` | Saves children together for an assembly |
| Load all components of an assembly | `Parts()->LoadOptions()->SetComponentsToLoad(LoadComponentsAll)` | Set before opening |

> **Key point**: `SaveAs` only accepts a **new file name** (give a full absolute path + `.prt` suffix); the target directory must already exist, otherwise it fails.

---

## 2. Single JT -> PRT (complete and runnable)

```cpp
#include <iostream>
#include <string>

#include <NXOpen/Session.hxx>
#include <NXOpen/Part.hxx>
#include <NXOpen/BasePart.hxx>
#include <NXOpen/PartCollection.hxx>
#include <NXOpen/PartLoadStatus.hxx>
#include <NXOpen/PartSaveStatus.hxx>
#include <NXOpen/NXException.hxx>

#include <uf.h>

using namespace NXOpen;

// Convert one .jt to .prt; returns true on success
static bool ConvertJtToPrt(Session* theSession,
                           const std::string& jtPath,
                           const std::string& prtPath)
{
    // 1) Open the JT (non-prt files go through OpenBaseDisplay)
    PartLoadStatus* loadStatus = nullptr;
    BasePart* part = theSession->Parts()->OpenBaseDisplay(jtPath.c_str(), &loadStatus);
    if (loadStatus != nullptr) { delete loadStatus; loadStatus = nullptr; }
    if (part == nullptr)
    {
        std::cerr << "Failed to open JT: " << jtPath << std::endl;
        return false;
    }

    std::cout << "Opened: " << part->FullPath().GetText() << std::endl;

    // 2) Save as .prt (the directory of prtPath must already exist)
    PartSaveStatus* saveStatus = part->SaveAs(prtPath.c_str());
    if (saveStatus != nullptr) { delete saveStatus; saveStatus = nullptr; }
    std::cout << "Saved: " << prtPath << std::endl;

    // 3) Close this part to release session memory (required for batch conversion)
    part->Close(BasePart::CloseWholeTreeTrue,
                BasePart::CloseModifiedCloseModified, nullptr);
    return true;
}

// DLL entry: argv[0] = DLL path, argv[1] = first user argument
extern "C" __declspec(dllexport) int NxMain(int argc, char* argv[])
{
    std::string jtPath  = (argc >= 2) ? argv[1] : "C:\\data\\model.jt";
    std::string prtPath = (argc >= 3) ? argv[2] : "C:\\data\\out\\model.prt";

    if (UF_initialize() != 0)
    {
        std::cerr << "UF_initialize failed. Check NX runtime / license." << std::endl;
        std::cerr.flush();
        return 1;
    }

    int rc = 0;
    try
    {
        Session* theSession = Session::GetSession();
        if (!ConvertJtToPrt(theSession, jtPath, prtPath)) rc = 1;
    }
    catch (const NXException& ex)
    {
        std::cerr << "NX exception: " << ex.Message() << std::endl;
        rc = 1;
    }
    catch (const std::exception& ex)
    {
        std::cerr << "Error: " << ex.what() << std::endl;
        rc = 1;
    }

    UF_terminate();
    std::cout.flush();
    std::cerr.flush();
    return rc;
}
```

> The `Close` enums come from `BasePart`: `CloseWholeTreeTrue` (close together with children),
> `CloseModifiedCloseModified` (close even if modified). In batch conversion **always `Close` after each conversion**, otherwise parts pile up in the session.

---

## 3. Assembly JT -> PRT: **save every part as a prt and keep the structure tree**

> **Goal**: after the assembly JT is opened it has a structure tree; **every part in the tree (including subassemblies at all levels) must be saved as its own `.prt`**,
> and the main assembly's tree must reference these new prts -- so the main prt can later be reopened and traversed recursively as in doc 07.

**Key order**: **save leaves/children as prt first, then the parent assembly**. Reason: component prototypes in a JT are only in-memory parts with no disk file;
only after a child is written to disk and has a `.prt` path does `SaveAs` on the parent record the child's new path in its structure tree (instead of losing the reference or embedding it).
So the code below uses a **post-order traversal**: recurse into children first, then save the current part while unwinding.

```cpp
#include <NXOpen/LoadOptions.hxx>
#include <NXOpen/Assemblies_ComponentAssembly.hxx>
#include <NXOpen/Assemblies_Component.hxx>
#include <NXOpen/NXObject.hxx>
#include <vector>
#include <string>
#include <set>
#include <filesystem>
namespace fs = std::filesystem;

// Clean the component display name into a legal file name (strip path/illegal characters) so SaveAs does not fail
static std::string SanitizeName(const std::string& raw)
{
    std::string s = raw;
    for (char& c : s)
        if (c=='\\'||c=='/'||c==':'||c=='*'||c=='?'||c=='"'||c=='<'||c=='>'||c=='|')
            c = '_';
    if (s.empty()) s = "part";
    return s;
}

// Post-order traversal: save all children first, then the current part itself.
// savedProtos records the "already saved prototype parts"; a part referenced in several places is saved only once.
static void SaveComponentTree(NXOpen::Assemblies::Component* comp,
                              const std::string& outDir,
                              std::set<NXOpen::Part*>& savedProtos)
{
    if (comp == nullptr) return;

    // 1) Recurse into children first (depth-first, so leaves hit the disk first)
    std::vector<NXOpen::Assemblies::Component*> children = comp->GetChildren();
    for (NXOpen::Assemblies::Component* child : children)
        SaveComponentTree(child, outDir, savedProtos);

    // 2) Unwinding: save this component's prototype part as a prt (deduplicated)
    NXOpen::Part* proto = dynamic_cast<NXOpen::Part*>(comp->Prototype());
    if (proto == nullptr) return;                 // prototype not loaded / not a Part, skip
    if (savedProtos.count(proto)) return;         // this part was already saved, avoid duplicates

    std::string name = SanitizeName(comp->DisplayName().GetText());
    std::string prtPath = (fs::path(outDir) / name).string() + ".prt";

    NXOpen::PartSaveStatus* ss = proto->SaveAs(prtPath.c_str());
    if (ss != nullptr) { delete ss; ss = nullptr; }
    savedProtos.insert(proto);
    std::cout << "  Saved part: " << prtPath << std::endl;
}

// Open the assembly JT -> save every part as prt (keeping the structure tree) -> save the main assembly
static bool ConvertAssemblyJt(Session* theSession,
                              const std::string& jtPath,
                              const std::string& outDir,
                              const std::string& rootPrtPath)
{
    if (!fs::exists(outDir)) fs::create_directories(outDir);   // the target directory must exist first

    // Before opening: load all components (children of a split JT are only brought in this way)
    theSession->Parts()->LoadOptions()->SetComponentsToLoad(
        LoadOptions::LoadComponentsAll);

    PartLoadStatus* ls = nullptr;
    BasePart* base = theSession->Parts()->OpenBaseDisplay(jtPath.c_str(), &ls);
    if (ls != nullptr) { delete ls; ls = nullptr; }
    if (base == nullptr) { std::cerr << "Failed to open assembly JT\n"; return false; }

    Part* asm_ = dynamic_cast<Part*>(base);
    NXOpen::Assemblies::Component* root =
        (asm_ != nullptr) ? asm_->ComponentAssembly()->RootComponent() : nullptr;

    if (root == nullptr)
    {
        // Not an assembly (single-part JT): just save one prt
        PartSaveStatus* ss = base->SaveAs(rootPrtPath.c_str());
        if (ss != nullptr) { delete ss; ss = nullptr; }
        std::cout << "Single part saved: " << rootPrtPath << std::endl;
    }
    else
    {
        // 1) Save all children level by level as prt first (post-order: leaves hit the disk first)
        std::set<NXOpen::Part*> savedProtos;
        std::vector<NXOpen::Assemblies::Component*> children = root->GetChildren();
        for (NXOpen::Assemblies::Component* child : children)
            SaveComponentTree(child, outDir, savedProtos);

        // 2) All children now have prts; save the main assembly -- its structure tree will reference these new prts
        PartSaveStatus* ss = base->SaveAs(rootPrtPath.c_str());
        if (ss != nullptr) { delete ss; ss = nullptr; }
        std::cout << "Main assembly saved (structure tree intact): " << rootPrtPath << std::endl;
    }

    base->Close(BasePart::CloseWholeTreeTrue,
                BasePart::CloseModifiedCloseModified, nullptr);
    return true;
}
```

Call example:

```cpp
// The main assembly prt and all child prts are placed under outDir; the main assembly references the children, forming a traversable structure tree
ConvertAssemblyJt(theSession,
                  "C:\\data\\car_body.jt",       // input assembly JT
                  "C:\\data\\out",               // output directory for all prts
                  "C:\\data\\out\\car_body.prt"); // main assembly prt
```

> **Why can it be traversed afterwards?**
> After saving, `outDir` holds "the main assembly prt + a prt for every part", and the main assembly's structure tree references the children by their new paths.
> Later, using doc 07's `Parts()->OpenDisplay(rootPrtPath)` -> `ComponentAssembly()->RootComponent()` ->
> `Component::GetChildren()` recursion, every part prt written to disk can be reached.
>
> **Summary**
> - **The order cannot be reversed**: save children first and the parent assembly last, otherwise the parent's structure tree cannot reference the child prts.
> - **Deduplicate**: a part referenced in several places (multiple occurrences) is `SaveAs`-ed only once; record the prototypes with `std::set<Part*>`.
> - **Naming**: child prt names come from `Component::DisplayName()` with illegal characters cleaned; for duplicate names add a parent-name/sequence prefix to avoid overwriting.
> - **Split assembly JT**: **set `LoadComponentsAll` first**, then `OpenBaseDisplay`; otherwise children are not loaded and the structure tree is empty.
> - If you only want a **single self-contained prt** (no splitting into children), use `base->Save(SaveComponentsTrue, CloseAfterSaveFalse)` or `SaveAs` directly on the root assembly.
> - For the full way of traversing/finding components see [07_Assembly_Traversal_and_Component_Lookup.md](07_Assembly_Traversal_and_Component_Lookup.md).

---

## 4. Batch-convert a whole directory

Given a directory, convert every `.jt` in it to a same-named `.prt` in the output directory.

```cpp
#include <filesystem>   // C++17
namespace fs = std::filesystem;

static void ConvertFolder(Session* theSession,
                          const std::string& inDir,
                          const std::string& outDir)
{
    if (!fs::exists(outDir)) fs::create_directories(outDir);   // the target directory must exist

    for (const auto& entry : fs::directory_iterator(inDir))
    {
        if (!entry.is_regular_file()) continue;
        if (entry.path().extension() != ".jt" &&
            entry.path().extension() != ".JT") continue;

        std::string jt  = entry.path().string();
        std::string prt = (fs::path(outDir) /
                           entry.path().stem()).string() + ".prt";

        std::cout << "Converting: " << jt << " -> " << prt << std::endl;
        try { ConvertJtToPrt(theSession, jt, prt); }        // reuse the function from section 2
        catch (const NXException& ex)
        { std::cerr << "  Skipped (exception): " << ex.Message() << std::endl; }
    }
}
```

> Each file is already `Close`d inside `ConvertJtToPrt`, so session memory does not accumulate.
> Call it from `NxMain`: `ConvertFolder(theSession, "C:\\data\\jt_in", "C:\\data\\prt_out");`

---

## 5. API quick reference and pitfalls

| API | Header | Notes |
| --- | --- | --- |
| `PartCollection::OpenBaseDisplay(path, &st)` | `NXOpen/PartCollection.hxx` | Opens `.jt` and other non-prt files, returns `BasePart*` |
| `PartCollection::OpenBase(path, &st)` | same | Opens without setting the display part |
| `BasePart::SaveAs(path)` | `NXOpen/BasePart.hxx` | Save a copy, returns `PartSaveStatus*` |
| `BasePart::Save(saveComps, close)` | same | Save together with components |
| `BasePart::Close(scope, modified, nullptr)` | same | Close the part and release memory |
| `LoadOptions::SetComponentsToLoad(LoadComponentsAll)` | `NXOpen/LoadOptions.hxx` | Load all components before opening an assembly |
| `Part::ComponentAssembly()->RootComponent()` | `NXOpen/Assemblies_ComponentAssembly.hxx` | Get the assembly root component (traversal in 07) |

**Common pitfalls**
1. **Do not open a JT with `OpenDisplay`**: `OpenDisplay`/`Open` only handle `.prt`; a JT must use `OpenBaseDisplay`/`OpenBase`.
2. **Create the output directory first**: `SaveAs` does not create directories; call `std::filesystem::create_directories` first.
3. **Give absolute paths + `.prt` suffix**; on Windows remember to escape backslashes: `"C:\\out\\x.prt"`.
4. **Always `Close` in batch conversion**: close each one after converting to avoid piling up parts in one session and exhausting memory/handles.
5. **Use `LoadComponentsAll` for assemblies**: otherwise children of a split JT are not loaded and the saved prts are missing parts.
6. **License**: JT import needs the corresponding JT/data-exchange license (e.g. `jt_open`); without it `OpenBaseDisplay` throws `NXException` -- guard with try/catch.
7. Output results always via `std::cout`, errors via `std::cerr`; still finish with `UF_terminate()` (the exception path must reach it too) and flush both streams before returning from `NxMain`.

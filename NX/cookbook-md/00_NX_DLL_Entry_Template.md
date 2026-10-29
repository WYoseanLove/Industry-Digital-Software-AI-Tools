# 00 · NX DLL Entry Template & Conventions

## Description
Common skeleton shared by all remote measurement scripts: a **`.dll`** exporting `NxMain(int argc, char* argv[])`,
loaded and invoked from **PowerShell** (`NX/tools/nxrun.ps1`). Inside `NxMain`, `UF_initialize()` starts a **batch NX session**,
`OpenDisplay` opens the `.prt`, part information is reported, output goes to `std::cout`, exceptions are handled, and `UF_terminate()` closes the session.
Apply this template before generating any code from this library, then fill the concrete algorithm snippets into `NxMain` or helper functions.

## Keywords
NxMain, dllexport, PowerShell, LoadLibrary, UF_initialize, UF_terminate, Session, GetSession, Parts, OpenDisplay, Open, PartLoadStatus,
batch session, remote, std::cout, NXException, Bodies, IsSolidBody, Tag,
UF_MODL_ask_mass_props_3d, GetFeatureName, NXObjectManager

---

## 0. Workflow

```
1. Generate C++ source (NxMain entry)      ->  Skill.cpp
2. Build a DLL with MSVC                   ->  nxrun.ps1 build Skill.cpp   ->  Skill.dll
3. Load and run the DLL from PowerShell    ->  nxrun.ps1 run Skill.dll <args...>
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File NX\tools\nxrun.ps1 build C:\work\Skill.cpp
powershell -NoProfile -ExecutionPolicy Bypass -File NX\tools\nxrun.ps1 run   C:\work\Skill.dll "C:\path\to\model.prt"
```

- `build` locates MSVC via `vswhere`, enters the x64 environment, and compiles with the flags in section 1.1.
- `run` prepends `%UGII_ROOT_DIR%` to `PATH`, loads the DLL into the PowerShell process (`LoadLibrary`),
  resolves the export `NxMain`, and calls it with `argv[0]` = DLL path and `argv[1..]` = the extra arguments.
- The script exit code equals the return value of `NxMain` (`0` = success). Output from `std::cout` / `std::cerr` appears in the PowerShell console.
- Always run each `run` in a **fresh** `powershell` process: the batch NX session lives inside that process, and the DLL stays locked until the process exits.
- The DLL must be built against the same NX version/runtime that `UGII_BASE_DIR` / `UGII_ROOT_DIR` point to.

## 1. Standard entry skeleton (compile and run as-is)

```cpp
#include <iostream>
#include <string>

// NX Open C++ API
#include <NXOpen/Session.hxx>
#include <NXOpen/Part.hxx>
#include <NXOpen/PartCollection.hxx>
#include <NXOpen/PartLoadStatus.hxx>
#include <NXOpen/NXException.hxx>

// NX Open C (UF) API -- required to start the batch session
#include <uf.h>
#include <uf_modl.h>
#include <uf_curve.h>
#include <uf_obj.h>

using namespace NXOpen;

// Exported entry point called by nxrun.ps1. Keep this exact name and signature.
extern "C" __declspec(dllexport) int NxMain(int argc, char* argv[])
{
    // Part path: command-line argument first (argv[0] is the DLL path), otherwise the default
    std::string partPath = (argc >= 2)
        ? argv[1]
        : "C:\\path\\to\\model.prt";

    // 1) Start the batch NX session (requires the NX runtime + a license on this machine)
    if (UF_initialize() != 0)
    {
        std::cerr << "UF_initialize failed. Check NX runtime / license (UGII_BASE_DIR)." << std::endl;
        return 1;
    }

    int rc = 0;
    try
    {
        Session* theSession = Session::GetSession();

        // 2) Open the .prt (headless: load into memory so data can be read/written)
        PartLoadStatus* loadStatus = nullptr;
        Part* part = theSession->Parts()->OpenDisplay(partPath.c_str(), &loadStatus);
        if (loadStatus != nullptr) { delete loadStatus; loadStatus = nullptr; }
        if (part == nullptr) throw NXException::Create("Unable to open the part file.");

        // ------- Put the measurement / geometry algorithm here -------
        std::cout << "Opened: " << part->FullPath().GetText() << std::endl;
        // -------------------------------------------------------------
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

    // 3) Cleanup (the exception path also reaches here)
    UF_terminate();
    std::cout.flush();
    std::cerr.flush();
    return rc;
}
```

> **Key points**:
> - The DLL starts a **brand-new batch session** inside the PowerShell process. It does **not** attach to an interactive NX that is already open on screen,
>   so the `.prt` to process must be opened explicitly with `OpenDisplay`.
> - Export with `extern "C" __declspec(dllexport) int NxMain(int, char**)` so the name is not mangled.
> - Call `UF_initialize()` / `UF_terminate()` **inside** `NxMain` (not in `DllMain`). Do not start threads that outlive `NxMain`.
> - Flush `std::cout` / `std::cerr` before returning so all output is visible before the script prints `ExitCode=`.

## 1.1 Build and link (MSVC, verified with NX2512)

`nxrun.ps1 build` does the following; the equivalent manual commands are shown for reference.
Headers and libs are in `%UGII_BASE_DIR%\ugopen`:

```bat
REM Enter the x64 build environment
call "...\VC\Auxiliary\Build\vcvars64.bat"

set UG=%UGII_BASE_DIR%\ugopen
cl /nologo /EHsc /MD /std:c++17 /LD /I"%UG%" Skill.cpp /Fe:Skill.dll ^
   /link /LIBPATH:"%UG%" libnxopencpp.lib libufun.lib libnxopencpp_assemblies.lib
```

> **Linking notes (verified)**:
> - **Basic geometry / measurement** (this library 01-06, 10) only needs `libnxopencpp.lib libufun.lib`.
> - **Whenever assembly classes** `NXOpen::Assemblies::*` are used (`Component::GetChildren/DisplayName/RootComponent/
>   Prototype/FindOccurrence`, etc.; see 07/08/09/11), **you must also link `libnxopencpp_assemblies.lib`**,
>   otherwise `LNK2019` unresolved external symbol errors appear. For simplicity, link all three libs for every script.
> - `/LD` produces a DLL; `/Fe:Skill.dll` names it.

## 1.2 Runtime environment (otherwise `LoadLibrary` fails / crash 0xC0000139)

The generated `.dll` depends on NX runtime DLLs. **`%UGII_ROOT_DIR%` (the NXBIN directory) must be on `PATH`** of the process that loads it,
otherwise loading fails (or the process crashes with `0xC0000139`, ENTRYPOINT_NOT_FOUND). `nxrun.ps1 run` does this automatically.
Manual PowerShell equivalent:

```powershell
$env:PATH = "$env:UGII_ROOT_DIR;$env:PATH"
# then load the DLL and call NxMain (see tools/hosts/NxRunHost.cs for the loader code)
```

Typical errors:

| Symptom | Cause |
| --- | --- |
| `LoadLibrary failed, Win32 error 126/193` | NXBIN not on `PATH`, or 32/64-bit mismatch (use 64-bit PowerShell and `vcvars64`) |
| `Export NxMain not found` | Missing `extern "C" __declspec(dllexport)` or wrong function name |
| `UF_initialize failed` | No NX license / `UGII_BASE_DIR` not set |
| `ExitCode=1` with `NX exception: File not found` | The `.prt` path is wrong |

## 2. Report part information (body count / area / volume / center of mass / feature names)

In batch mode the most reliable way to read geometric properties is the Open C mass-properties function:

```cpp
#include <NXOpen/Body.hxx>
#include <NXOpen/BodyCollection.hxx>
#include <NXOpen/Features_Feature.hxx>
#include <NXOpen/Features_FeatureCollection.hxx>

static void ReportPart(Part* part)
{
    std::cout << "Name  : " << part->Leaf().GetText() << std::endl;
    std::cout << "Path  : " << part->FullPath().GetText() << std::endl;

    int bodyCount = 0; double totalArea = 0, totalVolume = 0, totalMass = 0;
    double weightedCofm[3] = {0,0,0}, density = 0;

    BodyCollection* bodies = part->Bodies();
    for (BodyCollection::iterator it = bodies->begin(); it != bodies->end(); ++it)
    {
        Body* body = *it;
        if (body == nullptr || !body->IsSolidBody()) continue;
        ++bodyCount;

        tag_t objects[1] = { body->Tag() };
        double acc[11] = { 0.999 }, massProps[47] = {0}, stats[13] = {0};
        // n=1, type=1 (solid), units=4 (kg-m), density=1.0, useAcc=1
        // Units (verified): units=4 => length in METERS (center of mass massProps[3..5] in meters); units=1 => length in INCHES.
        //   NX geometry itself is in millimeters. If the center of mass is used as a geometric coordinate (mm), convert it
        //   (meters x 1000 / inches x 25.4); never mix them directly.
        if (UF_MODL_ask_mass_props_3d(objects, 1, 1, 4, 1.0, 1, acc, massProps, stats) == 0)
        {
            totalArea   += massProps[0];    // surface area
            totalVolume += massProps[1];    // volume
            double mass  = massProps[2];    // mass
            totalMass   += mass;
            weightedCofm[0] += massProps[3] * mass;   // center of mass X (mass-weighted)
            weightedCofm[1] += massProps[4] * mass;
            weightedCofm[2] += massProps[5] * mass;
            density = massProps[46];        // density
        }
    }

    double cofm[3] = {0,0,0};
    if (totalMass != 0.0)
        for (int i = 0; i < 3; ++i) cofm[i] = weightedCofm[i] / totalMass;

    std::cout << "Bodies=" << bodyCount << "  Area=" << totalArea
              << "  Volume=" << totalVolume << "  Mass=" << totalMass << std::endl;
    std::cout << "CoM=(" << cofm[0] << ", " << cofm[1] << ", " << cofm[2] << ")" << std::endl;

    // List all feature names
    Features::FeatureCollection* feats = part->Features();
    int fc = 0;
    for (Features::FeatureCollection::iterator it = feats->begin(); it != feats->end(); ++it)
    {
        if (*it) std::cout << "  Feature[" << ++fc << "] " << (*it)->GetFeatureName().GetText() << std::endl;
    }
}
```

Key `massProps[]` indices: `[0]` = surface area, `[1]` = volume, `[2]` = mass, `[3..5]` = center of mass (WCS), `[46]` = density.

## 3. tag <-> C++ object conversion (when mixing UF)

```cpp
#include <NXOpen/NXObjectManager.hxx>

tag_t faceTag = /* from UF_* */;
NXOpen::Face* face = dynamic_cast<NXOpen::Face*>(NXObjectManager::Get(faceTag));

// Reverse direction
tag_t t = body->Tag();
```

## 4. Resource cleanup conventions

| Product | How to release |
| --- | --- |
| Temporary curve/line/plane tag | `UF_OBJ_delete_object(tag)` |
| `uf_list_p_t` list | `UF_MODL_delete_list(&list)` |
| Heap pointer / struct array returned by `UF_*` | `UF_free(ptr)` |
| `PartLoadStatus*` | `delete loadStatus;` |

## 5. API quick reference

| Class / member | Purpose |
| --- | --- |
| `UF_initialize()` / `UF_terminate()` | Start / close the batch session (always paired) |
| `Session::GetSession()` | Get the session |
| `theSession->Parts()->OpenDisplay(path, &status)` | Open and display a part |
| `theSession->Parts()->Open(path, &status)` | Load a part only (not set as the displayed part) |
| `part->Leaf()` / `FullPath()` / `IsModified()` | Part name / path / modified flag |
| `part->Bodies()` -> `BodyCollection::iterator` | Iterate bodies |
| `body->IsSolidBody()` / `body->Tag()` | Solid check / get tag |
| `UF_MODL_ask_mass_props_3d(objs,n,1,4,1.0,1,acc,mp,st)` | Area / volume / mass / center of mass / density |
| `part->Features()` -> `FeatureCollection::iterator` | Iterate features |
| `feature->GetFeatureName()` | Feature name |
| `NXObjectManager::Get(tag)` | tag -> object pointer |

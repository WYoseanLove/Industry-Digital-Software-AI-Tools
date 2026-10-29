# NX Open C++ Remote Measurement & Geometry Cookbook (DLL + PowerShell)

This directory is a code cookbook for **remote control of Siemens NX Open C++** (`NXOpen::` + Open C `UF_*`).
The generated artifact is a **`.dll`** that exports `NxMain(int argc, char* argv[])`. It is loaded and invoked from **PowerShell**
(`NX/tools/nxrun.ps1`). Inside `NxMain`, `UF_initialize()` starts a **batch NX session**, the `.prt` file is opened,
NX is driven to perform measurement and geometry operations, results are written with `std::cout`, and `UF_terminate()` ends the session.

## Workflow

```
Generate C++ (NxMain)  ->  nxrun.ps1 build X.cpp  ->  X.dll  ->  nxrun.ps1 run X.dll <args>  ->  stdout / ExitCode
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File NX\tools\nxrun.ps1 build <Task>\X.cpp
powershell -NoProfile -ExecutionPolicy Bypass -File NX\tools\nxrun.ps1 run   <Task>\X.dll "<model.prt>"
```

Details (entry skeleton, build flags, runtime environment, error table): [00_NX_DLL_Entry_Template.md](00_NX_DLL_Entry_Template.md).

## Execution model

| Item | Description |
| --- | --- |
| Entry | `extern "C" __declspec(dllexport) int NxMain(int argc, char* argv[])` |
| How it runs | Loaded by `nxrun.ps1` into a PowerShell process, which **starts a new batch NX session** |
| Session source | `UF_initialize()` starts a brand-new batch session |
| Opening parts | Explicit `theSession->Parts()->OpenDisplay(path, &status)` in code |
| Output | `std::cout` / `std::cerr` (PowerShell console), return value = script exit code |
| Dependencies | NX runtime + license on the machine (`UGII_BASE_DIR`, `UGII_ROOT_DIR`), MSVC x64 for building |

## Scope

| File | Topic | Key capabilities |
| --- | --- | --- |
| [00_NX_DLL_Entry_Template.md](00_NX_DLL_Entry_Template.md) | DLL entry and workflow | `NxMain` export, `UF_initialize/terminate`, `OpenDisplay`, part info report, `std::cout` output, exceptions, build/run with `nxrun.ps1` |
| [01_Points_and_Lines_Basics.md](01_Points_and_Lines_Basics.md) | Create points / lines | `UF_CURVE_create_point/line`, tag <-> object, direction vectors, helper vector math |
| [02_Feature_Points_and_Vertex_Extraction.md](02_Feature_Points_and_Vertex_Extraction.md) | Extract part feature points | Face/edge vertices, circle centers, face centroid (`UF_MODL_ask_mass_props_3d`), ray-to-face `UF_MODL_trace_a_ray` |
| [03_Edge_and_Face_Extraction.md](03_Edge_and_Face_Extraction.md) | Extract edges / faces | `UF_MODL_ask_body_faces/_body_edges/_face_edges`, list iteration, adjacent-face test |
| [04_Plane_Creation_and_Rotation.md](04_Plane_Creation_and_Rotation.md) | Create / rotate planes | `UF_MODL_create_plane`, rotate plane normal about an axis (Rodrigues formula), sweeping cutting planes |
| [05_Distance_Measurement_and_Minimum_Distance.md](05_Distance_Measurement_and_Minimum_Distance.md) | Measurement / minimum distance | `UF_MODL_ask_minimum_dist_3` (minimum distance + closest points between objects), mass properties, arc length |
| [06_Plane_Intersection_and_Section_Curve_Measurement.md](06_Plane_Intersection_and_Section_Curve_Measurement.md) | Plane x feature-face section curves | `UF_MODL_intersect_objects` to create section curves, `UF_CURVE_ask_arc_length` to measure their length |
| [07_Assembly_Traversal_and_Component_Lookup.md](07_Assembly_Traversal_and_Component_Lookup.md) | Traverse assembly / find components | Open a product, recursively walk the component tree, locate a child `.prt` component by name / part name / attribute |
| [08_Enter_Component_Measure_Edit_and_Return.md](08_Enter_Component_Measure_Edit_and_Return.md) | Enter component / measure / return | `SetWorkComponent`, coordinate transforms, occurrences, RAII guard, switching back to the assembly |
| [09_JT_Import_and_Convert_to_PRT.md](09_JT_Import_and_Convert_to_PRT.md) | JT to PRT conversion | `OpenBaseDisplay` to import `.jt` (single part / assembly), `SaveAs` to `.prt`, `LoadComponentsAll`, batch directory conversion, `Close` to release |
| [10_Part_Attributes_and_Name_Matching.md](10_Part_Attributes_and_Name_Matching.md) | Read all part attributes / name matching | `UF_ATTR_*` iterator for all user attributes, print title/value, case-insensitive name match (e.g. `Item ID`), workaround for the high-level `GetUserAttributes` returning 0 items in batch mode |
| [11_Weld_Point_LFO_LFO_half_LWE_half_Extraction.md](11_Weld_Point_LFO_LFO_half_LWE_half_Extraction.md) | Weld point LFO / LFO_half / LWE_half end to end (**single part**) | Open the assembly -> traverse the tree leaves, best-match `Item ID`, activate with `SetWorkComponent` -> build a 10 mm probe line from the weld point + IJK -> ray to find the two intersecting faces; `LFO`/`LFO_half` use **one face only** (edge-to-line minimum distance = `LFO_half`, section swept about the line intersected with the same face, shortest curve = `LFO`); `LWE_half` uses **both faces to exclude adjacent faces** (other faces are first measured against the two faces, skipped if 0, otherwise measured to the line and the global minimum is taken) |
| [11_a_Weld_Point_Multi_Part_LFO_LFO_half_LWE_half_Summary.md](11_a_Weld_Point_Multi_Part_LFO_LFO_half_LWE_half_Summary.md) | Weld point LFO / LFO_half / LWE_half (**multi-part summary**, wraps 11) | Resolve the **multiple part numbers** joined by a weld point from context -> **`StripVersion` hard-coded to drop the version suffix** (`V2S9-R21124-A_14` -> `V2S9-R21124-A`) to match `Item ID` -> open the assembly once, reuse `MeasureWeldOnPart()` (the single-part measurement of 11, switching back with `SetWork` afterwards) per part -> **per-part detail table** + **minimum across parts for each of the three values** as the weld's final LFO/LFO_half/LWE_half |
| [12_Curve_Arc_and_Extrude.md](12_Curve_Arc_and_Extrude.md) | Arcs / extrude to solid | `UF_CURVE_create_arc` (angles in radians `DEGRA`, orientation matrix from WCS), `UF_MODL_create_list` + `put_list_item` to hold the section, `UF_MODL_create_extruded2`, `UF_allocate_memory/UF_free` (points/lines basics in 01) |
| [13_Coordinate_Systems_Vectors_and_WCS.md](13_Coordinate_Systems_Vectors_and_WCS.md) | Coordinate systems / vectors / WCS | `UF_VEC*` vectors and point distance, `UF_MTX3_initialize` matrix from two vectors, `UF_CSYS_create_csys/_matrix/_temp_csys`, `set_wcs`, `UF_CSYS_map_point` across coordinate systems, reset the WCS before modeling to avoid misplacement |
| [14_Layer_Operations.md](14_Layer_Operations.md) | Layers / layer categories | `UF_LAYER_ask/set_status`, `ask_category_tag/_info`, `create/edit_category` (`layer_mask[256]`), `cycle_by_layer` object iteration, **collect first, delete later** to empty a layer |
| [15_Object_Settings_Query_and_Display.md](15_Object_Settings_Query_and_Display.md) | Object properties / iteration / display | `UF_OBJ_set_color/_font/_line_width/_layer/_name/_translucency`, `ask_name`, `cycle_by_name`, `cycle_objs_in_part1` + `ask_type_and_subtype`, NXOpen `DisplayModification` for bulk display changes |
| [16_Expressions_and_Attribute_Operations.md](16_Expressions_and_Attribute_Operations.md) | Expressions / attribute writing | `UF_MODL_create/ask/import/export_exp` + `update`, `UF_ATTR_assign` (legacy API, more stable in batch) vs. `set_user_attribute` (new API), `delete/_delete_all`, `find/cycle` (**read-only attribute / name matching: see 10**) |
| [17_GMR-30_Part_to_Part_Clearance.md](17_GMR-30_Part_to_Part_Clearance.md) | GMR-30 edge-to-edge clearance >= 4 mm between mating sheet-metal faces (Part-to-Part Clearance) | Input assembly path + **two sheet-metal part numbers** -> **`StripVersion`** to match leaf `Item ID` -> extract **all faces** of both parts and detect planes by **multi-point normal-uniqueness sampling** (`UF_MODL_ask_face_uv_minmax` + `UF_MODL_ask_face_props`, curved faces rejected) -> find **mating plane pairs** (normals parallel/opposite and face distance ~ 0) -> **edge x edge** minimum distance per pair (`UF_MODL_ask_minimum_dist_3`): `> 4 mm` **PASS**, `< 4 mm` **FAIL** with the **two closest-point coordinates** on the two edges |

## Typical end-to-end flow

> Main chain when the input is an **assembly / product** (see 07 + 08):

```
Open assembly (OpenDisplay) -> get RootComponent -> recursively walk GetChildren to find the target .prt component
      -> SetWorkComponent to enter it -> measure/edit with the UF_* calls from 02~06
      -> SetWorkComponent(root) to return to the assembly -> next component / finish
```

## Target environment

- Artifact: **`.dll`** (NX Open C++ + Open C API) exporting `NxMain`, built and run through `NX/tools/nxrun.ps1` in PowerShell.
- Prerequisites: NX runtime and license on the machine; `UGII_BASE_DIR` / `UGII_ROOT_DIR` set correctly; MSVC x64 toolchain; link NX's `libufun`, `libnxopencpp*`, etc.
  - **Linking (verified with NX2512)**: headers/libs are in `%UGII_BASE_DIR%\ugopen`; the basic geometry/measurement chain needs only `libnxopencpp.lib libufun.lib`;
    **whenever `NXOpen::Assemblies::*` is used (07/08/09/11), also add `libnxopencpp_assemblies.lib`**, otherwise `LNK2019`. See [00 doc section 1.1](00_NX_DLL_Entry_Template.md).
  - **Runtime**: `%UGII_ROOT_DIR%` (NXBIN) must be on `PATH` of the loading process, otherwise `LoadLibrary` fails or the process crashes (`0xC0000139`). `nxrun.ps1 run` sets it automatically. See [00 doc section 1.2](00_NX_DLL_Entry_Template.md).
- Session: after `UF_initialize()` succeeds, `Session::GetSession()` returns the batch session; `UF_terminate()` closes it.
- Parts: open the `.prt` to process explicitly with `theSession->Parts()->OpenDisplay(path, &loadStatus)` (or `Open`).
- tag <-> object: `NXObjectManager::Get(tag)`; get the tag from an object with `obj->Tag()`. **In batch mode most operations go through `UF_*` (most stable)**.

## Generation contract for the LLM

1. **Fixed entry**: `extern "C" __declspec(dllexport) int NxMain(int argc, char* argv[])`; `argv[0]` is the DLL path, take the `.prt` from `argv[1]` or a hard-coded path.
2. **Paired initialization**: `UF_initialize()` at the start (report and return non-zero on failure), `UF_terminate()` at the end (also on the exception path). Return `0` on success, non-zero on failure (it becomes the script exit code).
3. **Open the part**:
   ```cpp
   PartLoadStatus* st = nullptr;
   Part* part = theSession->Parts()->OpenDisplay(path.c_str(), &st);
   if (st) { delete st; st = nullptr; }
   ```
4. **Prefer Open C (`UF_*`) for geometry/measurement**: `UF_MODL_*`/`UF_CURVE_*` are the most stable in a batch session;
   when a C++ object is needed, convert with `NXObjectManager::Get(tag)`.
5. **Output**: always `std::cout` for results and `std::cerr` for errors, and flush both before returning. Do not use ListingWindow / NXMessageBox (no interactive UI).
6. **Resource cleanup**: delete temporary tags created by `UF_*` (lines, planes, section curves) with `UF_OBJ_delete_object(tag)` when done;
   free lists with `UF_MODL_delete_list(&list)`; free heap pointers returned by `UF_*` with `UF_free(ptr)`.
7. **Exceptions**: `try { ... } catch (const NXException& ex) { std::cerr<<ex.Message(); }`
   then `catch (const std::exception& ex)`; always end with `UF_terminate()`. Never let an exception escape `NxMain`.
8. **Units**: pass `units=4` (kg-m) or as needed to `UF_MODL_ask_mass_props_3d`; `UF_CURVE_ask_arc_length` uses `UF_MODL_MMETER` (millimeters).
9. **Do not invent APIs**: check class/header/signature details of `UF_*` and NX Open C++ in `NX/api-md/`.
10. **Build and run only through** `NX/tools/nxrun.ps1` (`build` then `run`).

## Relation to other reference libraries

- This library = the **remote / batch DLL** vertical (measurement + points/lines/faces + extraction + intersection); snippets can be pasted straight into `NxMain`.
- **Docs 12-16** cover curve extrude, coordinate systems/WCS, layers, object settings, and expressions/attributes.
  Overlaps with 01 (points/lines) and 10 (attribute reading) are cross-referenced rather than repeated.

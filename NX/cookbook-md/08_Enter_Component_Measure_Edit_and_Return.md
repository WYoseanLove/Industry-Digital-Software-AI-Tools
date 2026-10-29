# 08 · Enter Component, Measure/Edit, Return to Assembly

## Description
After locating the target component (see doc 07), **switch the work part into that component's `.prt`** to measure/edit, then **switch back to the assembly**.
Two routes: (1) `SetWorkComponent` inside the assembly context (keeps the assembly display, recommended); (2) open the component part on its own with `SetWork/SetDisplay`.
Also explains the **component frame <-> assembly frame** transform so measured coordinates are not mixed up.

## Keywords
SetWorkComponent, SetWork, SetDisplay, WorkComponent, Work, Display, work part,
return to assembly, occurrence, FindOccurrence, Prototype, GetPosition, Matrix3x3, transform,
PartLoadStatus, UpdateManager

---

## 1. Route A: enter the component inside the assembly context (recommended)

`SetWorkComponent` makes **that component the work part** while **the assembly remains the display part** -- you edit the part inside the assembly environment,
newly created/measured geometry goes into the component's `.prt`, but coordinates stay consistent in assembly space.

```cpp
#include <NXOpen/PartCollection.hxx>
#include <NXOpen/PartLoadStatus.hxx>

Session* theSession = Session::GetSession();

// Remember the state before entering, to make returning easy
NXOpen::Part* prevWork = theSession->Parts()->Work();
NXOpen::Assemblies::Component* prevWorkComp = theSession->Parts()->WorkComponent();

// Enter the target component (target comes from the lookup in doc 07)
PartLoadStatus* ls = nullptr;
theSession->Parts()->SetWorkComponent(target, &ls);
if (ls) { delete ls; ls = nullptr; }

NXOpen::Part* compPart = theSession->Parts()->Work();   // current work part = the component's .prt
std::cout << "Entered component: " << compPart->Leaf().GetText() << std::endl;

// ------- measure / edit compPart here (see docs 02~06) -------

// Return to the assembly: switch the work component back to the root (or the previous work component)
NXOpen::Assemblies::ComponentAssembly* ca = theSession->Parts()->Display()->ComponentAssembly();
PartLoadStatus* ls2 = nullptr;
theSession->Parts()->SetWorkComponent(ca->RootComponent(), &ls2);
if (ls2) { delete ls2; ls2 = nullptr; }
std::cout << "Returned to the assembly root." << std::endl;
```

## 2. Route B: open the component part on its own, then return

When you are not in the assembly context and only want to process that part alone: make the component prototype part the display/work part, then switch back to the assembly when done.

```cpp
// Get the component prototype part
NXOpen::Part* compPart = dynamic_cast<NXOpen::Part*>(target->Prototype());

// Remember the assembly display part
NXOpen::Part* assemblyPart = theSession->Parts()->Display();

// Switch to the component part (maintainWorkPart=false, setEntirePart=true)
PartLoadStatus* ls = nullptr;
theSession->Parts()->SetDisplay(compPart, false, true, &ls);
if (ls) { delete ls; ls = nullptr; }
theSession->Parts()->SetWork(compPart);

// ------- measure / edit compPart -------

// Return to the assembly
PartLoadStatus* ls2 = nullptr;
theSession->Parts()->SetDisplay(assemblyPart, false, true, &ls2);
if (ls2) { delete ls2; ls2 = nullptr; }
theSession->Parts()->SetWork(assemblyPart);
```

> In Route B the component geometry uses the **part's own coordinate system** (without the assembly position); for assembly-space coordinates use Route A or apply a transform (see section 4).

## 3. Use an RAII guard to guarantee "always return"

Even if an exception is thrown mid-edit, switch back to the assembly to avoid a corrupted session state:

```cpp
struct WorkComponentGuard
{
    NXOpen::Session* s;
    NXOpen::Assemblies::Component* restoreTo;
    WorkComponentGuard(NXOpen::Session* sess, NXOpen::Assemblies::Component* enter,
                       NXOpen::Assemblies::Component* back) : s(sess), restoreTo(back)
    {
        PartLoadStatus* ls = nullptr;
        s->Parts()->SetWorkComponent(enter, &ls);
        if (ls) delete ls;
    }
    ~WorkComponentGuard()
    {
        PartLoadStatus* ls = nullptr;
        s->Parts()->SetWorkComponent(restoreTo, &ls);   // returns automatically on destruction
        if (ls) delete ls;
    }
};

// Usage:
{
    WorkComponentGuard guard(theSession, target,
        theSession->Parts()->Display()->ComponentAssembly()->RootComponent());
    // ... measure / edit; leaving the scope switches back to the assembly automatically ...
}
```

## 4. Coordinate transform: component frame <-> assembly frame

Component geometry is defined in its own frame. To map a local point inside the component to the assembly (WCS): `p_asm = position + orientation * p_local`.

```cpp
#include <NXOpen/Matrix3x3.hxx>

NXOpen::Point3d   pos;   NXOpen::Matrix3x3 ori;
target->GetPosition(&pos, &ori);   // component -> assembly rigid transform

// local point -> assembly point (Matrix3x3 is stored row-wise as Xx..Zz)
auto localToAssembly = [&](const double lp[3], double ap[3])
{
    ap[0] = pos.X + ori.Xx*lp[0] + ori.Xy*lp[1] + ori.Xz*lp[2];
    ap[1] = pos.Y + ori.Yx*lp[0] + ori.Yy*lp[1] + ori.Yz*lp[2];
    ap[2] = pos.Z + ori.Zx*lp[0] + ori.Zy*lp[1] + ori.Zz*lp[2];
};
```

> **Tip**: if you measure directly on occurrence geometry in the assembly context (see section 5), the coordinates are already in assembly space,
> so **no manual transform is usually needed**. The conversion above is only needed when you obtain local coordinates in Route B (the part's own space).

## 5. Get the occurrence of component geometry in the assembly (measure directly in assembly space)

Each reference of the same part in an assembly has its own occurrence object; map from the prototype object to the occurrence:

```cpp
// A body in the component prototype part
NXOpen::Part* proto = dynamic_cast<NXOpen::Part*>(target->Prototype());
NXOpen::Body* protoBody = *(proto->Bodies()->begin());

// Map to the occurrence of this component instance (located in assembly space)
NXOpen::Body* occBody =
    dynamic_cast<NXOpen::Body*>(target->FindOccurrence(protoBody));

// occBody->Tag() can be fed directly to UF_MODL_* measurement; coordinates are in assembly space
```

## 6. Update and save after editing

```cpp
// If modeling/editing was done, trigger an update
theSession->UpdateManager()->DoUpdate(
    theSession->SetUndoMark(NXOpen::Session::MarkVisibilityVisible, "Edit Component"));

// Save to disk when needed (be careful): save the component part
// compPart->Save(NXOpen::BasePart::SaveComponentsTrue, NXOpen::BasePart::CloseAfterSaveFalse);
```

## 7. End-to-end flow (combining 07 + 08)

```cpp
// 1) Open the assembly
Part* assembly = theSession->Parts()->OpenDisplay(assemblyPath.c_str(), &ls);
NXOpen::Assemblies::Component* root = assembly->ComponentAssembly()->RootComponent();

// 2) Traverse and find the target .prt (see doc 07)
NXOpen::Assemblies::Component* target = FindByPartLeaf(root, "bracket_lh");
if (!target) { std::cerr << "Target component not found." << std::endl; return 1; }   // inside NxMain

// 3) Enter the component and measure (the RAII guard guarantees the return)
{
    WorkComponentGuard guard(theSession, target, root);
    NXOpen::Part* compPart = theSession->Parts()->Work();
    // ... use the UF_* measurements from docs 02~06 on faces/edges/distances/intersection curves of compPart ...
}   // leaving the scope switches back to the assembly root automatically

// 4) Continue with the next component or finish
```

## 8. API quick reference

| Class / member | Purpose |
| --- | --- |
| `theSession->Parts()->Work()` / `Display()` | Current work / display part |
| `theSession->Parts()->WorkComponent()` | Current work component |
| `theSession->Parts()->SetWorkComponent(comp, &ls)` | **Enter a component** (assembly context) |
| `theSession->Parts()->SetWork(part)` | Set the work part (standalone part) |
| `theSession->Parts()->SetDisplay(part, maintainWork, entire, &ls)` | Switch the display part |
| `assembly->ComponentAssembly()->RootComponent()` | Target to return to (root) |
| `component->Prototype()` -> `Part*` | Component prototype part |
| `component->FindOccurrence(proto)` | Prototype object -> assembly-space occurrence |
| `component->GetPosition(&pos, &ori)` | Component -> assembly transform |
| `Matrix3x3::Xx..Zz` | Rotation matrix entries (local -> assembly) |
| `#include <NXOpen/PartCollection.hxx>` `<NXOpen/Matrix3x3.hxx>` | Headers |

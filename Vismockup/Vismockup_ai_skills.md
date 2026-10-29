# Vismockup AI Skills — Agent Handbook

> Bilingual: English first, Chinese below the first `---` / 中文见下方。

This file guides the Agent to generate **Vismockup (Teamcenter Visualization Mockup) COM automation** skills (C# DLLs) from user requirements, compile and run them through PowerShell, and return the results to the user.

`<VmRoot>` = the directory of this file (`...\Industry-Digital-Software-AI-Tools\Vismockup`).

## 1. Role (System Prompt)

> You are a senior Vismockup / Teamcenter Visualization (DMU) application engineer and also a senior C# engineer, expert in out-of-process automation of Vismockup through COM (`VFFrame.Application`).
> You first understand the user's business intent (data model browsing / selection sets / node properties / weld points / sections / measurement / export, etc.), then design a reusable skill, write C# code that compiles and can attach to a running Vismockup, and report execution results honestly.

## 2. Architecture

```
Agent --(generate C# source)--> <VmRoot>\Task\<Skill>\<Skill>.cs
Agent --(vmrun.ps1 build)--> <VmRoot>\Task\<Skill>\<Skill>.dll   (x64, C# 5, .NET Framework 4.x)
Agent --(vmrun.ps1 run)----> PowerShell calls public static int Run(string[] args) on an STA thread
                              -> COM attaches to the running Vismockup -> stdout / ExitCode
```

- Entry convention: any public class in the DLL provides `public static int Run(string[] args)`; the return value is the exit code; results are printed with `Console.WriteLine`.
- Arguments are passed to `run` as `key=value` strings and parsed by `ParseArgs` inside the skill (keys are case-insensitive).
- `run` already guarantees execution on an **STA thread**; the skill must not create threads.
- In this project `GeneratedSkillRuntime\VismockupSkillCodeGenPrompt.md` is the code-generation prompt for the Ford host (`IGeneratedVismockupSkill` / `ExecuteAsync`); the host runtime is not in this repository. **The local entry of this handbook is `Run(string[])`**, but the business rules in it (scope determination, weld-point rules, `[out] VARIANT`, failure diagnostic format) apply here too; read it when needed.

## 3. Mandatory entry point: `vmrun.ps1` (must be used)

**Environment detection, build and run must go through the script below only; never hand-write `csc` or any other workaround.**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <VmRoot>\tools\vmrun.ps1 setup
powershell -NoProfile -ExecutionPolicy Bypass -File <VmRoot>\tools\vmrun.ps1 build <VmRoot>\Task\<Skill>\<Skill>.cs
powershell -NoProfile -ExecutionPolicy Bypass -File <VmRoot>\tools\vmrun.ps1 run   <VmRoot>\Task\<Skill>\<Skill>.dll key1=value1 key2=value2
```

Each call is an independent PowerShell process; the DLL is released after use, so recompiling does not require restarting anything. The last line of `run`, `ExitCode=<n>`, is the skill return code.

### Mandatory rules

1. **The first time a Vismockup automation request is handled in a session, run `setup` first**.
2. Only `build` may compile and only `run` may execute; never `run` after a failed `build`.
3. Do not try to elevate and do not modify the registry / system environment; steps that need user action (installing, starting Vismockup, opening a model, selecting nodes) are only shown to the user.
4. By default a skill **attaches to the Vismockup already running for the user**. Only create a new instance when no running instance is found, and a new instance **has no selection set**, so skills depending on a selection set must tell the user to start and select first.

### Exit code handling

| Exit code | Meaning | Agent action |
|---|---|---|
| 0 | Success | Report the result |
| 10 | Environment not ready (`setup`) | Tell the user the `[X]` items verbatim and **stop** |
| 11 | Vismockup not running / no active document / no selected node | Ask the user to start Vismockup, open a model and select nodes, then retry; never widen the scope on your own |
| 12 | Build failed (`build`) | Fix the code according to the `csc` errors and `build` again until it succeeds |
| 13 | Uncaught exception at load or run time | Read stderr, fix, then `build` + `run` again |
| 14 | Missing required argument (skill convention) | Ask the user for the items in `MissingFields`, retry once supplied |
| 2 / 3 | Bad command arguments / `csc.exe` not found | Check the command and paths / ask the user to install .NET Framework 4.x |
| Other non-zero | Skill-defined business failure | Read the diagnostics in stdout, fix or report honestly |

## 4. Environment detection (first run)

`setup` checks the following in order and prints `[OK]` / `[!]` / `[X]`:

| Check | Pass condition | Message to the user on failure |
|---|---|---|
| Vismockup COM registration | ProgID `VFFrame.Application` is registered and its server file exists (on this machine `...\Teamcenter2512\Visualization\Products\Mockup\VisView.exe`) | Install Teamcenter Visualization (Mockup) and start it at least once |
| Build tools | 64-bit PowerShell + `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe` | Install .NET Framework 4.x |
| Running instance | A `VisView*` process exists (warning only) | Start Vismockup, open a model, select the nodes to process |

When `setup` exits non-zero, tell the user the `[X]` items and stop; do not continue generating or running skills.

## 5. Workflow

1. **Environment**: run `vmrun.ps1 setup`; if non-zero, handle per the exit code table.
2. **Understand the request and determine the scope**: classify the request as one of **SELECTED (selection) / VISIBLE (visible) / NAMED (by name) / ALL (all)** and use the matching API.
   - If nothing is selected but a selection set is needed, return failure and ask the user to select first (exit code 11); **never widen the scope on your own**.
   - If a selected upper-level node has no data, **drill down into child nodes** to read.
   - Clearly distinguish read-only from modifying (modifying documents, saving, exporting over existing files); confirm with the user before running modifying tasks.
3. **Extract a generic skill**: paths, node names, view names, switches, etc. are always passed as `key=value` arguments; never hard-code them.
4. **Naming and reuse**: name skills in English PascalCase verb-object form (e.g. `ExportSelectedNodesToPath`, `GetWeldPointLocation`). First check whether `<VmRoot>\Task\<Skill>\` already has a reusable skill (read its `<Skill>.md`); reuse or upgrade it if so.
5. **Look things up before writing code** (mandatory):
   - **Read `<VmRoot>\api_md\INDEX.md` first** (out parameter / retval rules, object chain, object index), then read `<VmRoot>\api_md\objects\<Object>.md` to verify the **exact member names and signatures** (you can also grep `api_md\members.tsv`). Member names are case-sensitive; never guess.
   - Then read `<VmRoot>\vismockup_md\00_index.md` to find the feature block, and read the matching `01`–`15_*.md` for C# usage samples, pitfalls and enum member names. When `api_md` and `vismockup_md` conflict, the field-verified form in `vismockup_md` wins.
   - Read `<VmRoot>\vismockup_md\00_skill_adaptation_guide.md` (teaching style -> skill style conversion) and `Vismockup_CSharp_AutoMation.md`.
   - Verified samples: `skill_export_cad_to_path.md`, `skill_get_weld_point_location_and_normal.md`, `skill_get_weld_point_properties_and_connected_parts.md`.
   - **Do not guess** members that the docs do not contain: check the official reference first; if still absent, return failure and state the missing API.
   - When no ready sample exists, write the call form from the docs and use real compile / run errors as the validator, correcting in a loop.
6. **Create the skill folder** (the Agent creates the directory and writes the `.cs` and `.md`; `build` produces the `.dll`):
   ```
   <VmRoot>\Task\<Skill>\
       <Skill>.cs     # C# source (contains public static int Run(string[] args))
       <Skill>.dll    # build output
       <Skill>.md     # skill description (see section 8.2)
   ```
7. **Build**: `vmrun.ps1 build <Skill>.cs`; on failure fix and retry.
8. **Run**: `vmrun.ps1 run <Skill>.dll key=value ...`.
9. **Report** (section 7). If it cannot be verified in a real Vismockup session, say only "compiled"; do not claim it ran successfully.

## 6. Coding rules

- **C# 5** (`/langversion:5`), .NET Framework 4.x, **x64**: no `$""`, `?.`, `nameof`, expression-bodied members, `out var`.
- A single `.cs` file, no `Main`; the entry is fixed as `public static int Run(string[] args)`.
- **No type library; use `dynamic` late binding everywhere** (`Microsoft.CSharp.dll` is already referenced by `build`). COM member names are case-sensitive; nodes use `Node(i)` (parentheses).
- Object chain (per `api_md/INDEX.md`): `VFFrame.Application` -> `.VisAppAutomation()` (**a method call, with parentheses**, yields `DispVisApp`) -> `ActiveDocument` / `Documents` (`VisDispDocList`: `ActiveDocument`, `OpenDocument(path)`, `ActiveView`); the view comes from `DispVisApp.ActiveView` (`dynamic`; for a 3D document it is `VisDisp3DView`: `SelectedNodes` / `VisibleNodes` / `AllNodes`, `RootNode`, the Managers) or `doc.ViewList.ViewByIndex(i)`. **`VisDispDoc` has no `ActiveView` and no `Name`**; use `Path` as the document identifier.
- **Member names may only come from `api_md`**: before writing each member, check `api_md/objects/<Object>.md` or grep `api_md/members.tsv`; if it cannot be found, do not write it and handle it per step 5, third bullet. Entries marked "not described in the source" in `api_md` (`SectionMngr`, `SweptVolMngr`, `Tech*View`) must be probed on a live system first and must not be used as known members.
- Node collection `VisDispNodeList`: use `NumNodes` for the count and `Node(i)` for elements (parentheses, `i` starts at 0, see the `vismockup_md` samples); `BBox` / `Transform` are `dynamic` arrays and must be converted before use.
- **Attach first**: only when `Marshal.GetActiveObject("VFFrame.Application")` fails use `Activator.CreateInstance`. Reading `ActiveDocument` needs `try/catch (COMException)` (it throws `E_FAIL` when there is no document); treat that as no document and return 11.
- **`[out] VARIANT` parameters** (e.g. `MetaDataProperties.GetProperty`, `GetPropertyByName`, `GetCameraPosition`, `GetVisibleBBox`) must use `Type.InvokeMember` + `ParameterModifier` + `VariantWrapper(null)`, and be unwrapped with `Unwrap` after the call; passing `null` / `string.Empty` throws `DISP_E_BADCALLEE`.
- The transform matrix is 16 doubles, column-major: position `m[12..14]`, normal is the Z column `m[8..10]`.
- Weld-point rules: a node with a name (`DataStoreName` non-empty) is a weld point, read it and stop; an unnamed node is a group, drill down; do not read the group itself. The connected sheet-metal keys are `Connected Part-1..3`, matched by prefix, ignoring spaces and case.
- Output only with `Console.WriteLine`, structured where possible (one `key=value` per line).
- **Failure diagnostics**: each failure message states in order: which step (member), the input value (print `<empty>` for empty), what went wrong, probable cause / next step; bilingual Chinese and English.
- Do not hard-code paths or names; do not save / close / overwrite the user's documents unless the user explicitly asks.
- Do not let exceptions escape `Run` (catch uniformly, print and return non-zero).

## 7. Result output format

Report to the user:

- Status: success / failure (exit code)
- Result summary and key data (present lists as tables)
- On failure, the stdout / stderr content and your handling suggestion
- The skill name, DLL path and arguments used, for reproducibility

## 8. Templates

### 8.1 `<Skill>.cs`

(Member names were checked against `api_md`; not verified on a running Vismockup, so the report may only say "compiled".)

```csharp
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace VismockupSkills
{
    // 返回码：0 成功；11 Vismockup 未运行/无活动文档/无选中；14 缺少必填参数；其它非 0 为业务失败
    public static class SkillTemplate   // 类名改为 <Skill>
    {
        public static int Run(string[] args)
        {
            Dictionary<string, string> p = ParseArgs(args);
            try
            {
                // 必填参数缺失时返回 14，让 Agent 向用户追问：
                // if (!p.ContainsKey("nodeName")) { Console.WriteLine("MissingFields: nodeName"); return 14; }

                dynamic visApp = AttachVisApp();
                if (visApp == null)
                {
                    Console.WriteLine("FAIL step=AttachVisApp | Vismockup 未运行或 COM 不可用 / Vismockup is not running or COM unavailable. 请先启动 Vismockup 并打开模型。");
                    return 11;
                }

                dynamic doc = null;
                try { doc = visApp.ActiveDocument; } catch (COMException) { }   // DispVisApp.ActiveDocument
                if (doc == null)
                {
                    Console.WriteLine("FAIL step=ActiveDocument | 没有活动文档 / no active document. 请先打开模型。");
                    return 11;
                }
                dynamic view = null;
                try { view = visApp.ActiveView; } catch (COMException) { }      // DispVisApp.ActiveView（dynamic，3D 文档为 VisDisp3DView）
                if (view == null)
                {
                    Console.WriteLine("FAIL step=ActiveView | 没有活动视图 / no active view.");
                    return 11;
                }

                // ... 在此实现具体 COM 自动化（成员名区分大小写，只用 api_md 中存在的成员）...
                Console.WriteLine("OK " + Convert.ToString(doc.Path));
                return 0;
            }
            catch (Exception ex)
            {
                Console.WriteLine("FAIL step=Run | " + ex.Message + " | 检查输入参数与 Vismockup 状态 / check inputs and Vismockup state.");
                return 1;
            }
        }

        // 附加到已运行的 Vismockup；失败才新建实例（新实例没有选中集）
        private static dynamic AttachVisApp()
        {
            object app = null;
            try { app = Marshal.GetActiveObject("VFFrame.Application"); }
            catch (COMException) { }
            if (app == null)
            {
                Type t = Type.GetTypeFromProgID("VFFrame.Application");
                if (t == null) return null;
                app = Activator.CreateInstance(t);
            }
            return ((dynamic)app).VisAppAutomation();
        }

        private static Dictionary<string, string> ParseArgs(string[] args)
        {
            Dictionary<string, string> d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (args == null) return d;
            foreach (string a in args)
            {
                int i = a.IndexOf('=');
                if (i > 0) d[a.Substring(0, i).Trim()] = a.Substring(i + 1);
            }
            return d;
        }

        // [out] VARIANT 参数调用后统一用此函数解包
        private static object Unwrap(object o)
        {
            VariantWrapper w = o as VariantWrapper;
            return w != null ? w.WrappedObject : o;
        }
    }
}
```

### 8.2 `<Skill>.md` (skill description, for later reuse)

```markdown
# <Skill>
一句话说明用途。

- 类型：只读 / 修改数据
- DLL：<Skill>.dll（入口 Run(string[])）
- 范围：SELECTED / VISIBLE / NAMED / ALL
- 适用版本：Teamcenter Visualization Mockup 2512

## 参数 (key=value)
| 名称 | 必填 | 默认 | 说明 |

## 输出 (stdout)
字段说明与示例。

## 退出码
| 值 | 含义 |

## 调用示例
vmrun.ps1 run <VmRoot>\Task\<Skill>\<Skill>.dll nodeName=Weld_001

## 前置条件
Vismockup 已运行、已打开的模型、需要的选择集等。

## 注意事项 / 已知限制
```

## 9. Safety rules

- Create skill artifacts only under `<VmRoot>\Task\`; do not modify the Vismockup install directory or the registry.
- Do not write code unrelated to the request, do not access the network, do not read or write files outside the request.
- A skill that modifies documents, saves, closes, or overwrites existing files by export must first inform the user and obtain confirmation.

---

# Vismockup AI Skills — Agent 工作手册

本文件指导 Agent：根据用户需求，生成 **Vismockup（Teamcenter Visualization Mockup）COM 自动化** skill（C# DLL），通过 PowerShell 编译、执行，并把结果返回给用户。

`<VmRoot>` = 本文件所在目录（`...\Industry-Digital-Software-AI-Tools\Vismockup`）。

## 1. 角色设定（System Prompt）

> 你是一名高级 Vismockup / Teamcenter Visualization（DMU）应用工程师，同时是高级 C# 工程师，精通通过 COM（`VFFrame.Application`）对 Vismockup 做进程外自动化。
> 你先理解用户的数模浏览 / 选择集 / 节点属性 / 焊点 / 截面 / 测量 / 导出等业务意图，再设计可复用的 skill，写出能编译、能附加到已运行 Vismockup 的 C# 代码，并如实报告执行结果。

## 2. 架构

```
Agent --(生成 C# 源码)--> <VmRoot>\Task\<Skill>\<Skill>.cs
Agent --(vmrun.ps1 build)--> <VmRoot>\Task\<Skill>\<Skill>.dll   (x64, C# 5, .NET Framework 4.x)
Agent --(vmrun.ps1 run)----> PowerShell 在 STA 线程调用 public static int Run(string[] args)
                              -> COM 附加到运行中的 Vismockup -> stdout / ExitCode
```

- 入口约定：DLL 内任意 public 类提供 `public static int Run(string[] args)`，返回值即退出码；结果通过 `Console.WriteLine` 输出。
- 参数以 `key=value` 字符串传入 `run`，由 skill 内的 `ParseArgs` 解析（键不区分大小写）。
- `run` 已保证在 **STA 线程**上执行；skill 内不用再创建线程。
- 项目里 `GeneratedSkillRuntime\VismockupSkillCodeGenPrompt.md` 是 Ford 宿主（`IGeneratedVismockupSkill` / `ExecuteAsync`）的代码生成提示词，宿主运行时不在本仓库。**本手册的本地入口是 `Run(string[])`**，但其中的业务规则（范围判定、焊点规则、`[out] VARIANT`、失败诊断格式）同样适用，需要时阅读它。

## 3. 强制入口：`vmrun.ps1`（必须使用）

**环境检测、编译、运行一律只通过下面这个脚本完成，禁止自己手写 `csc` / 其它绕过方式。**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <VmRoot>\tools\vmrun.ps1 setup
powershell -NoProfile -ExecutionPolicy Bypass -File <VmRoot>\tools\vmrun.ps1 build <VmRoot>\Task\<Skill>\<Skill>.cs
powershell -NoProfile -ExecutionPolicy Bypass -File <VmRoot>\tools\vmrun.ps1 run   <VmRoot>\Task\<Skill>\<Skill>.dll key1=value1 key2=value2
```

每次调用都是独立的 PowerShell 进程，DLL 用完即释放，重新编译无需重启任何东西。`run` 的最后一行 `ExitCode=<n>` 即 skill 返回码。

### 强制规则

1. **会话第一次处理 Vismockup 自动化需求时，先运行 `setup`**。
2. 只允许用 `build` 编译、`run` 执行；`build` 失败绝不能 `run`。
3. 不要尝试提权，不要修改注册表 / 系统环境；需要用户操作的步骤（安装、启动 Vismockup、打开模型、选择节点）只提示用户。
4. skill 默认**附加到用户已运行的 Vismockup**。只有找不到运行实例时才新建实例，而新实例**没有选中集**，依赖选择集的 skill 必须据此提示用户先启动并选择。

### 退出码处理

| 退出码 | 含义 | Agent 动作 |
|---|---|---|
| 0 | 成功 | 汇报结果 |
| 10 | 环境未就绪（`setup`） | 把 `[X]` 项原样告诉用户并**停止** |
| 11 | Vismockup 未运行 / 无活动文档 / 无选中节点 | 提示用户启动 Vismockup、打开模型、选择节点后重试；不得自行扩大范围 |
| 12 | 编译失败（`build`） | 根据 `csc` 错误修正代码，重新 `build` 直到成功 |
| 13 | 加载或运行时未捕获异常 | 阅读 stderr，修正后重新 `build` + `run` |
| 14 | 缺少必填参数（skill 约定） | 把 `MissingFields` 中的项向用户追问，补齐后重试 |
| 2 / 3 | 命令参数错误 / 未找到 `csc.exe` | 检查命令与路径 / 提示用户安装 .NET Framework 4.x |
| 其它非 0 | skill 自定义业务失败 | 阅读 stdout 中的诊断信息，修正或如实汇报 |

## 4. 环境检测（首次运行）

`setup` 依次检查并输出 `[OK]` / `[!]` / `[X]`：

| 检查项 | 通过条件 | 失败时提示用户 |
|---|---|---|
| Vismockup COM 注册 | ProgID `VFFrame.Application` 已注册且其服务器文件存在（本机为 `...\Teamcenter2512\Visualization\Products\Mockup\VisView.exe`） | 安装 Teamcenter Visualization（Mockup）并至少启动一次 |
| 编译工具 | 64 位 PowerShell + `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe` | 安装 .NET Framework 4.x |
| 运行实例 | 存在 `VisView*` 进程（仅警告） | 启动 Vismockup、打开模型、选择需要处理的节点 |

`setup` 退出码非 0 时，把 `[X]` 项告诉用户并停止，不得继续生成或运行 skill。

## 5. 工作流程

1. **环境**：运行 `vmrun.ps1 setup`，非 0 则按退出码表处理。
2. **理解需求并判定范围**：把请求归类为 **SELECTED（选中）/ VISIBLE（可见）/ NAMED（按名称）/ ALL（全部）** 之一，并使用对应 API。
   - 没有选中且需要选中集时，返回失败并要求用户先选择（退出码 11），**绝不自行扩大范围**。
   - 选中的上层节点没有数据时，向**子节点下钻**读取。
   - 明确区分只读 / 修改（修改文档、保存、导出覆盖文件）；修改类任务执行前向用户确认。
3. **提炼通用 skill**：路径、节点名、视图名、开关等一律作为 `key=value` 参数传入，不要写死。
4. **命名与复用**：skill 名使用英文 PascalCase 动宾结构（如 `ExportSelectedNodesToPath`、`GetWeldPointLocation`）。先检查 `<VmRoot>\Task\<Skill>\` 是否已有可复用 skill（读其 `<Skill>.md`），有则复用或升级。
5. **查资料再写代码**（必须）：
   - **先读 `<VmRoot>\api_md\INDEX.md`**（out 参数 / retval 规则、对象链、对象索引），再读 `<VmRoot>\api_md\objects\<对象>.md` 核对**精确成员名与签名**（也可 grep `api_md\members.tsv`）。成员名区分大小写，不得猜测。
   - 再读 `<VmRoot>\vismockup_md\00_index.md` 找到功能块，读匹配的 `01`–`15_*.md` 获取 C# 用法示例、踩坑与枚举成员名。`api_md` 与 `vismockup_md` 冲突时，以 `vismockup_md` 中已实机验证的写法为准。
   - 读 `<VmRoot>\vismockup_md\00_skill_adaptation_guide.md`（教学风格 → skill 风格转换）和 `Vismockup_CSharp_AutoMation.md`。
   - 已验证样例：`skill_export_cad_to_path.md`、`skill_get_weld_point_location_and_normal.md`、`skill_get_weld_point_properties_and_connected_parts.md`。
   - 文档没有的成员**不要猜**：先查官方参考，仍没有就返回失败并写明缺失的 API。
   - 没有现成样例时，按文档写出调用形式，以真实的编译 / 运行报错作为验证器，循环修正。
6. **创建 skill 文件夹**（Agent 创建目录并写 `.cs` 和 `.md`，`build` 生成 `.dll`）：
   ```
   <VmRoot>\Task\<Skill>\
       <Skill>.cs     # C# 源码（含 public static int Run(string[] args)）
       <Skill>.dll    # 编译输出
       <Skill>.md     # skill 说明（见第 8.2 节）
   ```
7. **编译**：`vmrun.ps1 build <Skill>.cs`，失败则修正后重试。
8. **执行**：`vmrun.ps1 run <Skill>.dll key=value ...`。
9. **汇报**（第 7 节）。无法在真实 Vismockup 会话中验证时，只说“已编译”，不要声称运行成功。

## 6. 代码规范

- **C# 5**（`/langversion:5`）、.NET Framework 4.x、**x64**：不用 `$""`、`?.`、`nameof`、表达式体成员、`out var`。
- 单个 `.cs` 文件，不要 `Main`；入口固定为 `public static int Run(string[] args)`。
- **无类型库，全部用 `dynamic` 晚绑定**（`Microsoft.CSharp.dll` 已由 `build` 引用）。COM 成员名区分大小写，节点用 `Node(i)`（圆括号）。
- 对象链（依据 `api_md/INDEX.md`）：`VFFrame.Application` → `.VisAppAutomation()`（**方法调用，带括号**，得到 `DispVisApp`）→ `ActiveDocument` / `Documents`（`VisDispDocList`：`ActiveDocument`、`OpenDocument(path)`、`ActiveView`）；视图取自 `DispVisApp.ActiveView`（`dynamic`，3D 文档为 `VisDisp3DView`：`SelectedNodes` / `VisibleNodes` / `AllNodes`、`RootNode`、各 Manager）或 `doc.ViewList.ViewByIndex(i)`。**`VisDispDoc` 没有 `ActiveView` 和 `Name`**，文档标识用 `Path`。
- **成员名只能取自 `api_md`**：写每个成员前先查 `api_md/objects/<对象>.md` 或 grep `api_md/members.tsv`；查不到就不要写，按第 5 步第 3 条处理。`api_md` 里标注“原文未说明”的入口（`SectionMngr`、`SweptVolMngr`、`Tech*View`）必须先实机探测，不得当作已知成员使用。
- 节点集合 `VisDispNodeList`：数量用 `NumNodes`，取元素用 `Node(i)`（圆括号，`i` 从 0 起，见 `vismockup_md` 样例）；`BBox` / `Transform` 是 `dynamic` 数组，需转换后使用。
- **附加优先**：`Marshal.GetActiveObject("VFFrame.Application")` 失败再 `Activator.CreateInstance`。读取 `ActiveDocument` 时要 `try/catch (COMException)`（无文档时会抛 `E_FAIL`），按无文档处理并返回 11。
- **`[out] VARIANT` 参数**（如 `MetaDataProperties.GetProperty`、`GetPropertyByName`、`GetCameraPosition`、`GetVisibleBBox`）必须用 `Type.InvokeMember` + `ParameterModifier` + `VariantWrapper(null)`，调用后用 `Unwrap` 解包；传 `null` / `string.Empty` 会抛 `DISP_E_BADCALLEE`。
- 变换矩阵为 16 个 double，列主序：位置 `m[12..14]`，法向为 Z 列 `m[8..10]`。
- 焊点规则：有名字（`DataStoreName` 非空）的节点是焊点，读取后停止；无名节点是分组，向下钻取；不要读分组自身。关联钣金键 `Connected Part-1..3`，按前缀、去空格、忽略大小写匹配。
- 输出只用 `Console.WriteLine`，尽量结构化（每行 `key=value`）。
- **失败诊断**：每条失败信息依次说明：哪一步（成员）、输入值（空值打印 `<empty>`）、出了什么问题、可能原因 / 下一步；中英双语。
- 不写死路径、名称；不保存 / 关闭 / 覆盖用户文档，除非用户明确要求。
- 不让异常逃出 `Run`（统一 `catch` 后输出并返回非 0）。

## 7. 结果输出格式

向用户汇报：

- 状态：成功 / 失败（退出码）
- 结果摘要及关键数据（列表用表格呈现）
- 失败时给出 stdout / stderr 内容和你的处理建议
- 使用的 skill 名称、DLL 路径、传入参数，便于复现

## 8. 模板

### 8.1 `<Skill>.cs`

（成员名已对照 `api_md` 核对；未在运行中的 Vismockup 上验证，汇报时只能说“已编译”。）

```csharp
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace VismockupSkills
{
    // 返回码：0 成功；11 Vismockup 未运行/无活动文档/无选中；14 缺少必填参数；其它非 0 为业务失败
    public static class SkillTemplate   // 类名改为 <Skill>
    {
        public static int Run(string[] args)
        {
            Dictionary<string, string> p = ParseArgs(args);
            try
            {
                // 必填参数缺失时返回 14，让 Agent 向用户追问：
                // if (!p.ContainsKey("nodeName")) { Console.WriteLine("MissingFields: nodeName"); return 14; }

                dynamic visApp = AttachVisApp();
                if (visApp == null)
                {
                    Console.WriteLine("FAIL step=AttachVisApp | Vismockup 未运行或 COM 不可用 / Vismockup is not running or COM unavailable. 请先启动 Vismockup 并打开模型。");
                    return 11;
                }

                dynamic doc = null;
                try { doc = visApp.ActiveDocument; } catch (COMException) { }   // DispVisApp.ActiveDocument
                if (doc == null)
                {
                    Console.WriteLine("FAIL step=ActiveDocument | 没有活动文档 / no active document. 请先打开模型。");
                    return 11;
                }
                dynamic view = null;
                try { view = visApp.ActiveView; } catch (COMException) { }      // DispVisApp.ActiveView（dynamic，3D 文档为 VisDisp3DView）
                if (view == null)
                {
                    Console.WriteLine("FAIL step=ActiveView | 没有活动视图 / no active view.");
                    return 11;
                }

                // ... 在此实现具体 COM 自动化（成员名区分大小写，只用 api_md 中存在的成员）...
                Console.WriteLine("OK " + Convert.ToString(doc.Path));
                return 0;
            }
            catch (Exception ex)
            {
                Console.WriteLine("FAIL step=Run | " + ex.Message + " | 检查输入参数与 Vismockup 状态 / check inputs and Vismockup state.");
                return 1;
            }
        }

        // 附加到已运行的 Vismockup；失败才新建实例（新实例没有选中集）
        private static dynamic AttachVisApp()
        {
            object app = null;
            try { app = Marshal.GetActiveObject("VFFrame.Application"); }
            catch (COMException) { }
            if (app == null)
            {
                Type t = Type.GetTypeFromProgID("VFFrame.Application");
                if (t == null) return null;
                app = Activator.CreateInstance(t);
            }
            return ((dynamic)app).VisAppAutomation();
        }

        private static Dictionary<string, string> ParseArgs(string[] args)
        {
            Dictionary<string, string> d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (args == null) return d;
            foreach (string a in args)
            {
                int i = a.IndexOf('=');
                if (i > 0) d[a.Substring(0, i).Trim()] = a.Substring(i + 1);
            }
            return d;
        }

        // [out] VARIANT 参数调用后统一用此函数解包
        private static object Unwrap(object o)
        {
            VariantWrapper w = o as VariantWrapper;
            return w != null ? w.WrappedObject : o;
        }
    }
}
```

### 8.2 `<Skill>.md`（skill 说明，供日后复用）

```markdown
# <Skill>
一句话说明用途。

- 类型：只读 / 修改数据
- DLL：<Skill>.dll（入口 Run(string[])）
- 范围：SELECTED / VISIBLE / NAMED / ALL
- 适用版本：Teamcenter Visualization Mockup 2512

## 参数 (key=value)
| 名称 | 必填 | 默认 | 说明 |

## 输出 (stdout)
字段说明与示例。

## 退出码
| 值 | 含义 |

## 调用示例
vmrun.ps1 run <VmRoot>\Task\<Skill>\<Skill>.dll nodeName=Weld_001

## 前置条件
Vismockup 已运行、已打开的模型、需要的选择集等。

## 注意事项 / 已知限制
```

## 9. 安全规则

- 只在 `<VmRoot>\Task\` 下创建 skill 产物，不修改 Vismockup 安装目录与注册表。
- 不写入与需求无关的代码，不访问网络，不读写需求之外的文件。
- 修改文档、保存、关闭、导出覆盖已有文件的 skill，必须先告知用户并获得确认。

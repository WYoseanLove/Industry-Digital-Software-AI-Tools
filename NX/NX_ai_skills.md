# NX AI Skills — Agent Handbook

> Bilingual: English first, Chinese below the first `---` / 中文见下方。

This file guides the Agent to generate **NX Open C++** skills (DLLs) from user requirements, run them through PowerShell in a batch NX session, and return the results to the user.

`<NxRoot>` = the directory of this file (`...\Industry-Digital-Software-AI-Tools\NX`).

## 1. Role (System Prompt)

> You are a senior NX application and customization engineer and also a senior C++ engineer, expert in NX Open (the `NXOpen::` C++ API and Open C `UF_*`).
> You first understand the user's business intent (modeling / measurement / assembly / attributes, etc.), then design a reusable skill, write C++ code that compiles and runs safely in a batch NX session, and report execution results honestly.

## 2. Architecture

```
Agent --(generate C++ source)--> <NxRoot>\Task\<Skill>\<Skill>.cpp
Agent --(nxrun.ps1 build)--> <NxRoot>\Task\<Skill>\<Skill>.dll   (exports NxMain)
Agent --(nxrun.ps1 run)----> PowerShell loads the DLL -> NxMain -> UF_initialize starts batch NX -> stdout / ExitCode
```

- The return value of `NxMain` is the exit code; results are printed with `std::cout`, errors with `std::cerr`.
- For the entry skeleton, build options and runtime environment see `cookbook-md/00_NX_DLL_Entry_Template.md`.

## 3. Mandatory entry point: `nxrun.ps1` (must be used)

**Environment detection, build and run must go through the script below only; never hand-write `cl` / `cmd` commands or any other workaround.**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <NxRoot>\tools\nxrun.ps1 setup
powershell -NoProfile -ExecutionPolicy Bypass -File <NxRoot>\tools\nxrun.ps1 build <NxRoot>\Task\<Skill>\<Skill>.cpp
powershell -NoProfile -ExecutionPolicy Bypass -File <NxRoot>\tools\nxrun.ps1 run   <NxRoot>\Task\<Skill>\<Skill>.dll <arg1> <arg2> ...
```

`run` arguments start at `argv[1]` (`argv[0]` is the DLL path). Each call is an independent PowerShell process; the DLL is released after use, so recompiling does not require restarting anything.

### Mandatory rules

1. **The first time an NX automation request is handled in a session, run `setup` first**.
2. Only `build` may compile and only `run` may execute; never `run` after a failed `build`.
3. Do not try to elevate and do not modify system environment variables yourself; steps that need user action (installing NX, setting variables) are only shown to the user.

### Exit code handling

| Exit code | Meaning | Agent action |
|---|---|---|
| 0 | Success | Continue / report the result |
| 10 | Environment not ready | Tell the user the `[X]` items printed by the script verbatim and **stop**; re-run `setup` after the user fixes them |
| 2 | Argument error | Check the command and paths |
| 3 | MSVC not found | Ask the user to install Visual Studio Build Tools (Desktop development with C++) |
| Other non-zero (`build`) | Build failed | Fix the code per the `cl` errors and `build` again until it succeeds |
| Other non-zero (`run`) | Error code returned by `NxMain` | Read stdout / stderr, fix, then `build` + `run` again; if it still fails after several rounds, report honestly |

## 4. Environment detection (first run)

`setup` checks the following in order and prints `[OK]` / `[!]` / `[X]`:

| Check | Pass condition | Message to the user on failure |
|---|---|---|
| NX installed | An NX installation exists under `C:\Program Files\Siemens\` (containing `NXBIN`, `UGOPEN`) | Install Siemens NX first (this repository is written for NX2512) |
| NX Open installed | `<UGII_BASE_DIR>\UGOPEN\` contains `NXOpen\Session.hxx`, `uf.h`, `libnxopencpp.lib`, `libufun.lib`, `libnxopencpp_assemblies.lib` | Re-run the NX installer and select NX Open / programming support |
| NX Open environment variables set | `UGII_BASE_DIR` (NX install root) and `UGII_ROOT_DIR` (the `NXBIN` below it) are set and the paths exist | Set them with the `setx` commands given by the script, **open a new terminal**, then re-run `setup` |
| License | `UGS_LICENSE_SERVER` or `SPLM_LICENSE_SERVER` is set (warning only) | Confirm the license server is reachable; batch NX needs a license |
| Build tools | 64-bit PowerShell + MSVC C++ x64 toolchain | Install VS Build Tools |

Example (NX2512 default path):

```powershell
setx UGII_BASE_DIR "C:\Program Files\Siemens\DesigncenterNX2512"
setx UGII_ROOT_DIR "C:\Program Files\Siemens\DesigncenterNX2512\NXBIN"
```

When `setup` exits non-zero, tell the user the `[X]` items and stop; do not continue generating or running skills.

## 5. Workflow

1. **Environment**: run `nxrun.ps1 setup`; if non-zero, handle per the exit code table and do not continue.
2. **Understand the request**: from an NX engineer's viewpoint, confirm the objects (`.prt` path, assembly components, features, attributes, etc.), the expected output, and whether the part will be **modified** or **saved**. Clearly distinguish read-only from modifying; confirm with the user before running modifying tasks.
3. **Extract a generic skill**: abstract the request into a reusable, parameterized capability (paths, names, tolerances, etc. are passed through `argv`; never hard-code them).
4. **Naming and reuse**: name skills in English PascalCase verb-object form (e.g. `ExportWeldPoints`, `MeasurePartClearance`). First check whether `<NxRoot>\Task\<Skill>\` already has a reusable skill (read its `<Skill>.md`); reuse or upgrade it if so.
5. **Look things up before writing code** (mandatory):
   - First read `<NxRoot>\cookbook-md\README.md` and pick 1–4 best-matching cookbook files to read; the entry must follow `00_NX_DLL_Entry_Template.md`.
   - Use `<NxRoot>\api-md\INDEX.md` and `api-md\modules\` to verify the **exact signatures** of classes / methods; for Open C functions check `C:\Program Files\Siemens\DesigncenterNX2512\UGOPEN\uf_*.h`.
   - You may also consult the samples in the install directory: `C:\Program Files\Siemens\DesigncenterNX2512\UGOPEN\SampleNXOpenApplications\C++\` (read-only reference; do not modify the install directory).
   - Do not write APIs from memory.
6. **Create the skill folder** (the Agent creates the directory and writes the `.cpp` and `.md`; `build` produces the `.dll`):
   ```
   <NxRoot>\Task\<Skill>\
       <Skill>.cpp    # C++ source (contains NxMain)
       <Skill>.dll    # build output
       <Skill>.md     # skill description (see section 7)
   ```
7. **Build**: `nxrun.ps1 build <Skill>.cpp`; on failure fix and retry.
8. **Run**: `nxrun.ps1 run <Skill>.dll <args...>`.
9. **Report** (section 6).

## 6. Coding rules

- C++17, MSVC x64, `/MD`; export `extern "C" __declspec(dllexport) int NxMain(int argc, char* argv[])`.
- Call `UF_initialize()` / `UF_terminate()` inside `NxMain`, and make sure `UF_terminate()` is called on every path; return 0 for success and non-zero for failure (use different values to distinguish error categories).
- Validate arguments at the entry (return 2 for missing arguments and print usage with `std::cerr`).
- Output only with `std::cout` / `std::cerr`, flush before returning; do not use ListingWindow, message boxes or other interactive UI.
- Structure the output where possible (`key=value` per line or JSON) so the Agent can parse it.
- Free memory returned by Open C with `UF_free`; NX Open objects follow their own lifetime, do not `delete` them manually.
- Use `try { ... } catch (const NXOpen::NXException& ex)` to catch and print `ex.Message()`; do not let exceptions escape `NxMain`.
- Angles: most `UF_*` functions use degrees, vector rotation uses radians; check the header comments; units follow the part units.
- Modifying skills must not save / overwrite the user's `.prt` unless the user explicitly asks; when saving is needed, save as to a new path specified by the user.

## 7. Result output format

Report to the user:

- Status: success / failure (exit code)
- Result summary and key data (present lists as tables)
- On failure, the stderr content and your handling suggestion
- The skill name, DLL path and arguments used, for reproducibility

## 8. Templates

### 8.1 `<Skill>.cpp`

```cpp
#include <uf.h>
#include <uf_part.h>
#include <NXOpen/Session.hxx>
#include <NXOpen/PartCollection.hxx>
#include <NXOpen/Part.hxx>
#include <NXOpen/NXException.hxx>
#include <iostream>

using namespace NXOpen;

extern "C" __declspec(dllexport) int NxMain(int argc, char* argv[])
{
    if (argc < 2) { std::cerr << "Usage: run <Skill>.dll <part.prt>" << std::endl; return 2; }
    int rc = 0;
    if (UF_initialize() != 0) { std::cerr << "UF_initialize failed" << std::endl; return 3; }
    try
    {
        Session* session = Session::GetSession();
        PartLoadStatus* status = NULL;
        Part* part = session->Parts()->OpenDisplay(argv[1], &status);
        delete status;
        std::cout << "part=" << part->Name().GetText() << std::endl;
    }
    catch (const NXException& ex)
    {
        std::cerr << "NXException: " << ex.Message() << std::endl;
        rc = 1;
    }
    UF_terminate();
    std::cout.flush();
    std::cerr.flush();
    return rc;
}
```

Check: the exact headers and signatures follow `00_NX_DLL_Entry_Template.md` and `api-md`.

### 8.2 `<Skill>.md` (skill description, for later reuse)

```markdown
# <Skill>
一句话说明用途。

- 类型：只读 / 修改数据
- DLL：<Skill>.dll（入口 NxMain）
- 适用版本：NX2512

## 参数 (argv)
| 位置 | 名称 | 必填 | 默认 | 说明 |

## 输出 (stdout)
字段说明与示例。

## 退出码
| 值 | 含义 |

## 调用示例
nxrun.ps1 run <NxRoot>\Task\<Skill>\<Skill>.dll "C:\data\model.prt"

## 前置条件
需要的 .prt、许可证等。

## 注意事项 / 已知限制
```

## 9. Safety rules

- Create skill artifacts only under `<NxRoot>\Task\`; do not modify the NX install directory.
- Do not write code unrelated to the request, do not access the network, do not read or write files outside the request.
- A skill that modifies or saves parts must first inform the user and obtain confirmation.

---

# NX AI Skills — Agent 工作手册

本文件指导 Agent：根据用户需求，生成 **NX Open C++** skill（DLL），通过 PowerShell 在批处理 NX 会话中执行，并把结果返回给用户。

`<NxRoot>` = 本文件所在目录（`...\Industry-Digital-Software-AI-Tools\NX`）。

## 1. 角色设定（System Prompt）

> 你是一名高级 NX 应用与二次开发工程师，同时是高级 C++ 工程师，精通 NX Open（`NXOpen::` C++ API 与 Open C `UF_*`）。
> 你先理解用户的建模 / 测量 / 装配 / 属性等业务意图，再设计可复用的 skill，写出能编译、能在批处理 NX 会话里安全运行的 C++ 代码，并如实报告执行结果。

## 2. 架构

```
Agent --(生成 C++ 源码)--> <NxRoot>\Task\<Skill>\<Skill>.cpp
Agent --(nxrun.ps1 build)--> <NxRoot>\Task\<Skill>\<Skill>.dll   (导出 NxMain)
Agent --(nxrun.ps1 run)----> PowerShell 加载 DLL -> NxMain -> UF_initialize 启动批处理 NX -> stdout / ExitCode
```

- `NxMain` 的返回值即退出码；结果通过 `std::cout` 输出，错误通过 `std::cerr` 输出。
- 入口骨架、编译参数、运行环境详见 `cookbook-md/00_NX_DLL_Entry_Template.md`。

## 3. 强制入口：`nxrun.ps1`（必须使用）

**环境检测、编译、运行一律只通过下面这个脚本完成，禁止自己手写 `cl` / `cmd` 命令或其它绕过方式。**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <NxRoot>\tools\nxrun.ps1 setup
powershell -NoProfile -ExecutionPolicy Bypass -File <NxRoot>\tools\nxrun.ps1 build <NxRoot>\Task\<Skill>\<Skill>.cpp
powershell -NoProfile -ExecutionPolicy Bypass -File <NxRoot>\tools\nxrun.ps1 run   <NxRoot>\Task\<Skill>\<Skill>.dll <arg1> <arg2> ...
```

`run` 的参数从 `argv[1]` 开始（`argv[0]` 是 DLL 路径）。每次调用都是独立的 PowerShell 进程，DLL 用完即释放，重新编译无需重启任何东西。

### 强制规则

1. **会话第一次处理 NX 自动化需求时，先运行 `setup`**。
2. 只允许用 `build` 编译、`run` 执行；`build` 失败绝不能 `run`。
3. 不要尝试提权，不要自行修改系统环境变量；需要用户操作的步骤（安装 NX、设置变量）只提示用户。

### 退出码处理

| 退出码 | 含义 | Agent 动作 |
|---|---|---|
| 0 | 成功 | 继续 / 汇报结果 |
| 10 | 环境未就绪 | 把脚本输出的 `[X]` 项原样告诉用户并**停止**；用户处理后重新 `setup` |
| 2 | 参数错误 | 检查命令与路径 |
| 3 | 未找到 MSVC | 提示用户安装 Visual Studio Build Tools（Desktop development with C++） |
| 其它非 0（`build`） | 编译失败 | 根据 `cl` 错误修正代码，重新 `build`，直到成功 |
| 其它非 0（`run`） | `NxMain` 返回的错误码 | 阅读 stdout / stderr，修正后重新 `build` + `run`；多轮仍失败则如实汇报 |

## 4. 环境检测（首次运行）

`setup` 依次检查并输出 `[OK]` / `[!]` / `[X]`：

| 检查项 | 通过条件 | 失败时提示用户 |
|---|---|---|
| 是否安装 NX | `C:\Program Files\Siemens\` 下存在 NX 安装（含 `NXBIN`、`UGOPEN`） | 先安装 Siemens NX（本库按 NX2512 编写） |
| 是否安装 NX Open | `<UGII_BASE_DIR>\UGOPEN\` 下有 `NXOpen\Session.hxx`、`uf.h`、`libnxopencpp.lib`、`libufun.lib`、`libnxopencpp_assemblies.lib` | 重新运行 NX 安装程序，勾选 NX Open / 编程支持 |
| 是否设置 NX Open 环境变量 | `UGII_BASE_DIR`（NX 安装根目录）和 `UGII_ROOT_DIR`（其下的 `NXBIN`）已设置且路径存在 | 按脚本给出的 `setx` 命令设置，**新开终端**后重新 `setup` |
| 许可证 | `UGS_LICENSE_SERVER` 或 `SPLM_LICENSE_SERVER` 已设置（仅警告） | 确认许可证服务器可达，批处理 NX 需要许可证 |
| 编译工具 | 64 位 PowerShell + MSVC C++ x64 工具链 | 安装 VS Build Tools |

示例（NX2512 默认路径）：

```powershell
setx UGII_BASE_DIR "C:\Program Files\Siemens\DesigncenterNX2512"
setx UGII_ROOT_DIR "C:\Program Files\Siemens\DesigncenterNX2512\NXBIN"
```

`setup` 退出码非 0 时，把 `[X]` 项告诉用户并停止，不得继续生成或运行 skill。

## 5. 工作流程

1. **环境**：运行 `nxrun.ps1 setup`，非 0 则按退出码表处理，不得继续。
2. **理解需求**：以 NX 工程师视角确认对象（`.prt` 路径、装配组件、特征、属性等）、期望输出、是否会**修改**或**保存**零件。只读 / 修改要明确区分；修改类任务执行前向用户确认。
3. **提炼通用 skill**：把需求抽象成可复用、带参数的能力（路径、名称、容差等通过 `argv` 传入，不要写死）。
4. **命名与复用**：skill 名使用英文 PascalCase 动宾结构（如 `ExportWeldPoints`、`MeasurePartClearance`）。先检查 `<NxRoot>\Task\<Skill>\` 是否已有可复用的 skill（读取其 `<Skill>.md`），有则复用或升级。
5. **查资料再写代码**（必须）：
   - 先读 `<NxRoot>\cookbook-md\README.md`，挑选 1–4 个最匹配的 cookbook 文件阅读；入口必须遵循 `00_NX_DLL_Entry_Template.md`。
   - 用 `<NxRoot>\api-md\INDEX.md` 与 `api-md\modules\` 核对类 / 方法的**精确签名**；Open C 函数查 `C:\Program Files\Siemens\DesigncenterNX2512\UGOPEN\uf_*.h`。
   - 还可参考安装目录示例：`C:\Program Files\Siemens\DesigncenterNX2512\UGOPEN\SampleNXOpenApplications\C++\`（只读参考，不要修改安装目录）。
   - 不要凭记忆写 API。
6. **创建 skill 文件夹**（Agent 创建目录并写 `.cpp` 和 `.md`，`build` 生成 `.dll`）：
   ```
   <NxRoot>\Task\<Skill>\
       <Skill>.cpp    # C++ 源码（含 NxMain）
       <Skill>.dll    # 编译输出
       <Skill>.md     # skill 说明（见第 7 节）
   ```
7. **编译**：`nxrun.ps1 build <Skill>.cpp`，失败则修正后重试。
8. **执行**：`nxrun.ps1 run <Skill>.dll <args...>`。
9. **汇报**（第 6 节）。

## 6. 代码规范

- C++17，MSVC x64，`/MD`；导出 `extern "C" __declspec(dllexport) int NxMain(int argc, char* argv[])`。
- `NxMain` 内调用 `UF_initialize()` / `UF_terminate()`，所有路径都要保证 `UF_terminate()` 被调用；返回 0 表示成功，非 0 表示失败（用不同值区分错误类别）。
- 参数校验在入口完成（缺参数返回 2 并用 `std::cerr` 输出用法）。
- 输出只用 `std::cout` / `std::cerr`，返回前 flush；不使用 ListingWindow、消息框等交互 UI。
- 结果输出尽量结构化（每行 `key=value` 或 JSON），便于 Agent 解析。
- Open C 返回的内存用 `UF_free` 释放；NX Open 对象用其自身生命周期，不要手动 `delete`。
- 用 `try { ... } catch (const NXOpen::NXException& ex)` 捕获并输出 `ex.Message()`，不让异常逃出 `NxMain`。
- 角度：`UF_*` 多数使用度，向量旋转使用弧度，注意核对头文件注释；单位以零件单位为准。
- 修改类 skill 不得保存 / 覆盖用户 `.prt`，除非用户明确要求；需要保存时另存到用户指定的新路径。

## 7. 结果输出格式

向用户汇报：

- 状态：成功 / 失败（退出码）
- 结果摘要及关键数据（列表用表格呈现）
- 失败时给出 stderr 内容和你的处理建议
- 使用的 skill 名称、DLL 路径、传入参数，便于复现

## 8. 模板

### 8.1 `<Skill>.cpp`

```cpp
#include <uf.h>
#include <uf_part.h>
#include <NXOpen/Session.hxx>
#include <NXOpen/PartCollection.hxx>
#include <NXOpen/Part.hxx>
#include <NXOpen/NXException.hxx>
#include <iostream>

using namespace NXOpen;

extern "C" __declspec(dllexport) int NxMain(int argc, char* argv[])
{
    if (argc < 2) { std::cerr << "Usage: run <Skill>.dll <part.prt>" << std::endl; return 2; }
    int rc = 0;
    if (UF_initialize() != 0) { std::cerr << "UF_initialize failed" << std::endl; return 3; }
    try
    {
        Session* session = Session::GetSession();
        PartLoadStatus* status = NULL;
        Part* part = session->Parts()->OpenDisplay(argv[1], &status);
        delete status;
        std::cout << "part=" << part->Name().GetText() << std::endl;
    }
    catch (const NXException& ex)
    {
        std::cerr << "NXException: " << ex.Message() << std::endl;
        rc = 1;
    }
    UF_terminate();
    std::cout.flush();
    std::cerr.flush();
    return rc;
}
```

核对：具体头文件与签名以 `00_NX_DLL_Entry_Template.md` 和 `api-md` 为准。

### 8.2 `<Skill>.md`（skill 说明，供日后复用）

```markdown
# <Skill>
一句话说明用途。

- 类型：只读 / 修改数据
- DLL：<Skill>.dll（入口 NxMain）
- 适用版本：NX2512

## 参数 (argv)
| 位置 | 名称 | 必填 | 默认 | 说明 |

## 输出 (stdout)
字段说明与示例。

## 退出码
| 值 | 含义 |

## 调用示例
nxrun.ps1 run <NxRoot>\Task\<Skill>\<Skill>.dll "C:\data\model.prt"

## 前置条件
需要的 .prt、许可证等。

## 注意事项 / 已知限制
```

## 9. 安全规则

- 只在 `<NxRoot>\Task\` 下创建 skill 产物，不修改 NX 安装目录。
- 不写入与需求无关的代码，不访问网络，不读写需求之外的文件。
- 会修改或保存零件的 skill 必须先告知用户并获得确认。

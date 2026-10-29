<a id="english"></a>

# Industry-Digital-Software-AI-Tools

![Industry-Digital-Software-AI-Tools — Prompt, Skill, Run, Report](docs/Industry-Digital-Software-AI-Tools_Promo_Minimal.png)

<p align="center">
  <strong>Say it. AI builds it.</strong><br>
  Natural-language automation for manufacturing software.
</p>

<p align="center">
  <a href="#english">English</a> · <a href="#中文">简体中文</a><br>
  <strong>Tecnomatix · NX · Vismockup · CATIA · Excel / PowerPoint</strong>
</p>

### At a glance

| One workflow | Reusable knowledge | Controlled execution |
|---|---|---|
| Describe a need, generate a skill, build and run it, then report the results. | Product manuals, exact API references and topic-based Memory guide each task. | Environment checks, build-before-run and confirmation before data changes. |

**Prompt → Skill → Run → Report**

### Explore

[Overview](#en-overview) · [Setup & detection](#en-setup) · [NX development](#en-nx) · [Version adaptation](#en-versions) · [Memory](#en-memory) · [Repository layout](#en-layout) · [API documentation](#en-api)

> **Documentation:** English first, Chinese second. Main hand-written Markdown files are bilingual; reference material may retain its source language. Agent replies follow the user's language and include an estimated token / cost footer. See [.github/copilot-instructions.md](.github/copilot-instructions.md) and [token pricing](tools/token_pricing.md).

> **Tecnomatix first-use reminder:** the script is `txai.ps1`. On detecting Tecnomatix, the Agent's environment check automatically runs `txai.ps1 setup` to build missing plugin DLLs and create `%LOCALAPPDATA%\TxAi\txai.config.json` with the Task whitelist. **Automatic preparation is not deployment:** you must then run the printed copy command in an administrator PowerShell, restart Process Simulate, open a Study and click **AI > AI Bridge**. Setup must return 0 before skills can run. Full configuration and verification instructions are in section 2.3.

<a id="en-overview"></a>

## 1. Purpose

An AI automation toolkit for manufacturing software: the user states a need in natural language, the Agent reads the product manuals and API docs, generates a skill (a small C# / C++ program), builds and runs it inside the target software through a unified runner script, and, when needed, turns the results into an Excel / PowerPoint report.

| Product | Method | Language | Runner | Manual | Output folder |
|---|---|---|---|---|---|
| Tecnomatix Process Simulate | AI Bridge add-in + named pipe | C# 5 / .NET 4.8 | `Tecnomatix/Tecnomatix-AI-Client/tools/txai.ps1` | `Tecnomatix/Tecnomatix_ai_skills.md` | `Tecnomatix/Task/<Skill>/` |
| Siemens NX | NX Open C++ (batch-loaded DLL) | C++17 | `NX/tools/nxrun.ps1` | `NX/NX_ai_skills.md` | `NX/Task/<Skill>/` |
| Vismockup (Teamcenter Visualization) | COM `VFFrame.Application` | C# 5 / .NET 4.x x64 | `Vismockup/tools/vmrun.ps1` | `Vismockup/Vismockup_ai_skills.md` | `Vismockup/Task/<Skill>/` |
| CATIA V5 | COM `CATIA.Application` | C# 5 / .NET 4.x x64 | `Catia/tools/catrun.ps1` | `Catia/Catia_ai_skills.md` | `Catia/Task/<Skill>/` |
| Office (Excel / PowerPoint reports) | COM, always a new independent instance | C# 5 / .NET 4.x x64 | `Office/tools/officerun.ps1` | `Office/Office_ai_skills.md` | `Office/Task/<Skill>/` |

Common conventions:

- Every runner provides `setup` / `build` / `run`; a `setup` exit code of 10 means the environment is not ready and you must stop.
- Invocation (`-File` must be an absolute path):
  `powershell -NoProfile -ExecutionPolicy Bypass -File <absolute path>\<product>\tools\<runner>.ps1 <command>`
- Before writing API code, check the product's API docs for exact signatures; a DLL whose `build` failed must never be `run`; a skill that modifies / saves / overwrites data needs user confirmation first.
- The Agent must never elevate by itself; steps that need administrator rights are only shown to the user.
- Full rules: [.github/copilot-instructions.md](.github/copilot-instructions.md).

### 1.1 Required Software and API Authorization

**Before generating, building or running a skill, users must hold a valid license for the target software and all API, SDK, automation, add-in and functional-module rights required by that specific use.** Obtain software and development components through authorized channels. This repository does not supply or grant proprietary software licenses, API entitlements, SDK redistribution rights or permission to bypass licensing controls.

| Product | What the user must verify with their license administrator or vendor |
|---|---|
| Tecnomatix Process Simulate | The licensed edition and modules permit the intended Engineering API use, custom add-in deployment and automation. |
| Siemens NX | The licensed edition and modules permit the intended NX Open / Open C operations; obtain the matching UGOPEN development components lawfully and confirm any applicable development or execution entitlements. |
| Vismockup / Teamcenter Visualization | The licensed edition exposes and permits the required `VFFrame.Application` COM automation and target functions. |
| CATIA V5 | The licensed configuration permits the intended V5 Automation interfaces and functions. CAA development is a separate capability; do not assume COM Automation grants CAA SDK rights. |
| Excel / PowerPoint | A properly licensed supported desktop installation permits the intended COM automation in the deployment scenario; a web subscription alone is not proof of desktop automation rights. Review unattended / server-side deployment terms and support limitations separately. |

Exact requirements depend on the vendor agreement, software version, edition, modules and deployment scenario; not every API requires a separately purchased license. Ask the license administrator or vendor support to identify the applicable contract clauses and entitlements in writing. If permission is missing or unclear, stop the affected work until it is resolved.

`USABLE`, a successful `setup`, COM registration, installed headers / assemblies and a successful API call indicate technical readiness only. **They do not verify legal authorization.** The current scripts do not implement vendor entitlement verification; this README states usage conditions, not an enforceable license gate. Users must also obtain permission before sharing proprietary API documentation or customer data with an AI service.

<a id="en-setup"></a>

## 2. Automatic Flow When the Project Is Opened (the Agent must run it)

Before handling the first request of every session, run the unified detection script and show the result to the user:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <absolute path>\tools\envcheck.ps1
```

Flow:

1. **Detect and initialize** (`envcheck.ps1`, default `detect`): prints the build-environment table and the detection result of the five software products. When Tecnomatix is detected, it automatically runs `txai.ps1 setup`: builds missing AI Bridge plugin artifacts and initializes the user-level JSON config (section 2.3). This first setup is automatic; do not ask the user to run it manually.
2. **Report**: tell the user in a table which software is `USABLE`, which is `DETECTED, NOT READY` (with the reason) and which is `NOT DETECTED`. **Only `USABLE` software may be used to generate and run skills**; for the others, explain why and stop.
3. **Missing items**: if the build environment is missing, tell the user and ask whether to install; after consent run `envcheck.ps1 install` (optionally `-NxDeployDir <dir>`).
   - Current PowerShell is administrator: the script installs missing build tools with `winget` and (NX) runs the UGOPEN deployment automatically.
   - Not administrator: the script only prints the commands for the user to run; it never elevates.
4. **Re-check**: after installing / setting environment variables, run `envcheck.ps1` again in a **new terminal**, then the `setup` of the matching product runner.

### 2.1 Build environment (per skill needs)

| Need | Used by | Detection | Auto-install when missing (admin required) |
|---|---|---|---|
| 64-bit PowerShell 5.1+ | all | `[Environment]::Is64BitProcess` | start 64-bit PowerShell / VS Code |
| C# compiler `csc.exe` (.NET Framework 4.x, x64) | Vismockup / CATIA / Office | `%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe` | ships with Windows; otherwise enable .NET Framework 4.x |
| .NET Framework 4.8 Developer Pack | Tecnomatix | `Reference Assemblies\...\v4.8` | `winget install --id Microsoft.DotNet.Framework.DeveloperPack_4 -e` |
| .NET SDK | Tecnomatix | `dotnet --version` | `winget install --id Microsoft.DotNet.SDK.8 -e` |
| MSVC C++ x64 (Build Tools, Desktop development with C++) | NX | `vswhere -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64` | `winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override "--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"` |

Only install what the **detected** software needs; never install build tools for software that is not installed.

### 2.2 Software detection

`envcheck.ps1` reports for each product: detected or not, version, usable or not, reason, runner path.

| Software | Detection basis | Usable when |
|---|---|---|
| Vismockup | COM ProgID `VFFrame.Application` -> CLSID -> server file exists | registered and file exists + 64-bit PowerShell + csc |
| Office | COM `Excel.Application` / `PowerPoint.Application` -> server file exists | Excel present + 64-bit PowerShell + csc (missing PowerPoint only affects PPT reports) |
| CATIA | COM `CATIA.Application`, fallback scan of `Dassault Systemes\B*\win_b64\code\bin\CNEXT.exe` | installation found + 64-bit PowerShell + csc; files without COM registration are marked not ready |
| NX | `UGII_BASE_DIR`, fallback scan of `Siemens\*` under every `Program Files` root on all fixed drives (with `NXBIN\ugraf.exe`); version read from the file version | see section 3: complete UGOPEN + environment variables + MSVC |
| Tecnomatix | `TX_INSTALL_DIR`, else scan `Tecnomatix*\eMPower\Tecnomatix.Engineering.dll` under every `Program Files` root on all fixed drives; newest version wins | .NET SDK + .NET 4.8 Dev Pack + valid config + AI Bridge add-in installed and running (`txai.ps1 setup` exits 0) |

### 2.3 AI Bridge first-time setup (automatic preparation, administrator deployment)

When Tecnomatix is detected, `envcheck.ps1` automatically invokes `txai.ps1 setup`, without elevation. With the .NET SDK and .NET Framework 4.8 Developer Pack available, setup builds missing `TxAi.Addin.dll` / `TxAi.Contracts.dll` into `Tecnomatix\Tecnomatix-AI-Client\deploy\TxAi` and creates `%LOCALAPPDATA%\TxAi\txai.config.json`. Existing complete build artifacts are reused. No manual first setup or JSON editing is needed. If prerequisites are missing or a build fails, the error is reported; deployment must wait until preparation succeeds.

- Missing fields receive these defaults: `PipeName = TxAiClient`, `DefaultTimeoutMs = 120000`, `AutoStart = false`.
- `AllowedDirectories` receives the absolute path of this checkout's `Tecnomatix\Task` directory. No drive, user name or installation version is hard-coded; no parent directory or wildcard is added.
- Existing settings and whitelist entries are preserved; repeated checks do not rewrite an unchanged config. Invalid JSON is reported without overwriting the file and must be corrected before continuing.
- Automatic setup prepares local files only; it does not install the add-in, start Process Simulate or elevate. Once preparation succeeds, the script prints the actual administrator copy command for the detected installation.

**Remaining user steps (administrator deployment):**

1. Open PowerShell using **Run as administrator**. Run the copy command printed by setup; its equivalent with placeholders is:

   ```powershell
   Copy-Item -LiteralPath '<RepoRoot>\Tecnomatix\Tecnomatix-AI-Client\deploy\TxAi' -Destination '<TxInstallDir>\DotNetCommands' -Recurse -Force
   ```

   `<TxInstallDir>` is the detected `eMPower` directory. Only the plugin is copied into the installation; config remains under the same Windows user's profile. The Agent never requests elevation or runs this copy automatically.
2. Save your work and restart Process Simulate, open a Study, then click **AI > AI Bridge**.
3. Rerun the environment check or the verification commands below. `USABLE` requires setup exit 0.

Initialize the config **before starting AI Bridge for the first time**. If Process Simulate is already running when the config changes, save your work and restart it, open a Study, then click **AI > AI Bridge**. Verify the connection with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <RepoRoot>\Tecnomatix\Tecnomatix-AI-Client\tools\txai.ps1 setup
powershell -NoProfile -ExecutionPolicy Bypass -File <RepoRoot>\Tecnomatix\Tecnomatix-AI-Client\tools\txai.ps1 ping
```

On the first automatic setup, exit 10 can mean local preparation succeeded but administrator deployment is still pending; follow the detailed output. Exit 11 means the Bridge is not running yet. Neither is runtime success. Exit 12 means compilation failed: fix the reported error before deploying. Exit 0 confirms the environment and connection, not just the presence of the JSON file. Repeated environment checks rerun setup, reuse complete staged DLLs and preserve unchanged config.

### 2.4 Antivirus notice (read before first use)

The runners build and load small programs on your machine, which is behaviour some antivirus / endpoint-protection products treat as suspicious. Nothing in this repo is signed, so a block is possible and cannot be ruled out in advance.

What is generated, and when:

| Item | Created by | Location |
|---|---|---|
| `ComRunHost.exe` (Vismockup / CATIA / Office) and `NxRunHost.exe` (NX) | compiled from `tools/hosts/*.cs` with `csc` on the **first `run`** (not by `envcheck` / `setup`); rebuilt only when missing or the source is newer | `%LOCALAPPDATA%\Industry-Digital-Software-AI-Tools\bin` (fallback `%TEMP%`) |
| Skill DLLs | `build` of each skill (C# via `csc`, NX via MSVC) | `<Product>/Task/<Skill>/` |

The hosts load a skill DLL into a child process. The runner scripts contain no inline `Add-Type` / P/Invoke loader, which lowers the chance of a false positive, but the generated unsigned exe / DLL can still be flagged (cloud lookup, ASR rules, company policy).

Symptoms: the runner exits with code 3 (host build failed) or 13 (host / skill load failed), the exe or DLL disappears right after being built, or the antivirus shows a quarantine / block message.

How to avoid or fix it:

1. Add an exclusion for `%LOCALAPPDATA%\Industry-Digital-Software-AI-Tools\bin` and for the repo folder in your antivirus (ask your IT team if it is centrally managed).
2. Restore the quarantined file, or delete the exe so the next `run` rebuilds it.
3. If your organisation allows it, sign the exes and DLLs with your own code-signing certificate, or ask IT to allow-list them by hash / path.
4. Do not run the runners from a network share or a temporary download folder; use a local path.
5. Elevation is never used; if a step needs administrator rights, run it yourself.
6. The scripts are plain text: no download, no obfuscation / encoded commands, no hidden windows, no Defender or registry changes (only the user-level `setx` in `envcheck.ps1 install`). Instead of `-ExecutionPolicy Bypass` you can run `Unblock-File` on the repo scripts and use the `RemoteSigned` policy for the current user (`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`), or sign the scripts with your own certificate.

<a id="en-nx"></a>

## 3. NX Development Environment (NX Open)

Based on `NX/NXOpen_setup.png`: after installation NX has no `UGOPEN` folder (NX Open headers and libraries) by default; it is only installed by running Section 3 of the CAD deployment package with administrator rights. The distilled logic:

```
Detect NX (UGII_BASE_DIR or C:\Program Files\Siemens\*)
 ├─ not installed -> report NX unusable, stop
 └─ installed -> check <NX root>\UGOPEN for
              NXOpen\Session.hxx, uf.h, libnxopencpp.lib, libufun.lib, libnxopencpp_assemblies.lib
      ├─ complete -> continue with environment variables and MSVC
      └─ missing  -> administrator must install UGOPEN:
            1. In the deployment folder (like CAD\<NX version>, e.g. CAD\2512) find the Siemens_NXCAD file
               and read its "software dump location" (where the software package is stored)
            2. Open a command prompt / PowerShell as administrator in that location
            3. Run: Deploy-Application.exe -Section 3
               (installs the ugopen folder in the NX installation; administrator mode required)
            4. Without permission, contact the local helpdesk and attach the steps above
Set environment variables (user level, no admin needed, open a new terminal afterwards):
   setx UGII_BASE_DIR "<NX root>"            e.g. C:\Program Files\Siemens\DesigncenterNX2512
   setx UGII_ROOT_DIR "<NX root>\NXBIN"
Finally run: NX\tools\nxrun.ps1 setup (exit code 0 before build / run)
```

How to run with administrator rights:

- The user starts VS Code (or PowerShell) with "Run as administrator" before starting the project, so the Agent can run administrator steps in the same session.
- The Agent first checks whether it is administrator (`envcheck.ps1` prints `Admin: True/False`):
  - `True`: `envcheck.ps1 install -NxDeployDir <deployment folder>` runs `Deploy-Application.exe -Section 3` automatically.
  - `False`: only print the commands above to the user and stop; re-check after the user is done. **The Agent must never try `runas` / `Start-Process -Verb RunAs`.**

<a id="en-versions"></a>

## 4. Version Adaptation

Docs and scripts are written against NX 2512, Tecnomatix 2502, Teamcenter Visualization 2512, CATIA V5-6 B34 and Office 16, but do not depend on a fixed version:

- All paths are discovered dynamically through the registry (COM ProgID / CLSID / CurVer), environment variables (`UGII_BASE_DIR`) and directory wildcards (`Siemens\*`, `Tecnomatix_*`, `Dassault Systemes\B*`, vswhere); with several versions installed the newest is used.
- Version numbers are read live by `envcheck.ps1`; when they differ from the documentation baseline the Agent must tell the user.
- When writing code, check signatures against the locally installed headers / assemblies (NX: `UGII_BASE_DIR\UGOPEN`; Tecnomatix: `Tecnomatix.Engineering.dll`; COM: object-model members). If the repo API docs differ from the local machine, the local machine wins; note it in the skill description.
- Never hard-code version numbers in skill source; read them from environment variables or the registry when needed.

<a id="en-memory"></a>

## 5. Self-learning and Correction

The Agent accumulates experience in the repo's `Memory/` folder, shared through the repo:

- **All lessons learnt / corrections / pitfalls live in `Memory/`** (`learned.md` = user traits + general / environment corrections; the rest are topic files split by topic / situation, such as `env_and_tooling.md`, `task_workflow_rules.md`, and under `Costomer/` `nx_weld_lfo_lwe.md` and topic files for OEM part-number rules; `INDEX.md` is an auto-generated directory). Tier by subject: repository configuration (repo / tooling / environment / workflow rules) -> `Memory/*.md`; anything about the products (NX / Vismockup / CATIA / Tecnomatix, algorithms, API pitfalls, part-number rules) and anything produced by the user's own runs (paths, datasets, benchmark numbers, batch results) -> `Memory/Costomer/`.
- **Topic file format**: front matter (`title`, `scope`, `triggers`, `always`, `updated`); entries are `## PREFIX-NN title` + Wrong / Right / Trigger / Evidence (English lines first, Chinese lines second).
- **Program-level gate**: every runner (`envcheck.ps1`, `txai.ps1`, `nxrun.ps1`, `vmrun.ps1`, `catrun.ps1`, `officerun.ps1`) first runs `tools/memcheck.ps1`: it always prints `learned.md` and `always: true` files; topic files whose scope matches and whose triggers hit the task context (`$env:MFG_TASK_HINT` + runner arguments) are printed in full, scope matches without a trigger hit list only entry titles, others list only file names; it also rebuilds `INDEX.md`; exit code 14 if `learned.md` is missing.
- At session start read `INDEX.md` + `learned.md`, then the topic files matching the request keywords.
- When the user points out an error or states a preference, the Agent first appends a record (wrong -> right -> trigger) in the same turn, then fixes it.
- Before product tasks, check the entries of the matching scope to avoid repeating mistakes; update same-kind entries instead of duplicating; on conflict the user's latest statement wins.
- Never record passwords, tokens or other secrets; the user may ask to delete an entry at any time.

<a id="en-layout"></a>

## 6. Layout

```
.github/copilot-instructions.md   Mandatory Agent rules (single source of truth)
AGENTS.md  CLAUDE.md             Entry points for Codex / Claude clients, pointing to the file above
tools/envcheck.ps1                Environment and software detection / install (section 2)
tools/memcheck.ps1                Memory gate (called by every runner)
tools/tokencost.ps1               Token and cost estimate (rule G2); see tools/token_pricing.md
tools/hostbuild.ps1  tools/hosts/ Source of the small run hosts (compiled with csc on first use into %LOCALAPPDATA%\Industry-Digital-Software-AI-Tools\bin; no inline Add-Type, no signing)
Memory/                           All lessons / corrections: learned.md + topic files + INDEX.md (section 5)
Tecnomatix/  NX/  Vismockup/  Catia/  Office/   Product manuals, API docs, runners, Task
Teamcenter/                       Reserved
```

<a id="en-api"></a>

## 7. API Documentation: Access and Local Configuration

For reference documentation, the public repository currently provides cookbook files only; the product API reference collections listed below are not included. Loading the matching software version's API Markdown files locally helps the Agent verify types, members and exact signatures, improving skill code generation and reducing guessed API calls. Cookbooks provide workflows and examples, but do not replace the complete API references.

Due to development-access and authorization restrictions, contact the author at [wyosean1987@gmail.com](mailto:wyosean1987@gmail.com) to request the API documentation and configuration guidance. Include the product and version you use. Access and use remain subject to the applicable vendor permissions; contacting the author does not itself grant software or API rights.

After obtaining authorized documentation, extract it into the corresponding directory under the repository root, preserving its indexes and subdirectory structure:

| Product | Local API documentation directory |
|---|---|
| Tecnomatix Process Simulate | `Tecnomatix/Tecnomatix_Engineering/` |
| Siemens NX | `NX/api-md/` |
| CATIA V5 | `Catia/api-md/` |
| Vismockup / Teamcenter Visualization | `Vismockup/api_md/` |

Vismockup's current manual uses `api_md` (underscore), not `api-md` (hyphen). Both spellings are ignored by Git, but configure the files under `api_md` so existing lookup paths work. These API directories are local-only and excluded by `.gitignore`; adding the rules does not delete local files or untrack files already in Git. Before generating a skill, ensure the relevant API indexes can be read and that the documentation matches the installed software version.

---

<a id="中文"></a>

# Industry-Digital-Software-AI-Tools（中文）

<p align="center">
  <strong>一句话，AI 搞定制造软件自动化。</strong><br>
  用自然语言连接需求、程序执行与结果报告。
</p>

<p align="center">
  <a href="#english">English</a> · <a href="#中文">简体中文</a><br>
  <strong>Tecnomatix · NX · Vismockup · CATIA · Excel / PowerPoint</strong>
</p>

### 核心特点

| 统一工作流 | 可复用知识 | 可控执行 |
|---|---|---|
| 描述需求，生成 skill，编译并运行，再整理结果报告。 | 产品手册、精确 API 参考与按主题组织的 Memory 为每次任务提供依据。 | 环境检查、先编译后运行，修改数据前须确认。 |

**需求 → Skill → 运行 → 报告**

### 快速导航

[项目用途](#zh-overview) · [配置与检测](#zh-setup) · [NX 开发环境](#zh-nx) · [版本适配](#zh-versions) · [Memory](#zh-memory) · [仓库目录](#zh-layout) · [API 文档](#zh-api)

> **文档约定：**英文在前，中文在后。主要手写 Markdown 文件保持双语，参考资料可保留源语言。Agent 回复跟随用户输入语言，并附 Token 与费用估算。详见 [.github/copilot-instructions.md](.github/copilot-instructions.md) 与 [Token 计价说明](tools/token_pricing.md)。

> **Tecnomatix 首次使用必读：**脚本名称为 `txai.ps1`。检测到 Tecnomatix 后，Agent 的环境检查会自动运行 `txai.ps1 setup`，编译缺失的插件 DLL，并创建 `%LOCALAPPDATA%\TxAi\txai.config.json` 及 Task 白名单。**自动准备不等于部署完成：**随后必须由用户在管理员 PowerShell 中执行输出的复制命令，重启 Process Simulate，打开 Study 并点击 **AI > AI Bridge**。setup 返回 0 后才能运行 skill。完整配置与验证步骤见第 2.3 节。

<a id="zh-overview"></a>

## 1. 项目用途

面向制造软件的 AI 自动化工具集：用户用自然语言提出需求，Agent 读取各产品手册与 API 文档，生成 skill（C# / C++ 小程序），通过统一的 runner 脚本编译并在目标软件中执行，必要时把结果整理成 Excel / PowerPoint 报告。

| 产品 | 方式 | 语言 | Runner | 手册 | 产物目录 |
|---|---|---|---|---|---|
| Tecnomatix Process Simulate | AI Bridge 插件 + 命名管道 | C# 5 / .NET 4.8 | `Tecnomatix/Tecnomatix-AI-Client/tools/txai.ps1` | `Tecnomatix/Tecnomatix_ai_skills.md` | `Tecnomatix/Task/<Skill>/` |
| Siemens NX | NX Open C++（批处理加载 DLL） | C++17 | `NX/tools/nxrun.ps1` | `NX/NX_ai_skills.md` | `NX/Task/<Skill>/` |
| Vismockup（Teamcenter Visualization） | COM `VFFrame.Application` | C# 5 / .NET 4.x x64 | `Vismockup/tools/vmrun.ps1` | `Vismockup/Vismockup_ai_skills.md` | `Vismockup/Task/<Skill>/` |
| CATIA V5 | COM `CATIA.Application` | C# 5 / .NET 4.x x64 | `Catia/tools/catrun.ps1` | `Catia/Catia_ai_skills.md` | `Catia/Task/<Skill>/` |
| Office（Excel / PowerPoint 报告） | COM，每次新建独立实例 | C# 5 / .NET 4.x x64 | `Office/tools/officerun.ps1` | `Office/Office_ai_skills.md` | `Office/Task/<Skill>/` |

通用约定：

- 每个 runner 提供 `setup` / `build` / `run`；`setup` 退出码 10 表示环境未就绪，必须停止。
- 调用方式（`-File` 必须是绝对路径）：
  `powershell -NoProfile -ExecutionPolicy Bypass -File <绝对路径>\<产品>\tools\<runner>.ps1 <command>`
- 写 API 代码前先查该产品的 API 文档核对精确签名；`build` 失败的 DLL 绝不能 `run`；会修改 / 保存 / 覆盖数据的 skill 必须先获得用户确认。
- Agent 不得自行提权；需要管理员权限的步骤只提示用户执行。
- 详细规则见 [.github/copilot-instructions.md](.github/copilot-instructions.md)。

### 1.1 软件与 API 授权前提

**在生成、编译或运行 skill 前，用户必须拥有目标软件的有效许可证，以及该具体用途所需的 API、SDK、自动化、插件和功能模块使用权限。** 软件与开发组件应通过授权渠道获取。本仓库不提供或授予商业软件许可证、API 使用权、SDK 再分发权，也不允许绕过许可控制。

| 产品 | 用户必须向许可证管理员或厂商核实的事项 |
|---|---|
| Tecnomatix Process Simulate | 已授权的版本与模块允许所需的 Engineering API 调用、自定义插件部署和自动化。 |
| Siemens NX | 已授权的版本与模块允许所需的 NX Open / Open C 操作；合法取得匹配的 UGOPEN 开发组件，并确认适用的开发或执行许可。 |
| Vismockup / Teamcenter Visualization | 已授权的版本提供并允许所需的 `VFFrame.Application` COM 自动化及目标功能。 |
| CATIA V5 | 已授权的配置允许所需的 V5 Automation 接口及功能。CAA 开发属于另一类能力，不得因具备 COM Automation 就推定拥有 CAA SDK 权限。 |
| Excel / PowerPoint | 已正确授权且受支持的桌面安装允许该部署场景下的 COM 自动化；仅有网页订阅不能证明具备桌面自动化权限。无人值守或服务器端部署的条款与支持限制需另行核实。 |

具体要求取决于厂商协议、软件版本、配置、模块和部署场景，并非每个 API 都要求单独购买许可证。请许可证管理员或厂商支持以书面形式指出适用合同条款及许可权益；缺少权限或权限不明确时，停止相关工作，解决后再继续。

`USABLE`、`setup` 成功、COM 已注册、存在头文件或程序集，以及 API 调用成功，都只表示技术就绪，**不证明具备合法授权**。当前脚本未实现厂商许可权益核验；本 README 声明使用条件，不构成强制许可证门禁。向 AI 服务提供专有 API 文档或客户数据前，也必须取得相应许可。

<a id="zh-setup"></a>

## 2. 打开项目时的自动流程（Agent 必须执行）

每个会话第一次处理请求之前，先运行统一检测脚本，并把结果输出给用户：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <绝对路径>\tools\envcheck.ps1
```

流程：

1. **检测并初始化**（`envcheck.ps1`，默认 `detect`）：输出编译环境表 + 五个软件的检测结果。检测到 Tecnomatix 时，自动运行 `txai.ps1 setup`：编译缺失的 AI Bridge 插件产物并初始化用户级 JSON 配置（见 2.3 节）。首次 setup 必须自动完成，不要求用户手动执行。
2. **汇报**：以表格告诉用户哪些软件 `USABLE`、哪些 `DETECTED, NOT READY`（给出原因）、哪些 `NOT DETECTED`。**只有 `USABLE` 的软件才可用于生成和执行 skill**；其余软件的请求要说明原因并停止，不得继续。
3. **缺失处理**：编译环境缺失时提醒用户，并询问是否安装；用户同意后运行
   `envcheck.ps1 install`（可加 `-NxDeployDir <目录>`）。
   - 当前 PowerShell 已是管理员：脚本用 `winget` 自动安装缺失的编译环境，并（NX）自动执行 UGOPEN 部署。
   - 当前不是管理员：脚本只打印需要用户执行的命令，不自行提权。
4. **复检**：安装 / 设置环境变量后，在**新终端**重新运行 `envcheck.ps1`，再运行对应产品 runner 的 `setup`。

### 2.1 编译环境（按 skill 需求）

| 需求 | 用于 | 检测 | 缺失时自动安装（需管理员） |
|---|---|---|---|
| 64 位 PowerShell 5.1+ | 全部 | `[Environment]::Is64BitProcess` | 以 64 位 PowerShell / VS Code 启动 |
| C# 编译器 `csc.exe`（.NET Framework 4.x，x64） | Vismockup / CATIA / Office | `%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe` | Windows 自带，缺失则启用 .NET Framework 4.x |
| .NET Framework 4.8 Developer Pack | Tecnomatix | `Reference Assemblies\...\v4.8` | `winget install --id Microsoft.DotNet.Framework.DeveloperPack_4 -e` |
| .NET SDK | Tecnomatix | `dotnet --version` | `winget install --id Microsoft.DotNet.SDK.8 -e` |
| MSVC C++ x64（Build Tools，Desktop development with C++） | NX | `vswhere -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64` | `winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override "--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"` |

只安装"已检测到的软件"所需的环境，不为未安装的软件安装编译环境。

### 2.2 软件检测

`envcheck.ps1` 对每个产品分别给出：是否检测到、版本、是否可用、问题原因、runner 路径。

| 软件 | 检测依据 | 可用条件 |
|---|---|---|
| Vismockup | COM ProgID `VFFrame.Application` -> CLSID -> 服务器文件存在 | 已注册且文件存在 + 64 位 PowerShell + csc |
| Office | COM `Excel.Application` / `PowerPoint.Application` -> 服务器文件存在 | Excel 存在 + 64 位 PowerShell + csc（PowerPoint 缺失只影响 PPT 报告） |
| CATIA | COM `CATIA.Application`，兜底扫描 `Dassault Systemes\B*\win_b64\code\bin\CNEXT.exe` | 找到安装 + 64 位 PowerShell + csc；仅有文件但 COM 未注册时标记未就绪 |
| NX | `UGII_BASE_DIR`，兜底扫描所有固定盘上各 `Program Files` 根目录下的 `Siemens\*`（含 `NXBIN\ugraf.exe`）；版本取自文件版本信息 | 见第 3 节：UGOPEN 完整 + 环境变量 + MSVC |
| Tecnomatix | `TX_INSTALL_DIR`，否则扫描所有固定盘上各 `Program Files` 根目录下的 `Tecnomatix*\eMPower\Tecnomatix.Engineering.dll`，取版本最新者 | .NET SDK + .NET 4.8 Dev Pack + 配置有效 + AI Bridge 插件已安装并启动（`txai.ps1 setup` 退出码为 0） |

### 2.3 AI Bridge 首次 setup（自动准备，管理员部署）

检测到 Tecnomatix 时，`envcheck.ps1` 自动调用 `txai.ps1 setup`，不提权。具备 .NET SDK 和 .NET Framework 4.8 Developer Pack 时，setup 会将缺失的 `TxAi.Addin.dll` / `TxAi.Contracts.dll` 编译到 `Tecnomatix\Tecnomatix-AI-Client\deploy\TxAi`，并创建 `%LOCALAPPDATA%\TxAi\txai.config.json`。已有完整编译产物会复用。用户不必手动执行首次 setup，也无需手工编辑 JSON。缺少编译环境或编译失败时明确报错，准备成功前不得部署。

- 缺失字段自动补齐默认值：`PipeName = TxAiClient`、`DefaultTimeoutMs = 120000`、`AutoStart = false`。
- `AllowedDirectories` 自动加入当前仓库的 `Tecnomatix\Task` 绝对路径。不写死盘符、用户名或安装版本，不加入上级目录或通配符。
- 保留已有设置和白名单；配置无变化时重复检查不会重写文件。JSON 损坏时报告错误，不覆盖原文件，修正后才可继续。
- 自动 setup 仅准备本地文件，不安装插件、不启动 Process Simulate、不自行提权。准备成功后，脚本会针对检测到的安装位置输出实际的管理员复制命令。

**后续用户操作（管理员部署）：**

1. 通过**以管理员身份运行**打开 PowerShell，执行 setup 输出的复制命令；其占位符形式如下：

   ```powershell
   Copy-Item -LiteralPath '<RepoRoot>\Tecnomatix\Tecnomatix-AI-Client\deploy\TxAi' -Destination '<TxInstallDir>\DotNetCommands' -Recurse -Force
   ```

   `<TxInstallDir>` 为检测到的 `eMPower` 目录。仅将插件复制到软件安装目录；配置仍保留在同一 Windows 用户的个人目录中。Agent 不请求提权，也不自动执行此复制。
2. 保存工作并重启 Process Simulate，打开 Study，再点击 **AI > AI Bridge**。
3. 重新运行环境检测或下方验证命令。setup 退出码为 0 才能判定 `USABLE`。

**首次启动 AI Bridge 前应先完成配置初始化。** 如果配置变更时 Process Simulate 已运行，请先保存工作并重启，打开 Study，再点击 **AI > AI Bridge**。用以下命令验证连接：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <RepoRoot>\Tecnomatix\Tecnomatix-AI-Client\tools\txai.ps1 setup
powershell -NoProfile -ExecutionPolicy Bypass -File <RepoRoot>\Tecnomatix\Tecnomatix-AI-Client\tools\txai.ps1 ping
```

首次自动 setup 返回 10，可能表示本地准备已完成、但仍待管理员部署，应按详细输出处理；返回 11 表示 Bridge 尚未运行，两者均不代表运行就绪。返回 12 表示编译失败，修正错误前不得部署。退出码 0 才表示环境与连接均已通过，而不只是 JSON 文件存在。重复环境检查会重新执行 setup，但复用完整的插件 DLL，并保留未变化的配置。

### 2.4 杀毒软件提示（首次使用前请阅读）

runner 会在你的电脑上编译并加载小型程序，这类行为部分杀毒 / 终端防护产品会视为可疑。本仓库没有任何签名，所以可能被拦截，且无法事先排除。

会生成什么、什么时候生成：

| 内容 | 生成方式 | 位置 |
|---|---|---|
| `ComRunHost.exe`（Vismockup / CATIA / Office）与 `NxRunHost.exe`（NX） | 在**第一次 `run`** 时用 `csc` 从 `tools/hosts/*.cs` 编译（`envcheck` / `setup` 不生成）；仅在 exe 缺失或源码更新时重编 | `%LOCALAPPDATA%\Industry-Digital-Software-AI-Tools\bin`（兜底 `%TEMP%`） |
| Skill DLL | 每个 skill 的 `build`（C# 用 `csc`，NX 用 MSVC） | `<产品>/Task/<Skill>/` |

宿主会在子进程中加载 skill DLL。runner 脚本里没有内嵌的 `Add-Type` / P/Invoke 加载器，误报概率因此降低，但生成的未签名 exe / DLL 仍可能被拦截（云查杀、ASR 规则、公司策略）。

常见表现：runner 退出码为 3（宿主编译失败）或 13（宿主 / skill 加载失败）、exe 或 DLL 在编译后立刻消失、杀毒软件弹出隔离 / 拦截提示。

如何避免或处理：

1. 在杀毒软件中为 `%LOCALAPPDATA%\Industry-Digital-Software-AI-Tools\bin` 和本仓库目录添加排除项（统一管理的电脑请联系 IT）。
2. 恢复被隔离的文件，或删除该 exe，下次 `run` 会自动重编。
3. 若公司允许，用自己的代码签名证书给 exe 和 DLL 签名，或让 IT 按哈希 / 路径加入白名单。
4. 不要从网络共享目录或临时下载目录运行 runner，请使用本地路径。
5. 不会自动提权；若某步需要管理员权限，请用户自己执行。
6. 脚本都是纯文本：不下载、不混淆 / 编码命令、不开隐藏窗口、不改 Defender 或注册表（仅 `envcheck.ps1 install` 里有用户级 `setx`）。也可以不用 `-ExecutionPolicy Bypass`：对仓库脚本执行 `Unblock-File`，并把当前用户的策略设为 `RemoteSigned`（`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`），或用自己的证书给脚本签名。

<a id="zh-nx"></a>

## 3. NX 二次开发环境（NX Open）

依据 `NX/NXOpen_setup.png`：NX 安装后默认没有 `UGOPEN` 文件夹（NX Open 头文件与库），必须以管理员权限运行 CAD 部署包的 Section 3 才会安装。提炼出的逻辑：

```
检测 NX（UGII_BASE_DIR 或 C:\Program Files\Siemens\*）
 ├─ 未安装 -> 报告 NX 不可用，停止
 └─ 已安装 -> 检查 <NX根>\UGOPEN 下是否有
              NXOpen\Session.hxx, uf.h, libnxopencpp.lib, libufun.lib, libnxopencpp_assemblies.lib
      ├─ 齐全 -> 继续检查环境变量与 MSVC
      └─ 缺失 -> 需要管理员安装 UGOPEN：
            1. 在部署目录（形如 CAD\<NX 版本>，如 CAD\2512）找到 Siemens_NXCAD 文件，
               查看其中的 "software dump location"（软件包存放位置）
            2. 在该位置以管理员身份打开命令提示符 / PowerShell
            3. 运行：Deploy-Application.exe -Section 3
               （在 NX 安装位置安装 ugopen 文件夹；必须管理员模式）
            4. 无权限时联系本地 helpdesk，并附上上述步骤
设置环境变量（用户级，无需管理员，设置后开新终端）：
   setx UGII_BASE_DIR "<NX根>"            例：C:\Program Files\Siemens\DesigncenterNX2512
   setx UGII_ROOT_DIR "<NX根>\NXBIN"
最后运行：NX\tools\nxrun.ps1 setup（退出码 0 才可 build / run）
```

管理员权限的运行方式：

- 用户用"以管理员身份运行"启动 VS Code（或管理员 PowerShell）后再启动项目，Agent 才能在同一会话内执行管理员步骤。
- Agent 先检测当前是否管理员（`envcheck.ps1` 输出 `Admin: True/False`）：
  - `True`：`envcheck.ps1 install -NxDeployDir <部署目录>` 自动执行 `Deploy-Application.exe -Section 3`。
  - `False`：只向用户输出上述命令并停止，等用户处理后复检。**Agent 不得尝试 `runas` / `Start-Process -Verb RunAs`。**

<a id="zh-versions"></a>

## 4. 版本适配

文档与脚本基于 NX 2512、Tecnomatix 2502、Teamcenter Visualization 2512、CATIA V5-6 B34、Office 16 编写，但不依赖固定版本：

- 所有路径通过注册表（COM ProgID / CLSID / CurVer）、环境变量（`UGII_BASE_DIR`）、目录通配（`Siemens\*`、`Tecnomatix_*`、`Dassault Systemes\B*`、vswhere）动态发现，多个版本并存时取最新。
- 版本号由 `envcheck.ps1` 实时读取并输出；与文档基准版本不同时，Agent 要告知用户。
- 写代码时以本机安装的头文件 / 程序集为准核对签名（NX：`UGII_BASE_DIR\UGOPEN`；Tecnomatix：`Tecnomatix.Engineering.dll`；COM：对象模型成员）。仓库 API 文档与本机不一致时，以本机为准，并在 skill 说明里标注。
- 不要把版本号写死到 skill 源码；需要时从环境变量或注册表读取。

<a id="zh-memory"></a>

## 5. 自学习与纠错

Agent 通过仓库内的 `Memory/` 积累经验，随仓库共享：

- **所有 lessons learnt / 纠错 / 踩坑文件一律放在 `Memory/`**（`learned.md` 用户特点 + 通用 / 环境纠错；其余为按主题 / 情境拆分的主题文件，如 `env_and_tooling.md`、`task_workflow_rules.md`，以及 `Costomer/` 下的 `nx_weld_lfo_lwe.md` 和 OEM 零件号规则主题文件；`INDEX.md` 为自动生成的目录）。按主题分层：仓库配置（仓库 / 工具 / 环境 / 工作流规则）-> `Memory/*.md`；涉及产品的一切（NX / Vismockup / CATIA / Tecnomatix、算法、API 坑、零件号规则）以及用户每次运行产生的内容（路径、数据集、对比数字、批量结果）-> `Memory/Costomer/`。
- **主题文件格式**：开头 front matter（`title`、`scope`、`triggers`、`always`、`updated`），条目为 `## 前缀-序号 标题` + 错误 / 正确 / 触发 / 证据。
- **程序级门禁**：所有 runner（`envcheck.ps1`、`txai.ps1`、`nxrun.ps1`、`vmrun.ps1`、`catrun.ps1`、`officerun.ps1`）启动时先执行 `tools/memcheck.ps1`：始终打印 `learned.md` 与 `always: true` 文件；scope 匹配且 triggers 命中任务上下文（`$env:MFG_TASK_HINT` + runner 参数）的主题文件完整打印，scope 匹配未命中的只列条目标题，其它只列文件名；同时重建 `INDEX.md`；`learned.md` 缺失则退出码 14。
- 会话启动时读取：`INDEX.md` + `learned.md`，再按请求关键词读取命中的主题文件。
- 用户指出错误或表达偏好时，Agent 当轮先追加记录（错误 -> 正确做法 -> 触发条件），再修正。
- 执行相关产品任务前按范围核对条目，避免重犯；同类条目更新而不是重复添加，冲突时以用户最新说法为准。
- 不记录密码、令牌等敏感信息；用户可随时要求删除某条。

<a id="zh-layout"></a>

## 6. 目录

```
.github/copilot-instructions.md   Agent 强制规则（唯一规则来源）
AGENTS.md  CLAUDE.md             Codex / Claude 客户端的入口文件，指向上一个文件
tools/envcheck.ps1                环境与软件检测 / 安装（本文件第 2 节）
tools/memcheck.ps1                Memory 门禁（被所有 runner 调用）
tools/tokencost.ps1               Token 与费用估算（规则 G2），详见 tools/token_pricing.md
tools/hostbuild.ps1  tools/hosts/ 运行宿主的源码（首次使用时用 csc 编译到 %LOCALAPPDATA%\Industry-Digital-Software-AI-Tools\bin；脚本内无 Add-Type，无需签名）
Memory/                           全部 lessons / 纠错：learned.md + 主题文件 + INDEX.md（本文件第 5 节）
Tecnomatix/  NX/  Vismockup/  Catia/  Office/   各产品手册、API 文档、runner、Task
Teamcenter/                       预留
```

<a id="zh-api"></a>

## 7. API 文档获取与本地配置

参考资料目前仅开放 cookbook 文件；下表所列的各产品 API 参考文档不随公开仓库提供。在本地加载与软件版本匹配的 API Markdown 文件，有助于 Agent 核对类型、成员及精确签名，提高 skill 代码生成质量，减少猜测 API 调用。Cookbook 提供流程与示例，不能替代完整 API 参考。

由于开发访问权限及授权限制，需要 API 文档及配置指导时，请发送邮件给作者：[wyosean1987@gmail.com](mailto:wyosean1987@gmail.com)，注明使用的软件及版本。资料获取和使用仍须符合厂商相应授权；联系作者本身不授予软件或 API 使用权限。

取得获授权的文档后，解压到仓库根目录下对应位置，保留索引和子目录结构：

| 产品 | 本地 API 文档目录 |
|---|---|
| Tecnomatix Process Simulate | `Tecnomatix/Tecnomatix_Engineering/` |
| Siemens NX | `NX/api-md/` |
| CATIA V5 | `Catia/api-md/` |
| Vismockup / Teamcenter Visualization | `Vismockup/api_md/` |

Vismockup 当前手册使用 `api_md`（下划线），而非 `api-md`（连字符）。Git 同时忽略两种拼写，但应将资料配置到 `api_md`，以匹配现有查阅路径。这些 API 目录仅供本地使用，已由 `.gitignore` 排除；添加规则不会删除本地文件，也不会自动取消 Git 已跟踪的文件。生成 skill 前，应确认对应 API 索引可读取，且文档与已安装软件版本匹配。

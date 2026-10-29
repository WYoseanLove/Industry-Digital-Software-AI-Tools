---
title: Environment and tooling pitfalls (PowerShell, NX runner, encoding) / 环境与工具使用坑（PowerShell、NX runner、编码）
scope: all
triggers: 硬编码, hardcoded, 死路径, 版本适配, version, envdetect, Program Files, powershell, 编码, encoding, 乱码, garbled, 中文, Chinese, build, run, nxrun, vmrun, 进程, process, ugraf, argv, 编译, compile, 重定向, redirect, 日志, log, buffered, antivirus, 杀毒, Defender, Add-Type, host, 宿主, Task, Directory.Build, 配置文件, config, Git, browser, 浏览器, screenshot, 截图
always: false
updated: 2026-10-29
---
# Environment and tooling pitfalls / 环境与工具使用坑

## ET-11 Public repository name and private output boundaries / 公开仓库名称与私有产物边界
- Wrong: publishing generated skills or customer memory, dropping their empty folders, retaining the old repository name, or treating Vismockup/api-md as the API reference path.
- Right: use Industry-Digital-Software-AI-Tools; keep product Task, Memory/Costomer, and local API reference folders through .gitkeep exceptions, ignore all other contents and the generated Memory/INDEX.md, and preserve local files. Exclude contents of Tecnomatix/Tecnomatix_Engineering, NX/api-md, Catia/api-md and Vismockup/api_md from Git; Vismockup/api_md is the correct path. Document cookbook availability and authorized local API configuration rather than GitHub publishing instructions. Ignore rules do not remove previously tracked data or Git history.
- Trigger: GitHub, open source, rename, Task, Costomer, gitignore, 开源, 更名, 忽略。
- Evidence: repository .gitignore, README.md, and product Task / Memory/Costomer .gitkeep files.
- 错误：发布已生成技能或客户记忆、丢失空目录、继续使用旧仓库名称，或误把 Vismockup/api-md 当作 API 参考目录。
- 正确：使用 Industry-Digital-Software-AI-Tools；各产品 Task、Memory/Costomer 和本地 API 参考目录通过 .gitkeep 例外保留目录，其余内容及自动生成的 Memory/INDEX.md 均忽略，保留本地文件。Git 排除 Tecnomatix/Tecnomatix_Engineering、NX/api-md、Catia/api-md 和 Vismockup/api_md 内的其他内容；Vismockup/api_md 才是正确路径。说明 cookbook 开放及获授权 API 的本地配置，不再保留 GitHub 发布操作说明。忽略规则不会移除已跟踪数据或 Git 历史。
- 触发：GitHub、开源、更名、Task、Costomer、gitignore、忽略。
- 证据：仓库 .gitignore、README.md 及各产品 Task / Memory/Costomer 中的 .gitkeep 文件。

## ET-10 Initialize AI Bridge config during the first environment check / 首次环境检查自动初始化 AI Bridge 配置
- Wrong: only initializing JSON during detection leaves a new user to run setup and compile the plugin manually.
- Right: when Tecnomatix is detected, envcheck automatically invokes txai setup to build missing plugin artifacts and initialize user-level config and the Task whitelist, preserving existing settings. Then show administrator deployment and restart instructions; never self-elevate or equate preparation with runtime readiness. Keep a prominent first-use reminder in both README languages, pointing to section 2.3.
- Trigger: first-time setup, txai.config.json, AI Bridge configuration.
- Evidence: tools/envcheck.ps1 and Tecnomatix/Tecnomatix-AI-Client/tools/txai.ps1 use txai-config.ps1.
- 错误：环境检测仅初始化 JSON，仍让新用户手动运行 setup 和编译插件。
- 正确：检测到 Tecnomatix 时，envcheck 自动调用 txai setup，编译缺失的插件产物、初始化用户级配置及 Task 白名单，并保留已有设置；随后提示管理员部署及重启步骤，不自行提权，不将准备完成视为运行就绪。README 中英两部分都应保留醒目的首次使用提醒，并指向第 2.3 节。
- 触发：首次配置、txai.config.json、AI Bridge 配置。
- 证据：tools/envcheck.ps1 和 Tecnomatix/Tecnomatix-AI-Client/tools/txai.ps1 使用 txai-config.ps1。

## ET-01 Chinese written via PowerShell turns into ???? / PowerShell 写中文会变成 ????
- Wrong: writing a file containing Chinese with PowerShell `-Command` or a here-string.
- Right: create a `.py` script with the `create` tool, run it with `python -X utf8`, write the file with `utf-8-sig` + CRLF, delete the script afterwards; check that the file contains no `??` after writing. Python printing Chinese also needs `-X utf8`.
- Trigger: writing Chinese into Memory, md, csv.
- 错误：用 PowerShell `-Command` 或 here-string 写含中文的文件。
- 正确：用 `create` 工具建 `.py` 脚本，`python -X utf8` 执行，写文件用 `utf-8-sig` + CRLF，用完删除脚本；写完检查文件里没有 `??`。Python 打印中文也要 `-X utf8`。
- 触发：向 Memory、md、csv 写中文。

## ET-02 PowerShell 5.1 syntax limits / PowerShell 5.1 语法限制
- Wrong: using `&&`, `||`, `head`, or the unsupported `Select-Object -SkipWhile` parameter in Windows PowerShell 5.1, or concluding Git is absent because it is not on PATH.
- Right: use PowerShell syntax and check command success; to filter output after a marker, use a boolean flag with `ForEach-Object`. Before installing Git, check PATH and the detected Visual Studio installation for bundled Git and verify it with `git --version`.
- Trigger: PowerShell syntax errors or Git unavailable on PATH.
- Evidence: Visual Studio Team Explorer can include a working Git executable without exposing it on PATH.
- 错误：在 Windows PowerShell 5.1 中使用 `&&`、`||`、`head` 或不支持的 `Select-Object -SkipWhile` 参数，或因 PATH 中没有 Git 就断定未安装。
- 正确：使用 PowerShell 语法并检查命令是否成功；按标记过滤后续输出时，使用布尔标志配合 `ForEach-Object`。安装 Git 前先检查 PATH 和已检测到的 Visual Studio 安装目录中的自带 Git，并用 `git --version` 验证。
- 触发：PowerShell 语法错误或 PATH 中找不到 Git。
- 证据：Visual Studio Team Explorer 可以附带可用的 Git 可执行文件，但未将其加入 PATH。

## ET-12 Wait for GUI exports before validating files / 校验文件前等待 GUI 导出完成
- Wrong: assuming direct invocation of a GUI executable from an interactive PowerShell terminal waits until its output files are written.
- Right: for a one-shot headless browser export, use an isolated temporary profile and `Start-Process -Wait -PassThru`; check the exit code and output timestamp before inspecting the image or cleaning up the profile. Do not stop unrelated browser processes.
- Trigger: browser screenshot or another GUI export appears to return before updating the output file.
- Evidence: explicit process waiting makes screenshot output validation occur after the browser finishes.
- 错误：认为在交互式 PowerShell 终端中直接调用 GUI 可执行程序，一定会等到输出文件写入后才返回。
- 正确：单次无界面浏览器导出使用独立临时配置和 `Start-Process -Wait -PassThru`；检查退出码及输出时间戳后再查看图片、清理配置，不终止无关浏览器进程。
- 触发：浏览器截图或其它 GUI 导出命令似乎在文件更新前已返回。
- 证据：显式等待进程可确保截图文件校验发生在浏览器完成导出之后。

## ET-03 NX runner details / NX runner 细节
- The argv of `nxrun.ps1 run` starts at index 1.
- NX may print "Fatal error" on exit; the output is already complete and can be ignored. The `vswhere.exe not recognized` build message is harmless.
- A `ugraf` process may be the user's own NX session; do not kill it.
- Do not run a broad `-Recurse` grep over the NX install directory; it hangs.
- `nxrun.ps1 run` 的 argv 从下标 1 开始。
- NX 退出时可能打印 "Fatal error"，输出已完整，可忽略。`vswhere.exe not recognized` 的构建提示无害。
- `ugraf` 进程可能是用户自己的 NX 会话，不要杀。
- 不要对 NX 安装目录做大范围 `-Recurse` grep，会卡住。

## ET-04 The gate prints a lot of output / 门禁输出很多
- Every runner call prints the Memory gate content; filter the output with `Select-String`, but first read all the matched entries in the gate.
- 每次调用 runner 都会打印 Memory 门禁内容，过滤输出用 `Select-String`，但必须先读完门禁里命中的条目。

## ET-06 Do not put inline Add-Type / P/Invoke loaders in runner scripts / runner 脚本里不要内嵌 Add-Type / P/Invoke 加载器
- Wrong: runners compiled C# with `Add-Type` (LoadLibrary / reflection loader) inside the `.ps1`; antivirus flags this as a loader and blocks the scripts. Code signing is not portable (the certificate carries a company name).
- Right: keep loader code in `tools/hosts/*.cs`; `tools/hostbuild.ps1` (`Get-RunHost`) compiles it with csc into `%LOCALAPPDATA%\Industry-Digital-Software-AI-Tools\bin` on first use (rebuilt when the source is newer) and runners call the exe. Host exit codes: 13 = skill exception / load failure, 2 = usage. Never commit the compiled exe.
- Trigger: antivirus / Defender blocks runner scripts; adding a new runner or native loading code.
- Evidence: `nxrun.ps1` / `vmrun.ps1` / `catrun.ps1` / `officerun.ps1` contain no `Add-Type`.
- 错误：runner 在 `.ps1` 内用 `Add-Type` 编译 C#（LoadLibrary / 反射加载器），杀毒软件判为加载器而拦截脚本；代码签名不可移植（证书带公司名）。
- 正确：加载器代码放在 `tools/hosts/*.cs`；`tools/hostbuild.ps1`（`Get-RunHost`）首次使用时用 csc 编译到 `%LOCALAPPDATA%\Industry-Digital-Software-AI-Tools\bin`（源码更新时重编），runner 调用该 exe。宿主退出码：13 = skill 异常 / 加载失败，2 = 用法错误。不要提交编译产物 exe。
- 触发：杀毒 / Defender 拦截 runner 脚本；新增 runner 或原生加载代码。
- 证据：`nxrun.ps1` / `vmrun.ps1` / `catrun.ps1` / `officerun.ps1` 中不再含 `Add-Type`。

## ET-05 NX stdout is block-buffered when the log is redirected / NX 日志重定向时 stdout 块缓冲
- Wrong: after `*>` redirection the log long contains only the memory gate text, wrongly judged as a failure.
- Right: NX output is flushed only when the process exits; check whether the process CPU is growing to tell whether it is running. CATIA logs are flushed progressively.
- Trigger: redirecting a long NX task to a file.
- 错误：`*>` 重定向后日志长期只有 memory gate 文本，误判为失败。
- 正确：NX 输出在进程退出时才刷新；看进程 CPU 是否增长判断是否在跑。CATIA 日志会逐步刷新。
- 触发：NX 长任务重定向到文件。

## ET-07 Never put shared config under a product's Task/ folder / 共享配置文件不要放在产品的 Task/ 目录下
- Wrong: put `Directory.Build.targets` (or any shared config / helper) inside `<Product>/Task/`; `Task/` is user output and is deleted on a new user's machine, so the config disappears.
- Right: put shared config one level up in `<Product>/` and scope it to skill projects by path condition, or skip it when the runner already covers the case. `Task/` holds only skill outputs.
- Trigger: adding any non-skill file (config, props, targets, helper) near the `Task/` folders.
- Evidence: a `Directory.Build.targets` that only improved the missing-`TxInstallDir` error was moved to `Tecnomatix/`, then deleted as unnecessary because `txai.ps1` always passes `TxInstallDir`.
- 错误：把 `Directory.Build.targets`（或任何共享配置 / 辅助文件）放进 `<产品>/Task/`；`Task/` 是用户产物目录，新用户那里会被删除，配置随之丢失。
- 正确：共享配置放在上一级 `<产品>/`，用路径条件限定只作用于 skill 项目；runner 已覆盖该情形时就不要加。`Task/` 只放 skill 产物。
- 触发：在 `Task/` 附近新增任何非 skill 文件（配置、props、targets、辅助脚本）。
- 证据：一个仅用于改善缺少 `TxInstallDir` 报错的 `Directory.Build.targets` 先被移到 `Tecnomatix/`，后因 `txai.ps1` 总会传入 `TxInstallDir` 而判定多余并删除。

## ET-08 No hardcoded install paths or folder-name versions; detect via tools/envdetect.ps1 / 不要硬编码安装路径或用文件夹名取版本，统一用 tools/envdetect.ps1 探测
- Wrong: `C:\Program Files\...` literals, versions parsed from folder names (`Tecnomatix_2502`), a fixed .NET 4.8 targeting-pack path, a user path or install path as a default in skill source (`.cs` / `.cpp`), a temp `.bat` + `cmd /c`, or a nested `powershell -ExecutionPolicy Bypass` call. These break on other drives / locales / versions and look like malware to antivirus.
- Right: runners dot-source `tools/envdetect.ps1` (`Find-NxInstalls`, `Find-TxInstalls`, `Find-VcRoot`, `Import-VcEnvironment`, `Get-Net48Pack`, `Find-Csc`): use env vars (`UGII_BASE_DIR`, `TX_INSTALL_DIR`), all fixed drives and the file ProductVersion; pick the newest, allow an override. Skill sources derive paths at runtime (args, `Path.GetTempPath()`, `Environment.GetFolderPath`, the loaded assembly location). Call other scripts directly with `&`. Docs use placeholders (`<Root>`, `<RepoRoot>`), and `.ps1` stays ASCII-only.
- Trigger: writing or editing a runner / setup / build script, or a skill with a default path.
- Evidence: `envcheck.ps1`, `nxrun.ps1`, `txai.ps1` and the Task defaults were migrated; grep for `C:\\Program` in `*.ps1` returns only the helper's comments.
- 错误：写死 `C:\Program Files\...`、从文件夹名解析版本（`Tecnomatix_2502`）、固定的 .NET 4.8 targeting pack 路径、在 skill 源码（`.cs` / `.cpp`）里把用户路径或安装路径当默认值、临时 `.bat` + `cmd /c`、嵌套 `powershell -ExecutionPolicy Bypass` 调用。这些在其它盘符 / 语言 / 版本下会失败，也容易被杀毒当成恶意软件。
- 正确：runner 点源 `tools/envdetect.ps1`（`Find-NxInstalls`、`Find-TxInstalls`、`Find-VcRoot`、`Import-VcEnvironment`、`Get-Net48Pack`、`Find-Csc`）：用环境变量（`UGII_BASE_DIR`、`TX_INSTALL_DIR`）、所有固定盘和文件 ProductVersion，取最新版并允许覆盖。skill 源码在运行时推导路径（参数、`Path.GetTempPath()`、`Environment.GetFolderPath`、已加载程序集位置）。调用其它脚本直接用 `&`。文档用占位符（`<Root>`、`<RepoRoot>`），`.ps1` 保持纯 ASCII。
- 触发：编写或修改 runner / setup / build 脚本，或带默认路径的 skill。
- 证据：`envcheck.ps1`、`nxrun.ps1`、`txai.ps1` 与 Task 默认值已迁移；在 `*.ps1` 中 grep `C:\\Program` 只剩辅助脚本的注释。

## ET-09 Updating a PPT template: check the real extension, edit a copy with python-pptx, dump Chinese via a UTF-8 file / 按模板更新 PPT：先确认真实扩展名，用 python-pptx 改副本，中文用 UTF-8 文件导出
- Wrong: assuming the path the user typed (`.ppt`) is the real file; reading Chinese from redirected terminal output (garbled); editing the template in place; adding text boxes before knowing the template's shape ids and multi-run structure.
- Right: list the folder to find the real file (usually `.pptx`); `pip install python-pptx` if missing; copy the template to a new name (abort if it exists) and edit by `shape_id`, keeping the first run's formatting and deleting extra runs; dump shapes/runs to a UTF-8 file from Python and read it with the file reader; remove template hint text and "Guiding Questions" labels; mark assumptions (ticked options, team/date) to the user. The model cannot view images, so state that visuals were verified only structurally.
- Trigger: user asks to update / fill a PPT from a template.
- Evidence: a 6-slide hackathon template was filled this way; the dump showed no leftover `[`, `Guiding`, `MM.DD` and no out-of-bounds shapes.
- 错误：以为用户输入的路径（`.ppt`）就是真实文件；从重定向的终端输出读中文（乱码）；直接改模板原文件；没摸清模板形状 id 与多 run 结构就加文本框。
- 正确：先列目录找真实文件（通常是 `.pptx`）；缺 `python-pptx` 就安装；把模板复制成新文件名（已存在则中止），按 `shape_id` 修改，保留第一个 run 的格式并删除多余 run；用 Python 把形状 / run 导出到 UTF-8 文件再用文件读取工具查看；删除模板提示文字和 “Guiding Questions” 标签；向用户说明假设（勾选项、团队 / 日期）。模型看不到图片，须说明视觉效果仅做了结构核对。
- 触发：用户要求按模板更新 / 填写 PPT。
- 证据：6 页黑客松模板按此方式填写；导出核对无残留 `[`、`Guiding`、`MM.DD`，无越界形状。
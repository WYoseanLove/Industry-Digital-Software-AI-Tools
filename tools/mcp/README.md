# Local MCP for Claude Desktop

This Windows stdio MCP server lets Claude Desktop read this checkout, create skill source/docs in product `Task` directories, and call the **existing** PowerShell runners. It does not change those runners, COM automation, NX hosts, or the Tecnomatix AI Bridge. It does not install or license manufacturing software.

## Installation

Requirements: Node.js 20+ (LTS recommended), npm, 64-bit Windows PowerShell, and the normal repository prerequisites. Dependencies are pinned in `package-lock.json`. From PowerShell, replace the placeholders with absolute paths:

```powershell
Set-Location '<RepoRoot>\tools\mcp'
& '<NpmCmdAbsolutePath>' ci --ignore-scripts --no-audit --no-fund
& '<NodeExeAbsolutePath>' '<RepoRoot>\tools\mcp\server.mjs' --print-config
```

The last command prints a valid JSON configuration fragment using the actual Node executable and checkout paths. It does **not** modify Claude's settings or start any software. No globally installed MCP package, HTTP port, API key, or separate manually started server is required.

## Claude Desktop configuration

1. Back up `%APPDATA%\Claude\claude_desktop_config.json`.
2. Run `--print-config` above.
3. Merge its `mcpServers` object into the existing top-level JSON object. Preserve `preferences`, `coworkUserFilesPath`, and other servers. Do not replace the entire file or create duplicate `mcpServers` keys.
4. Save valid JSON (no comments or trailing commas), fully quit Claude Desktop, then restart it.
5. In Settings > Developer, check that `industry-digital-software` connects. In a new conversation, request `repository_context`, then `repository_list`. Six tools should be available.

Claude launches Node directly and communicates through stdin/stdout. Node locates the checkout from the server file, not Claude's working directory. No `cwd` setting is needed. Move the checkout or Node installation: regenerate the fragment and restart Claude.

The MCP layer supports filtered Desktop launch environments: before starting the runner PowerShell process, it queries the adapter's environment-bootstrap mode to restore missing Windows Machine/User settings (User takes precedence), derive missing Program Files/profile/ProgramData directories from Windows special folders, and merge persistent PATH and PATHEXT entries after the caller's existing entries. Preparing a complete PATHEXT before process startup avoids stale executable-discovery caches; a nonempty but incomplete value such as `.CPL` also needs repair. It preserves nonempty scalar overrides and caller path/extension entries, and reports recovery without printing values; environment JSON is exchanged only between local processes, never as a tool result. This changes only child-process settings, never Windows persistent settings or the existing runners.

After changing user environment variables, fully restart Claude so explicit inherited values are refreshed. NX still requires valid `UGII_BASE_DIR` and `UGII_ROOT_DIR`; license variables must remain configured as required by NX. Recovery cannot supply settings that were never configured or install missing tools. If an explicit Desktop override is wrong, correct or remove that server's `env` entry. Do not invent paths or licenses.

## Tools and workflow

| Tool | Purpose |
|---|---|
| `repository_context` | Read startup rules, README and Memory; does not run software. |
| `repository_read` | Page through supported text files inside the checkout. |
| `repository_list` | List a directory with pagination. |
| `skill_write` | Create source/Markdown only under a product's `Task/<Skill>`; overwrite requires approval. |
| `runner_start` | Start `environment`, `setup`, `ping` (Tecnomatix only), `build`, or `run`. |
| `runner_status` | Poll a job and retrieve its output pages and actual exit code. |

At the start of every conversation, explicitly ask Claude to call `repository_context` and follow the repository workflow; do not assume Desktop automatically discovers the repository's agent entry files. Read relevant product manuals and Memory topics, then:

1. Call `runner_start` with `command: "environment"` and a meaningful `taskHint`.
2. Poll `runner_status` until completed/failed, and read all pages, including the Memory gate. Environment detection can perform the existing Tecnomatix local preparation; it is not a pure read-only operation.
3. Only use products reported `USABLE`. Run the selected product's `setup` and require exit 0.
4. Read exact API references before generating source. Use `skill_write` with the correct product extension: NX `.cpp`; other products `.cs`. Use the skill name as the primary source filename (e.g. `Example.cpp`). Skill Markdown must be English first, then `---`, then Chinese.
5. Confirm software/API authorization, then `build` the skill. Wait for exit 0.
6. Obtain user approval for the specific run, selection scope, modifications and output/overwrite effects; then `run`. Every MCP run requires approval, even a claimed read-only skill.

`runner_start` requires `taskHint`; product names are `NX`, `Office`, `Catia`, `Vismockup`, `Tecnomatix`. `skill` is required for build/run. NX/COM runners receive `args` as a string array; Tecnomatix receives `argsJson` as a JSON object. These argument forms are not interchangeable. `authorized: true` is required for build/run; `userConfirmed: true` for run; `overwriteConfirmed: true` only when overwriting a skill file.

**These flags are caller assertions, not independent proof of permission or a human approval dialog.** Claude must not fabricate them; keep action-tool approvals enabled in Desktop. Compiled skills are executable code running with your Windows account and software privileges, not sandboxed programs.

Jobs avoid holding an MCP request open during long builds/runs. The default runner timeout is 120 seconds; `timeoutSeconds` supports 10–3600 seconds. A job ID means only "started". Success requires `status: "completed"` **and** `exitCode: 0`. Nonzero exits and process failures are explicitly reported. Read `runner_status.output` until `nextOffset` reaches `outputLength`, continuing to poll while running.

Only one runner or skill write can be active at a time. Setup/build records and up to 20 recent jobs live in this MCP process and reset on restart. Rebuild if source or DLL content changes. Existing DLLs without a successful build in this MCP session cannot run. A timeout, output above 4 MiB, or MCP disconnection stops the runner process tree; interruption can leave partial files or software changes, so inspect results before retrying.

## Execution and access boundaries

- The ASCII-only [PowerShell adapter](invoke-runner.ps1) passes structured arguments to the existing absolute runner paths in a fresh PowerShell process. It preserves argument boundaries, UTF-8 output, `MFG_TASK_HINT`, Memory gates, runner exit codes and the existing software hosts/Bridge.
- No arbitrary shell tool, automatic elevation, new DLL loader, or software-install command is exposed. Existing direct runner use outside MCP remains unchanged.
- Text reads stay inside the checkout; `.git`, dependencies and build-cache folders are excluded. Parent traversal, absolute paths, alternate streams and junction escapes are rejected. Skill writes cannot edit repository rules, runners or arbitrary external files.
- This is not an OS sandbox. Runner skill arguments can refer to external input/output files as before; obtain approval for the exact targets. Concurrent edits outside MCP are not locked.
- Local MCP does not make Claude's model local. Tool results may be sent to Claude's service. Do not return secrets or proprietary/customer material without authorization.

## Verification and troubleshooting

```powershell
Set-Location '<RepoRoot>\tools\mcp'
& '<NpmCmdAbsolutePath>' test
```

Tests cover stdio handshake, tools, paths/junctions, source-write limits, setup/build/run gates, approval flags, output pagination, timeouts, cancellation, filtered-environment recovery and PowerShell argument/JSON transport. Optional live tests call the existing environment detection and NX setup with both complete and minimal MCP launch environments (no model edits):

```powershell
$env:MFG_MCP_LIVE_TEST = '1'
& '<NpmCmdAbsolutePath>' test
Remove-Item Env:\MFG_MCP_LIVE_TEST
```

- Server missing: verify JSON nesting and actual executable/server paths, run `npm ci`, then fully restart Claude.
- `ERR_MODULE_NOT_FOUND`: dependencies are missing; run `npm ci` in this directory.
- No response: normal server mode waits for MCP input; running it manually is not a connectivity test. Use Claude or the protocol tests.
- Setup fails: read the full runner output; do not bypass the failure. Tecnomatix needs an open Study and a running AI Bridge; MCP cannot replace its deployment/activation.
- Check `%APPDATA%\Claude\logs\mcp.log` and `mcp-server-industry-digital-software.log`. Normal MCP stdout contains protocol messages only; runner output is returned through job status.

---

# Claude Desktop 本地 MCP

此 Windows stdio MCP 服务让 Claude Desktop 读取当前仓库、在各产品 `Task` 目录创建技能源码/文档，并调用**现有** PowerShell runner。不修改 runner、COM 自动化、NX 宿主或 Tecnomatix AI Bridge，也不安装或授权制造软件。

## 安装

要求：Node.js 20+（建议 LTS）、npm、64 位 Windows PowerShell，以及仓库原有前提条件。依赖版本锁定在 `package-lock.json` 中。在 PowerShell 中运行，将占位符替换为绝对路径：

```powershell
Set-Location '<RepoRoot>\tools\mcp'
& '<NpmCmdAbsolutePath>' ci --ignore-scripts --no-audit --no-fund
& '<NodeExeAbsolutePath>' '<RepoRoot>\tools\mcp\server.mjs' --print-config
```

最后一条命令使用实际 Node 可执行文件和仓库路径输出有效 JSON 配置片段，**不会**修改 Claude 设置或启动软件。不需要全局安装 MCP 包、HTTP 端口、API key，也不需要手动另起服务。

## Claude Desktop 配置

1. 备份 `%APPDATA%\Claude\claude_desktop_config.json`。
2. 执行上述 `--print-config` 命令。
3. 将输出的 `mcpServers` 对象合并到现有 JSON 顶层，保留 `preferences`、`coworkUserFilesPath` 和其它服务。不要整份替换，也不要出现重复的 `mcpServers` 键。
4. 保存有效 JSON（无注释、无末尾多余逗号），完全退出 Claude Desktop 后重新启动。
5. 在 Settings > Developer 检查 `industry-digital-software` 已连接。在新对话中请求 `repository_context`，再请求 `repository_list`，应出现六个工具。

Claude 直接启动 Node，通过 stdin/stdout 通讯。Node 根据服务文件定位仓库，不依赖 Claude 的工作目录，无需 `cwd` 配置。移动仓库或 Node 安装后，重新生成片段并重启 Claude。

MCP 层支持经过过滤的 Desktop 启动环境：启动 runner PowerShell 进程前，通过适配器的环境准备模式恢复缺失的 Windows Machine/User 设置（User 优先），从 Windows 特殊目录恢复缺失的 Program Files/个人目录/ProgramData 变量，并将持久 PATH 和 PATHEXT 条目合并到调用方现有条目之后。进程启动前准备完整 PATHEXT，避免可执行命令发现缓存过期；非空但仅含 `.CPL` 等残缺值也要修复。保留非空标量覆盖值及调用方路径/扩展名条目，报告恢复但不打印变量值；环境 JSON 仅在本地进程之间传输，不作为工具结果返回。仅改变子进程设置，不修改 Windows 持久设置或原有 runner。

修改用户环境变量后，完全重启 Claude，刷新显式继承的值。NX 仍要求有效的 `UGII_BASE_DIR`、`UGII_ROOT_DIR`，许可证变量保持 NX 原有配置。恢复无法补出从未配置的设置，也不会安装工具。如果 Desktop 显式覆盖值错误，修正或移除该服务的对应 `env` 条目，不编造路径或许可证。

## 工具与流程

| Tool | Purpose |
|---|---|
| `repository_context` | Read startup rules, README and Memory; does not run software. |
| `repository_read` | Page through supported text files inside the checkout. |
| `repository_list` | List a directory with pagination. |
| `skill_write` | Create source/Markdown only under a product's `Task/<Skill>`; overwrite requires approval. |
| `runner_start` | Start `environment`, `setup`, `ping` (Tecnomatix only), `build`, or `run`. |
| `runner_status` | Poll a job and retrieve its output pages and actual exit code. |

每次对话开始时，明确要求 Claude 调用 `repository_context` 并遵循仓库流程，不假设 Desktop 自动发现仓库 Agent 入口文件。读取相关产品手册和 Memory 主题后：

1. 调用 `runner_start`，设置 `command: "environment"` 和有意义的 `taskHint`。
2. 轮询 `runner_status` 至完成/失败，读取全部分页，包含 Memory 门禁。环境检测可能执行原有 Tecnomatix 本地准备，不是纯只读操作。
3. 仅使用检测为 `USABLE` 的产品。执行目标产品 `setup`，要求退出码 0。
4. 生成源码前核对精确 API 参考。通过 `skill_write` 写对应扩展名：NX `.cpp`，其它产品 `.cs`。主源码文件名使用技能名（如 `Example.cpp`）。技能 Markdown 英文在前、`---` 分隔、中文在后。
5. 确认软件/API 授权后 `build`，等待退出码 0。
6. 获得用户对具体运行、选择范围、修改和输出/覆盖影响的批准后再 `run`。所有 MCP run 都要求批准，即使声称技能只读。

`runner_start` 必须提供 `taskHint`；产品名称为 `NX`、`Office`、`Catia`、`Vismockup`、`Tecnomatix`。build/run 必须提供 `skill`。NX/COM runner 的参数用字符串数组 `args`；Tecnomatix 用 JSON 对象 `argsJson`，两种形式不能混用。build/run 要求 `authorized: true`，run 要求 `userConfirmed: true`；只有获准覆盖技能文件时才设置 `overwriteConfirmed: true`。

**这些标志是调用方声明，并非独立权限证明或人工确认对话框。** Claude 不得编造标志；在 Desktop 保持操作工具审批开启。编译后的技能是以你的 Windows 账户和软件权限运行的可执行代码，不是沙箱程序。

任务机制避免长时间编译/运行占住 MCP 请求。runner 默认超时 120 秒，`timeoutSeconds` 支持 10–3600 秒。任务 ID 只表示“已启动”；成功必须同时满足 `status: "completed"` 和 `exitCode: 0`。非零退出码及进程错误会明确报告。读取 `runner_status.output` 至 `nextOffset` 达到 `outputLength`；任务仍运行时继续轮询。

同一时间仅允许一个 runner 或技能写入。setup/build 记录和最多 20 个近期任务保存在 MCP 进程中，重启清空。源码或 DLL 内容变化后要重编；没有在本次 MCP 会话成功编译的旧 DLL 不能运行。超时、输出超过 4 MiB 或 MCP 断开会停止 runner 进程树；中断可能留下部分文件或软件修改，重试前检查结果。

## 执行与访问边界

- 纯 ASCII 的 [PowerShell 适配器](invoke-runner.ps1) 在新 PowerShell 进程中，将结构化参数传给现有 runner 绝对路径；保持参数边界、UTF-8 输出、`MFG_TASK_HINT`、Memory 门禁、runner 退出码及原有软件宿主/Bridge。
- 不开放任意 shell 工具、自动提权、新 DLL 加载器或软件安装命令。MCP 之外直接使用 runner 的方式保持不变。
- 文本读取限当前仓库，排除 `.git`、依赖和编译缓存目录；拒绝父目录跳转、绝对路径、备用数据流和 junction 越界。技能写入不能修改仓库规则、runner 或任意外部文件。
- 这不是操作系统沙箱。runner 技能参数仍可像原来一样引用外部输入/输出文件，必须对具体目标获准。MCP 不锁定外部并发编辑。
- 本地 MCP 不会使 Claude 模型本地化；工具结果可能发送到 Claude 服务。未经授权不得返回秘密或专有/客户资料。

## 验证与排错

```powershell
Set-Location '<RepoRoot>\tools\mcp'
& '<NpmCmdAbsolutePath>' test
```

测试覆盖 stdio 握手、工具、路径/junction、源码写入限制、setup/build/run 门禁、确认标志、输出分页、超时、取消、过滤环境恢复及 PowerShell 参数/JSON 传输。可选真实测试分别用完整和最小 MCP 启动环境调用原有环境检测和 NX setup，不修改模型：

```powershell
$env:MFG_MCP_LIVE_TEST = '1'
& '<NpmCmdAbsolutePath>' test
Remove-Item Env:\MFG_MCP_LIVE_TEST
```

- 看不到服务：检查 JSON 层级和实际可执行文件/服务路径，执行 `npm ci`，再完全重启 Claude。
- `ERR_MODULE_NOT_FOUND`：依赖缺失，在此目录执行 `npm ci`。
- 无回应：正常服务模式等待 MCP 输入，手动启动不能证明通讯成功；使用 Claude 或协议测试。
- setup 失败：读完 runner 输出，不绕过错误。Tecnomatix 要求打开 Study 并启动 AI Bridge，MCP 不能替代部署/激活。
- 查看 `%APPDATA%\Claude\logs\mcp.log` 和 `mcp-server-industry-digital-software.log`。正常 MCP stdout 仅含协议消息，runner 输出通过任务状态返回。

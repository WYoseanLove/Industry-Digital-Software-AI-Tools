# Tecnomatix-AI-Client

In-process Process Simulate add-in. It listens on a local named pipe, loads task DLLs the agent asks for, runs them on the PS UI thread and returns the result as JSON.

```
Agent / MCP server --(named pipe, JSON lines)--> TxAi.Addin (inside PS) --> task DLL --> result
```

## Projects

| Project | Purpose |
|---|---|
| `src/TxAi.Contracts` | `ITxAiTask`, `TxAiContext`, `TxAiResult`. Referenced by the add-in and by every task DLL. |
| `src/TxAi.Addin` | `TxButtonCommand` host, pipe server, UI-thread dispatcher, task loader. |
| `src/TxAi.Tasks.Samples` | Sample task: `ListRobotsTask`. |
| `tools/TxAi.TestClient` | Console client for manual testing. |

Targets .NET Framework 4.8, C# 5. References the Process Simulate assemblies from the folder given by `-p:TxInstallDir=<PS install>\eMPower\` (required; `txai.ps1` detects and passes it automatically).

## Build and deploy

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <RepoRoot>\tools\envcheck.ps1
```

The Agent runs this environment check automatically on first use. When Tecnomatix is detected, it invokes `txai.ps1 setup` to build missing add-in / contracts DLLs and initialize the user config without elevation. Complete staged DLLs are reused. Only after preparation succeeds does the user perform the administrator deployment below, using the actual copy command printed by setup. Missing prerequisites or build errors must be resolved first; the Agent never self-elevates.

1. Copy `deploy\TxAi\` (the add-in only, admin needed once) to `<PS install>\eMPower\DotNetCommands\`.
2. Task DLLs are NOT installed into Program Files. They live in `Tecnomatix\Task\` in this repo (written by `package.ps1` for the samples; new skill DLLs are generated there on demand). The agent sends the full DLL path in `run_dll`.
3. Initialize the config **before first starting AI Bridge**. The first root `tools\envcheck.ps1` call automatically creates `%LOCALAPPDATA%\TxAi\txai.config.json` when Tecnomatix is detected; `txai.ps1 setup` uses the same initializer. No administrator rights or manual JSON editing are needed. Missing defaults are filled and this checkout's `Tecnomatix\Task` absolute path is added to the whitelist. Existing settings and whitelist entries are preserved; unchanged configs are not rewritten. Invalid JSON is reported without overwriting the file. The following JSON is an example, not a file to copy (`<RepoRoot>` is a placeholder):

```json
{ "PipeName": "TxAiClient", "AllowedDirectories": ["<RepoRoot>\\Tecnomatix\\Task"], "DefaultTimeoutMs": 120000, "AutoStart": false }
```

4. Start Process Simulate, open a Study and click "AI Bridge" (category "AI"). If the config was initialized or changed while Process Simulate was running, save your work and restart it first. Then verify through the runner:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <RepoRoot>\Tecnomatix\Tecnomatix-AI-Client\tools\txai.ps1 setup
powershell -NoProfile -ExecutionPolicy Bypass -File <RepoRoot>\Tecnomatix\Tecnomatix-AI-Client\tools\txai.ps1 ping
```

`setup` initializes the config before testing the connection. Exit 11 means the Bridge is not running, not that config generation failed; start the Bridge and run `setup` again. Exit 0 confirms the environment and connection.

With no `AllowedDirectories`, `run_dll` refuses every path.

## Protocol

One JSON object per line.

```json
{"id":"1","method":"run_dll","params":{"path":"C:\\...\\Tecnomatix\\Task\\TxAi.Tasks.Samples.dll","args":{"type":"ListRobotsTask"},"timeoutMs":60000}}
{"id":"1","ok":true,"result":{"count":2,"robots":[...]},"error":null,"logs":["Found 2 robot(s)."],"durationMs":35}
```

Methods: `ping`, `get_status`, `run_dll`.

## Writing a task

Reference `TxAi.Contracts` and `Tecnomatix.Engineering` (both `Private=false`), implement `ITxAiTask.Run`. It runs on the UI thread; poll `context.Cancellation` in long loops. DLLs are loaded from bytes, so they can be rebuilt without restarting PS.

## Limits

- Task DLLs run with full PS privileges; the directory whitelist is the only gate.
- A task that blocks the UI thread blocks PS; on timeout the caller gets an error but the task is not aborted.
- Assemblies loaded from bytes cannot be unloaded until PS exits.


---

# Tecnomatix-AI-Client（中文）

进程内的 Process Simulate 插件。它监听本地命名管道，加载 agent 请求的任务 DLL，在 PS UI 线程上运行，并以 JSON 返回结果。

```
Agent / MCP server --(named pipe, JSON lines)--> TxAi.Addin (inside PS) --> task DLL --> result
```

## 项目

| Project | 用途 |
|---|---|
| `src/TxAi.Contracts` | `ITxAiTask`、`TxAiContext`、`TxAiResult`。插件和每个任务 DLL 都引用它。 |
| `src/TxAi.Addin` | `TxButtonCommand` 宿主、管道服务器、UI 线程调度器、任务加载器。 |
| `src/TxAi.Tasks.Samples` | 示例任务：`ListRobotsTask`。 |
| `tools/TxAi.TestClient` | 用于手工测试的控制台客户端。 |

目标 .NET Framework 4.8、C# 5。引用 `-p:TxInstallDir=<PS 安装目录>\eMPower\` 指定文件夹下的 Process Simulate 程序集（必填；`txai.ps1` 会自动检测并传入）。

## 构建与部署

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <RepoRoot>\tools\envcheck.ps1
```

首次使用时 Agent 自动运行此环境检查。检测到 Tecnomatix 后，自动调用 `txai.ps1 setup`，无需提权即可编译缺失的插件 / contracts DLL 并初始化用户配置；已有完整 DLL 会复用。准备成功后，用户才按下方步骤完成管理员部署，使用 setup 输出的实际复制命令。缺少编译环境或编译报错时须先解决；Agent 不自行提权。

1. 把 `deploy\TxAi\`（仅插件，需管理员权限，一次即可）复制到 `<PS install>\eMPower\DotNetCommands\`。
2. 任务 DLL 不安装到 Program Files。它们位于本仓库的 `Tecnomatix\Task\`（示例由 `package.ps1` 写入；新的 skill DLL 按需在此生成）。agent 在 `run_dll` 中发送完整的 DLL 路径。
3. **首次启动 AI Bridge 前先初始化配置。** 根目录 `tools\envcheck.ps1` 首次检测到 Tecnomatix 时，会自动创建 `%LOCALAPPDATA%\TxAi\txai.config.json`；`txai.ps1 setup` 使用相同的初始化逻辑。无需管理员权限或手工编辑 JSON，缺失默认项会自动补齐，并将当前仓库 `Tecnomatix\Task` 的绝对路径加入白名单。已有设置和白名单会保留，配置无变化时不重写；JSON 损坏时报告错误而不覆盖。下面的 JSON 仅供说明，无需复制创建文件（`<RepoRoot>` 是占位符）：

```json
{ "PipeName": "TxAiClient", "AllowedDirectories": ["<RepoRoot>\\Tecnomatix\\Task"], "DefaultTimeoutMs": 120000, "AutoStart": false }
```

4. 启动 Process Simulate，打开 Study 并点击 "AI Bridge"（类别 "AI"）。如果初始化或修改配置时 Process Simulate 已运行，请先保存工作并重启。随后通过 runner 验证：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <RepoRoot>\Tecnomatix\Tecnomatix-AI-Client\tools\txai.ps1 setup
powershell -NoProfile -ExecutionPolicy Bypass -File <RepoRoot>\Tecnomatix\Tecnomatix-AI-Client\tools\txai.ps1 ping
```

`setup` 先初始化配置，再检测连接。退出码 11 表示 Bridge 未启动，不代表配置生成失败；启动 Bridge 后重新运行 `setup`。退出码 0 才表示环境和连接均通过。

未配置 `AllowedDirectories` 时，`run_dll` 会拒绝所有路径。

## 协议

每行一个 JSON 对象。

```json
{"id":"1","method":"run_dll","params":{"path":"C:\\...\\Tecnomatix\\Task\\TxAi.Tasks.Samples.dll","args":{"type":"ListRobotsTask"},"timeoutMs":60000}}
{"id":"1","ok":true,"result":{"count":2,"robots":[...]},"error":null,"logs":["Found 2 robot(s)."],"durationMs":35}
```

方法：`ping`、`get_status`、`run_dll`。

## 编写任务

引用 `TxAi.Contracts` 和 `Tecnomatix.Engineering`（两者均为 `Private=false`），实现 `ITxAiTask.Run`。它在 UI 线程上运行；长循环中请轮询 `context.Cancellation`。DLL 以字节方式加载，因此可以在不重启 PS 的情况下重新编译。

## 限制

- 任务 DLL 以 PS 的完整权限运行；目录白名单是唯一的闸门。
- 阻塞 UI 线程的任务会阻塞 PS；超时时调用方会收到错误，但任务不会被中止。
- 以字节方式加载的程序集在 PS 退出前无法卸载。
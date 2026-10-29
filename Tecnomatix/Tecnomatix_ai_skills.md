# Tecnomatix AI Skills — Agent Handbook

> Bilingual: English first, Chinese below the first `---` / 中文见下方。

This file guides the Agent to generate C# skill DLLs from user requirements, execute them through the **AI Bridge** (a plugin inside Process Simulate), and return the results to the user.

`<TxRoot>` = the directory of this file (`...\Industry-Digital-Software-AI-Tools\Tecnomatix`).

## 1. Role (System Prompt)

> You are an experienced simulation engineer, expert in the business and operation of Tecnomatix Process Simulate; you are also a developer fluent in C#, very proficient in Process Simulate customization (the `Tecnomatix.Engineering` .NET API).
> You first understand the user's process intent, then design a reusable skill, write code that compiles and runs safely inside PS, and report execution results honestly.

## 2. Architecture

```
Agent --(generate C# + dotnet build)--> <TxRoot>\Task\<Skill>\<Skill>.dll
Agent --(named pipe \\.\pipe\TxAiClient, run_dll + absolute DLL path)--> AI Bridge (inside the PS process, runs on the UI thread)
Agent <--(JSON: ok / result / error / logs / durationMs)-- AI Bridge
```

- Only the AI Bridge plugin (`TxAi.Addin.dll`, `TxAi.Contracts.dll`) is installed in `<PS>\eMPower\DotNetCommands\` (requires administrator, one time).
- Skill DLLs are placed in `<TxRoot>\Task\`, need no administrator rights, and are allowed by the configured whitelist.
- DLLs are loaded as bytes and do not lock the file, so recompiling does not require restarting PS (but an old assembly already loaded in the same process is not unloaded; after changing code, use a new class name or restart PS to make sure the new version is executed).

## 3. Mandatory entry point: `txai.ps1` (must be used)

`<AIC>` = `<TxRoot>\Tecnomatix-AI-Client`. **Environment detection, build and run must go through the script below only; never hand-write `dotnet build`, a pipe client or any other workaround.** On every call the script first performs environment checks (PS installation, dotnet and the net48 targeting pack, `TxAi.Contracts.dll`, config file and whitelist, whether the plugin is installed); if they do not pass, it does not continue.

```powershell
$TX = "powershell -NoProfile -ExecutionPolicy Bypass -File <AIC>\tools\txai.ps1"
& powershell -NoProfile -ExecutionPolicy Bypass -File <AIC>\tools\txai.ps1 setup                  # 环境检测 + 自动配置
& powershell -NoProfile -ExecutionPolicy Bypass -File <AIC>\tools\txai.ps1 ping                   # 检查 AI Bridge
& powershell -NoProfile -ExecutionPolicy Bypass -File <AIC>\tools\txai.ps1 build <Skill>          # 编译 <TxRoot>\Task\<Skill>\
& powershell -NoProfile -ExecutionPolicy Bypass -File <AIC>\tools\txai.ps1 run <Skill> -ArgsJson '{"key":"value"}' [-TimeoutMs 120000]
```

(Comments: `setup` = environment detection + auto configuration; `ping` = check the AI Bridge; `build` = compile `<TxRoot>\Task\<Skill>\`.)

### Mandatory rules

The root `envcheck.ps1` automatically invokes `txai.ps1 setup` when Tecnomatix is detected: missing add-in / contracts DLLs are built and the user config is initialized before administrator deployment instructions are printed. Complete staged DLLs are reused. Preparation does not require the Bridge to be running, but setup still exits 10 until deployment is complete, or 11 until the Bridge is started; only exit 0 permits automation.

1. **The first time a Tecnomatix automation request is handled in a session, run `setup` first**; also make sure `setup` has passed in this session before generating each new skill.
2. Only `build` may compile and only `run` may execute; never execute `run` after a failed `build` (exit code 12).
3. Do not try to elevate; steps that need administrator (copying the plugin to `DotNetCommands`) are only shown to the user.

### Exit code handling

| Exit code | Meaning | Agent action |
|---|---|---|
| 0 | Success | Continue / report the result |
| 10 | Environment not ready | Tell the user the `[X]` items printed by the script verbatim and **stop**; re-run `setup` after the user fixes them |
| 11 | AI Bridge not running | Ask the user to open a Study in Process Simulate and click "AI Bridge" under the "AI" category to start it; `ping` after confirmation |
| 12 | Build failed | Fix the code per the errors and `build` again until it succeeds |
| 13 | Skill execution failed | Read `error` / `logs`, fix, then `build` + `run` again; if it still fails after several rounds, report honestly |
| 2 | Invalid skill name | Change to a PascalCase English name |

The config file `%LOCALAPPDATA%\TxAi\txai.config.json` is read when the plugin starts: if `setup` reports that the config was updated, the user must restart Process Simulate.

## 4. Protocol (reference)

Named pipe `\\.\pipe\TxAiClient`, one JSON per line. Request `{"id","method","params"}`; methods `ping`, `get_status`, `run_dll`. Response `{id, ok, result, error, logs, durationMs}`. The `path` of `run_dll` must be an absolute `.dll` path under `AllowedDirectories`; `args.type` specifies the class name when the DLL contains several `ITxAiTask`; a timeout only stops waiting and **does not abort** a task already running inside PS.

## 5. Workflow

1. **Environment**: run `txai.ps1 setup`; if non-zero, handle per the exit code table and do not continue.
2. **Understand the request**: from a simulation engineer's viewpoint, confirm the objects (Study, robot, operation, weld points, etc.), the expected output, and whether data will be **modified**. Clearly distinguish read-only from modifying; confirm with the user before running modifying tasks, and if needed do a read-only precheck first (the skill provides a `dryRun` argument).
3. **Extract a generic skill**: abstract the request into a reusable, parameterized capability; it may be split into several steps (several skills or several task classes in one DLL); do not hard-code specific object names, pass them through `args`.
4. **Naming and reuse**: name skills in English PascalCase verb-object form (e.g. `ListRobots`, `ExportWeldPoints`). First check whether `<TxRoot>\Task\<Skill>\` already has a reusable skill (read its `<Skill>.md`); reuse or upgrade it if so.
5. **Look things up before writing code** (mandatory):
   - First read `<TxRoot>\cookbook-md\INDEX.md` and pick 1–4 best-matching cookbook files to read.
   - Use `<TxRoot>\Tecnomatix_Engineering\types.tsv` to look up types, then read `types\<Namespace>\<Type>.md` to verify the **exact signatures**; do not write APIs from memory.
   - Code constraints: .NET Framework 4.8 / **C# 5** (no string interpolation, no `?.`, no `nameof`; use `string.Format`); rotation / joint angles use **radians**; all PS APIs are called on the UI thread (the Bridge guarantees it; do not start your own threads to operate PS objects); poll `context.Cancellation` in long loops; for null objects and exceptions return `TxAiResult.Fail(...)`, do not throw unhandled exceptions.
6. **Create the files** (`txai.ps1 build` generates the csproj from a template when it is missing; the `.cs` and `.md` are written by the Agent):
   ```
   <TxRoot>\Task\<Skill>\
       <Skill>.csproj
       <Skill>Task.cs      # C# source
       <Skill>.dll         # build output
       <Skill>.md          # skill description (see section 7)
   ```
7. **Build**: `txai.ps1 build <Skill>`; on failure fix and retry.
8. **Run**: `txai.ps1 run <Skill> -ArgsJson '{...}'` (internally it checks the environment again and pings the Bridge).
9. **Report** (section 6). After changing code, if the same PS process has already loaded an old version, use a new class name or ask the user to restart PS.

- To analyze the process flow of an open Study (BIW area, pick/place, GEO vs re-spot), follow `cookbook-md/18-Tecnomatix_Process_Simulate_Station_Analysis.md`.

## 6. Result output format

Report to the user:

- Status: success / failure (`ok`) and duration (`durationMs`)
- Result summary (`result.message`) and key data (`result.data`, present lists as tables)
- Valuable parts of the process log (`logs`)
- On failure, the `error` and your handling suggestion
- The skill name, DLL path and arguments used, for reproducibility

## 7. Templates

### 7.1 `<Skill>.csproj`

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net48</TargetFramework>
    <LangVersion>5</LangVersion>
    <AssemblyName>$(MSBuildProjectName)</AssemblyName>
    <RootNamespace>TxAiSkills.$(MSBuildProjectName)</RootNamespace>
    <AppendTargetFrameworkToOutputPath>false</AppendTargetFrameworkToOutputPath>
    <OutputPath>.\</OutputPath>
    <DebugType>none</DebugType>
    <TxContractsDll Condition="'$(TxContractsDll)' == ''">$(MSBuildProjectDirectory)\..\..\Tecnomatix-AI-Client\deploy\TxAi\TxAi.Contracts.dll</TxContractsDll>
  </PropertyGroup>
  <ItemGroup>
    <!-- 宿主已加载这些程序集，不要复制到输出目录 -->
    <Reference Include="TxAi.Contracts"><HintPath>$(TxContractsDll)</HintPath><Private>false</Private></Reference>
    <Reference Include="Tecnomatix.Engineering"><HintPath>$(TxInstallDir)Tecnomatix.Engineering.dll</HintPath><Private>false</Private></Reference>
    <!-- 需要 UI 类型时再加： Tecnomatix.Engineering.Ui.dll -->
  </ItemGroup>
</Project>
```

(XML comments: the host has already loaded these assemblies, do not copy them to the output directory; add `Tecnomatix.Engineering.Ui.dll` only when UI types are needed.) `obj\` holds intermediate build files and can be ignored / not committed.

### 7.2 `<Skill>Task.cs`

```csharp
using System.Collections.Generic;
using Tecnomatix.Engineering;
using TxAi.Contracts;

namespace TxAiSkills.ListRobots
{
    public class ListRobotsTask : ITxAiTask
    {
        public TxAiResult Run(TxAiContext context)
        {
            TxDocument document = TxApplication.ActiveDocument;
            if (document == null) { return TxAiResult.Fail("No active document."); }

            string namePart = context.GetString("nameContains", "");   // 参数来自 args
            TxObjectList robots = document.PhysicalRoot.GetAllDescendants(new TxTypeFilter(typeof(TxRobot)));
            List<Dictionary<string, object>> items = new List<Dictionary<string, object>>();
            foreach (ITxObject robot in robots)
            {
                if (context.Cancellation.IsCancellationRequested) { return TxAiResult.Fail("Cancelled."); }
                if (namePart.Length > 0 && robot.Name.IndexOf(namePart, System.StringComparison.OrdinalIgnoreCase) < 0) { continue; }
                Dictionary<string, object> item = new Dictionary<string, object>();
                item["name"] = robot.Name;
                items.Add(item);
            }
            context.Log("Found " + items.Count + " robot(s).");
            Dictionary<string, object> data = new Dictionary<string, object>();
            data["count"] = items.Count;
            data["robots"] = items;
            return TxAiResult.Success(data, "Listed " + items.Count + " robot(s).");
        }
    }
}
```

Key points: put only JSON-serializable content in `Data` (primitive types, `List`, `Dictionary<string, object>`), never PS objects; read arguments with `GetString` / `GetInt`, etc. For the reference implementation see `Tecnomatix-AI-Client\src\TxAi.Tasks.Samples\ListRobotsTask.cs`. (The comment `// 参数来自 args` means "arguments come from args".)

### 7.3 `<Skill>.md` (skill description, for later reuse)

```markdown
# <Skill>
一句话说明用途。

- 类型：只读 / 修改数据
- DLL：<Skill>.dll（任务类：<Skill>Task）
- 适用版本：Process Simulate 2502（.NET Framework 4.8）

## 参数 (args)
| 名称 | 类型 | 必填 | 默认 | 说明 |

## 返回 (result.data)
字段说明与示例 JSON。

## 调用示例
run_dll: path=<TxRoot>\Task\<Skill>\<Skill>.dll, args={...}

## 前置条件
需要打开的 Study / 需要选中的对象等。

## 注意事项 / 已知限制
```

## 8. Safety rules

- Only load DLLs under `AllowedDirectories` (`<TxRoot>\Task`); the path must be absolute.
- A skill that modifies the Study must first inform the user and obtain confirmation, and must not save / overwrite user files unless the user explicitly asks.
- Do not write code unrelated to the request, do not access the network, do not read or write files outside the Study, unless the request explicitly needs it.
- The named pipe is open only to the current Windows user; never expose the Bridge to the network.

---

# Tecnomatix AI Skills — Agent 工作手册

本文件指导 Agent：根据用户需求，生成 C# skill DLL，通过 **AI Bridge**（Process Simulate 内的插件）执行，并把结果返回给用户。

`<TxRoot>` = 本文件所在目录（`...\Industry-Digital-Software-AI-Tools\Tecnomatix`）。

## 1. 角色设定（System Prompt）

> 你是一名经验丰富的仿真工程师，精通 Tecnomatix Process Simulate 的业务与操作；同时你也是精通 C# 的开发人员，对 Process Simulate 的二次开发（`Tecnomatix.Engineering` .NET API）非常熟练。
> 你先理解用户的工艺意图，再设计可复用的 skill，写出能编译、能在 PS 里安全运行的代码，并如实报告执行结果。

## 2. 架构

```
Agent --(生成 C# + dotnet build)--> <TxRoot>\Task\<Skill>\<Skill>.dll
Agent --(命名管道 \\.\pipe\TxAiClient, run_dll + DLL 绝对路径)--> AI Bridge (PS 进程内, UI 线程执行)
Agent <--(JSON: ok / result / error / logs / durationMs)-- AI Bridge
```

- 只有 AI Bridge 插件（`TxAi.Addin.dll`, `TxAi.Contracts.dll`）安装在 `<PS>\eMPower\DotNetCommands\`（需管理员，一次性）。
- Skill DLL 放在 `<TxRoot>\Task\`，不需要管理员权限，由配置白名单放行。
- DLL 以字节加载，不锁文件，重新编译后无需重启 PS（但同一进程内已加载的旧程序集不会卸载；改了代码后请换新的类名或重启 PS 以确保执行的是新版本）。

## 3. 强制入口：`txai.ps1`（必须使用）

`<AIC>` = `<TxRoot>\Tecnomatix-AI-Client`。**环境检测、编译、运行一律只通过下面这个脚本完成，禁止自己手写 `dotnet build`、管道客户端或其它绕过方式。** 脚本每次调用都会先做环境检查（PS 安装、dotnet 与 net48 targeting pack、`TxAi.Contracts.dll`、配置文件与白名单、插件是否安装），不通过就不会继续。

```powershell
$TX = "powershell -NoProfile -ExecutionPolicy Bypass -File <AIC>\tools\txai.ps1"
& powershell -NoProfile -ExecutionPolicy Bypass -File <AIC>\tools\txai.ps1 setup                  # 环境检测 + 自动配置
& powershell -NoProfile -ExecutionPolicy Bypass -File <AIC>\tools\txai.ps1 ping                   # 检查 AI Bridge
& powershell -NoProfile -ExecutionPolicy Bypass -File <AIC>\tools\txai.ps1 build <Skill>          # 编译 <TxRoot>\Task\<Skill>\
& powershell -NoProfile -ExecutionPolicy Bypass -File <AIC>\tools\txai.ps1 run <Skill> -ArgsJson '{"key":"value"}' [-TimeoutMs 120000]
```

### 强制规则

根目录 `envcheck.ps1` 检测到 Tecnomatix 时自动调用 `txai.ps1 setup`：先编译缺失的插件 / contracts DLL、初始化用户配置，再输出管理员部署步骤；已有完整 DLL 会复用。准备阶段不要求 Bridge 运行，但未完成部署时 setup 仍返回 10、Bridge 未启动时返回 11；只有退出码为 0 才能执行自动化。

1. **会话第一次处理 Tecnomatix 自动化需求时，先运行 `setup`**；每次生成新 skill 之前也要确保本会话 `setup` 已通过。
2. 只允许用 `build` 编译、`run` 执行；`build` 失败（退出码 12）绝不能执行 `run`。
3. 不要尝试提权；需要管理员的步骤（复制插件到 `DotNetCommands`）只提示用户。

### 退出码处理

| 退出码 | 含义 | Agent 动作 |
|---|---|---|
| 0 | 成功 | 继续 / 汇报结果 |
| 10 | 环境未就绪 | 把脚本输出的 `[X]` 项原样告诉用户并**停止**；用户处理后重新 `setup` |
| 11 | AI Bridge 未运行 | 提示用户：在 Process Simulate 打开 Study，点击 “AI” 分类下的 “AI Bridge” 启动；确认后再 `ping` |
| 12 | 编译失败 | 根据错误修正代码，重新 `build`，直到成功 |
| 13 | skill 执行失败 | 阅读 `error` / `logs`，修正后重新 `build` + `run`；多轮仍失败则如实汇报 |
| 2 | skill 名称不合法 | 改为 PascalCase 英文名 |

配置文件 `%LOCALAPPDATA%\TxAi\txai.config.json` 在插件启动时读取：`setup` 若提示更新了配置，需让用户重启 Process Simulate。

## 4. 协议（参考）

命名管道 `\\.\pipe\TxAiClient`，每行一个 JSON。请求 `{"id","method","params"}`；方法 `ping`、`get_status`、`run_dll`。响应 `{id, ok, result, error, logs, durationMs}`。`run_dll` 的 `path` 必须是 `AllowedDirectories` 下的 `.dll` 绝对路径；`args.type` 用于 DLL 内有多个 `ITxAiTask` 时指定类名；超时只是停止等待，**不会中止**已在 PS 内运行的任务。

## 5. 工作流程

1. **环境**：运行 `txai.ps1 setup`，非 0 则按退出码表处理，不得继续。
2. **理解需求**：以仿真工程师视角确认对象（Study、机器人、操作、焊点等）、期望输出、是否会**修改**数据。只读 / 修改要明确区分；修改类任务执行前向用户确认，必要时先做只读预检（skill 里提供 `dryRun` 参数）。
3. **提炼通用 skill**：把需求抽象成可复用、带参数的能力，可拆成多步（多个 skill 或同一 DLL 中的多个任务类），不要把具体对象名写死，通过 `args` 传入。
4. **命名与复用**：skill 名使用英文 PascalCase 动宾结构（如 `ListRobots`、`ExportWeldPoints`）。先检查 `<TxRoot>\Task\<Skill>\` 是否已有可复用的 skill（读取其 `<Skill>.md`），有则复用或升级。
5. **查资料再写代码**（必须）：
   - 先读 `<TxRoot>\cookbook-md\INDEX.md`，挑选 1–4 个最匹配的 cookbook 文件阅读。
   - 用 `<TxRoot>\Tecnomatix_Engineering\types.tsv` 查类型，再读 `types\<Namespace>\<Type>.md` 核对**精确签名**；不要凭记忆写 API。
   - 代码约束：.NET Framework 4.8 / **C# 5**（无字符串插值、无 `?.`、无 `nameof`，用 `string.Format`）；旋转/关节角用**弧度**；所有 PS API 都在 UI 线程调用（Bridge 已保证，不要自己开线程操作 PS 对象）；长循环轮询 `context.Cancellation`；对象为空和异常要返回 `TxAiResult.Fail(...)`，不要抛出未处理异常。
6. **创建文件**（`txai.ps1 build` 会在缺少 csproj 时按模板自动生成；`.cs` 和 `.md` 由 Agent 写）：
   ```
   <TxRoot>\Task\<Skill>\
       <Skill>.csproj
       <Skill>Task.cs      # C# 源码
       <Skill>.dll         # 编译输出
       <Skill>.md          # skill 说明（见第 7 节）
   ```
7. **编译**：`txai.ps1 build <Skill>`，失败则修正后重试。
8. **执行**：`txai.ps1 run <Skill> -ArgsJson '{...}'`（内部会再次检查环境并 ping Bridge）。
9. **汇报**（第 6 节）。改了代码后若同一 PS 进程已加载过旧版本，请换新的类名或让用户重启 PS。

- 分析已打开 Study 的工艺流程（白车身区域、抓放、GEO 与补焊）时，遵循 `cookbook-md/18-Tecnomatix_Process_Simulate_Station_Analysis.md`。

## 6. 结果输出格式

向用户汇报：

- 状态：成功 / 失败（`ok`）与耗时（`durationMs`）
- 结果摘要（`result.message`）及关键数据（`result.data`，列表用表格呈现）
- 过程日志（`logs`）中有价值的部分
- 失败时给出 `error` 和你的处理建议
- 使用的 skill 名称、DLL 路径、传入参数，便于复现

## 7. 模板

### 7.1 `<Skill>.csproj`

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net48</TargetFramework>
    <LangVersion>5</LangVersion>
    <AssemblyName>$(MSBuildProjectName)</AssemblyName>
    <RootNamespace>TxAiSkills.$(MSBuildProjectName)</RootNamespace>
    <AppendTargetFrameworkToOutputPath>false</AppendTargetFrameworkToOutputPath>
    <OutputPath>.\</OutputPath>
    <DebugType>none</DebugType>
    <TxContractsDll Condition="'$(TxContractsDll)' == ''">$(MSBuildProjectDirectory)\..\..\Tecnomatix-AI-Client\deploy\TxAi\TxAi.Contracts.dll</TxContractsDll>
  </PropertyGroup>
  <ItemGroup>
    <!-- 宿主已加载这些程序集，不要复制到输出目录 -->
    <Reference Include="TxAi.Contracts"><HintPath>$(TxContractsDll)</HintPath><Private>false</Private></Reference>
    <Reference Include="Tecnomatix.Engineering"><HintPath>$(TxInstallDir)Tecnomatix.Engineering.dll</HintPath><Private>false</Private></Reference>
    <!-- 需要 UI 类型时再加： Tecnomatix.Engineering.Ui.dll -->
  </ItemGroup>
</Project>
```

`obj\` 为编译中间文件，可忽略 / 不提交。

### 7.2 `<Skill>Task.cs`

```csharp
using System.Collections.Generic;
using Tecnomatix.Engineering;
using TxAi.Contracts;

namespace TxAiSkills.ListRobots
{
    public class ListRobotsTask : ITxAiTask
    {
        public TxAiResult Run(TxAiContext context)
        {
            TxDocument document = TxApplication.ActiveDocument;
            if (document == null) { return TxAiResult.Fail("No active document."); }

            string namePart = context.GetString("nameContains", "");   // 参数来自 args
            TxObjectList robots = document.PhysicalRoot.GetAllDescendants(new TxTypeFilter(typeof(TxRobot)));
            List<Dictionary<string, object>> items = new List<Dictionary<string, object>>();
            foreach (ITxObject robot in robots)
            {
                if (context.Cancellation.IsCancellationRequested) { return TxAiResult.Fail("Cancelled."); }
                if (namePart.Length > 0 && robot.Name.IndexOf(namePart, System.StringComparison.OrdinalIgnoreCase) < 0) { continue; }
                Dictionary<string, object> item = new Dictionary<string, object>();
                item["name"] = robot.Name;
                items.Add(item);
            }
            context.Log("Found " + items.Count + " robot(s).");
            Dictionary<string, object> data = new Dictionary<string, object>();
            data["count"] = items.Count;
            data["robots"] = items;
            return TxAiResult.Success(data, "Listed " + items.Count + " robot(s).");
        }
    }
}
```

要点：`Data` 只放可 JSON 序列化的内容（基本类型、`List`、`Dictionary<string, object>`），不要放 PS 对象；参数用 `GetString` / `GetInt` 等读取。参考实现见 `Tecnomatix-AI-Client\src\TxAi.Tasks.Samples\ListRobotsTask.cs`。

### 7.3 `<Skill>.md`（skill 说明，供日后复用）

```markdown
# <Skill>
一句话说明用途。

- 类型：只读 / 修改数据
- DLL：<Skill>.dll（任务类：<Skill>Task）
- 适用版本：Process Simulate 2502（.NET Framework 4.8）

## 参数 (args)
| 名称 | 类型 | 必填 | 默认 | 说明 |

## 返回 (result.data)
字段说明与示例 JSON。

## 调用示例
run_dll: path=<TxRoot>\Task\<Skill>\<Skill>.dll, args={...}

## 前置条件
需要打开的 Study / 需要选中的对象等。

## 注意事项 / 已知限制
```

## 8. 安全规则

- 只加载 `AllowedDirectories`（`<TxRoot>\Task`）下的 DLL，路径必须是绝对路径。
- 会修改 Study 的 skill 必须先告知用户并获得确认，且不得保存/覆盖用户文件，除非用户明确要求。
- 不写入与需求无关的代码，不访问网络、不读写 Study 以外的文件，除非需求明确需要。
- 命名管道仅对当前 Windows 用户开放；不要把 Bridge 暴露到网络。

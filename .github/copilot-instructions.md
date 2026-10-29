# Industry-Digital-Software-AI-Tools — Agent Instructions

> This project is global. Every `.md` file is bilingual: **English first, Chinese second**. The Chinese section starts after the first `---` below.
> 本项目面向全球使用。所有 `.md` 文件均为中英双语：**英文在前，中文在后**；中文部分从下方第一个 `---` 之后开始。

## Global Rules (mandatory)

### G1. Reply language follows the user's input language

- Detect the language of the user's latest message and reply in that language: Chinese in -> Chinese out; English in -> English out; any other language -> reply in that language when reasonable, otherwise English.
- If the message mixes languages, use the language of the main request sentence. If the user explicitly asks for a language, follow that.
- Generated artifacts follow the same rule for narrative text (reports, skill `.md`, summaries). Code, identifiers, API names, file paths and commands stay in English. Main project `.md` files stay bilingual (see G3).
- Record the user's language preference in `Memory/learned.md` only when the user states one explicitly.

### G2. Token and cost report on EVERY reply

- The assistant cannot see real usage counters, so the report is an **estimate** and must be labelled as such. Never present it as exact.
- At the end of every reply (including short answers and replies that stop on an error), run:
  `powershell -NoProfile -ExecutionPolicy Bypass -File <absolute path>\tools\tokencost.ps1 -Model <model id you are running as>`
  If your exact model id is not in the price table, omit `-Model` and say which model was assumed.
- Append a footer in the reply language, in this form (numbers from the script output):
  - EN: `Token estimate (not exact): this turn ≈ <total> tokens (in <fresh+cached>, out <out>) ≈ $<USD> on <model>; session total ≈ <tokens> tokens ≈ $<USD>. Same turn on other models: <model> $<x>, <model> $<y>.`
  - ZH: `Token 估算（非精确值）：本次约 <总数> tokens（输入 <新增+缓存>，输出 <输出>），按 <模型> 约 $<美元>；本会话累计约 <tokens> tokens，约 $<美元>。同样用量换其它模型：<模型> $<x>，<模型> $<y>。`
- How the estimate works: characters / 4 for Latin text and characters / 1.5 for CJK, replayed from the Copilot transcript; the whole context is re-billed on each model call (cached part at the cache-read price); tool results and hidden reasoning are not logged, so they are approximated by `-ToolResult` and `-Base`; auto-summarisation is assumed to reset context at `-MaxContext`.
- Prices come from `tools/model_prices.json` (snapshot of Copilot `models.json`, USD per 1M tokens, refreshed with `tokencost.ps1 -Refresh`). Prices change; state that figures are indicative. See `tools/token_pricing.md`.
- Clients without a Copilot transcript (Codex, Claude, ...): set `MFG_TRANSCRIPT_DIR` if the client keeps a `*.jsonl` transcript, otherwise run manual mode: `tokencost.ps1 -Model <id> -InChars <n> -OutChars <n> -Calls <n>` (this turn only; session total n/a).
- If the script fails (exit 20/21), still give a rough manual estimate (characters of this conversation / 4) and say so.

### G3. Main `.md` files are bilingual, English first

- Scope (main files only): `README.md`, `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`, the product manuals (`*_ai_skills.md`), skill docs (`*/Task/<Skill>/<Skill>.md`), `Memory/*.md`, and `tools/*.md`. Everything else (reference / extracted docs, `vismockup_md/`, code-generation prompts, generated index pages) may stay in its source language.

- Every main `.md` file listed above contains an English section first and a Chinese section second, with the same content in both. Order is fixed: English, then Chinese.
- Layout for documents: `# English title`, English body, `---`, `# 中文标题`, Chinese body. Keep tables, code blocks and command examples identical in both sections (do not translate code).
- Layout for `Memory/` topic files: keep the front matter (put `triggers` in both languages) and keep the `## XX-01 title` entry headings so `memcheck.ps1` still passes; inside each entry write the English lines first (`- Wrong:` / `- Right:` / `- Trigger:` / `- Evidence:`), then the Chinese lines (`- 错误：` / `- 正确：` / `- 触发：` / `- 证据：`). `learned.md` entries are one line each: English sentence, ` / `, Chinese sentence; keep the Chinese scope tags `[通用]` / `[环境]` (and `[NX]` etc.) because `memcheck.ps1` filters on them.
- When creating or editing any `.md`, update both languages in the same change. A one-language edit is incomplete.
- Exception: reference material (API cards, cookbook extracts, `types/`, `api-md/`, `api_md/`, `cookbook-md/`, `vismockup_md/`, `Tecnomatix_Engineering/`, code-generation prompts and their index pages) is not required to be bilingual; keep it in its source language.

## Session Start (mandatory)

1. Read the root `README.md` first (purpose, environment, NX administrator deployment logic, version adaptation).
2. Before handling the first request of every session, run `powershell -NoProfile -ExecutionPolicy Bypass -File <absolute path>\tools\envcheck.ps1`, show the user the "build environment + five software (Vismockup / Office / CATIA / NX / Tecnomatix) detection results", and state clearly that only `USABLE` software can be used.
3. If the build environment is missing, tell the user and run `envcheck.ps1 install` only after consent; administrator steps are only shown to the user, never self-elevated.
4. If the request involves software that is not detected / not ready, explain why and stop.
5. Also read `Memory/INDEX.md` (topic file directory) and `Memory/learned.md` (user traits + general / environment corrections); answer according to the preferences there; then read the topic files matching the request keywords, and avoid repeating recorded mistakes.
6. **All lessons learnt / corrections / pitfalls go in `Memory/`, never elsewhere.** Two tiers, decided by subject: **repository configuration** (repo / tooling / environment / workflow rules, e.g. `env_and_tooling.md`, `task_workflow_rules.md`, `learned.md`) -> directly in `Memory/*.md`; **anything about the products** (NX / Vismockup / CATIA / Tecnomatix / Office product knowledge, algorithms, API pitfalls, part-number rules) **and anything produced by the user's own runs** (paths, datasets, benchmark numbers, batch results) -> files under `Memory/Costomer/` (folder name spelled exactly `Costomer`). `memcheck.ps1` reads both tiers with the same format and selection rules. Create technical-experience files by topic / situation, with lowercase underscore, self-explanatory names (e.g. `nx_weld_lfo_lwe.md`, `ford_part_numbering.md`), not by product name or date. Every file starts with front matter: `title`, `scope` (NX / Vismockup / Catia / Office / Tecnomatix / all, comma separated), `triggers` (trigger keywords, in both Chinese and English), `always` (true = always printed in full), `updated`. Entries use `## PREFIX-NN title` plus the four items Wrong / Right / Trigger / Evidence. `INDEX.md` is generated by memcheck; never edit it by hand. **From now on everything the user's own runs produce (paths, datasets, part numbers, benchmark numbers, batch results, per-run pitfalls) goes only into `Memory/Costomer/`.** **Files directly under `Memory/` must stay user-independent so the repo works for a new user on a new machine:** no user names, absolute paths, dataset / project names or run results; `memcheck.ps1` must pass with `Memory/Costomer/` empty or missing (it creates the folder itself).
7. **Every runner call (`envcheck.ps1` / `txai.ps1` / `nxrun.ps1` / `vmrun.ps1` / `catrun.ps1` / `officerun.ps1`) first passes the `tools/memcheck.ps1` Memory gate**: it always prints `learned.md` and `always: true` files; files whose `scope` matches and whose `triggers` hit the task context are printed in full; scope matches without a trigger hit list only entry titles; other scopes list only file names. Task context = environment variable `MFG_TASK_HINT` + runner arguments, so **set `$env:MFG_TASK_HINT` to the user's request keywords before calling a runner** (e.g. `'weld LFO 焊点'`), otherwise only argument matching applies. Read the output fully before continuing; write matched entries into the execution plan and follow them; files listed by title only must be opened and read when the task touches them. If `Memory/learned.md` is missing the exit code is 14 and you must not continue.

## Self-learning and Correction (mandatory)

1. **Trigger**: when the user points out an error, corrects an approach, or states a preference / habit. Also record when: (a) you hit a pitfall and succeeded only after changing approach (failure cause + working approach); (b) you find a reusable algorithm / parameter / threshold / API usage conclusion; (c) you find a regularity in data problems (e.g. part-number error types); (d) the user teaches a domain rule. **Do not record**: one-off result data (statistics; a file path list may keep one piece of evidence), content already covered by an existing entry, temporary debugging steps, sensitive information.
   - Decision flow: check `INDEX.md` scope + triggers and existing entries -> if a same-kind entry exists, update it (add evidence / rewrite) -> if none but it belongs to an existing topic, append the next number in that file -> create a new file only if it fits no topic.
   - **Format gate**: memcheck validates topic-file format on every run (missing front matter field, entry heading not `## XX-01 title`, empty entry) and prints `[!] Memory format` warnings; fix them in the same turn.
2. **Record immediately**: write to Memory in the same reply, then continue fixing. User traits / preferences go to section 1 of `learned.md`; general / environment corrections to section 2; technical corrections and process experience with a clear topic go to the matching topic file under `Memory/` (match scope and triggers in `INDEX.md`); create a new topic file with complete front matter if none matches (update `triggers` for new keywords too).
3. **Entry requirements**: topic files use Wrong / Right / Trigger / Evidence; `learned.md` uses a one-line "wrong -> right -> trigger"; update an existing entry instead of duplicating; on conflict with an old entry follow the user's latest statement and rewrite the old entry; delete outdated entries, no archive. All entries are bilingual, English first (see G3).
4. **Reuse**: read at session start; memcheck selects relevant topic files by scope + triggers on every runner call; when about to repeat a mistake, follow the recorded correct approach first. After a task, add newly found pitfalls and algorithm conclusions to the matching topic file.
5. **Boundary**: record only facts about the way of working; no passwords, tokens or personal privacy; recording never relaxes security rules (elevation, overwriting files, etc. still need user confirmation).
6. **When the user asks to forget or delete an entry**, delete it directly and tell the user.

## Tecnomatix / Process Simulate Automation (mandatory)

For any automation, script, or skill generation / execution request involving Tecnomatix / Process Simulate:

1. **Read and follow first** `Tecnomatix/Tecnomatix_ai_skills.md` (role, workflow, templates, safety rules).
2. **Environment detection, build and run only through** `Tecnomatix/Tecnomatix-AI-Client/tools/txai.ps1` (`setup` / `ping` / `build <Skill>` / `run <Skill>`), invoked as:
   `powershell -NoProfile -ExecutionPolicy Bypass -File Tecnomatix/Tecnomatix-AI-Client/tools/txai.ps1 <command>`
3. Run `setup` before the first execution of every session; on a non-zero exit code follow the exit-code table in the md and do not continue.
4. Before writing API code, check `Tecnomatix/cookbook-md/INDEX.md` and `Tecnomatix/Tecnomatix_Engineering/` for exact signatures; code is C# 5 / .NET Framework 4.8.
5. Never try to elevate; a DLL whose `build` failed must never be `run`; a skill that modifies the Study needs user confirmation first.
6. Skill outputs go to `Tecnomatix/Task/<Skill>/`.

## NX / NX Open C++ Automation (mandatory)

For any automation, development, or skill generation / execution request involving Siemens NX:

1. **Read and follow first** `NX/NX_ai_skills.md` (role, environment detection, workflow, templates, safety rules).
2. **Environment detection, build and run only through** `NX/tools/nxrun.ps1` (`setup` / `build <cpp>` / `run <dll> [args]`), invoked as:
   `powershell -NoProfile -ExecutionPolicy Bypass -File <absolute path>\NX\tools\nxrun.ps1 <command>`
3. Run `setup` before the first execution of every session; on a non-zero exit code follow the exit-code table in the md and do not continue.
4. Before writing API code, check `NX/cookbook-md/README.md`, `NX/api-md/INDEX.md` and the headers / samples under `UGII_BASE_DIR\UGOPEN` for exact signatures; code is C++17 (NX Open C++ / Open C), entry `NxMain`.
5. Never try to elevate; a DLL whose `build` failed must never be `run`; a skill that modifies or saves parts needs user confirmation first.
6. Skill outputs (`.cpp` / `.dll` / `.md`) go to `NX/Task/<Skill>/`.

## Vismockup (Teamcenter Visualization) COM Automation (mandatory)

For any automation, script, or skill generation / execution request involving Vismockup / Teamcenter Visualization Mockup:

1. **Read and follow first** `Vismockup/Vismockup_ai_skills.md` (role, scope judgement, workflow, templates, safety rules).
2. **Environment detection, build and run only through** `Vismockup/tools/vmrun.ps1` (`setup` / `build <cs>` / `run <dll> [key=value ...]`), invoked as:
   `powershell -NoProfile -ExecutionPolicy Bypass -File <absolute path>\Vismockup\tools\vmrun.ps1 <command>`
3. Run `setup` before the first execution of every session; on a non-zero exit code follow the exit-code table in the md and do not continue.
4. Before writing API code, check `Vismockup/api_md/INDEX.md` and `Vismockup/api_md/objects/<Object>.md` (or grep `members.tsv`) for exact member names and signatures, then `Vismockup/vismockup_md/00_index.md` and the matching `01`-`15` docs for C# samples; code is C# 5 / .NET Framework 4.x / x64, late-bound (`dynamic`) through COM `VFFrame.Application`.
5. Never try to elevate; a DLL whose `build` failed must never be `run`; never widen the selection scope on your own; a skill that modifies / saves / overwrites documents needs user confirmation first.
6. Skill outputs (`.cs` / `.dll` / `.md`) go to `Vismockup/Task/<Skill>/`.

## CATIA V5 COM Automation (mandatory)

For any automation, script, or skill generation / execution request involving CATIA V5:

1. **Read and follow first** `Catia/Catia_ai_skills.md` (role, scope judgement, workflow, templates, safety rules).
2. **Environment detection, build and run only through** `Catia/tools/catrun.ps1` (`setup` / `build <cs>` / `run <dll> [key=value ...]`), invoked as:
   `powershell -NoProfile -ExecutionPolicy Bypass -File <absolute path>\Catia\tools\catrun.ps1 <command>`
3. Run `setup` before the first execution of every session; on a non-zero exit code follow the exit-code table in the md and do not continue.
4. Before writing API code, check `Catia/api-md/INDEX.md` and `Catia/api-md/objects/<Object>.md` (or grep `members.tsv`) for exact member names and signatures, then `Catia/api-md/samples/INDEX.md` for samples; code is C# 5 / .NET Framework 4.x / x64, late-bound (`dynamic`) through COM `CATIA.Application`.
5. Never try to elevate; a DLL whose `build` failed must never be `run`; never widen the selection scope on your own; a skill that modifies / saves / overwrites documents needs user confirmation first.
6. Skill outputs (`.cs` / `.dll` / `.md`) go to `Catia/Task/<Skill>/`.

## Office (Excel / PowerPoint) Report Automation (mandatory)

For any request that turns results of other software or user requirements into an Excel / PowerPoint report:

1. **Read and follow first** `Office/Office_ai_skills.md` (role, workflow, existing skills, reporting guidelines, safety rules).
2. **Environment detection, build and run only through** `Office/tools/officerun.ps1` (`setup` / `build <cs>` / `run <dll> [key=value ...]`), invoked as:
   `powershell -NoProfile -ExecutionPolicy Bypass -File <absolute path>\Office\tools\officerun.ps1 <command>`
3. Run `setup` before the first execution of every session; on a non-zero exit code follow the exit-code table in the md and do not continue.
4. Reuse existing skills under `Office/Task/` first (`CsvToExcelReport`, `SpecToPptReport`), create new ones only when insufficient; code is C# 5 / .NET Framework 4.x / x64, late-bound (`dynamic`) through COM (`Excel.Application` / `PowerPoint.Application`), always with a new independent instance.
5. Never try to elevate; a DLL whose `build` failed must never be `run`; never fabricate data, state missing upstream data honestly in the report; get user confirmation before overwriting existing files.
6. Skill outputs (`.cs` / `.dll` / `.md`) go to `Office/Task/<Skill>/`.

## Vismockup -> JT -> NX Flow Notes (mandatory)

For any request that exports Hierarchy / JT from Vismockup, converts to NX prt, or computes weld-spot LFO / LWE, first read the related topic files under `Memory/Costomer/`: `vismockup_hierarchy_export.md` (Hierarchy selection, JT export ini, weld-spot export), `jt_to_nx_conversion.md` (B-rep conversion), `ford_part_numbering.md` (part number / version / left-right symmetry rules), `nx_weld_lfo_lwe.md` (weld-spot calculation and matching fallback), `nx_assembly_transform.md` (instance coordinate transforms).

---

# Industry-Digital-Software-AI-Tools — Agent 指令（中文）

## 全局规则（强制）

### G1. 回复语言跟随用户输入语言

- 判断用户最新一条消息的语言并用同一语言回复：中文提问 -> 中文回复；英文提问 -> 英文回复；其它语言 -> 能用就用该语言，否则用英文。
- 消息混合多种语言时，以主要请求句的语言为准；用户明确指定语言时从其指定。
- 生成物中的叙述性文字（报告、skill 的 `.md`、总结）遵循同一规则；代码、标识符、API 名、路径、命令保持英文；项目内的 `.md` 文件保持双语（见 G3）。
- 仅当用户明确表达语言偏好时，才记入 `Memory/learned.md`。

### G2. 每次回复都要给出 Token 与费用报告

- 助手看不到真实用量计数器，所以报告是**估算值**，必须标明“估算”，不得当作精确值。
- 每次回复结束时（含很短的回答、因错误而停止的回复），运行：
  `powershell -NoProfile -ExecutionPolicy Bypass -File <绝对路径>\tools\tokencost.ps1 -Model <当前运行的模型 id>`
  若当前模型 id 不在价格表中，则省略 `-Model`，并说明假设了哪个模型。
- 用回复语言在末尾追加页脚，格式见上文 G2 的 EN / ZH 两行（数字取自脚本输出）。
- 估算方法：拉丁文字符数 / 4、中日韩字符数 / 1.5，按 Copilot 对话记录回放；每次模型调用都会重新计费整个上下文（缓存部分按缓存读取价）；工具返回内容与隐藏推理不会被记录，用 `-ToolResult` 与 `-Base` 近似；假设上下文到达 `-MaxContext` 时被自动摘要重置。
- 价格来自 `tools/model_prices.json`（Copilot `models.json` 快照，美元 / 百万 token，用 `tokencost.ps1 -Refresh` 刷新）。价格会变，须说明数字仅供参考。详见 `tools/token_pricing.md`。
- 没有 Copilot 对话记录的客户端（Codex、Claude 等）：若客户端保存 `*.jsonl` 对话记录，设置 `MFG_TRANSCRIPT_DIR`；否则用手动模式：`tokencost.ps1 -Model <id> -InChars <n> -OutChars <n> -Calls <n>`（仅本轮；会话累计为 n/a）。
- 脚本失败（退出码 20 / 21）时，仍给出粗略手工估算（本次对话字符数 / 4）并如实说明。

### G3. 主要 `.md` 文件中英双语，英文在前

- 范围（仅主要文件）：`README.md`、`AGENTS.md`、`CLAUDE.md`、`.github/copilot-instructions.md`、各产品手册（`*_ai_skills.md`）、skill 文档（`*/Task/<Skill>/<Skill>.md`）、`Memory/*.md`、`tools/*.md`。其余（参考 / 提取类文档、`vismockup_md/`、代码生成提示词、生成的索引页）可保持源语言。

- 上述每个主要 `.md` 文件先写英文部分、再写中文部分，两部分内容一致；顺序固定：先英文，后中文。
- 文档布局：`# 英文标题`、英文正文、`---`、`# 中文标题`、中文正文。表格、代码块、命令示例在两部分中保持一致（不翻译代码）。
- `Memory/` 主题文件布局：保留 front matter（`triggers` 中英文都写）与 `## XX-01 标题` 条目标题以通过 `memcheck.ps1`；每个条目内先写英文行（`- Wrong:` / `- Right:` / `- Trigger:` / `- Evidence:`），再写中文行（`- 错误：` / `- 正确：` / `- 触发：` / `- 证据：`）。`learned.md` 每条一行：英文句 + ` / ` + 中文句；范围标签保持中文 `[通用]` / `[环境]`（及 `[NX]` 等），因为 `memcheck.ps1` 按它们过滤。
- 新建或修改任何 `.md` 时，必须同一次改动里同时更新两种语言；只改一种语言视为未完成。
- 例外：参考资料（API 卡片、cookbook 摘录、`types/`、`api-md/`、`api_md/`、`cookbook-md/`、`vismockup_md/`、`Tecnomatix_Engineering/`、代码生成提示词及其索引页）不要求双语，保持源语言。

## 会话启动（强制）

1. 先阅读根目录 `README.md`（项目用途、环境、NX 管理员部署逻辑、版本适配）。
2. 每个会话第一次处理请求前，运行 `powershell -NoProfile -ExecutionPolicy Bypass -File <绝对路径>\tools\envcheck.ps1`，把"编译环境 + 五个软件（Vismockup / Office / CATIA / NX / Tecnomatix）检测结果"输出给用户，明确只有 `USABLE` 的软件可用。
3. 编译环境缺失时提醒用户并征得同意后运行 `envcheck.ps1 install`；管理员步骤只提示用户执行，绝不自行提权。
4. 请求涉及未检测到 / 未就绪的软件时，说明原因并停止。
5. 同时阅读 `Memory/INDEX.md`（主题文件目录）和 `Memory/learned.md`（用户特点 + 通用 / 环境纠错），按其中偏好回答；再按本次请求的关键词读取命中的主题文件，并避免重犯已记录的错误。
6. **所有 lessons learnt / 纠错 / 踩坑文件一律放在 `Memory/`，不得放到其它目录。** 分两层，按主题判断：**仓库配置**（仓库 / 工具 / 环境 / 工作流规则，如 `env_and_tooling.md`、`task_workflow_rules.md`、`learned.md`）-> 直接放 `Memory/*.md`；**涉及产品的一切**（NX / Vismockup / CATIA / Tecnomatix / Office 的产品知识、算法、API 坑、零件号规则）**以及用户每次运行过程中产生的内容**（路径、数据集、对比数字、批量结果）-> 放到 `Memory/Costomer/` 下的文件（文件夹名严格拼写为 `Costomer`）。`memcheck.ps1` 两层都读取，格式与筛选规则相同。技术经验按“主题 / 情境”建文件，文件名小写下划线、见名知义（如 `nx_weld_lfo_lwe.md`、`ford_part_numbering.md`），不按产品名或时间命名；文件开头必须有 front matter：`title`、`scope`（NX / Vismockup / Catia / Office / Tecnomatix / all，逗号分隔）、`triggers`（触发关键词，中英文都写）、`always`（true 则每次都完整打印）、`updated`；条目用 `## 前缀-序号 标题` + “错误 / 正确 / 触发 / 证据”四项。`INDEX.md` 由 memcheck 自动生成，不手改。**今后用户每次运行产生的内容（路径、数据集、零件号、对比数字、批量结果、单次运行的坑）一律只写入 `Memory/Costomer/`。** **`Memory/` 根目录下的文件必须与用户无关，保证换新用户 / 新机器也能配置成功：** 不得出现用户名、绝对路径、数据集 / 项目名或运行结果；`Memory/Costomer/` 为空或不存在时 `memcheck.ps1` 也必须通过（它会自行创建该文件夹）。
7. **每次调用任何 runner（`envcheck.ps1` / `txai.ps1` / `nxrun.ps1` / `vmrun.ps1` / `catrun.ps1` / `officerun.ps1`）都会先经过 `tools/memcheck.ps1` 的 Memory 门禁**：始终打印 `learned.md` 和 `always: true` 的文件；`scope` 匹配且 `triggers` 命中任务上下文的文件完整打印；scope 匹配但未命中的只列条目标题；其它 scope 的只列文件名。任务上下文 = 环境变量 `MFG_TASK_HINT` + runner 参数，**调用 runner 前先设置 `$env:MFG_TASK_HINT` 为用户请求的关键词**（如 `'weld LFO 焊点'`），否则只能按参数匹配。Agent 必须先读完输出再继续，命中的条目要写进执行方案并照做；标题列出但未完整打印的文件，任务涉及时必须自己打开阅读。`Memory/learned.md` 缺失时退出码 14，不得继续。

## 自学习与纠错（强制）

1. **触发**：用户指出错误、纠正做法，或明确表达偏好 / 习惯时；另外任务中出现下列情况也必须记录：①自己踩坑后换了做法才成功（失败原因 + 有效做法）；②发现可复用的算法 / 参数 / 阈值 / API 用法结论；③发现数据问题的规律（如零件号错误类型）；④用户教授领域规则。**不记录**：一次性结果数据（统计数、文件路径清单可只留一条证据）、已有条目已覆盖的内容、临时调试过程、敏感信息。
   - 判断流程：先查 `INDEX.md` 的 scope + triggers 与已有条目 -> 已有同类条目则更新（补证据 / 改写）-> 没有但属于已有主题则在该文件追加下一个编号 -> 不属于任何主题才新建文件。
   - **格式门禁**：memcheck 每次运行都会校验主题文件格式（front matter 缺字段、条目标题不是 `## XX-01 标题`、条目无内容），输出 `[!] Memory format` 警告时必须当轮修正。
2. **立即记录**：当轮回复内先写入 Memory，再继续修正。用户特点 / 偏好写 `learned.md` 第一节；通用 / 环境纠错写第二节；有明确主题的技术纠错和流程经验写入 `Memory/` 下对应主题文件（匹配 `INDEX.md` 里的 scope 与 triggers），没有对应主题就新建一个并补全 front matter（新增触发词也要更新 `triggers`）。
3. **条目要求**：主题文件用“错误 / 正确 / 触发 / 证据”四项，`learned.md` 用“错误 -> 正确做法 -> 触发条件”一行；同一问题已有条目则更新，不重复添加；与旧条目冲突时以用户最新说法为准并改写旧条目；过期条目直接删除，不做归档。
4. **复用**：每个会话启动读取；每次调用 runner 由 memcheck 按 scope + triggers 选出相关主题文件；发现将要重犯时，先按记录的正确做法执行。任务结束后，把新发现的踩坑、算法结论补进对应主题文件。
5. **边界**：只记录与工作方式有关的事实，不记录密码、令牌、个人隐私；不得因记录而放宽安全规则（提权、覆盖文件等仍须用户确认）。
6. **用户要求遗忘或删除某条时**，直接删除，并告知用户。

## Tecnomatix / Process Simulate 自动化（强制）

凡是涉及 Tecnomatix / Process Simulate 的自动化、脚本、skill 生成或执行请求：

1. **先阅读并遵循** `Tecnomatix/Tecnomatix_ai_skills.md`（角色设定、工作流程、模板、安全规则）。
2. **环境检测、编译、运行只能通过** `Tecnomatix/Tecnomatix-AI-Client/tools/txai.ps1`（`setup` / `ping` / `build <Skill>` / `run <Skill>`），调用方式：
   `powershell -NoProfile -ExecutionPolicy Bypass -File Tecnomatix/Tecnomatix-AI-Client/tools/txai.ps1 <command>`
3. 每个会话第一次执行前必须运行 `setup`；退出码非 0 时按 md 中的退出码表处理，不得继续。
4. 写 API 代码前必须查 `Tecnomatix/cookbook-md/INDEX.md` 与 `Tecnomatix/Tecnomatix_Engineering/` 核对精确签名；代码为 C# 5 / .NET Framework 4.8。
5. 不要尝试提权；`build` 失败的 DLL 绝不能 `run`；会修改 Study 的 skill 必须先获得用户确认。
6. Skill 产物统一放在 `Tecnomatix/Task/<Skill>/`。

## NX / NX Open C++ 自动化（强制）

凡是涉及 Siemens NX 的自动化、二次开发、skill 生成或执行请求：

1. **先阅读并遵循** `NX/NX_ai_skills.md`（角色设定、环境检测、工作流程、模板、安全规则）。
2. **环境检测、编译、运行只能通过** `NX/tools/nxrun.ps1`（`setup` / `build <cpp>` / `run <dll> [args]`），调用方式：
   `powershell -NoProfile -ExecutionPolicy Bypass -File <绝对路径>\NX\tools\nxrun.ps1 <command>`
3. 每个会话第一次执行前必须运行 `setup`；退出码非 0 时按 md 中的退出码表处理，不得继续。
4. 写 API 代码前必须查 `NX/cookbook-md/README.md`、`NX/api-md/INDEX.md` 以及 `UGII_BASE_DIR\UGOPEN` 下的头文件 / 示例核对精确签名；代码为 C++17（NX Open C++ / Open C），入口 `NxMain`。
5. 不要尝试提权；`build` 失败的 DLL 绝不能 `run`；会修改或保存零件的 skill 必须先获得用户确认。
6. Skill 产物（`.cpp` / `.dll` / `.md`）统一放在 `NX/Task/<Skill>/`。

## Vismockup（Teamcenter Visualization）COM 自动化（强制）

凡是涉及 Vismockup / Teamcenter Visualization Mockup 的自动化、脚本、skill 生成或执行请求：

1. **先阅读并遵循** `Vismockup/Vismockup_ai_skills.md`（角色设定、范围判定、工作流程、模板、安全规则）。
2. **环境检测、编译、运行只能通过** `Vismockup/tools/vmrun.ps1`（`setup` / `build <cs>` / `run <dll> [key=value ...]`），调用方式：
   `powershell -NoProfile -ExecutionPolicy Bypass -File <绝对路径>\Vismockup\tools\vmrun.ps1 <command>`
3. 每个会话第一次执行前必须运行 `setup`；退出码非 0 时按 md 中的退出码表处理，不得继续。
4. 写 API 代码前必须先查 `Vismockup/api_md/INDEX.md` 及 `Vismockup/api_md/objects/<对象>.md`（或 grep `members.tsv`）核对精确成员名与签名，再查 `Vismockup/vismockup_md/00_index.md` 及对应的 `01`–`15` 文档获取 C# 示例；代码为 C# 5 / .NET Framework 4.x / x64，通过 COM `VFFrame.Application` 晚绑定（`dynamic`）。
5. 不要尝试提权；`build` 失败的 DLL 绝不能 `run`；不得自行扩大选择范围；会修改 / 保存 / 覆盖文档的 skill 必须先获得用户确认。
6. Skill 产物（`.cs` / `.dll` / `.md`）统一放在 `Vismockup/Task/<Skill>/`。

## CATIA V5 COM 自动化（强制）

凡是涉及 CATIA V5 的自动化、脚本、skill 生成或执行请求：

1. **先阅读并遵循** `Catia/Catia_ai_skills.md`（角色设定、范围判定、工作流程、模板、安全规则）。
2. **环境检测、编译、运行只能通过** `Catia/tools/catrun.ps1`（`setup` / `build <cs>` / `run <dll> [key=value ...]`），调用方式：
   `powershell -NoProfile -ExecutionPolicy Bypass -File <绝对路径>\Catia\tools\catrun.ps1 <command>`
3. 每个会话第一次执行前必须运行 `setup`；退出码非 0 时按 md 中的退出码表处理，不得继续。
4. 写 API 代码前必须先查 `Catia/api-md/INDEX.md` 及 `Catia/api-md/objects/<对象>.md`（或 grep `members.tsv`）核对精确成员名与签名，再查 `Catia/api-md/samples/INDEX.md` 获取示例；代码为 C# 5 / .NET Framework 4.x / x64，通过 COM `CATIA.Application` 晚绑定（`dynamic`）。
5. 不要尝试提权；`build` 失败的 DLL 绝不能 `run`；不得自行扩大选择范围；会修改 / 保存 / 覆盖文档的 skill 必须先获得用户确认。
6. Skill 产物（`.cs` / `.dll` / `.md`）统一放在 `Catia/Task/<Skill>/`。

## Office（Excel / PowerPoint）报告自动化（强制）

凡是涉及把其它软件的运行结果或用户要求整理成 Excel / PowerPoint 报告的请求：

1. **先阅读并遵循** `Office/Office_ai_skills.md`（角色设定、工作流程、现有 skill、报告准则、安全规则）。
2. **环境检测、编译、运行只能通过** `Office/tools/officerun.ps1`（`setup` / `build <cs>` / `run <dll> [key=value ...]`），调用方式：
   `powershell -NoProfile -ExecutionPolicy Bypass -File <绝对路径>\Office\tools\officerun.ps1 <command>`
3. 每个会话第一次执行前必须运行 `setup`；退出码非 0 时按 md 中的退出码表处理，不得继续。
4. 先复用 `Office/Task/` 下已有 skill（`CsvToExcelReport`、`SpecToPptReport`），不足再新建；代码为 C# 5 / .NET Framework 4.x / x64，通过 COM（`Excel.Application` / `PowerPoint.Application`）晚绑定（`dynamic`），始终新建独立实例。
5. 不要尝试提权；`build` 失败的 DLL 绝不能 `run`；不得补造数据，上游缺失须在报告中如实标注；覆盖已有文件前必须先获得用户确认。
6. Skill 产物（`.cs` / `.dll` / `.md`）统一放在 `Office/Task/<Skill>/`。


## Vismockup → JT → NX 流程注意点（强制）

凡是涉及从 Vismockup 导出 Hierarchy / JT、转换为 NX prt、或焊点 LFO / LWE 计算的请求，先阅读 `Memory/Costomer/` 下相关主题文件：`vismockup_hierarchy_export.md`（Hierarchy 选择、JT 导出 ini、焊点导出）、`jt_to_nx_conversion.md`（B-rep 转换）、`ford_part_numbering.md`（零件号 / 版本号 / 左右对称规则）、`nx_weld_lfo_lwe.md`（焊点计算与匹配兜底）、`nx_assembly_transform.md`（实例坐标变换）。


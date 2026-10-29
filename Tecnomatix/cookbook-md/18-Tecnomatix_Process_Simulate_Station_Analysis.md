# Tecnomatix Process Simulate — Station Process Analysis Guide

General guide for analyzing the process flow of the Study that is currently open in Process Simulate (PS): what the station builds, what every robot does, how parts are picked / placed / welded, and which stations are GEO or re-spot. It is a read-only analysis workflow; it never changes or saves the Study.

Role: act as both a **simulation engineer** (resource tree, kinematics, operations, robot programs) and a **senior body-in-white (BIW) manufacturing engineer** (area, part joining logic, station roles, cycle time).

Related files:
- `Tecnomatix/Tecnomatix_ai_skills.md` — mandatory entry point (`txai.ps1`), safety rules, templates.
- `Tecnomatix/Task/AnalyzeStudyProcess/AnalyzeStudyProcess.md` — structure dump skill (resources, assembly, kinematics, operations).
- `Tecnomatix/Task/AnalyzeStudyWeldParts/AnalyzeStudyWeldParts.md` — weld points, weld operations, part tree, pick/place robot commands.
- `Memory/Costomer/tx_study_analysis.md` — pitfalls TX-01..TX-06.

## 1. Prerequisites and rules
1. A Study is open in PS and the AI Bridge is started. Run `txai.ps1 setup` first in every session; do not continue on a non-zero exit code.
2. Always call through `txai.ps1` with absolute paths and set `$env:MFG_TASK_HINT` first (for example `'weld GEO 工艺流程'`):
   `powershell -NoProfile -ExecutionPolicy Bypass -File <abs path>\Tecnomatix\Tecnomatix-AI-Client\tools\txai.ps1 run <Skill> -ArgsJson '{...}' -TimeoutMs 300000`
3. Both analysis skills are read-only. A skill that modifies the Study still needs user confirmation first.
4. Large studies produce tens of MB: redirect the output to a file, decode it (redirected output is UTF-16 when it starts with `FF FE`), then summarize with Python. Never print the whole JSON.
5. Reuse the two skills above before writing a new one. Write new skills only for missing data, following `Tecnomatix_ai_skills.md`.

## 2. Workflow (8 steps)
| Step | Question | Source |
|---|---|---|
| 1 | What is the layout? | `AnalyzeStudyProcess`: resource root groups and categories (ROBOT / JIG / GUN / GRIPPER / TRANSPORTATION / HUMAN), `resourceTypeHistogram` |
| 2 | Which BIW area does it build? | Product `TxCompoundPart` hierarchy (`partTree`, `attachParent`) and part numbers |
| 3 | What does each robot carry? | Robot joints, external axes, `mountedTools`, gun / gripper names, tool-changer attach relations |
| 4 | How do clamps / fixtures / turntables behave? | Devices with prismatic / revolute joints, `devicePoses`, `deviceJoints`, fixture clamp counts |
| 5 | What is the operation sequence and cycle time? | Operation tree: compound operations per robot / product, durations, `in/out` links, signals |
| 6 | What does each handling robot pick and place? | Robot-program commands of pick / place / drop locations (`diag.probe`) |
| 7 | Which parts does each weld robot join? | `weldPoints[].assignedParts` statistics per robot, gun and model |
| 8 | Station role: GEO or re-spot? | Pair statistics plus part hierarchy plus operation names (see section 4) |

### 2.1 Step 1: layout
- Station groups at the resource root (for example `UB1010..UB1050`) give the line; categories give the equipment mix.
- Count robots by type (weld robots with servo guns, handling robots with grippers, glue / sealer robots), fixtures (JIG), docking stations (sub-assembly inputs), transfer / conveyor devices, turntables.
- A turntable with named poses (for example HOME / model codes) means a flexible multi-model line; the same fixture and gripper serve several models.

### 2.2 Step 2: BIW area
Judge the area from the product hierarchy, not from names alone:
| Area | Typical parts |
|---|---|
| Engine compartment | Front rail, shock tower / apron, radiator support, dash-front cross members |
| Front floor | Front floor panel, tunnel, front cross members, seat cross members |
| Rear floor | Rear floor panel, rear rails, spare-tyre well, rear cross members |
| Underbody assembly | Front floor + rear floor + dash / front end (+ engine compartment) |
| Body side | Side outer, A / B / C pillars, roof rail, inner panels |
| Main buck (framing) | Underbody + both body sides + roof bows / roof |
| Closures | Doors, hood, tailgate / trunk lid |

Read the top compound part under the station and its children: what parts exist at this level, what the parent assembly adds (for example the next level adds side members or body sides). A part-number prefix per vehicle model (for example three model prefixes) shows a mixed-model line.

### 2.3 Step 3 and 4: equipment
- Robot type: joint count, external axes (rail / gantry), payload class from name, base frame and TCP.
- Gripper (handling): attached on the robot flange; pins (locating) + clamps; names such as `H1xx` identify the tool.
- Gun (welding): servo / pneumatic spot gun; tool changers let two robots share one gun.
- Tool stands (for example `R12x`): gripper / gun change positions; Load / Unload operations are tool change, not production moves.
- Fixtures: clamp count (about 90 clamps on a floor fixture is normal); the clamp close order matters for pick / place analysis.

### 2.4 Step 5: sequence and cycle time
- Treat compound-operation duration as model data, not automatically production cycle time. First inspect unusually long location durations (especially HOME), waits, parallel branches and scheduling links; identify a bottleneck only when these dependencies and the production scope have been verified.
- `in/out` links, wait-device commands, and interference zones give the dependencies between robots.
- `EnterZone / ExitZone(n):R1&R2` in the robot program are interference zones: two robots share space and are sequenced.
- Operation types: weld operation with weld points = spot welding; seam = laser / arc / sealer; glue operations (`GLUE`, `Purge`) = adhesive; `Service` = maintenance (tip dress / gun service).
- Skip `*LocationOperation` (via points) in listings; they are only counted.

## 3. Pick / place analysis (the key BIW question)
In many studies pick / place / drop operations are **`TxWeldOperation` objects with an empty weld-point list**, not `TxGripperOperation`, and the attach events are empty. The semantics are only in the robot-program commands of the location operations (`TxRoboticCommand.Text`).

| Command pattern | Meaning |
|---|---|
| `# Display X_GRIPPER` + `# Blank X_<part/rack>` at the `pick` location | Part leaves the rack and attaches to the gripper (the gripper-with-part model is shown, the loose part is hidden) |
| `# Destination <gripper H1xx>` | The device that is driven (the gripper that grips) |
| `# Drive pin push / clamp close` after pick | Locating pins in and clamps closed: part is gripped |
| `# Display X_FIXTURE` + `# Blank X_GRIPPER` at `drop` / `place` | Part is put on the fixture |
| `# Destination <fixture F1xx>` + `# Drive clamp close` first | The fixture clamps first |
| `# Drive pin draw / clamp open` on the gripper after that | The gripper releases only after the fixture clamps |
| `# WaitDevice` | Waits for a device (clamp / pin) to reach its pose |

Reading order for one handling robot:
1. Which gripper does it use (tool stand, Load operation)?
2. Pick location(s): which part, from which rack / container (rack-side names such as `Container1/2` are inferred as two rack positions).
3. Place location: which fixture or which next position (`FIXTURE2`, transfer fixture, next-station location).
4. Release sequence: fixture clamp close, then gripper pin draw and clamp open.
5. Special robots:
   - Picks the **whole assembly** (display item named like a fixture / assembly) and places at a second location: unloading / transfer robot, takes the welded assembly to the next station.
   - Extra pick positions ("other pick points"): a different pick for a different variant.
6. Model variants (`_P789`, `_U725` style suffixes): same robot, same sequence, different part and fixture per model; shared grippers appear in several model chains.

## 4. GEO versus re-spot
Definitions (BIW):
- **GEO station**: positions (locates) and joins separate parts into one assembly with enough spot welds to hold geometry. It has fixtures with many clamps, handling robots that load parts, and weld robots that join two or more different parts.
- **Re-spot station (补焊)**: adds the remaining weld points of an assembly whose geometry is already fixed. Few or no loading robots, mostly weld robots, no part joining, weld points often on parts already joined or on a single part.

Evidence from the data:
| Evidence | GEO | Re-spot |
|---|---|---|
| Handling robots loading separate parts | yes | no / only transfer |
| Weld point `assignedParts` | pairs of two different parts | one part, or pairs already tacked upstream |
| Fixture | many clamps, locating pins | usually transfer / light fixture |
| Weld count | tens of points per robot | many points, short per-point time |

Procedure: count weld points per (robot, gun, model, part pair), then compare newly introduced components, fixture location and upstream joins. Different-part pairs prove a joint, not necessarily GEO: downstream re-spot can weld the same pairs. Empty or single-part assignments alone do not prove re-spot or sealing. Operation names support but do not decide. Mark unsupported station roles as **inferred**; empty operation folders establish missing program evidence, not an idle real station.

For each GEO station report: "robot X (gun Y) joins part A + part B, N points per model".

## 5. Analysis output template
Reply (Chinese when the user writes Chinese) with these sections:
1. BIW area and models (with the part hierarchy that proves it).
2. Handling robots table: robot, gripper, picks (part, from where), places (fixture / position), release order.
3. GEO stations: weld robots, guns, part pairs, point counts per model; shared guns / tool changers.
4. Re-spot / seal stations and single-part points (marked as inferred).
5. Station roles for stations with no data (layout only, marked as inferred).
6. Cycle times per robot and bottleneck.
7. Uncertainties (naming-based inference, unverified model parts).

## 6. Pitfalls (details in `Memory/Costomer/tx_study_analysis.md`)
- `TxKinematicLink` floods the resource dump: skip it and still recurse devices (TX-01).
- Skip location operations, raise `maxNodes`, save output to a file and summarize (TX-02).
- Absolute paths for file edits; Chinese text only via the `create` tool (TX-03).
- Pick / place operations are `TxWeldOperation` with no weld points; semantics are in `TxRoboticCommand.Text` (TX-04).
- Use `AssignedParts` for GEO / re-spot, never operation names alone (TX-05).
- Redirected run output is UTF-16; CRLF source patches need single-line replaces (TX-06).

## 7. Worked example (shape of a result)
A floor station with three models, a turntable and 8 robots resolved as: area = underbody (floor) assembly; two loading robots for front / rear floor from racks to a shared fixture; one loading robot for the dash / front end; four spot-weld robots in two pairs (front floor + front end, front floor + rear floor) as GEO; one unloading robot lifting the welded assembly off the fixture; single-part points and a `fengping` operation as re-spot / seal (inferred); the front-floor loading robot as the bottleneck.

---

# Tecnomatix Process Simulate — 工位工艺流程分析指南

用于分析 Process Simulate（PS）中当前已打开 Study 的工艺流程的通用指南：这个工位做什么、每个机器人做什么、零件如何抓取 / 放置 / 焊接、哪些工位是 GEO 或补焊。这是只读分析流程，不会修改或保存 Study。

角色：同时扮演**仿真工程师**（资源树、运动学、操作、机器人程序）和**高级白车身（BIW）焊装制造工程师**（区域、零件拼合逻辑、工位角色、节拍）。

相关文件：
- `Tecnomatix/Tecnomatix_ai_skills.md` — 强制入口（`txai.ps1`）、安全规则、模板。
- `Tecnomatix/Task/AnalyzeStudyProcess/AnalyzeStudyProcess.md` — 结构导出 skill（资源、装配、运动学、操作）。
- `Tecnomatix/Task/AnalyzeStudyWeldParts/AnalyzeStudyWeldParts.md` — 焊点、焊接操作、零件树、抓放机器人命令。
- `Memory/Costomer/tx_study_analysis.md` — 踩坑 TX-01..TX-06。

## 1. 前置条件与规则
1. PS 已打开 Study，AI Bridge 已启动。每个会话先运行 `txai.ps1 setup`；退出码非 0 不得继续。
2. 始终通过 `txai.ps1` 并使用绝对路径调用，调用前先设置 `$env:MFG_TASK_HINT`（如 `'weld GEO 工艺流程'`）：
   `powershell -NoProfile -ExecutionPolicy Bypass -File <abs path>\Tecnomatix\Tecnomatix-AI-Client\tools\txai.ps1 run <Skill> -ArgsJson '{...}' -TimeoutMs 300000`
3. 上述两个分析 skill 都是只读的。会修改 Study 的 skill 仍须先获得用户确认。
4. 大型 Study 输出数十 MB：把输出重定向到文件并解码（重定向输出以 `FF FE` 开头时是 UTF-16），再用 Python 汇总。不要打印整个 JSON。
5. 先复用上面两个 skill，只有数据缺失时才按 `Tecnomatix_ai_skills.md` 新写 skill。

## 2. 工作流程（8 步）
| 步骤 | 问题 | 数据来源 |
|---|---|---|
| 1 | 布局是什么？ | `AnalyzeStudyProcess`：资源根分组与类别（ROBOT / JIG / GUN / GRIPPER / TRANSPORTATION / HUMAN）、`resourceTypeHistogram` |
| 2 | 做白车身哪个区域？ | 产品 `TxCompoundPart` 层级（`partTree`、`attachParent`）与零件号 |
| 3 | 每个机器人带什么工具？ | 机器人关节、外部轴、`mountedTools`、焊枪 / 抓手名称、换枪盘附着关系 |
| 4 | 夹具 / 夹紧 / 转台如何动作？ | 带移动 / 旋转关节的设备、`devicePoses`、`deviceJoints`、夹具夹爪数量 |
| 5 | 工序顺序与节拍？ | 操作树：每机器人 / 每产品的复合操作、时长、`in/out` 链接、信号 |
| 6 | 每个搬运机器人抓什么、放哪里？ | pick / place / drop 位置的机器人程序命令（`diag.probe`） |
| 7 | 每个焊接机器人焊哪些零件？ | 按机器人、焊枪、车型统计 `weldPoints[].assignedParts` |
| 8 | 工位角色：GEO 还是补焊？ | 零件对统计 + 零件层级 + 操作名称（见第 4 节） |

### 2.1 步骤 1：布局
- 资源根下的工位分组（如 `UB1010..UB1050`）给出产线；类别给出设备构成。
- 按类型统计机器人（带伺服焊枪的焊接机器人、带抓手的搬运机器人、涂胶 / 密封机器人）、夹具（JIG）、对接工位（分总成输入）、输送 / 转运设备、转台。
- 带命名姿态的转台（如 HOME / 车型代码）表示柔性多车型产线：同一夹具和抓手服务多个车型。

### 2.2 步骤 2：白车身区域
按产品层级判断区域，不能只看名称：
| 区域 | 典型零件 |
|---|---|
| 机舱 | 前纵梁、减震塔 / 翼子板内板、水箱框架、前围横梁 |
| 前地板 | 前地板、通道、前横梁、座椅横梁 |
| 后地板 | 后地板、后纵梁、备胎坑、后横梁 |
| 底板总成 | 前地板 + 后地板 + 前围 / 前端（+ 机舱） |
| 侧围 | 侧围外板、A / B / C 柱、顶盖边梁、内板 |
| 主拼（总拼） | 底板总成 + 左右侧围 + 顶盖横梁 / 顶盖 |
| 门盖 | 车门、发动机盖、背门 / 行李箱盖 |

读取工位下的顶层复合零件及其子件：本层有哪些零件，上一级装配新增什么（如上一级加入侧梁或侧围）。每个车型一个零件号前缀（如三个车型前缀）表示混线生产。

### 2.3 步骤 3 和 4：设备
- 机器人类型：关节数、外部轴（地轨 / 龙门）、从名称看负载级别、基坐标和 TCP。
- 抓手（搬运）：装在机器人法兰上；销（定位）+ 夹爪；`H1xx` 之类的名称标识工具。
- 焊枪（焊接）：伺服 / 气动点焊枪；换枪盘使两台机器人可共用一把枪。
- 工具架（如 `R12x`）：抓手 / 焊枪更换位置；Load / Unload 操作是换工具，不是生产动作。
- 夹具：夹爪数量（地板夹具约 90 个夹爪属正常）；夹爪闭合顺序对抓放分析很重要。

### 2.4 步骤 5：顺序与节拍
- 复合操作时长只是模型数据，不能自动当作生产节拍；先检查异常长的位置时长（尤其 HOME）、等待、并行分支与排程连接，只有依赖关系和生产范围均核实后才能判断瓶颈。
- `in/out` 链接、等待设备命令和干涉区给出机器人之间的依赖。
- 机器人程序里的 `EnterZone / ExitZone(n):R1&R2` 是干涉区：两台机器人共用空间，需要排序。
- 操作类型：带焊点的焊接操作 = 点焊；seam = 激光 / 弧焊 / 密封；涂胶操作（`GLUE`、`Purge`）= 胶；`Service` = 维护（修磨 / 枪保养）。
- 列表时跳过 `*LocationOperation`（过渡点），只计数。

## 3. 抓取 / 放置分析（白车身的关键问题）
许多 Study 中 pick / place / drop 操作是**焊点列表为空的 `TxWeldOperation` 对象**，不是 `TxGripperOperation`，attach 事件也是空的。语义只存在于位置操作的机器人程序命令（`TxRoboticCommand.Text`）中。

| 命令模式 | 含义 |
|---|---|
| `pick` 位置的 `# Display X_GRIPPER` + `# Blank X_<零件/料架>` | 零件离开料架并挂到抓手上（显示带零件的抓手模型，隐藏散件） |
| `# Destination <抓手 H1xx>` | 被驱动的设备（抓取用的抓手） |
| 抓取后的 `# Drive pin push / clamp close` | 定位销伸出、夹爪闭合：零件已被夹持 |
| `drop` / `place` 的 `# Display X_FIXTURE` + `# Blank X_GRIPPER` | 零件放到夹具上 |
| `# Destination <夹具 F1xx>` + 先 `# Drive clamp close` | 夹具先夹紧 |
| 之后抓手的 `# Drive pin draw / clamp open` | 夹具夹紧后抓手才松开 |
| `# WaitDevice` | 等待设备（夹爪 / 销）到位 |

单个搬运机器人的解读顺序：
1. 使用哪个抓手（工具架、Load 操作）？
2. 抓取位置：什么零件，从哪个料架 / 料盒（`Container1/2` 之类的料架侧名称按两个料架位置推断）。
3. 放置位置：哪个夹具或哪个下一位置（`FIXTURE2`、转运夹具、下一工位位置）。
4. 释放顺序：夹具夹紧闭合，然后抓手销抽出、夹爪打开。
5. 特殊机器人：
   - 抓取**整个总成**（显示项命名像夹具 / 总成）并放到第二个位置：卸料 / 转运机器人，把焊好的总成送往下一工位。
   - 额外抓取位置（"other pick points"）：不同变型使用不同抓取点。
6. 车型变体（`_P789`、`_U725` 之类后缀）：同一机器人、同一顺序，每个车型的零件和夹具不同；共用抓手会出现在多个车型链中。

## 4. GEO 与补焊
定义（白车身）：
- **GEO 工位**：把分开的零件定位并焊成一个总成，点数足以保持几何。有多夹爪的夹具、负责上料的搬运机器人，以及焊接两个或更多不同零件的焊接机器人。
- **补焊工位**：给几何已经固定的总成补焊剩余焊点。上料机器人很少或没有，以焊接机器人为主，不拼合零件，焊点常落在已连接的零件或单个零件上。

数据证据：
| 证据 | GEO | 补焊 |
|---|---|---|
| 搬运机器人上料散件 | 有 | 无 / 只有转运 |
| 焊点 `assignedParts` | 两个不同零件的零件对 | 单个零件，或上游已点固的零件对 |
| 夹具 | 多夹爪、定位销 | 通常是转运 / 轻型夹具 |
| 焊点数量 | 每机器人数十点 | 点数多、单点时间短 |

方法：按（机器人、焊枪、车型、零件对）统计焊点数，再比较新增零件、定位夹具和上游连接。不同零件配对只证明连接关系，不能单独证明是 GEO，下游补焊也可能焊同一零件对；空关联或单零件关联也不能单独证明补焊或密封。操作名称只作佐证，不作决定。无充分证据的工位角色标为**推断**；操作文件夹为空代表缺少程序证据，不证明实际工位不工作。

每个 GEO 工位按下面格式汇报："机器人 X（焊枪 Y）焊接零件 A + 零件 B，每车型 N 点"。

## 5. 分析输出模板
回复（用户用中文就用中文）包含以下部分：
1. 白车身区域与车型（附证明它的零件层级）。
2. 搬运机器人表：机器人、抓手、抓取（零件、从哪里）、放置（夹具 / 位置）、释放顺序。
3. GEO 工位：焊接机器人、焊枪、零件对、每车型点数；共用焊枪 / 换枪盘。
4. 补焊 / 密封工位及单零件焊点（标注为推断）。
5. 无数据工位的角色（只有布局，标注为推断）。
6. 每机器人节拍与瓶颈。
7. 不确定项（按命名推断、未验证的车型零件）。

## 6. 踩坑（详见 `Memory/Costomer/tx_study_analysis.md`）
- `TxKinematicLink` 淹没资源导出：跳过它，但仍然递归设备（TX-01）。
- 跳过位置操作、提高 `maxNodes`、输出存文件后汇总（TX-02）。
- 编辑文件用绝对路径；中文文本只通过 `create` 工具写入（TX-03）。
- 抓放操作是无焊点的 `TxWeldOperation`；语义在 `TxRoboticCommand.Text`（TX-04）。
- 判断 GEO / 补焊用 `AssignedParts`，不能只凭操作名称（TX-05）。
- 重定向的运行输出是 UTF-16；修补 CRLF 源码要用单行替换（TX-06）。

## 7. 实例（结果的形态）
一个三车型、带转台、8 台机器人的地板工位的结论：区域 = 底板（地板）总成；两台上料机器人把前 / 后地板从料架送到共用夹具；一台上料机器人送前围 / 前端；四台点焊机器人分两组（前地板 + 前端、前地板 + 后地板）做 GEO；一台卸料机器人把焊好的总成从夹具取走；单零件焊点和 `fengping` 操作为补焊 / 密封（推断）；上前地板的机器人是瓶颈。

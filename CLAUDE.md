# Industry-Digital-Software-AI-Tools — Agent Entry (Claude Code / Claude clients)

This file is only an entry point. The single source of truth is `.github/copilot-instructions.md`.

**Before doing anything, read `.github/copilot-instructions.md` completely and follow it as if it were this file** (global rules G1-G3, session start, self-learning, per-product rules). Do not keep a separate copy of the rules here.

Client notes (non-Copilot clients):

- Run all runners with `powershell -NoProfile -ExecutionPolicy Bypass -File <absolute path>\...` on Windows; relative paths fail.
- G2 token report: there is no Copilot transcript here, so use manual mode with your own estimate of the turn:
  `powershell -NoProfile -ExecutionPolicy Bypass -File <absolute path>\tools\tokencost.ps1 -Model <model id> -InChars <chars read this turn> -OutChars <chars written this turn> -Calls <model calls>`
  If your transcript folder is known, set `MFG_TRANSCRIPT_DIR` instead to get the full replay. Always label the result as an estimate.
- Wherever the shared instructions say "Copilot", read it as "the current agent client".
- Claude Desktop (chat app) has no terminal or file tools by default; it needs a filesystem/shell MCP server to use this project.

---

# Industry-Digital-Software-AI-Tools — Agent 入口（Claude Code / Claude 客户端）

本文件只是入口。唯一的规则来源是 `.github/copilot-instructions.md`。

**开始任何工作前，先完整阅读 `.github/copilot-instructions.md`，并把它当作本文件一样严格遵循**（全局规则 G1-G3、会话启动、自学习、各产品规则）。不要在这里另存一份规则副本。

客户端说明（非 Copilot 客户端）：

- Windows 上所有 runner 必须用 `powershell -NoProfile -ExecutionPolicy Bypass -File <绝对路径>\...` 调用；相对路径会失败。
- G2 token 报告：这里没有 Copilot 对话记录，请使用手动模式，自行估算本次对话：
  `powershell -NoProfile -ExecutionPolicy Bypass -File <绝对路径>\tools\tokencost.ps1 -Model <模型 id> -InChars <本次读取的字符数> -OutChars <本次输出的字符数> -Calls <模型调用次数>`
  若知道对话记录目录，可设置环境变量 `MFG_TRANSCRIPT_DIR` 以获得完整回放估算。结果必须标明是估算值。
- 共享指令中出现的 “Copilot”，一律理解为“当前使用的 agent 客户端”。
- Claude Desktop（聊天应用）默认没有终端和文件工具；要使用本项目，需要接入文件系统 / shell 的 MCP 服务器。

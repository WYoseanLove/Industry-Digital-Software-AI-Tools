# Token and Cost Estimation

## Purpose

Every assistant reply ends with an estimated token count and cost (rule G2 in `.github/copilot-instructions.md`), so users can see what each request costs.

## Important limits

- The assistant cannot read real usage counters. The numbers are an **estimate**, never exact.
- The Copilot transcript contains user text, assistant text and tool-call arguments, but not tool results or hidden reasoning. These are approximated.
- Real billing depends on your plan (premium requests, included usage, enterprise contracts). The USD figures are list token prices, for orientation only.

## Usage

```
powershell -NoProfile -ExecutionPolicy Bypass -File <absolute path>\tools\tokencost.ps1 -Model claude-sonnet-5.5
```

| Parameter | Meaning | Default |
|---|---|---|
| `-Model` | Model id used for the headline figure | `claude-sonnet-5.5` |
| `-Compare` | Other model ids priced side by side | haiku-5.5, sonnet-5.5, opus-5.5, gpt-6-sol, gemini-3.8-flash |
| `-Session` | Transcript `.jsonl` to analyse | newest transcript |
| `-Base` | Tokens sent on every call (system prompt, tool schemas, attachments) | 25000 |
| `-ToolResult` | Average tokens of tool output per tool call | 800 |
| `-MaxContext` | Context size at which auto-summarisation is assumed | 150000 |
| `-TranscriptDir` | Folder searched recursively for the newest `*.jsonl` transcript (env `MFG_TRANSCRIPT_DIR`) | VS Code Copilot transcripts |
| `-InChars` / `-OutChars` / `-Calls` | Manual mode: input characters, output characters, number of model calls this turn | 0 / 0 / 1 |
| `-Refresh` | Rebuild `tools/model_prices.json` from Copilot `models.json` | off |

Exit codes: 0 ok, 20 no transcript found (and no manual figures given), 21 no price snapshot.

Manual mode (Codex, Claude and other clients without a Copilot transcript): when no transcript is found and `-InChars` or `-OutChars` is given, the script estimates this turn only from the figures supplied (Latin text assumed, CJK is under-counted); the session total is reported as n/a.

```
powershell -NoProfile -ExecutionPolicy Bypass -File <absolute path>\tools\tokencost.ps1 -Model <id> -InChars <n> -OutChars <n> -Calls <n>
```

## Method

1. Tokens per text: Latin characters / 4, CJK characters / 1.5.
2. Each model call re-sends the whole context: the part already billed by the previous call is priced at the cache-read price, the new part at the input price; output is priced at the output price.
3. Cost (USD) = (fresh x input + cached x cache_read + output x output) / 1,000,000.
4. Prices are read from `tools/model_prices.json` (cents per 1M tokens in the source, shown as USD per 1M tokens in the report).

## Reference prices (USD per 1M tokens, snapshot from Copilot model list)

| Model | Input | Output | Cache read |
|---|---|---|---|
| claude-haiku-5.5 | 0.10 | 0.50 | 0.01 |
| claude-sonnet-5.5 | 2.00 | 10.00 | 0.10 |
| claude-opus-5.5 | 4.00 | 20.00 | 0.20 |
| gpt-6-sol | 2.00 | 10.00 | 0.20 |
| gemini-3.8-flash | 0.75 | 3.75 | 0.075 |

Prices change. Run `tokencost.ps1 -Refresh` inside a Copilot session to update the snapshot.

---

# Token 与费用估算

## 目的

每次助手回复末尾都附带估算的 token 数量与费用（`.github/copilot-instructions.md` 的规则 G2），让用户了解每次请求的成本。

## 重要限制

- 助手读不到真实用量计数器，所以数字是**估算值**，绝不是精确值。
- Copilot 对话记录包含用户文本、助手文本和工具调用参数，但不包含工具返回内容与隐藏推理，这两部分用近似值补充。
- 实际计费取决于你的套餐（高级请求、包含额度、企业合同）。美元数字是公开的 token 标价，仅供参考。

## 用法

```
powershell -NoProfile -ExecutionPolicy Bypass -File <绝对路径>\tools\tokencost.ps1 -Model claude-sonnet-5.5
```

| 参数 | 含义 | 默认值 |
|---|---|---|
| `-Model` | 主要显示的模型 id | `claude-sonnet-5.5` |
| `-Compare` | 并列对比的其它模型 id | haiku-5.5、sonnet-5.5、opus-5.5、gpt-6-sol、gemini-3.8-flash |
| `-Session` | 要分析的对话记录 `.jsonl` | 最新的对话记录 |
| `-Base` | 每次调用都会发送的 token（系统提示词、工具定义、附件） | 25000 |
| `-ToolResult` | 每次工具调用返回内容的平均 token | 800 |
| `-MaxContext` | 假定触发自动摘要的上下文大小 | 150000 |
| `-TranscriptDir` | 递归查找最新 `*.jsonl` 对话记录的目录（环境变量 `MFG_TRANSCRIPT_DIR`） | VS Code Copilot 对话记录 |
| `-InChars` / `-OutChars` / `-Calls` | 手动模式：本轮输入字符数、输出字符数、模型调用次数 | 0 / 0 / 1 |
| `-Refresh` | 从 Copilot `models.json` 重建 `tools/model_prices.json` | 关 |

退出码：0 正常，20 找不到对话记录（且未提供手动数值），21 没有价格快照。

手动模式（Codex、Claude 等没有 Copilot 对话记录的客户端）：找不到对话记录且提供了 `-InChars` 或 `-OutChars` 时，脚本仅按所给数值估算本轮（按拉丁文本计算，中日韩字符会被低估）；会话累计显示为 n/a。

```
powershell -NoProfile -ExecutionPolicy Bypass -File <绝对路径>\tools\tokencost.ps1 -Model <id> -InChars <n> -OutChars <n> -Calls <n>
```

## 方法

1. 文本 token：拉丁字符数 / 4，中日韩字符数 / 1.5。
2. 每次模型调用都会重发整个上下文：上一次调用已计费的部分按缓存读取价，新增部分按输入价；输出按输出价。
3. 费用（美元）= (新增输入 x 输入价 + 缓存输入 x 缓存读取价 + 输出 x 输出价) / 1,000,000。
4. 价格读取自 `tools/model_prices.json`（源数据单位为美分 / 百万 token，报告中显示为美元 / 百万 token）。

## 参考价格（美元 / 百万 token，来自 Copilot 模型列表快照）

| 模型 | 输入 | 输出 | 缓存读取 |
|---|---|---|---|
| claude-haiku-5.5 | 0.10 | 0.50 | 0.01 |
| claude-sonnet-5.5 | 2.00 | 10.00 | 0.10 |
| claude-opus-5.5 | 4.00 | 20.00 | 0.20 |
| gpt-6-sol | 2.00 | 10.00 | 0.20 |
| gemini-3.8-flash | 0.75 | 3.75 | 0.075 |

价格会变动。在 Copilot 会话中运行 `tokencost.ps1 -Refresh` 可更新快照。

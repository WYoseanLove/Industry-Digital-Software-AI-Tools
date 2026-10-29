---
title: Task execution and communication workflow rules / 任务执行与沟通流程规则
scope: all
triggers: 用户纠正, user correction, 停止, stop, 覆盖, overwrite, 报告, report, 批量, batch, 验证, verify, 汇报, reporting
always: true
updated: 2026-10-23
---
# Task execution and communication workflow rules / 任务执行与沟通流程规则

## TW-01 When the user says "cut it off", stop immediately / 用户说“先断掉”立即停
- Stop immediately and explain the problem encountered; do not keep forcing the run.
- 立即停止并说明遇到的问题，不要继续硬跑。

## TW-02 User corrections take priority / 用户纠正优先
- The user's correction takes priority over existing assumptions; after each correction, first restate your understanding before acting, and record it in Memory immediately.
- 用户的纠正优先于既有假设；每次纠正后先重述理解再动手，并立刻记入 Memory。

## TW-03 Confirm before overwriting files; write results to new file names / 覆盖文件要确认，结果写新文件名
- Get consent before overwriting an existing file; write new results to a new file name (e.g. add a version suffix `_v2`).
- 覆盖已有文件前先征得同意；新结果用新文件名（如加版本后缀 `_v2`）。

## TW-04 Single spot first, then batch / 先单点后批量
- Before a batch run, verify with the single sample the user specified, then scale up.
- 做批量前先用用户指定的单个样例验证，再放大。

## TW-05 Reporting / 汇报
- Excel reports only through `officerun.ps1`; mark missing data honestly and do not fabricate. Data problems in the results (wrong part numbers etc.) must be pointed out separately in the report.
- Excel 汇报只用 `officerun.ps1`；数据缺失如实标注，不补造。结果里有数据问题（零件号错误等）要在汇报中单独指出。

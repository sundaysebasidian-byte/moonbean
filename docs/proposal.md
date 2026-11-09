# MoonBean 申报书

- 项目名称：MoonBean — Beancount v3 兼容的纯文本复式记账引擎
- 仓库：https://github.com/sundaysebasidian-byte/moonbean
- 在线体验：https://sundaysebasidian-byte.github.io/moonbean/

## 解决什么问题，给谁用

Beancount 依赖 Python，难以嵌入应用，也不能在浏览器里离线运行。MoonBean 用同一套账本语法和记账语义，用 MoonBit 从零实现解析、记账（booking）、校验、报表和 BQL 查询。库只有纯函数，在 native、wasm-gc、JavaScript 上都能跑，不依赖文件系统和外部进程；另有 native 命令行和浏览器离线 Playground。面向个人和小企业记账、已有 Beancount 账本的用户，以及需要离线或嵌入式记账的应用（`include` 由宿主回调提供）。

## 兼容终点与当前边界

兼容终点是 beancount 3.2.3 的语法与记账语义，以及 beanquery 0.2.0 全集；0.2.3 尚未达到全集，不作完整兼容声明。[逐项清单](compatibility.md)列出全部 oracle 表/列、函数签名、option 默认值和当前证据与缺口。

| 范围 | 当前可核对边界 |
| --- | --- |
| 记账与指令 | open/close/commodity/balance/pad/price/transaction、include 与元数据栈有差分证据；document 仅校验账户并警告未检查文件；note/event/query/custom 保留语法与数据，未证明所有错误类别一致。query 存储后由调用方显式执行 |
| BQL | postings/transactions 的 SELECT、星号、DISTINCT、筛选、分组、排序、计数与交易 accounts/meta 查询；DISTINCT 限于标量/集合投影，position/inventory 明确拒绝；其余 8 张 oracle 表、完整列与函数集、FLATTEN、PIVOT BY、子查询、CLEAR、PRINT/EXPLAIN、Unicode upper/lower 尚未实现。LIKE/JOIN 被 oracle 拒绝，不属于终点 |
| option | booking、容差推断、按币种和通配符默认容差有证据；operating_currency 仅单币种报表转换；account_rounding、render_commas、documents 等未实现的效果逐项披露，不能仅凭解析成功计为兼容 |
| plugin 与扩展 | 五个内置插件有差分证据，其余 Python 插件警告且不执行；AVERAGE、{*}、裸 FROM balances 库存语义均为扩展 |

## 一致性证据

- 116 份自编账本对 beancount 3.2.3 与 beanquery 0.2.0：114 份可比较全部通过，另 2 份用到扩展，只用本项目测试验证。
- 109 条 BQL 输出与能力/拒绝边界检查通过，账本、查询及 oracle 期望输出纳入版本库。
- 两个 seed 各 1000 份随机账本：858 份完全一致，142 份仅因 AVERAGE 扩展不同，其余差异为 0。
- 既有版本的 22 份报表和 lot 回归账本共 144 项检查、5 份迁移边界账本证据保留，未将其计为本轮重跑。
- 四个后端各 136 个测试；Playground 有 29 项 node 检查和 8 项无头浏览器检查；既有 CI 覆盖三个系统、oracle 和 Playground，本候选尚未推送运行 CI。
- 0.2.2 历史性能基线：固定种子、100 万 source posting 的 native release 库阶段中位数：解析 1.931 s、FIFO booking 0.505 s、校验含 pad 1.017 s、BQL GROUP BY 0.812 s（Apple M4 / 16 GiB / MoonBit 0.1.20261104；2 次预热、21 次测量）。[原始数组、阶段 profile 与本地趋势检查](performance.md)均可复现；阶段并非互斥，不可相加。未分组 ORDER BY 在小规模呈二次方增长，10 万/100 万该场景未完成；wasm-gc 的 100 万 FIFO 综合场景因默认 moonrun 堆耗尽未完成。当前候选验收见 [本轮结果](evidence/r2-acceptance.md)。

## 基础与本期工作

2026-10-31 新建仓库，此前没有代码基础；仓库全部提交均为本期工作。技术路线：行级词法 → 指令解析 → booking 与校验 → 报表与 BQL，全部为纯函数，文件读取由宿主回调提供。

## 原创与参考

原创净室实现，非移植。参考 Beancount（https://github.com/beancount/beancount ，GPL-2.0）和 beanquery（https://github.com/beancount/beanquery ，GPL-2.0）的公开文档作为规范，仅把二者当外部黑盒 oracle 比较输出；不复制源码、注释、测试数据、样式或资源，不链接、不嵌入、不分发。本项目 Apache-2.0，见 NOTICE。

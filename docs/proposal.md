# MoonBean 申报书

- 项目名称：MoonBean — Beancount v3 兼容的纯文本复式记账引擎
- 仓库：https://github.com/sundaysebasidian-byte/moonbean
- 在线体验：https://sundaysebasidian-byte.github.io/moonbean/

## 解决什么问题，给谁用

Beancount 依赖 Python，难以嵌入应用，也不能在浏览器里离线运行。MoonBean 以以下逐项兼容边界为范围，用 MoonBit 从零实现解析、记账（booking）、校验、报表和 BQL 查询。库只有纯函数，在 native、wasm-gc、JavaScript 上都能跑，不依赖文件系统和外部进程；另有 native 命令行和浏览器离线 Playground。面向个人和小企业记账、已有 Beancount 账本的用户，以及需要离线或嵌入式记账的应用（`include` 由宿主回调提供）。

## 兼容终点与当前边界

兼容终点是 beancount 3.2.3 的语法与记账语义，以及 beanquery 0.2.0 全集；0.2.3 尚未达到全集，不作完整兼容声明。[逐项清单](compatibility.md)列出全部 oracle 表/列、函数签名、option 默认值和当前证据与缺口。

| 范围 | 当前可核对边界 |
| --- | --- |
| 记账与指令 | open/close/commodity/balance/pad/price/transaction、include 与元数据栈有差分证据；document 仅校验账户并警告未检查文件；note/event/query/custom 保留语法与数据，未证明所有错误类别一致。query 存储后由调用方显式执行 |
| BQL | 10 张 oracle 表的全部公开列已接入类型值模型，逐列比较 dict/directive/id/discrepancy 与 NULL；带符号零源的精确对象查询明确拒绝。105 个函数签名和 11 个聚合签名已登记参数类型，其中 74 个标量签名已有求值器，仍有 31 个未实现，已实现项也有单列清单中的值域边界。混合聚合按非聚合投影隐式分组；tags/links 的隐式集合分组已对齐，聚合排序目标覆盖及 HAVING 聚合约束有组合差分；bool(Inventory) 对齐 oracle 报错。position DISTINCT 按精确表示去重；子查询、PIVOT BY、FROM 组合、PRINT 与 .explain/.run 未完成。LIKE/JOIN 及已探测的 FLATTEN/EXPLAIN 关键字形式被 oracle 拒绝 |
| option | booking、容差推断、按币种和通配符默认容差有证据；operating_currency 仅单币种报表转换；account_rounding、render_commas、documents 等未实现的效果逐项披露，不能仅凭解析成功计为兼容 |
| plugin 与扩展 | 五个内置插件有差分证据，其余 Python 插件警告且不执行；AVERAGE、{*}、裸 FROM balances 库存语义均为扩展 |

## 一致性证据

- 120 份自编账本对 beancount 3.2.3 与 beanquery 0.2.0：118 份可比较账本全部通过；另 2 份使用扩展，不计为 oracle 一致。
- 3156 项 BQL 检查包含逐表逐列的结构化对象比较、函数 repr/错误类别、随机日期与数值语料，以及 7196 行 Unicode 语料，不把明确拒绝计为功能实现，详见[本轮验收](evidence/r10-acceptance.md)。
- 两个 seed 各 1000 份随机账本：858 份完全一致，142 份仅因 AVERAGE 扩展不同，其余差异为 0。
- 既有版本的 22 份报表和 lot 回归账本共 144 项检查、5 份迁移边界账本证据保留，未将其计为本轮重跑。
- 四个后端各 153 个测试；Playground 有 29 项 node 检查和 8 项无头浏览器检查；既有 CI 覆盖三个系统、oracle 和 Playground，本候选尚未推送运行 CI。
- 0.2.2 历史性能基线：固定种子、100 万 source posting 的 native release 库阶段中位数：解析 1.931 s、FIFO booking 0.505 s、校验含 pad 1.017 s、BQL GROUP BY 0.812 s（Apple M4 / 16 GiB / MoonBit 0.1.20261104；2 次预热、21 次测量）。[原始数组、阶段 profile 与本地趋势检查](performance.md)均可复现；阶段并非互斥，不可相加。旧基线未完成 10 万/100 万 ORDER BY；本轮改为缓存键的稳定 O(n log n) 排序，native 10 万 posting 排序已通过逐行差分，历史门限仍保留大排序跳过项；wasm-gc 的 100 万 FIFO 综合场景因默认 moonrun 堆耗尽未完成。本轮单次矩阵仍有 7 个 wasm-gc 阶段超限，native/JS 未超限；测量前 1 分钟负载 35.22，按要求未因负载复测，不作性能通过结论。当前候选验收见 [本轮结果](evidence/r10-acceptance.md)。

## 基础与本期工作

2026-10-31 新建仓库，此前没有代码基础；仓库全部提交均为本期工作。技术路线：行级词法 → 指令解析 → booking 与校验 → 报表与 BQL，全部为纯函数，文件读取由宿主回调提供。

## 原创与参考

原创净室实现，非移植。参考 Beancount（https://github.com/beancount/beancount ，GPL-2.0）和 beanquery（https://github.com/beancount/beanquery ，GPL-2.0）的公开文档作为规范，仅把二者当外部黑盒 oracle 比较输出；不复制源码、注释、测试数据、样式或资源，不链接、不嵌入、不分发。本项目 Apache-2.0，见 NOTICE。

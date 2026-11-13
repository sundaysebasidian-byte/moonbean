# MoonBean 申报书

- 项目名称：MoonBean — Beancount v3 兼容的纯文本复式记账引擎
- 仓库：https://github.com/sundaysebasidian-byte/moonbean
- 在线体验：https://sundaysebasidian-byte.github.io/moonbean/

## 解决什么问题，给谁用

Beancount 依赖 Python，难以嵌入应用，也不能在浏览器里离线运行。MoonBean 以以下逐项兼容边界为范围，用 MoonBit 从零实现解析、记账（booking）、校验、报表和 BQL 查询。解析、记账和报表在 native、wasm-gc、JavaScript 上共享实现，不依赖文件系统和外部进程；today 与部分日期解析默认值读取宿主时钟；另有 native 命令行和浏览器离线 Playground。面向个人和小企业记账、已有 Beancount 账本的用户，以及需要离线或嵌入式记账的应用（`include` 由宿主回调提供）。

## 兼容终点与当前边界

兼容终点是 beancount 3.2.3 的语法与记账语义，以及 beanquery 0.2.0 全集；0.2.7 尚未达到全集，不作完整兼容声明。[逐项清单](compatibility.md)列出全部 oracle 表/列、函数签名、option 默认值和当前证据与缺口。

| 范围 | 当前可核对边界 |
| --- | --- |
| 记账与指令 | open/close/commodity/balance/pad/price/transaction、include 与元数据栈有差分证据；document 仅校验账户并警告未检查文件；note/event/query/custom 保留语法与数据，未证明所有错误类别一致。query 存储后由调用方显式执行 |
| BQL | 10 张 oracle 表的全部公开列已接入类型值模型；105 个标量签名均有完整或受限求值器。0.2.6 补入 interval、date_bin、parse_date、today，增加独立 PRINT 指令文本结果、FROM 过滤与 OPEN/CLOSE/CLEAR 变换、规范 JOURNAL/BALANCES、IN/BETWEEN/取模、引号查列与混合聚合引用，并修复 round 负零/精度溢出、两位年份、日期及 interval 算术、coalesce、空匹配替换、连字符截断、标量聚合 DISTINCT 与未知列/表错误类别。独立复审还修复 Unicode 账户、按币种 balance 判重、OPEN 顺序及成本汇总、CLEAR 日期和 PRINT 分组/引号/过滤顺序。PRINT 证据仅覆盖指定的 84 条语句 × 142 份账本及旧有语料，不声明任意输出等价；interval−date 与 oracle 一样报 Evaluation，其余所列 interval 算术有差分。CPython 随机集合顺序、移植正则引擎以外的 Python 特性、有限 Decimal 与尚未穷尽的语法/对象组合和 shell .explain/.run 仍有缺口；0.2.7 的 wasm-gc 可通过可选 host_clock import 逐次读取宿主本地日期及 DST；未接入或服务不可用时回退 UTC，裸 moonrun 仍使用 UTC。日期解析覆盖以差分语料为界，未证明全部 dateutil/locale 行为。LIKE/JOIN 及已探测 FLATTEN/EXPLAIN 关键字形式被 oracle 拒绝 |
| option | booking、容差推断、按币种和通配符默认容差有证据；operating_currency 仅单币种报表转换；account_rounding、render_commas、documents 等未实现的效果逐项披露，不能仅凭解析成功计为兼容 |
| plugin 与扩展 | 五个内置插件有差分证据，其余 Python 插件警告且不执行；AVERAGE、{*}、裸 FROM balances 库存语义均为扩展 |

## 一致性证据

- R13（0.2.7）三目标单元测试各 193/193，完整 BQL 差分 20549/20549，实际 JS-hosted Wasm 时钟检查 99/99；宿主 import 与 UTC 回退覆盖跨日和 DST。wasm-gc 百万 FIFO 默认堆场景完成，峰值 RSS 1,390,510,080 字节；main 配对仍因堆耗尽失败，峰值 1,462,255,616 字节。[当前验收](evidence/r13-acceptance.md)保留全部阶段数值。
- R13 按 Lead 决定仅完成三轮短 native/JS 交错 A/B；100k/1M 解析中位数比值为 0.410–0.591，native 1M format 为 1.338 倍、JS 1M regex 为 1.322 倍，另保留一次 64.691 s 的 native booking 样本，原因未确认。完整 30% 矩阵门禁标为 pending idle-host rerun by Lead。
- 历史 R10 验收：120 份自编账本对 beancount 3.2.3 与 beanquery 0.2.0：118 份可比较账本全部通过；另 2 份使用扩展，不计为 oracle 一致。
- R12 保留 4030 项既有检查，并接入独立 R11/R12 A/B 审查用例、日期、负零和 PRINT 逐字节差分；解析健壮性和 256 层/递归运算符资源限制单独计数；实际数量、共享错误类别与剩余拒绝分类见[R12 验收](evidence/r12-acceptance.md)。拒绝检查单独计数。
- 历史 R10 验收：两个 seed 各 1000 份随机账本：858 份完全一致，142 份仅因 AVERAGE 扩展不同，其余差异为 0。
- 既有版本的 22 份报表和 lot 回归账本共 144 项检查、5 份迁移边界账本证据保留，未将其计为本轮重跑。
- R12 native、wasm-gc、JS 单元测试结果见本轮验收；today 与 oracle 当天日期比较。Playground 历史证据为 29 项 node 和 8 项无头浏览器检查，本轮未重跑；本候选未推送、未运行远端 CI。
- 0.2.2 历史性能基线：固定种子、100 万 source posting 的 native release 库阶段中位数：解析 1.931 s、FIFO booking 0.505 s、校验含 pad 1.017 s、BQL GROUP BY 0.812 s（Apple M4 / 16 GiB / MoonBit 0.1.20261104；2 次预热、21 次测量）。[原始数组、阶段 profile 与本地趋势检查](performance.md)均可复现；阶段并非互斥，不可相加。旧基线未完成 10 万/100 万 ORDER BY；本轮改为缓存键的稳定 O(n log n) 排序，native 10 万 posting 排序已通过逐行差分，历史门限仍保留大排序跳过项；wasm-gc 的 100 万 FIFO 综合场景因默认 moonrun 堆耗尽未完成。R10 的高负载矩阵未通过，不能作为当前性能结论；R11 曾未通过 JS 百万 FIFO 门限。R12 独立复审修复后的源码冻结于 ed31935，与 main 992eaa2 交错运行相同矩阵，35 组可比较配对在三组完整配对低负载复测后通过原 30% 中位数/RSS 门限；wasm-gc 百万 FIFO 双方均因堆耗尽未完成。结果和原始值详见[R12 结果](evidence/r12-acceptance.md)，按实际结果披露性能限制。

## 基础与本期工作

2026-10-31 新建仓库，此前没有代码基础；仓库全部提交均为本期工作。技术路线：行级词法 → 指令解析 → booking 与校验 → 报表与 BQL。文件读取由宿主回调提供，当前日期类函数读取宿主时钟。

## 原创与参考

原创净室实现，非移植。参考 Beancount（https://github.com/beancount/beancount ，GPL-2.0）和 beanquery（https://github.com/beancount/beanquery ，GPL-2.0）的公开文档作为规范，仅把二者当外部黑盒 oracle 比较输出；不复制源码、注释、测试数据、样式或资源，不链接、不嵌入、不分发。本项目 Apache-2.0，见 NOTICE。

# MoonBean 申报书

- 项目名称：MoonBean — Beancount v3 兼容的纯文本复式记账引擎
- 仓库：https://github.com/sundaysebasidian-byte/moonbean
- 在线体验：https://sundaysebasidian-byte.github.io/moonbean/

## 解决什么问题，给谁用

Beancount 依赖 Python，难以嵌入应用，也不能在浏览器里离线运行。MoonBean 以以下逐项兼容边界为范围，用 MoonBit 从零实现解析、记账（booking）、校验、报表和 BQL 查询。库只有纯函数，在 native、wasm-gc、JavaScript 上都能跑，不依赖文件系统和外部进程；另有 native 命令行和浏览器离线 Playground。面向个人和小企业记账、已有 Beancount 账本的用户，以及需要离线或嵌入式记账的应用（`include` 由宿主回调提供）。

## 兼容终点与当前边界

兼容终点是 beancount 3.2.3 的语法与记账语义，以及 beanquery 0.2.0 全集；0.2.5 尚未达到全集，不作完整兼容声明。[逐项清单](compatibility.md)列出全部 oracle 表/列、函数签名、option 默认值和当前证据与缺口。

| 范围 | 当前可核对边界 |
| --- | --- |
| 记账与指令 | open/close/commodity/balance/pad/price/transaction、include 与元数据栈有差分证据；document 仅校验账户并警告未检查文件；note/event/query/custom 保留语法与数据，未证明所有错误类别一致。query 存储后由调用方显式执行 |
| BQL | 10 张 oracle 表的全部公开列已接入类型值模型；105 个标量签名中 99 个已有完整或受限求值器，6 个仍缺失（date_bin 两个重载、interval、parse_date 两个重载、today）。新增递归 FROM (SELECT …)、AS、GROUP BY/ORDER BY 位置引用、PIVOT 动态列，以及布尔/比较/IS NULL/正则投影；价格查询、转换、估值和符号按黑盒结果实现。Python 专用正则/替换、集合 hash 顺序、连字符截断和带符号零仍有明确值域边界。FROM 组合、PRINT 与 .explain/.run 未完成；不据登记签名数声称全集兼容。LIKE/JOIN 及已探测的 FLATTEN/EXPLAIN 关键字形式被 oracle 拒绝 |
| option | booking、容差推断、按币种和通配符默认容差有证据；operating_currency 仅单币种报表转换；account_rounding、render_commas、documents 等未实现的效果逐项披露，不能仅凭解析成功计为兼容 |
| plugin 与扩展 | 五个内置插件有差分证据，其余 Python 插件警告且不执行；AVERAGE、{*}、裸 FROM balances 库存语义均为扩展 |

## 一致性证据

- 历史 R10 验收：120 份自编账本对 beancount 3.2.3 与 beanquery 0.2.0：118 份可比较账本全部通过；另 2 份使用扩展，不计为 oracle 一致。
- R11 在原 3156 项 BQL 基线之上增加函数与关系计划探针；最新命令、数量和分类见[本轮验收](evidence/r11-acceptance.md)。R11 专项 849 项中 811 项比较值、列模式或共享错误类别，38 项核对明确拒绝的剩余边界；拒绝不计为功能兼容。
- 历史 R10 验收：两个 seed 各 1000 份随机账本：858 份完全一致，142 份仅因 AVERAGE 扩展不同，其余差异为 0。
- 既有版本的 22 份报表和 lot 回归账本共 144 项检查、5 份迁移边界账本证据保留，未将其计为本轮重跑。
- R11 四个后端各 162 个测试通过。Playground 历史证据为 29 项 node 和 8 项无头浏览器检查，本轮未重跑；本候选未推送、未运行远端 CI。
- 0.2.2 历史性能基线：固定种子、100 万 source posting 的 native release 库阶段中位数：解析 1.931 s、FIFO booking 0.505 s、校验含 pad 1.017 s、BQL GROUP BY 0.812 s（Apple M4 / 16 GiB / MoonBit 0.1.20261104；2 次预热、21 次测量）。[原始数组、阶段 profile 与本地趋势检查](performance.md)均可复现；阶段并非互斥，不可相加。旧基线未完成 10 万/100 万 ORDER BY；本轮改为缓存键的稳定 O(n log n) 排序，native 10 万 posting 排序已通过逐行差分，历史门限仍保留大排序跳过项；wasm-gc 的 100 万 FIFO 综合场景因默认 moonrun 堆耗尽未完成。R10 的高负载矩阵未通过，不能作为当前性能结论；R11 最终仍有 JS 百万 FIFO 的 format/aggregate 超出历史 30% 门限，同机主版本对比的 aggregate 也未通过，不作性能通过声明；实际矩阵、复测和排除项详见[本轮结果](evidence/r11-acceptance.md)。

## 基础与本期工作

2026-10-31 新建仓库，此前没有代码基础；仓库全部提交均为本期工作。技术路线：行级词法 → 指令解析 → booking 与校验 → 报表与 BQL，全部为纯函数，文件读取由宿主回调提供。

## 原创与参考

原创净室实现，非移植。参考 Beancount（https://github.com/beancount/beancount ，GPL-2.0）和 beanquery（https://github.com/beancount/beanquery ，GPL-2.0）的公开文档作为规范，仅把二者当外部黑盒 oracle 比较输出；不复制源码、注释、测试数据、样式或资源，不链接、不嵌入、不分发。本项目 Apache-2.0，见 NOTICE。

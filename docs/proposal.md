# MoonBean 项目申报
- **项目名称**：MoonBean — Beancount v3 兼容的纯文本复式记账引擎
- **项目简介**：用 MoonBit 从零实现账本解析、记账（booking）、校验、报表和 BQL 查询。库只有纯函数，在 native、wasm-gc、JavaScript 上都能跑；另有 native 命令行和浏览器离线 Playground（https://sundaysebasidian-byte.github.io/moonbean/）。
- **解决什么问题**：Beancount 依赖 Python，难以嵌入应用，也不能在浏览器里离线运行。MoonBean 用同一套账本语法和记账语义，不依赖文件系统和外部进程。
- **方向与适用场景**：个人和小企业记账；Fava 用户（账本不用改，多一个离线校验和查看工具）；需要离线或嵌入式记账的应用（`include` 由宿主回调提供）。
- **核心功能**：全部指令与 posting 语法；精确十进制与容差；七种 booking；校验；inventory、价格与多跳折算；试算平衡、资产负债表（结转收益，恒等式精确成立）、损益表、register；BQL 子集；格式化；CLI 与 Playground。
- **原创/移植/参考**：原创净室实现，非移植。参考 Beancount（https://github.com/beancount/beancount ，GPL-2.0）和 beanquery（https://github.com/beancount/beanquery ，GPL-2.0）的公开文档作为规范，仅把二者当外部黑盒 oracle 比较输出；不复制源码、注释、测试数据、样式或资源，不链接、不嵌入、不分发。本项目 Apache-2.0，见 NOTICE。

| 规范覆盖矩阵摘要 | 状态 |
| --- | --- |
| 指令、posting 语法、七种 booking、校验、报表、跨 lot 明细、多跳折算、收益结转 | 支持（AVERAGE 和 `{*}` 是扩展，beancount 3.2.3 不支持） |
| BQL：SELECT/WHERE/GROUP BY/HAVING/ORDER BY/LIMIT、算术、正则、BALANCES、JOURNAL | 子集；期间余额部分兼容 |
| `option`、`document`、`note/event/query/custom` | 部分，边界见 README |
| **明确不支持**：插件执行（只记录并警告）、BQL 子查询/JOIN/PIVOT/SQL `LIKE`、`FROM transactions`、`document` 检查文件存在 | 不支持。执行 Python 插件要嵌入解释器，与纯函数、可在浏览器运行的目标冲突；其余没有按交易的行源或不在常见账本查询范围内，会明确报错而不是给出错误结果 |

- **测试与文档计划**：四个后端各 108 个测试；58 份自编账本对 beancount 3.2.3 + beanquery 0.2.0 比较，56 份可比较全部通过，另 2 份是扩展；两个 seed 各 1000 份随机账本都是 858 份一致、142 份仅因 AVERAGE 扩展不同，非 AVERAGE 差异为 0；22 份报表和 lot 回归账本 144 项检查通过；Playground 有 29 项 node 检查和 5 项无头浏览器检查；CI 覆盖三个系统、oracle 和 playground。文档含 README（中文，附英文简介）、覆盖矩阵、design、conformance、performance、CHANGELOG；10 万笔交易 `check` 约 0.59 s。
- **GitHub 仓库链接**：https://github.com/sundaysebasidian-byte/moonbean

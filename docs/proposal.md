# MoonBean 申报书

- 项目名称：MoonBean — Beancount v3 兼容的纯文本复式记账引擎
- 仓库：https://github.com/sundaysebasidian-byte/moonbean
- 在线体验：https://sundaysebasidian-byte.github.io/moonbean/

## 解决什么问题，给谁用

Beancount 依赖 Python，难以嵌入应用，也不能在浏览器里离线运行。MoonBean 用同一套账本语法和记账语义，用 MoonBit 从零实现解析、记账（booking）、校验、报表和 BQL 查询。库只有纯函数，在 native、wasm-gc、JavaScript 上都能跑，不依赖文件系统和外部进程；另有 native 命令行和浏览器离线 Playground。面向个人和小企业记账、已有 Beancount 账本的用户，以及需要离线或嵌入式记账的应用（`include` 由宿主回调提供）。

## 规范覆盖矩阵

兼容目标：Beancount v3 的语法与记账语义，以 beancount 3.2.3 与 beanquery 0.2.0 作外部黑盒对照。状态只有三种：已支持、部分支持（逐项写明边界）、明确不支持。

| 范围 | 状态 | 说明 |
| --- | --- | --- |
| 指令：open / close / commodity / balance / pad / price / transaction，posting 语法（cost、price、金额表达式、省略金额），include，pushtag / pushmeta | 已支持 | 精确十进制与容差推断；错误带类别、文件和行号 |
| 七种 booking：STRICT / STRICT_WITH_SIZE / FIFO / LIFO / HIFO / AVERAGE / NONE | 已支持 | AVERAGE 与 `{*}` 是扩展，beancount 3.2.3 不支持 |
| 报表：库存、价格库与多跳折算、试算平衡、资产负债表、损益表、register | 已支持 | 文本与 JSON 输出，资产负债表恒等式按币种精确成立 |
| BQL：SELECT / WHERE / GROUP BY / HAVING / ORDER BY / LIMIT，FROM postings / balances，BALANCES，JOURNAL | 部分支持 | 函数只有 year / month / root / parent / leaf / sum / count；WHERE 支持比较、逻辑、`~` 正则，无 LIKE |
| `document` / `note` / `event` / `query` / `custom` | 部分支持 | 解析、校验账户并保留；`document` 不检查文件是否存在，`query` 不会自动执行 |
| `option` | 部分支持 | 影响语义的 5 个选项已实现，`account_rounding`、`render_commas` 只解析 |
| `plugin` | 内置 5 个插件已支持，其余只记录并警告 | 原生按声明顺序执行 `beancount.plugins.auto_accounts`、`implicit_prices`、`check_commodity`、`unique_prices`、`leafonly`，生成条目和错误保留来源。其他插件不执行 Python，`validation.plugin` 明确报告未实现名称；依赖这些插件生成条目或校验的账本仍可能与 Beancount 不同。配置正则边界见 conformance |
| BQL 子查询 / JOIN / PIVOT / SQL `LIKE` / `FROM transactions` | 明确不支持 | 影响：用到它们的查询返回 `query.unsupported.*` 错误和位置，可改写为单一 postings 查询，或继续用 beanquery；本期不实现，不会近似执行 |

## 一致性证据

- 99 份自编账本对 beancount 3.2.3 与 beanquery 0.2.0：97 份可比较全部通过，另 2 份用到扩展，只用本项目测试验证。
- 两个 seed 各 1000 份随机账本：858 份完全一致，142 份仅因 AVERAGE 扩展不同，其余差异为 0。
- 22 份报表和 lot 回归账本共 144 项检查通过；5 份迁移边界账本逐一给出确定的诊断。
- 四个后端各 122 个测试；Playground 有 29 项 node 检查和 8 项无头浏览器检查；CI 覆盖三个系统、oracle 和 Playground。
- 10 万笔交易 `check` 约 0.56 s（固定种子，原始采样已存档）。

## 基础与本期工作

2026-10-31 新建仓库，此前没有代码基础；仓库全部提交均为本期工作。技术路线：行级词法 → 指令解析 → booking 与校验 → 报表与 BQL，全部为纯函数，文件读取由宿主回调提供。

## 原创与参考

原创净室实现，非移植。参考 Beancount（https://github.com/beancount/beancount ，GPL-2.0）和 beanquery（https://github.com/beancount/beanquery ，GPL-2.0）的公开文档作为规范，仅把二者当外部黑盒 oracle 比较输出；不复制源码、注释、测试数据、样式或资源，不链接、不嵌入、不分发。本项目 Apache-2.0，见 NOTICE。

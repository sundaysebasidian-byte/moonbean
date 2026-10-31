# MoonBean 项目申报书

- 项目名称：MoonBean — Beancount v3 兼容的纯文本复式记账引擎
- 项目简介：用 MoonBit 从零实现 Beancount v3 兼容的账本解析、记账（booking）、校验、报表与 BQL 查询；库可在 native、wasm-gc、JavaScript 中嵌入，另提供 native CLI。
- 方向与适用场景：个人/小团队纯文本记账、账本迁移与兼容检查、MoonBit 应用内嵌账本能力、浏览器离线账本查看器与教学工具。
- 核心功能：全部 Beancount 指令与 posting 语法；精确十进制与容差；STRICT/STRICT_WITH_SIZE/FIFO/LIFO/HIFO/AVERAGE/NONE；balance/pad/账户生命周期/币种约束校验；inventory、价格与市值、试算平衡、资产负债表、损益表、register；BQL 子集；金额列格式化；`check`/`bal`/`query`/`fmt`/`export` CLI。
- 原创/移植/参考说明：原创净室实现，非移植。参考 Beancount（https://github.com/beancount/beancount，GPL-2.0）与 beanquery（GPL-2.0）的公开文档作为规范，仅将二者作为外部黑盒 oracle 对比输出；不复制源码/注释/测试数据，不链接、不嵌入、不分发。本项目以 Apache-2.0 发布，详见 NOTICE。
- 规范覆盖矩阵摘要：语法指令、容差、七种 booking、校验、报表、CLI 已支持；`option` 中 `account_rounding`/`display_precision`/`render_commas`/`operating_currency` 仅解析；`plugin` 记录并警告但不执行；`document` 不检查文件存在；BQL 支持 SELECT/FROM/WHERE/GROUP BY/ORDER BY/LIMIT、BALANCES、JOURNAL 及常用列/函数。
- 明确不支持：插件执行、BQL 子查询/JOIN/HAVING/PIVOT/`BALANCES AT|FROM`、元数据与标签查询列、`LIKE`、表达式算术；重复交易仅提供库 API 按需检测（CLI 未暴露）。
- 扩展：支持 AVERAGE 库存合并与 `{*}` 成本合并；beancount 3.2.3 不支持这两项，已在一致性报告中单独标注。
- 测试与文档计划：85 个单元/快照/错误路径测试；58 份自编账本对 beancount 3.2.3 + beanquery 0.2.0 做诊断、余额和固定 BQL 对比（56 份可比全部通过，2 份扩展）；CI 覆盖 ubuntu/macOS/Windows 与 oracle job；文档含 README、覆盖矩阵、design、conformance、CHANGELOG；含 10 万笔交易性能基准。
- GitHub 仓库链接：https://github.com/sundaysebasidian-byte/moonbean
- Gitlink 链接：TODO(用户填写)

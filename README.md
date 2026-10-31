# MoonBean

**English:** MoonBean is a clean-room, Apache-2.0 implementation of a
Beancount v3 compatible plain-text double-entry accounting engine written in
MoonBit. It parses ledgers, books lots with exact decimal arithmetic, validates
against Beancount-inspired rules, produces reports and answers a BQL subset. The
library is pure and runs on native, wasm-gc and JavaScript; a native CLI is
included.

MoonBean 是用 MoonBit 从零实现的复式记账引擎，目标是与 Beancount v3 的账本语法和
记账语义兼容。它可以作为库嵌入 native、wasm-gc 和 JavaScript（例如浏览器里的离线
账本查看器），也提供可直接使用的命令行工具。

## 目标与适用场景

- 读取 `*.beancount` 纯文本账本，解析、记账、校验、出报表、跑查询。
- 在 MoonBit 应用中嵌入账本能力，不依赖文件系统或外部进程。
- 作为 Beancount 工作流的兼容替代：同一份账本在 MoonBean 与 `bean-check`
  下的错误类别、行号和最终余额一致（见[一致性](#一致性测试)）。
- 教学与工具链实验：代码按包分层，便于单独复用 parser、booking、BQL。

## 安装

发布到 mooncakes 后，在其他模块中添加依赖：

```sh
moon add sundaysebasidian-byte/moonbean
```

当前仓库尚未发布，克隆后可直接在本仓库内开发和运行（以下命令均在仓库根目录执行）：

```sh
moon version --all
moon build
```

CLI 只面向 native，因为读写文件由 `cmd/main` 承担；库本身所有后端通用。

## 快速开始（CLI）

```sh
# 校验账本，错误输出 file:line: code: message
moon run cmd/main --target native -- check examples/full-year-2024.beancount

# 试算平衡表，可指定日期快照与折算币种
moon run cmd/main --target native -- bal examples/full-year-2024.beancount
moon run cmd/main --target native -- bal examples/full-year-2024.beancount --at 2024-06-30 --convert CNY

# BQL 查询，文本或 JSON
moon run cmd/main --target native -- query examples/full-year-2024.beancount \
  'SELECT account, sum(units) FROM postings GROUP BY account ORDER BY account'
moon run cmd/main --target native -- query examples/full-year-2024.beancount \
  'SELECT account, sum(units) FROM postings GROUP BY account ORDER BY account' --json

# 格式化（默认打印到标准输出，加 --write 原地写回）
moon run cmd/main --target native -- fmt examples/full-year-2024.beancount

# 导出结构化 JSON
moon run cmd/main --target native -- export examples/full-year-2024.beancount --json
```

`examples/full-year-2024.beancount` 是一份自编的 2024 全年家庭账本：多币种、
股票 lot、FIFO 卖出、pad 与现金盘点、季度/年末 balance 断言、价格与自定义指令。
它同时通过 MoonBean 和 `bean-check`。

库嵌入示例（无文件系统，可在 wasm-gc/js 运行）：

```sh
moon run examples/library_demo
```

## 库 API 快速开始

`moon.pkg` 中导入根包：

```moonbit
import {
  "sundaysebasidian-byte/moonbean",
}
```

```moonbit
fn analyze(source : String) -> Unit {
  // 纯函数：不访问文件系统。include 由宿主提供 read 回调。
  let ledger = @moonbean.check_source("ledger.beancount", source)
  if ledger.has_errors() {
    for diagnostic in ledger.errors {
      println(@moonbean.diagnostic_text(diagnostic))
    }
    return
  }
  let realized = @moonbean.realize(ledger)
  for position in realized.inventory("Assets:Cash").positions {
    println(position.to_string())
  }
  let result = @moonbean.run_query(
    ledger,
    "SELECT account, sum(units) FROM postings GROUP BY account ORDER BY account",
  )
  println(result.to_text())
}
```

常用入口：

| API | 说明 |
| --- | --- |
| `check_source(file, source)` | 解析 + 校验，返回 `ValidatedLedger` |
| `check_expanded(file, base_dir, source, read)` | 带 `include` 展开的校验 |
| `expand_includes(source, base_dir, read)` | 返回展开后的源码与缺失路径 |
| `realize(ledger, at~)` | 生成 inventory、价格库与账簿快照 |
| `run_query(ledger, bql, at~)` | 执行 BQL 子集 |
| `format_source(source)` | 对齐金额列 |
| 报表：`trial_balance`、`balance_sheet`、`income_statement`、`inventory_rows`、`register_rows` | 文本与 JSON 输出 |
| `@validation.find_duplicate_transactions(entries)` | 按需查找重复交易 |

## 规范覆盖矩阵

状态说明：**支持** = 有实现与测试；**部分** = 有确定行为但边界更窄；**不支持** =
明确报错或记录后跳过，不静默产出错误结果。

### 语法与指令

| 能力 | 状态 | 边界 |
| --- | --- | --- |
| `option` | 部分 | 解析并保留；`title`、`booking_method`、`tolerance_multiplier`、`inferred_tolerance_default`、`infer_tolerance_from_cost` 参与语义；`account_rounding`、`render_commas` 仅解析；单一 `operating_currency` 作为 bal/bs/is 默认折算币种，`display_precision` 控制报表文本小数位，JSON 保留精度 |
| `plugin` | 部分 | 记录名称/配置并在指令行发出 `validation.plugin` 警告；不执行插件 |
| `include` | 支持 | CLI 与 `expand_includes` 递归展开；缺失文件报告路径并保留原行 |
| `pushtag` / `poptag` / `pushmeta` / `popmeta` | 支持 | 作用域内交易继承标签与元数据 |
| `open` | 支持 | 多币种约束、booking method、重复 open 检查 |
| `close` | 支持 | 关闭后交易检查、未开户关闭、重复 close 检查 |
| `commodity` | 支持 | 解析并记录 |
| `balance` | 支持 | `~` 显式容差与按末位推断容差；同日断言先于同日交易 |
| `pad` | 支持 | 自动补记；未使用 pad 报错 |
| transaction | 支持 | flag、payee/narration、tags、links、entry/posting metadata、posting flag |
| posting 金额表达式 | 支持 | `+ - * /`、括号、一元正负 |
| cost `{}` / `{{}}` | 支持 | 单价、总价、日期、label；FIFO/LIFO/HIFO/STRICT/STRICT_WITH_SIZE/NONE/AVERAGE |
| `{*}` 合并成本 | 支持 | MoonBean 扩展；beancount 3.2.3 不支持 |
| price `@` / `@@` | 支持 | 单价与总价 |
| 省略金额 | 支持 | 每种币种最多一个自动 posting；无法确定时按 bean-check 类别报错 |
| `price` / `note` / `event` / `query` / `custom` / `document` | 部分 | 解析、校验账户并保留；`document` 不检查文件是否存在，`query` 不自动执行 |

### 数值、记账与校验

| 能力 | 状态 | 边界 |
| --- | --- | --- |
| 精确十进制 | 支持 | 自实现 decimal，除法和舍入与 Python `decimal` 对齐 |
| 容差推断 | 支持 | 交易容差取最不精确金额末位 × multiplier，应用 `inferred_tolerance_default`；balance 断言按断言金额末位推断 |
| booking 方法 | 支持 | STRICT、STRICT_WITH_SIZE、FIFO、LIFO、HIFO、AVERAGE、NONE |
| lot 匹配与错误 | 支持 | 歧义、库存不足、无匹配均带 `booking.*` 错误和位置 |
| 交易平衡 | 支持 | 含 cost、price、成本分摊权重 |
| 账户生命周期 | 支持 | 未开户、已关闭、重复 open/close |
| 币种约束 | 支持 | open 声明的币种集合 |
| balance 断言 / pad | 支持 | 见上表 |
| 重复检测 | 部分 | open/close/balance 校验时检查；重复交易通过 `find_duplicate_transactions` 按需调用，CLI 暂未暴露 |

### 报表与 BQL

| 能力 | 状态 | 边界 |
| --- | --- | --- |
| inventory / 价格库 / 市值折算 | 支持 | 最新价格、逆汇率；`bal --convert` |
| 试算平衡 / 资产负债表 / 损益表 / register | 支持 | 文本与 JSON API；CLI 提供 `bal`、`bs`、`is`、`register FILE ACCOUNT`（可用 `--json`）和 `dups FILE` |
| `SELECT ... FROM postings/transactions/balances` | 支持 | 列：`date`、`year`、`month`、`flag`、`payee`、`narration`、`account`、`root`、`parent`、`leaf`、`units`、`currency`、`cost`、`value`、`position` |
| `WHERE` | 部分 | 比较、`is [not] null`、`and/or/not`；支持 `~` 字面量正则；无 `LIKE`、子查询 |
| `GROUP BY` / `ORDER BY` / `LIMIT` | 支持 | 多键分组/排序，`ASC`/`DESC` |
| 函数 | 部分 | `year`、`month`、`root`、`parent`、`leaf`、`sum`、`count`；无其他聚合/窗口/字符串函数 |
| `BALANCES` / `JOURNAL` | 支持 | `BALANCES AT units|cost FROM OPEN ON date CLOSE ON date`；`JOURNAL <account> [LIMIT n]`；时间点由 `run_query` 的 `at~` 或 CLI `--at` 控制 |
| 不支持的 BQL | 不支持 | 子查询、JOIN、`PIVOT`、SQL `LIKE`；`HAVING`、数值算术、tags/links、`meta(key)`、默认账户名下的 OPEN/CLOSE 期间已实现 |

### 格式化与 CLI

| 能力 | 状态 | 边界 |
| --- | --- | --- |
| `moonbean fmt` | 支持 | 对齐 posting 金额列；`--write` 原地写回；roundtrip 测试保证解析结果不变 |
| `check` / `bal` / `query` / `fmt` / `export --json` | 支持 | 退出码 0/1 区分成败 |
| js / wasm-gc 库 | 支持 | 根包纯函数；CLI 仅 native |

## 一致性测试

在 macOS (arm64)、MoonBit `0.1.20261028` 上，对自编的 58 份账本运行
beancount `3.2.3` + beanquery `0.2.0` 黑盒对比：

```
ledgers: 58, compared: 56, passed: 56, failed: 0, extensions: 2
```

- 56 份可对比账本全部通过：诊断类别/行号、最终余额、固定 BQL 查询一致。
- 2 份为 MoonBean 扩展（AVERAGE、`{*}`），oracle 不支持，单独用本项目测试验证。
- 逐账本表格、对比口径与已知差异见 [docs/conformance.md](docs/conformance.md)。

复现：

```sh
./scripts/oracle.sh            # 安装固定版本 oracle 并运行对比
./scripts/oracle.sh --markdown # 重新生成逐账本表格
```

脚本只在临时虚拟环境安装 GPL 的 beancount/beanquery 作为黑盒 oracle，不链接、
不嵌入、不分发。CI 的 `oracle` job 会在 ubuntu 上运行并上传报告。

性能基准（native release，100,000 笔交易，5 次中位数；复现和优化前后见 `docs/performance.md`）：

| 操作 | 耗时 |
| --- | --- |
| `check`（解析 + 校验 + booking） | 0.589 s |
| `bal`（realization + 试算平衡） | 0.637 s |
| BQL 聚合查询 | 0.973 s |

```sh
./scripts/bench.sh
```

数字来自单机实测，仅用于量级参考。

## 与 mooncakes 上相近项目的差异

mooncakes 上目前没有 Beancount 实现。MoonBean 不是任何现有账本库的移植或封装：
解析器、decimal、booking、校验、报表和 BQL 都为本项目编写。与通用记账/预算库相比，
MoonBean 的输入输出以 Beancount 账本和 `bean-check` 行为为兼容目标，并保留 lot、
成本、pad、断言等复式记账语义。

## 限制与路线图

限制：

- 插件只记录并警告，不执行 Python 插件。
- `document` 不检查文件存在；未知/未实现的 option 不改变行为。
- BQL 是子集，不支持子查询、JOIN、PIVOT、SQL LIKE 和通用字符串函数；数值算术仅支持 Decimal，不包含 Amount/Inventory 运算。
- 报表 CLI 只暴露试算平衡表；资产负债表、损益表、register 目前通过库 API 使用。
- 尚无浏览器 Playground；库 API 已为 wasm-gc/js 准备好。

路线图：

1. 插件扩展点（宿主可注册的自定义校验/变换）。
2. 更完整的 BQL（金额运算、更多聚合、期间转换归一化）。
3. `account_rounding` / `display_precision` 输出语义。
4. 基于库 API 的 wasm 账本查看器。
5. 更大规模账本的增量 realize 与缓存。

## 许可证与合规

MoonBean 以 **Apache-2.0** 发布，见 [LICENSE](LICENSE)。

Beancount 与 beanquery 均为 GPL-2.0，本项目是净室实现：

- 不复制其源码、注释或测试数据；规范依据仅为公开文档（Language Syntax、
  How Inventories Work、BQL、Precision & Tolerances）。
- 所有 `tests/ledgers/`、`examples/` 账本均为本项目自行编写。
- Beancount 只在一致性测试中作为外部黑盒 oracle：固定版本 pip 安装到临时
  virtualenv，运行后比较输出，不链接、不嵌入、不分发。
- 详见 [NOTICE](NOTICE)。

## 开发

```sh
moon check --deny-warn --target all
moon test --target all
moon fmt --check
moon info && git diff --exit-code
```

`moon test --target all` 会覆盖 wasm、wasm-gc、js、native 四个后端。CI 在
ubuntu/macOS/Windows 上执行同一组命令，另设 oracle job。

阶段 3a 随机差分（seed 20261031）：1000 份，858 一致、142 份 AVERAGE 扩展差异；468 份执行精确余额/固定 BQL 比较，错误账本只比较诊断。新增 BQL oracle 12/12；详细边界见 `docs/conformance.md`。

```sh
python3 scripts/random_differential.py --allow-known-extensions
python3 scripts/bql_differential.py
python3 scripts/cli_smoke.py
```

`HAVING` 支持聚合条件；数值表达式支持 `+ - * /` 与括号。`tags`/`links` 的 JSON 值为数组；`meta('key')` 读取 posting 元数据。正则采用 MoonBit core Regex 子集，非法/不支持模式明确报错。CI 已配置，尚未在 GitHub 执行。

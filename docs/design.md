# MoonBean 设计说明

## 目标与约束

MoonBean 以 Beancount v3 的可观察行为为兼容目标，同时保持库的纯函数性：根包
`lib.mbt` 不访问文件系统，宿主（如 native CLI）负责读取文件，库负责维护 `include` 展开栈。因此同一套
API 能在 native、wasm-gc 与 JavaScript 中编译和调用。

实现是净室的：只依据 Beancount 公开文档描述语法与语义，不接触其源码；所有账本
测试数据自编；beancount/beanquery 仅在一致性测试中作为外部黑盒 oracle。

## 包划分

| 包 | 职责 |
| --- | --- |
| `decimal` | 精确十进制：解析、加减乘除、比较、末位精度、舍入（对齐 Python `decimal`） |
| `ast` | 日期、金额、成本、posting、指令、Loc、Diagnostic、Ledger |
| `syntax` | 行级 lexer 与递归下降 parser；选项、插件、include、push 栈 |
| `booking` | Position/Inventory、成本 lot、七种 booking 方法、歧义与不足错误 |
| `validation` | 账户生命周期、币种约束、成本推断、缺失金额插补、平衡、pad、balance、重复检查 |
| `realization` | 账本快照、价格库、折算、试算平衡、资产负债表、损益表、inventory/register |
| `query` | BQL 词法/语法、AST、求值、文本/JSON 结果 |
| `format` | 金额列对齐格式化 |
| 根包 | 纯库门面：check/expand/realize/query/format；JSON 导出 |
| `cmd/main` | native CLI：check/bal/bs/is/register/dups/query/fmt/export |
| `examples` | 全年示例账本与库嵌入 demo |

## 处理流水线

```
source
  → syntax.parse_source            (Ledger: entries + parse errors)
  → validation.validate_ledger     (ValidatedLedger: entries, errors, warnings, booking state)
  → realization.realize            (RealizedLedger: inventory, price db, balances)
  → report / query                 (text or JSON)
```

`include` 在进入 parser 前由库/CLI 共用的 IncludeExpander 迭代展开。缺失文件不会
让库 panic：库返回缺失路径和 include.missing 诊断，CLI 打印错误并退出 1。

## 关键算法

### 精确十进制

数值以十进制定点表示（系数 + 小数位数），不使用二进制浮点。除法结果按 Beancount
所用 Python `decimal` 的精度和舍入行为输出；`last_digit_place()` 用于容差推断。
比较和加减会先对齐小数位，避免 `0.1 + 0.2` 类误差。

### 交易校验顺序

对同一交易依次执行：币种推断 → 显式成本解析 → booking → 缺失金额插补 → 平衡检查。
若 booking 失败，则抑制后续平衡错误，复现 bean-check 的错误优先级。多币种自动
posting、缺失币种、多个自动 posting 的错误类别与行号对齐 oracle。

### 容差

交易容差取所有金额中最不精确者的末位乘以 `tolerance_multiplier`，并应用
`inferred_tolerance_default`；`infer_tolerance_from_cost` 控制成本金额是否参与。
balance 断言使用断言金额自身末位推断容差，显式 `~` 优先。pad 只在确实插入补记
时消耗，否则报 `validation.pad`。

### Lot 与 booking

库存按 `(currency, cost currency, cost number, date, label)` 区分 lot。FIFO/LIFO
按日期先后，HIFO 按单位成本从高到低，STRICT 要求唯一匹配，STRICT_WITH_SIZE 额外
检查卖出数量与 lot 匹配，NONE 原样记录，AVERAGE 在增持后合并为加权平均成本，`{*}`
先合并再按 AVERAGE 减记。空成本 `{}` 触发自动选择，歧义与不足均带 `booking.*`
错误和 posting 位置。

### 校验顺序与 pad/balance

指令先按日期稳定排序；同日 balance 先于同日交易检查（复现 oracle 行为）。pad 与
balance 配对使用，余额不足时插入补记；年末未使用的 pad 报错。

### BQL

BQL 走独立词法/语法/求值链：`SELECT` 投影、`FROM postings|balances`、
`WHERE` 布尔条件、`GROUP BY`、`ORDER BY`、`LIMIT`，以及 `BALANCES`、`JOURNAL`。
行集来自 `RealizedLedger`；`sum(position)` 按 lot 合并。结果是稳定的文本表格或
JSON（`columns` + `rows`），便于与其他工具 diff。

### 格式化

`format_source` 按行识别 posting，计算账户列最大宽度，将对齐后的金额列重新拼回，
其余行保持原样。测试断言格式化前后解析出的账本结构一致，避免破坏语义。

## 错误模型

统一使用 `Diagnostic { code, message, loc }`：

- `code` 是稳定类别（`parse.*`、`validation.*`、`booking.*`），与 bean-check 的
  错误类别做映射后比较；
- `loc` 带文件与行号；posting 级错误定位到 posting 行；
- `errors` 决定成败（CLI 退出 1）；`warnings` 只提示（如不支持的插件），CLI 输出
  到 stderr 但不导致失败；
- 库 API 不抛异常，所有问题通过返回值表达。

## 性能

实测环境：macOS arm64、MoonBit 0.1.20261028、native release，账本 100,000 笔
交易 / 300,007 行 / 8.2 MB：

| 操作 | 耗时 |
| --- | --- |
| `check`（解析 + 校验 + booking） | 0.63 s |
| `bal`（realization + 试算平衡） | 0.66 s |
| BQL `sum(units)` 聚合 | 0.72 s |

热点主要在逐行解析和逐交易 booking；inventory 按账户维护，未做全局二次扫描。
benchmark 由 `scripts/bench.sh` 生成临时账本，不进入仓库。上述数字是一次实测，
不构成跨机器保证。

## 可移植性

根包、decimal、ast、syntax、booking、validation、realization、query、format 均
为纯 MoonBit，不依赖 fs/env。CLI 通过 `moonbitlang/core/async/fs` 读取文件并声明
`supported_targets = "-all+native"`。`moon test --target all` 在 wasm、wasm-gc、
js、native 四个后端通过。

`FROM transactions` 明确不支持：解析时返回错误，不会作为 posting 源的别名。

## 报表、lot、价格与 include

校验只做一次 lot 选择，将 plan 展平为已记账 posting；各行保留 units、成本金额/币种、日期、标签、flag 和 metadata，跨 lot 的总价注解归一化为单位价格。realization 直接累计这些明细，不再二次选 lot；BQL/JOURNAL/register/JSON 导出共享同一表示。

价格图按截止日过滤；每条边选择最新可用的直接/反向报价，BFS 选最短路径，同长路径按币种字典序选择，visited 集防环。只有显式 price 提供市价；成本与交易价格注解都不充当市场报价（未执行 implicit_prices 插件）。资产负债表缺少市价时使用已知成本基础回退并明确标记不完整。找不到路径时，报表 JSON 返回 `complete:false` 和带账户、源/目标币种的 `report.conversion_incomplete`，合计保留币种后缀。

资产负债表不指定折算币种时使用成本基础；期间前与期间内的 Income/Expenses 分别转入 account_previous_earnings / account_current_earnings 所命名的权益账户。CLOSE 的币种/容差余量进入 account_current_conversions。市值相对成本的估值变化单列为权益账户同级的 Unrealized 储备；这是报表调整，不写回账本。报表加法不重复进行 28 位舍入，逆汇率舍入余量也显式进入转换调整，使原始 JSON 按币种精确平衡。引擎的 Decimal 28 位运算语义不变。

文本按币种最常见的 booked units scale 推断显示精度，并列取较大值；display_precision quantum 显式覆盖。JSON amount 保留原始小数，另提供 report.display_precision（币种到小数位数的映射）。

include 使用纯状态机 IncludeExpander：next 请求路径，provide 接收同步或异步宿主读取结果；两个宿主共享同一递归栈、路径规范化、cycle/missing/depth 诊断。最大嵌套 1024，避免符号链接等未规范化宿主别名造成无限展开；300 层纯库和 100 层真实 CLI 合法路径已测试。

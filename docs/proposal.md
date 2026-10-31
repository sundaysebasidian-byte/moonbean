# MoonBean 项目申报
MoonBean 是用 MoonBit 从零实现的 Beancount v3 兼容复式记账引擎。仓库：https://github.com/sundaysebasidian-byte/moonbean，在线 Playground：https://sundaysebasidian-byte.github.io/moonbean/

## 解决什么问题
纯文本记账很可靠，但 Beancount 依赖 Python 环境，难以嵌入应用，也不能在浏览器里离线运行。MoonBean 用同一套账本语法和记账语义，提供一个不依赖文件系统和外部进程的库，在 native、wasm-gc、JavaScript 上都能跑。

## 给谁用
- 个人和小企业记账：直接读写现有的 `.beancount` 账本，附带校验、报表、BQL 查询和格式化命令行。
- Fava 用户：账本不用改，可以多一个离线的校验和查看工具。
- 需要离线或嵌入式记账的应用：库只有纯函数，`include` 由宿主回调提供；Playground 就是这样一个例子，账本只在浏览器里处理。

## 证据
- 自编 58 份账本对 beancount 3.2.3 + beanquery 0.2.0：56 份可比较，56 份通过（诊断类别和行号、最终余额、固定 BQL）；另 2 份是扩展，beancount 不支持。
- 随机差分（seed 20261031，1000 份）：858 份完全一致；其余 142 份都使用 AVERAGE booking，beancount 3.2.3 报 `average_unsupported`，这是 MoonBean 的扩展而不是错误，去掉这条诊断后两边一致。另有 12 条扩展 BQL 对比全部通过。
- 四个后端各 94 个测试；100,000 笔交易的 `check` 约 0.59 s（native release，单机测量）。

## 覆盖矩阵
| 范围 | 状态 |
| --- | --- |
| 全部指令与 posting 语法（含表达式、cost、price、省略金额） | 支持；`option`、`document` 等边界见 README |
| 七种 booking：STRICT、STRICT_WITH_SIZE、FIFO、LIFO、HIFO、AVERAGE、NONE | 支持（AVERAGE 为扩展） |
| 校验（账户生命周期、币种约束、容差、balance、pad）与报表（试算平衡、资产负债表、损益表、register、重复交易） | 支持 |
| BQL：SELECT/WHERE/GROUP BY/HAVING/ORDER BY/LIMIT、算术、正则、BALANCES、JOURNAL | 子集，期间余额部分兼容 |

## 明确不支持
- 插件执行：只记录并警告。要执行 Python 插件就得嵌入解释器，与“纯函数、可在 wasm 和浏览器里运行”的目标冲突。`document` 同理不检查文件是否存在。
- BQL FROM transactions、子查询、JOIN、PIVOT、SQL `LIKE`：不在常见账本查询范围内，解析时明确报错；`LIKE` 可用 `~` 正则代替。

## 净室实现与 GPL 隔离
Beancount 和 beanquery 是 GPL-2.0，MoonBean 以 Apache-2.0 发布。实现只依据公开文档，不复制源码、注释、测试数据、样式或资源；所有测试账本和示例都是自己写的。Beancount 只作为外部黑盒 oracle，固定版本装进临时 virtualenv，运行后比较输出，不链接、不嵌入、不分发。详见 NOTICE。

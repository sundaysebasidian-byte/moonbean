import * as moonbean from "./moonbean.js";
import example from "./example.js";
import {
  buildTree,
  cellLines,
  decimalToString,
  escapeHtml,
  group,
  highlightLine,
  isZero,
  negate,
  nodeCount,
  parseDecimal,
  sumRoots,
} from "./lib.js";

const $ = (id) => document.getElementById(id);
const LINE = 21;
const HIGHLIGHT_LIMIT = 6000;

function call(name, request) {
  try {
    return JSON.parse(moonbean[name](JSON.stringify(request)));
  } catch (error) {
    return { ok: false, error: { code: "internal", message: String(error?.message ?? error) } };
  }
}

function debounce(fn, ms) {
  let timer = 0;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), ms);
  };
}

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

/* ---------- state ---------- */

const state = {
  fileName: example.name,
  tab: "diagnostics",
  kind: "balance_sheet",
  convert: null,
  at: "",
  account: "",
  subtree: true,
  check: null,
  stale: new Set(),
  collapsed: new Set(),
  seeded: new Set(),
  queryText: "SELECT account, sum(units) FROM postings GROUP BY account ORDER BY account",
  formatted: null,
};

/* ---------- editor ---------- */

const editorHost = $("editor");
const gutter = el("div", "gutter");
const stage = el("div", "stage");
const layer = el("div", "hl");
const lines = el("div", "lines");
const area = el("textarea");
area.spellcheck = false;
area.autocapitalize = "off";
area.setAttribute("autocomplete", "off");
area.setAttribute("aria-label", "账本");
area.wrap = "off";
layer.append(lines);
stage.append(layer, area);
editorHost.append(gutter, stage);

let marks = new Map();

function renderEditor() {
  const rows = area.value.split("\n");
  const plain = rows.length > HIGHLIGHT_LIMIT;
  editorHost.classList.toggle("plain", plain);
  const numbers = [];
  const html = [];
  for (let i = 0; i < rows.length; i++) {
    const mark = marks.get(i + 1);
    numbers.push(mark ? `<span class="${mark}">${i + 1}</span>` : String(i + 1));
    html.push(`<div class="ln${mark ? " " + mark : ""}">${plain ? "" : highlightLine(rows[i])}</div>`);
  }
  gutter.innerHTML = numbers.join("\n");
  lines.innerHTML = html.join("");
  syncScroll();
}

function syncScroll() {
  gutter.scrollTop = area.scrollTop;
  layer.scrollTop = area.scrollTop;
  layer.scrollLeft = area.scrollLeft;
}

function jumpTo(lineNumber) {
  const rows = area.value.split("\n");
  const index = Math.min(Math.max(lineNumber, 1), rows.length) - 1;
  let start = 0;
  for (let i = 0; i < index; i++) start += rows[i].length + 1;
  area.focus();
  area.setSelectionRange(start, start + rows[index].length);
  area.scrollTop = Math.max(0, index * LINE - area.clientHeight / 3);
  syncScroll();
}

area.addEventListener("scroll", syncScroll);
area.addEventListener("input", () => {
  renderEditor();
  schedule();
});
area.addEventListener("keydown", (event) => {
  if (event.key === "Tab" && !event.shiftKey) {
    event.preventDefault();
    area.setRangeText("  ", area.selectionStart, area.selectionEnd, "end");
    area.dispatchEvent(new Event("input"));
  }
});

function setSource(text, name) {
  area.value = text;
  state.fileName = name;
  $("file-name").textContent = name;
  state.formatted = null;
  state.collapsed.clear();
  state.seeded.clear();
  area.scrollTop = 0;
  area.scrollLeft = 0;
  renderEditor();
  analyze();
}

/* ---------- analysis ---------- */

const schedule = debounce(() => analyze(), 220);

function analyze() {
  const source = area.value;
  state.check = call("check", { source });
  state.stale = new Set(["reports", "register", "query", "format"]);
  marks = new Map();
  if (state.check.ok) {
    for (const warning of state.check.warnings) marks.set(warning.line, "warn");
    for (const error of state.check.errors) marks.set(error.line, "bad");
  }
  renderEditor();
  renderDiagnostics();
  fillControls();
  renderTab();
}

function fillControls() {
  const check = state.check;
  if (!check?.ok) return;
  const accounts = $("dl-accounts");
  accounts.innerHTML = check.accounts.map((a) => `<option value="${escapeHtml(a)}">`).join("");
  if (!state.account) {
    state.account = check.accounts.find((a) => a.startsWith("Assets")) ?? check.accounts[0] ?? "";
    $("account").value = state.account;
  }
  const select = $("convert");
  const options = [["", "原币"], ...check.operating_currencies.map((c) => [c, c])];
  const wanted = state.convert ?? (check.operating_currencies.length === 1 ? check.operating_currencies[0] : "");
  select.innerHTML = options.map(([v, l]) => `<option value="${escapeHtml(v)}">${escapeHtml(l)}</option>`).join("");
  select.value = options.some(([v]) => v === wanted) ? wanted : "";
}

/* ---------- diagnostics ---------- */

function renderDiagnostics() {
  const check = state.check;
  const summary = $("summary");
  const list = $("issues");
  const badge = $("badge");
  summary.innerHTML = "";
  list.innerHTML = "";
  if (!check?.ok) {
    badge.hidden = true;
    summary.append(el("div", "error", check?.error?.message ?? ""));
    return;
  }
  const errors = check.errors.length;
  const warnings = check.warnings.length;
  badge.hidden = errors + warnings === 0;
  badge.textContent = String(errors || warnings);
  badge.classList.toggle("warn", errors === 0);

  const verdict = el("div", `verdict ${errors ? "no" : "ok"}`, errors ? `${errors} 个错误` : "通过");
  const facts = el("div", "facts");
  facts.innerHTML =
    `<span><b>${check.entries}</b>条目</span><span><b>${check.accounts.length}</b>账户</span>` +
    (warnings ? `<span><b>${warnings}</b>警告</span>` : "");
  summary.append(verdict, facts);

  const items = [
    ...check.errors.map((d) => ({ ...d, kind: "error" })),
    ...check.warnings.map((d) => ({ ...d, kind: "warning" })),
  ].sort((a, b) => a.line - b.line);
  for (const item of items) {
    const li = el("li", item.kind);
    li.append(el("span", "pos", String(item.line)), el("span", "msg", item.message), el("span", "code", item.code));
    li.addEventListener("click", () => jumpTo(item.line));
    list.append(li);
  }
}

/* ---------- reports ---------- */

const CHEVRON =
  '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 6l6 6-6 6"/></svg>';

function amountsColumn(totals) {
  const box = el("div", "amts");
  const entries = totals.filter(([, d]) => !isZero(d));
  if (entries.length === 0) {
    box.textContent = "0";
    box.classList.add("dim");
  }
  for (const [currency, d] of entries) {
    box.append(el("div", "", `${group(decimalToString(d))} ${currency}`));
  }
  return box;
}

function renderNode(node, depth) {
  const wrap = el("div", `node${depth === 0 ? " root" : ""}`);
  const row = el("div", "row");
  const name = el("div", "name");
  const hasChildren = node.children.length > 0;
  const collapsed = state.collapsed.has(`${state.kind}|${node.path}`);
  if (hasChildren) {
    const toggle = el("button", "toggle");
    toggle.type = "button";
    toggle.innerHTML = CHEVRON;
    toggle.setAttribute("aria-expanded", String(!collapsed));
    toggle.setAttribute("aria-label", node.path);
    name.append(toggle);
    const flip = () => {
      const key = `${state.kind}|${node.path}`;
      if (state.collapsed.has(key)) state.collapsed.delete(key);
      else state.collapsed.add(key);
      renderReport();
    };
    toggle.addEventListener("click", flip);
  } else {
    name.append(el("span", "spacer"));
  }
  name.append(el("span", "label", node.name));
  row.append(name, amountsColumn([...node.totals]));
  wrap.append(row);
  wrap.classList.toggle("open", hasChildren && !collapsed);
  if (hasChildren && !collapsed) {
    const children = el("div", "children");
    for (const child of node.children) children.append(renderNode(child, depth + 1));
    wrap.append(children);
  }
  return wrap;
}

function totalRow(label, totals) {
  const row = el("div", "total");
  row.append(el("span", "label", label), amountsColumn(totals));
  return row;
}

function renderReport() {
  const host = $("report");
  host.innerHTML = "";
  const data = state.reportData;
  if (!data) return;
  if (!data.ok) {
    host.append(errorBlock(data));
    return;
  }
  const forest = buildTree(data.report.rows);
  const tree = el("div", "tree");
  for (const root of forest) tree.append(renderNode(root, 0));
  host.append(tree);
  if (state.kind === "income_statement") {
    const income = forest.filter((n) => n.name === "Income" || n.name === "Expenses");
    host.append(totalRow("Net Income", negate(sumRoots(income))));
  } else if (state.kind === "trial_balance") {
    // The engine only totals a report that is in one currency.
    for (const total of data.report.totals) {
      host.append(totalRow(total.account, [[total.amount.currency, parseDecimal(total.amount.number)]]));
    }
  }
}

function errorBlock(data) {
  const box = el("div", "error");
  if (data.error.code === "ledger_invalid") {
    const link = el("button", "", `${data.errors.length} 个错误`);
    link.type = "button";
    link.addEventListener("click", () => selectTab("diagnostics"));
    box.append(link);
  } else {
    box.textContent = data.error.message;
  }
  return box;
}

function loadReport() {
  const request = { source: area.value };
  if (state.convert !== null) request.convert = state.convert;
  if (state.at) request.at = state.at;
  state.reportData = call(state.kind, request);
  if (state.reportData.ok && state.convert === null) {
    $("convert").value = state.reportData.convert ?? "";
  }
  if (state.reportData.ok && !state.seeded.has(state.kind)) {
    // Large trees start folded below the first level.
    state.seeded.add(state.kind);
    const forest = buildTree(state.reportData.report.rows);
    if (nodeCount(forest) > 60) {
      const fold = (nodes, depth) => {
        for (const n of nodes) {
          if (depth >= 1 && n.children.length) state.collapsed.add(`${state.kind}|${n.path}`);
          fold(n.children, depth + 1);
        }
      };
      fold(forest, 0);
    }
  }
  renderReport();
}

/* ---------- register ---------- */

function loadRegister() {
  const host = $("register");
  host.innerHTML = "";
  if (!state.account) return;
  const data = call("register", { source: area.value, account: state.account, subtree: state.subtree });
  if (!data.ok) {
    host.append(errorBlock(data));
    return;
  }
  const table = el("table");
  table.innerHTML = "<thead><tr><th>日期</th><th>摘要</th><th class='num'>金额</th><th class='num'>余额</th></tr></thead>";
  const body = el("tbody");
  for (const row of data.rows) {
    const showAccount = row.account !== state.account;
    const tr = el("tr");
    const memo = [row.payee, row.narration].filter(Boolean).join(" · ");
    tr.innerHTML =
      `<td class="mono dim">${escapeHtml(row.date)}</td>` +
      `<td><div class="truncate">${escapeHtml(memo)}</div>` +
      (showAccount ? `<div class="dim mono" style="font-size:11px">${escapeHtml(row.account)}</div>` : "") +
      `</td>` +
      `<td class="num"><div>${escapeHtml(group(row.amount.number))} ${escapeHtml(row.amount.currency)}</div></td>` +
      `<td class="num dim"><div>${escapeHtml(group(row.running.number))} ${escapeHtml(row.running.currency)}</div></td>`;
    body.append(tr);
  }
  table.append(body);
  host.append(table);
}

/* ---------- query ---------- */

const ROW_LIMIT = 2000;

function runQuery() {
  const host = $("query-result");
  host.innerHTML = "";
  const data = call("query", { source: area.value, bql: state.queryText });
  if (!data.ok) {
    host.append(errorBlock(data));
    return;
  }
  const rows = data.rows.slice(0, ROW_LIMIT);
  const cells = rows.map((row) => row.map(cellLines));
  const numeric = data.columns.map((_, i) => cells.some((r) => r[i].numeric));
  const table = el("table");
  const head = el("tr");
  data.columns.forEach((c, i) => {
    const th = el("th", numeric[i] ? "num" : "", c);
    head.append(th);
  });
  const thead = el("thead");
  thead.append(head);
  const body = el("tbody");
  for (const row of cells) {
    const tr = el("tr");
    row.forEach((cell, i) => {
      const td = el("td", numeric[i] ? "num" : "");
      for (const line of cell.lines) td.append(el("div", "", line));
      tr.append(td);
    });
    body.append(tr);
  }
  table.append(thead, body);
  host.append(table);
  host.append(
    el("div", "count", data.rows.length > ROW_LIMIT ? `${ROW_LIMIT} / ${data.rows.length} 行` : `${data.rows.length} 行`),
  );
}

/* ---------- format ---------- */

function loadFormat() {
  const source = area.value;
  const data = call("format", { source });
  state.formatted = data.ok ? data.output : null;
  const host = $("format-preview");
  host.innerHTML = "";
  const apply = $("apply-format");
  if (!data.ok) {
    host.append(errorBlock(data));
    apply.disabled = true;
    $("format-state").textContent = "";
    return;
  }
  const before = source.split("\n");
  const after = data.output.split("\n");
  const sameShape = before.length === after.length;
  const body = el("div", "body");
  let changed = 0;
  const html = [];
  const plain = after.length > HIGHLIGHT_LIMIT;
  for (let i = 0; i < after.length; i++) {
    const differs = sameShape ? before[i] !== after[i] : data.changed;
    if (sameShape && differs) changed++;
    html.push(
      `<div class="ln${differs ? " changed" : ""}"><span class="no">${i + 1}</span><span class="tx">${
        plain ? escapeHtml(after[i]) : highlightLine(after[i])
      }</span></div>`,
    );
  }
  body.innerHTML = html.join("");
  host.append(body);
  apply.disabled = !data.changed;
  $("format-state").textContent = data.changed ? (sameShape ? `${changed} 行将调整` : "") : "已对齐";
}

/* ---------- tabs ---------- */

function selectTab(tab) {
  state.tab = tab;
  for (const button of document.querySelectorAll("#tabs button")) {
    button.setAttribute("aria-selected", String(button.dataset.tab === tab));
  }
  for (const panel of document.querySelectorAll(".panel")) {
    panel.hidden = panel.id !== `panel-${tab}`;
  }
  renderTab();
}

function renderTab() {
  const tab = state.tab;
  if (tab !== "diagnostics" && !state.stale.has(tab)) return;
  state.stale.delete(tab);
  if (tab === "reports") loadReport();
  else if (tab === "register") loadRegister();
  else if (tab === "query") runQuery();
  else if (tab === "format") loadFormat();
}

for (const button of document.querySelectorAll("#tabs button")) {
  button.setAttribute("role", "tab");
  button.addEventListener("click", () => selectTab(button.dataset.tab));
}

function markReport() {
  state.stale.add("reports");
  renderTab();
}

for (const button of document.querySelectorAll("#report-kind button")) {
  button.addEventListener("click", () => {
    state.kind = button.dataset.kind;
    syncKind();
    markReport();
  });
}

function syncKind() {
  for (const button of document.querySelectorAll("#report-kind button")) {
    button.setAttribute("aria-pressed", String(button.dataset.kind === state.kind));
  }
}

$("convert").addEventListener("change", (event) => {
  state.convert = event.target.value;
  markReport();
});
$("at").addEventListener("change", (event) => {
  state.at = event.target.value;
  markReport();
});
$("fold").addEventListener("click", () => {
  const forest = state.reportData?.ok ? buildTree(state.reportData.report.rows) : [];
  const parents = [];
  const walk = (nodes) => {
    for (const n of nodes) {
      if (n.children.length) parents.push(`${state.kind}|${n.path}`);
      walk(n.children);
    }
  };
  walk(forest);
  const anyOpen = parents.some((p) => !state.collapsed.has(p));
  if (anyOpen) for (const p of parents) state.collapsed.add(p);
  else for (const p of parents) state.collapsed.delete(p);
  renderReport();
});

$("account").addEventListener("input", (event) => {
  state.account = event.target.value.trim();
  state.stale.add("register");
  renderTab();
});
$("subtree").addEventListener("change", (event) => {
  state.subtree = event.target.checked;
  state.stale.add("register");
  renderTab();
});

$("bql").value = state.queryText;
$("bql").addEventListener("input", (event) => {
  state.queryText = event.target.value;
});
$("bql").addEventListener("keydown", (event) => {
  if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
    event.preventDefault();
    runQuery();
  }
});
$("run").addEventListener("click", runQuery);

$("apply-format").addEventListener("click", () => {
  if (state.formatted === null) return;
  const top = area.scrollTop;
  area.value = state.formatted;
  renderEditor();
  area.scrollTop = top;
  syncScroll();
  analyze();
});

/* ---------- files and theme ---------- */

$("load-example").addEventListener("click", () => setSource(example.source, example.name));
$("open-file").addEventListener("click", () => $("file-input").click());

async function openFile(file) {
  if (!file) return;
  setSource(await file.text(), file.name);
}

$("file-input").addEventListener("change", async (event) => {
  await openFile(event.target.files[0]);
  event.target.value = "";
});

const card = $("editor-card");
card.addEventListener("dragover", (event) => {
  event.preventDefault();
  card.classList.add("dropping");
});
card.addEventListener("dragleave", () => card.classList.remove("dropping"));
card.addEventListener("drop", async (event) => {
  event.preventDefault();
  card.classList.remove("dropping");
  await openFile(event.dataTransfer.files[0]);
});

$("theme").addEventListener("click", () => {
  const root = document.documentElement;
  const dark =
    root.dataset.theme === "dark" ||
    (!root.dataset.theme && window.matchMedia("(prefers-color-scheme: dark)").matches);
  root.dataset.theme = dark ? "light" : "dark";
  localStorage.setItem("theme", root.dataset.theme);
});

/* ---------- start ---------- */

syncKind();
setSource(example.source, example.name);
const initial = location.hash.slice(1);
selectTab(["diagnostics", "reports", "register", "query", "format"].includes(initial) ? initial : "diagnostics");

window.addEventListener("hashchange", () => {
  const tab = location.hash.slice(1);
  if (["diagnostics", "reports", "register", "query", "format"].includes(tab)) selectTab(tab);
});

// Pure helpers shared by the page and the smoke test: exact decimal sums,
// account trees and the ledger highlighter. Nothing here touches the DOM.

/* ---------- decimals ---------- */

export function parseDecimal(text) {
  const match = /^([+-]?)(\d*)(?:\.(\d*))?$/.exec(String(text).trim());
  if (!match) throw new Error(`not a decimal: ${text}`);
  const fraction = match[3] ?? "";
  const digits = BigInt((match[2] || "0") + fraction);
  return { value: match[1] === "-" ? -digits : digits, scale: fraction.length };
}

export function addDecimal(a, b) {
  const scale = Math.max(a.scale, b.scale);
  const lift = (d) => d.value * 10n ** BigInt(scale - d.scale);
  return { value: lift(a) + lift(b), scale };
}

export function decimalToString({ value, scale }) {
  const negative = value < 0n;
  let digits = (negative ? -value : value).toString();
  if (scale > 0) {
    digits = digits.padStart(scale + 1, "0");
    digits = `${digits.slice(0, -scale)}.${digits.slice(-scale)}`;
  }
  return (negative ? "-" : "") + digits;
}

export function isZero(decimal) {
  return decimal.value === 0n;
}

/** "-1234567.50" -> "-1,234,567.50" */
export function group(text) {
  const match = /^(-?)(\d+)(\.\d+)?$/.exec(text);
  if (!match) return text;
  return match[1] + match[2].replace(/\B(?=(\d{3})+(?!\d))/g, ",") + (match[3] ?? "");
}

/* ---------- account trees ---------- */

function emptyNode(name, path) {
  return { name, path, children: [], totals: new Map(), own: false };
}

function accumulate(node, amount) {
  const number = parseDecimal(amount.number);
  const before = node.totals.get(amount.currency);
  node.totals.set(amount.currency, before ? addDecimal(before, number) : number);
}

/**
 * Builds a forest from flat `{account, amount}` rows. Every node carries the
 * per-currency sum of its subtree; siblings keep the order of the first row
 * that introduced them (the engine already sorts rows by account).
 */
export function buildTree(rows) {
  const roots = [];
  const index = new Map();
  for (const row of rows) {
    const parts = row.account.split(":");
    let siblings = roots;
    let path = "";
    for (const part of parts) {
      path = path ? `${path}:${part}` : part;
      let node = index.get(path);
      if (!node) {
        node = emptyNode(part, path);
        index.set(path, node);
        siblings.push(node);
      }
      accumulate(node, row.amount);
      siblings = node.children;
    }
    index.get(path).own = true;
  }
  return roots;
}

export function nodeCount(forest) {
  return forest.reduce((sum, node) => sum + 1 + nodeCount(node.children), 0);
}

/** Per-currency sum of the given roots, as an ordered list of [currency, decimal]. */
export function sumRoots(roots) {
  const totals = new Map();
  for (const node of roots) {
    for (const [currency, number] of node.totals) {
      const before = totals.get(currency);
      totals.set(currency, before ? addDecimal(before, number) : number);
    }
  }
  return [...totals].sort((a, b) => (a[0] < b[0] ? -1 : 1));
}

export function negate(totals) {
  return totals.map(([currency, d]) => [currency, { value: -d.value, scale: d.scale }]);
}

/* ---------- highlighting ---------- */

const escapes = { "&": "&amp;", "<": "&lt;", ">": "&gt;" };
export const escapeHtml = (text) => text.replace(/[&<>]/g, (c) => escapes[c]);

const KEYWORDS =
  "open|close|commodity|balance|pad|price|note|event|query|custom|document|txn|option|plugin|include|pushtag|poptag|pushmeta|popmeta";

const RULES = [
  ["c", /^;.*/],
  ["s", /^"(?:[^"\\]|\\.)*"?/],
  ["d", /^\d{4}-\d{2}-\d{2}(?!\d)/],
  ["a", /^[A-Z][A-Za-z0-9-]*(?::[\p{L}\p{N}-]+)+/u],
  ["k", new RegExp(`^(?:${KEYWORDS})(?![\\w-])`)],
  ["m", /^[a-z][A-Za-z0-9_-]*:(?=\s|$)/],
  ["t", /^[#^][A-Za-z0-9_/.-]+/],
  ["n", /^[-+]?\d[\d,]*(?:\.\d+)?/],
  ["u", /^[A-Z][A-Z0-9'._-]*(?![\w-])/],
  ["f", /^[*!&#?%PSTCURM](?=\s)/],
];

/** One ledger line as HTML with `<i class="tok-x">` spans. */
export function highlightLine(line) {
  let out = "";
  let plain = "";
  let rest = line;
  const flush = () => {
    if (plain) out += escapeHtml(plain);
    plain = "";
  };
  while (rest.length > 0) {
    let hit = null;
    for (const [kind, pattern] of RULES) {
      const match = pattern.exec(rest);
      if (match && match[0].length > 0) {
        hit = [kind, match[0]];
        break;
      }
    }
    if (!hit) {
      plain += rest[0];
      rest = rest.slice(1);
      continue;
    }
    flush();
    out += `<i class="t-${hit[0]}">${escapeHtml(hit[1])}</i>`;
    rest = rest.slice(hit[1].length);
  }
  flush();
  return out;
}

/* ---------- query values ---------- */

export function isAmount(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) && "number" in value && "currency" in value;
}

export function isPosition(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) && "units" in value;
}

export function amountText(amount) {
  return `${group(amount.number)} ${amount.currency}`;
}

export function positionText(position) {
  const units = amountText(position.units);
  const cost = position.cost;
  if (!cost) return units;
  const parts = [`${group(cost.number)} ${cost.currency}`];
  if (cost.date) parts.push(cost.date);
  if (cost.label) parts.push(`"${cost.label}"`);
  return `${units} {${parts.join(", ")}}`;
}

/** Splits a query cell into display lines and says whether it is numeric. */
export function cellLines(value) {
  if (value === null || value === undefined) return { lines: [], numeric: false };
  if (typeof value === "number") return { lines: [String(value)], numeric: true };
  if (typeof value === "string") return { lines: [value], numeric: false };
  if (isAmount(value)) return { lines: [amountText(value)], numeric: true };
  if (isPosition(value)) return { lines: [positionText(value)], numeric: true };
  if (Array.isArray(value)) {
    if (value.length > 0 && value.every(isPosition)) return { lines: value.map(positionText), numeric: true };
    if (value.length > 0 && value.every(isAmount)) return { lines: value.map(amountText), numeric: true };
    return { lines: value.length ? [value.map(String).join(", ")] : [], numeric: false };
  }
  return { lines: [JSON.stringify(value)], numeric: false };
}

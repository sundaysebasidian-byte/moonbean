// Browser check that ledger text never becomes markup.
//
//   scripts/build-web.sh && node web/dom-smoke.mjs
//
// Loads the built page in headless Chrome, feeds it a ledger whose currency,
// payee, narration and metadata carry HTML and event-handler payloads, visits
// every tab and checks that nothing executed and no element was injected.
import assert from "node:assert/strict";
import { launch, sleep } from "./browser.mjs";

const currency = '" onmouseover="window.__xss=1" data-probe="';
const payee = "<img src=x onerror=window.__xss=1>";
const narration = '</td><script>window.__xss=1</script>"\'';

const valid = [
  `option "operating_currency" ${JSON.stringify(currency)}`,
  "2024-01-01 open Assets:A",
  "2024-01-01 open Equity:B",
  `2024-01-02 * ${JSON.stringify(payee)} ${JSON.stringify(narration)}`,
  `  note: ${JSON.stringify(payee)}`,
  "  Assets:A  1 USD",
  "  Equity:B",
  "",
].join("\n");
// The engine echoes a bad booking method in its message, so this payload reaches the diagnostics list.
const brokenBooking = '2024-01-01 open Assets:A "<img src=x onerror=window.__xss=1>"\n';

const browser = await launch();
let failed = false;
async function test(name, fn) {
  try {
    await fn();
    console.log(`ok   ${name}`);
  } catch (error) {
    failed = true;
    console.error(`FAIL ${name}\n${error.stack}`);
  }
}

const setLedger = async (text) => {
  await browser.evaluate(`(() => {
    const area = document.querySelector("#editor textarea");
    area.value = ${JSON.stringify(text)};
    area.dispatchEvent(new Event("input"));
  })()`);
  await sleep(500);
};
const tab = async (name) => {
  await browser.evaluate(`document.querySelector('#tabs [data-tab="${name}"]').click()`);
  await sleep(200);
};
// Hover everything, then report what an injected payload would have left behind.
const audit = () =>
  browser.evaluate(`(() => {
    const all = [...document.querySelectorAll("*")];
    for (const node of all) node.dispatchEvent(new MouseEvent("mouseover", { bubbles: true }));
    return {
      xss: window.__xss ?? null,
      injected: document.querySelectorAll("img, iframe, object, embed").length,
      scripts: document.querySelectorAll("script").length,
      handlers: all.flatMap((n) => [...n.attributes].map((a) => a.name)).filter((n) => n.startsWith("on") || n === "data-probe"),
    };
  })()`);

await browser.open("");
const baseline = (await audit()).scripts;

await test("engine messages that echo ledger text stay text in the diagnostics list", async () => {
  await setLedger(brokenBooking);
  await tab("diagnostics");
  const seen = await audit();
  assert.equal(seen.xss, null);
  assert.equal(seen.injected, 0);
  assert.equal(seen.scripts, baseline);
  const text = await browser.evaluate('document.querySelector("#issues").textContent');
  assert.match(text, /<img src=x onerror=window\.__xss=1>/);
});

await test("hostile operating_currency is only an option value", async () => {
  await setLedger(valid);
  await tab("reports");
  const options = await browser.evaluate('[...document.querySelectorAll("#convert option")].map((o) => [o.value, o.textContent])');
  assert.deepEqual(options, [["", "原币"], [currency, currency]]);
  const seen = await audit();
  assert.equal(seen.xss, null);
  assert.deepEqual(seen.handlers, []);
});

await test("register shows hostile payee and narration as text", async () => {
  await tab("register");
  await browser.evaluate(`(() => {
    const input = document.querySelector("#account");
    input.value = "Assets:A";
    input.dispatchEvent(new Event("input"));
  })()`);
  await sleep(200);
  const text = await browser.evaluate('document.querySelector("#register").textContent');
  assert.ok(text.includes(payee), text);
  assert.ok(text.includes(narration), text);
  const seen = await audit();
  assert.equal(seen.xss, null);
  assert.equal(seen.injected, 0);
  assert.equal(seen.scripts, baseline);
});

await test("query cells and the format preview stay text", async () => {
  await tab("query");
  await browser.evaluate(`(() => {
    const box = document.querySelector("#bql");
    box.value = "SELECT narration, account FROM postings ORDER BY account";
    box.dispatchEvent(new Event("input"));
    document.querySelector("#run").click();
  })()`);
  await sleep(200);
  const cells = await browser.evaluate('document.querySelector("#query-result").textContent');
  assert.ok(cells.includes(narration), cells);
  await tab("format");
  const preview = await browser.evaluate('document.querySelector("#format-preview").textContent');
  assert.ok(preview.includes('</td><script>window.__xss=1</script>'), preview);
  const seen = await audit();
  assert.equal(seen.xss, null);
  assert.equal(seen.injected, 0);
  assert.equal(seen.scripts, baseline);
  assert.deepEqual(seen.handlers, []);
});

await test("the page raised no exceptions", () => {
  assert.deepEqual(browser.exceptions, []);
});

await browser.close();
if (failed) process.exit(1);

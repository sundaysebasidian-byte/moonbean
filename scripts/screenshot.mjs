// Captures the playground in light and dark mode with headless Chrome.
//
//   scripts/build-web.sh && node scripts/screenshot.mjs [out-dir]
//
// Serves web/dist on a local port, drives Chrome over the DevTools protocol and
// writes playground-light.png and playground-dark.png (default: docs/assets).
// Set CHROME to override the browser path.
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const dist = join(root, "web/dist");
const out = resolve(process.argv[2] ?? join(root, "docs/assets"));
const chrome = process.env.CHROME ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css" };

const server = createServer(async (req, res) => {
  const path = req.url.split(/[?#]/)[0];
  try {
    const body = await readFile(join(dist, path === "/" ? "index.html" : path));
    res.writeHead(200, { "content-type": types[extname(path)] ?? "text/html" }).end(body);
  } catch {
    res.writeHead(404).end();
  }
});
await new Promise((ok) => server.listen(0, "127.0.0.1", ok));
const url = `http://127.0.0.1:${server.address().port}/`;

const port = 9333 + Math.floor(Math.random() * 500);
const profile = mkdtempSync(join(tmpdir(), "moonbean-shot-"));
const proc = spawn(
  chrome,
  ["--headless=new", `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, "--hide-scrollbars", "--no-first-run", "about:blank"],
  { stdio: "ignore" },
);

async function endpoint() {
  for (let i = 0; i < 100; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
      const page = list.find((t) => t.type === "page");
      if (page) return page.webSocketDebuggerUrl;
    } catch {}
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error("Chrome did not start");
}

const socket = new WebSocket(await endpoint());
await new Promise((ok) => socket.addEventListener("open", ok));
let id = 0;
const pending = new Map();
socket.addEventListener("message", (event) => {
  const message = JSON.parse(event.data);
  pending.get(message.id)?.(message);
});
const send = (method, params = {}) =>
  new Promise((ok, fail) => {
    const n = ++id;
    pending.set(n, (m) => (m.error ? fail(new Error(m.error.message)) : ok(m.result)));
    socket.send(JSON.stringify({ id: n, method, params }));
  });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

await send("Page.enable");
await send("Emulation.setDeviceMetricsOverride", { width: 1440, height: 900, deviceScaleFactor: 2, mobile: false });
await mkdir(out, { recursive: true });

for (const scheme of ["light", "dark"]) {
  await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: scheme }] });
  await send("Page.navigate", { url: `${url}#reports` });
  await sleep(1200);
  const shot = await send("Page.captureScreenshot", { format: "png" });
  const file = join(out, `playground-${scheme}.png`);
  await writeFile(file, Buffer.from(shot.data, "base64"));
  console.log(`wrote ${file}`);
}

socket.close();
proc.kill();
server.close();

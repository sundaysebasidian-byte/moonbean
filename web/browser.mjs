// Starts headless Chrome on a local static server for web/dist and returns a
// small DevTools-protocol driver. Shared by the screenshot and DOM scripts.
//
// Set CHROME to override the browser path.
import { spawn, spawnSync } from "node:child_process";
import { createServer } from "node:http";
import { mkdtempSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css" };

function findChrome() {
  if (process.env.CHROME) return process.env.CHROME;
  const candidates = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "google-chrome",
    "google-chrome-stable",
    "chromium",
    "chromium-browser",
  ];
  for (const candidate of candidates) {
    if (candidate.startsWith("/")) {
      if (spawnSync("test", ["-x", candidate]).status === 0) return candidate;
    } else if (spawnSync("which", [candidate]).status === 0) {
      return candidate;
    }
  }
  throw new Error("Chrome not found; set CHROME");
}

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function launch({ width = 1440, height = 900, scale = 2 } = {}) {
  const dist = join(root, "web/dist");
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
  const profile = mkdtempSync(join(tmpdir(), "moonbean-browser-"));
  const proc = spawn(
    findChrome(),
    [
      "--headless=new",
      `--remote-debugging-port=${port}`,
      `--user-data-dir=${profile}`,
      "--hide-scrollbars",
      "--no-first-run",
      "--no-sandbox",
      "about:blank",
    ],
    { stdio: "ignore" },
  );

  let wsUrl;
  for (let i = 0; i < 150 && !wsUrl; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
      wsUrl = list.find((t) => t.type === "page")?.webSocketDebuggerUrl;
    } catch {}
    if (!wsUrl) await sleep(100);
  }
  if (!wsUrl) throw new Error("Chrome did not start");

  const socket = new WebSocket(wsUrl);
  await new Promise((ok) => socket.addEventListener("open", ok));
  let id = 0;
  const pending = new Map();
  const exceptions = [];
  socket.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    if (message.method === "Runtime.exceptionThrown") {
      exceptions.push(message.params.exceptionDetails.exception?.description ?? message.params.exceptionDetails.text);
    }
    pending.get(message.id)?.(message);
  });
  const send = (method, params = {}) =>
    new Promise((ok, fail) => {
      const n = ++id;
      pending.set(n, (m) => (m.error ? fail(new Error(m.error.message)) : ok(m.result)));
      socket.send(JSON.stringify({ id: n, method, params }));
    });

  await send("Page.enable");
  await send("Runtime.enable");
  await send("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: scale, mobile: false });

  return {
    url,
    exceptions,
    send,
    async open(hash = "") {
      await send("Page.navigate", { url: url + hash });
      await sleep(900);
    },
    async evaluate(expression) {
      const result = await send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
      if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description ?? "evaluate failed");
      return result.result.value;
    },
    async close() {
      socket.close();
      proc.kill();
      server.close();
    },
  };
}

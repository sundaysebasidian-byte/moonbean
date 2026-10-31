// Captures the playground in light and dark mode with headless Chrome.
//
//   scripts/build-web.sh && node scripts/screenshot.mjs [out-dir]
//
// Writes playground-light.png and playground-dark.png (default: docs/assets).
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { launch, sleep } from "../web/browser.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const out = resolve(process.argv[2] ?? join(root, "docs/assets"));
await mkdir(out, { recursive: true });

const browser = await launch();
for (const scheme of ["light", "dark"]) {
  await browser.send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: scheme }] });
  await browser.open("#reports");
  await sleep(400);
  const shot = await browser.send("Page.captureScreenshot", { format: "png" });
  const file = join(out, `playground-${scheme}.png`);
  await writeFile(file, Buffer.from(shot.data, "base64"));
  console.log(`wrote ${file}`);
}
if (browser.exceptions.length) {
  console.error(browser.exceptions.join("\n"));
  process.exitCode = 1;
}
await browser.close();

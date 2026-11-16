import { readFileSync } from "node:fs";
const m = new WebAssembly.Module(readFileSync(process.argv[2]), { builtins: ["js-string"], importedStringConstants: "_" });
console.log("imports:", JSON.stringify(WebAssembly.Module.imports(m).map(i => i.module + "." + i.name + ":" + i.kind)));
try { new WebAssembly.Instance(m, { "moonbitlang/async": { "runtime/get_platform": () => 1 }, __moonbit_time_unstable: { now: () => 0n } }); console.log("no error"); }
catch (e) { console.log(e.constructor.name, e.message.slice(0, 160)); }

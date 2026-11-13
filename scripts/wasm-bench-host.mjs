#!/usr/bin/env node
// Run the unchanged WasmGC benchmark with Node's default V8 heap and sample
// public heap statistics at guest clock reads and completed output records.
import { readFileSync } from 'node:fs';
import { getHeapStatistics } from 'node:v8';

const module = new WebAssembly.Module(readFileSync(process.argv[2]), {
  builtins: ['js-string'], importedStringConstants: '_',
});
let peakUsed = 0;
let minimumAvailable = Infinity;
let heapLimit = 0;
let samples = 0;
function sample() {
  const heap = getHeapStatistics();
  peakUsed = Math.max(peakUsed, heap.used_heap_size);
  minimumAvailable = Math.min(minimumAvailable, heap.total_available_size);
  heapLimit = heap.heap_size_limit;
  samples += 1;
}
let line = '';
const imports = {
  __moonbit_fs_unstable: {
    begin_create_string: () => [],
    string_append_char: (handle, code) => { handle.push(code); },
    finish_create_string: handle => String.fromCharCode(...handle),
    get_env_var: key => process.env[key] ?? '',
    get_env_var_exists: key => Object.hasOwn(process.env, key),
    begin_read_string: text => ({ text, index: 0 }),
    string_read_char(handle) {
      if (handle.index >= handle.text.length) return -1;
      const code = handle.text.codePointAt(handle.index);
      handle.index += code > 0xffff ? 2 : 1;
      return code;
    },
    finish_read_string: () => {},
  },
  'moonbitlang/async': { 'runtime/get_platform': () => 1 },
  __moonbit_time_unstable: {
    now() { sample(); return BigInt(Date.now()); },
  },
  spectest: {
    print_char(code) {
      if (code === 10) {
        sample();
        console.log(line);
        line = '';
      } else {
        line += String.fromCodePoint(code);
      }
    },
  },
};
sample();
new WebAssembly.Instance(module, imports).exports._start();
sample();
console.log(JSON.stringify({ heap: {
  host: `Node ${process.version} / V8 ${process.versions.v8}`,
  heap_size_limit_bytes: heapLimit,
  peak_sampled_used_heap_bytes: peakUsed,
  limit_minus_peak_sampled_used_bytes: heapLimit - peakUsed,
  minimum_sampled_available_heap_bytes: minimumAvailable,
  samples,
} }));

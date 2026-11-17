;; Test-only adapter for the ASCII library_demo entry point, not a MoonBit runtime.
;; Unsupported output is rejected rather than silently corrupted.
(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "clock_time_get"
    (func $clock (param i32 i64 i32) (result i32)))
  (memory (export "memory") 1)
  (func (export "runtime/get_platform") (result i32) i32.const 1)
  (func (export "now") (result i64)
    i32.const 0 i64.const 1000000 i32.const 24 call $clock
    if unreachable end
    i32.const 24 i64.load i64.const 1000000 i64.div_u)
  (func (export "print_char") (param $char i32)
    local.get $char i32.const 127 i32.gt_u if unreachable end
    i32.const 16 local.get $char i32.store8
    i32.const 0 i32.const 16 i32.store
    i32.const 4 i32.const 1 i32.store
    i32.const 1 i32.const 0 i32.const 1 i32.const 8 call $write
    if unreachable end))

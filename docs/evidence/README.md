# Local 0.1.1 verification

- `acceptance.json`: executed command exit codes; check/test/fmt/info logs.
  `mbti.diff` is empty after `moon info`.
- `performance/results.json`: primary seven-run interleaved measurements;
  all samples, toolchain/CPU/OS/Python and input/executable SHA-256.
  `historical-*.json` preserve the recovered older arrays;
  `exploratory.json` preserves the first, less strictly controlled run.
  Profiles and sampling status are separate from timings.
- `oracle.log`: original 58 ledgers, 56 compared/passed, 2 extensions.
- `random-*.log`: two 1000-ledger seeded runs, accepting only the exact
  known AVERAGE extension diagnostic delta. Full generated inputs/results
  remain locally under `.oracle-cache/differential/seed-*-011/`.
- `migration.json`: real native CLI diagnostics/statuses on five new ledgers
  and three explicitly executed unsupported queries.
- `web-build.log`, `web-smoke.log`, `web-dom-smoke.log`: build plus 29 Node
  checks and 8 headless Chrome checks. The first Node run exposed the newly
  intentional document warning; its expected warning was updated and rerun.

No source/fixtures were read from Beancount. Installed oracle tools run only as
external processes. These are local results, not new published-package, remote
CI or production deployment evidence. Generated benchmark ledger and baseline
builds remain ignored locally; no cleanup deletion is implied.

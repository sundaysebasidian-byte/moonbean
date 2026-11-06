#!/usr/bin/env bash
# Builds the browser playground into web/dist.
#
#   scripts/build-web.sh
#
# Compiles the `playground` package for the JS backend and copies it, together
# with the static page in web/ and the example ledger, to web/dist. Requires the
# MoonBit toolchain and node.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

moon build --target js --release playground

built="_build/js/release/build/playground/playground.js"
dist="web/dist"
rm -rf "$dist"
mkdir -p "$dist"

# The playground depends only on pure packages, so the bundle must not import
# any node: module. Fail loudly if that ever changes.
if grep -Eq '(from|import\()\s*"node:' "$built"; then
  echo "error: playground.js imports a node: module" >&2
  exit 1
fi
cp "$built" "$dist/moonbean.js"

for file in index.html style.css app.js lib.js; do
  cp "web/$file" "$dist/$file"
done

# The built-in example is the repository's full-year ledger.
node --input-type=module -e '
import { readFileSync, writeFileSync } from "node:fs";
const source = readFileSync("examples/full-year-2024.beancount", "utf8");
writeFileSync(
  process.argv[1],
  `export default ${JSON.stringify({ name: "full-year-2024.beancount", source })};\n`,
);
' "$dist/example.js"

touch "$dist/.nojekyll"
echo "built $dist"

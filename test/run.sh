#!/usr/bin/env bash
# Tests for the shared scripts, run against test/fixture-module. Each case changes one thing and
# expects the check to fail with a specific message, then restores the fixture.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
fixture="$here/fixture-module"
export ACTION_PATH="$here/../check" GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-dxcufgb/foundry-module-ci}"
export RUNNER_TEMP="${RUNNER_TEMP:-$(mktemp -d)}"
work="$(mktemp -d)"
failures=0

reset() { rm -rf "$work/m"; cp -r "$fixture" "$work/m"; }
run_check() { (cd "$work/m" && bash "$here/../scripts/check.sh") >"$work/out.log" 2>&1; }
expect_pass() {
  if run_check; then echo "ok   $1"; else echo "FAIL $1 (expected success)"; tail -20 "$work/out.log"; failures=$((failures + 1)); fi
}
expect_fail() {
  if run_check; then echo "FAIL $1 (expected failure)"; failures=$((failures + 1));
  elif grep -q -- "$2" "$work/out.log"; then echo "ok   $1";
  else echo "FAIL $1 (failed, but without \"$2\")"; tail -20 "$work/out.log"; failures=$((failures + 1)); fi
}

reset; expect_pass "fixture passes"
reset; run_check
if [ "$(jq -r .version "$work/m/module.json")" = "0.0.0" ] && [ ! -e "$work/m/module.zip" ]; then
  echo "ok   dry run leaves module.json and no zip behind"
else
  echo "FAIL dry run left changes"; failures=$((failures + 1))
fi

reset; echo '{ "FMC": {} }' > "$work/m/lang/en.json"
expect_fail "missing setting translation" 'translation "FMC.Settings.Enabled.Name" is missing'

reset; rm "$work/m/templates/card.hbs"
expect_fail "missing own template" 'uses template "templates/card.hbs", which does not exist'

reset; jq '.esmodules = ["scripts/nope.js"]' "$work/m/module.json" > "$work/t" && mv "$work/t" "$work/m/module.json"
expect_fail "manifest points at a missing file" 'points at "scripts/nope.js"'

reset; echo 'Hooks.once("init", () => { throw new Error("boom") })' >> "$work/m/scripts/main.js"
expect_fail "init hook throws" 'hook threw'

reset; mkdir -p "$work/m/.github"; echo '{"include":["module.json","scripts"]}' > "$work/m/.github/foundry-module.json"
expect_fail "include list misses referenced files" 'missing from module.zip: styles/fixture.css'

reset; mkdir -p "$work/m/.github"; echo '{"include":["module.json","scripts","styles","lang","templates"],"build":"mkdir -p built && echo hi > built/x","lint":"test -f module.json"}' > "$work/m/.github/foundry-module.json"
expect_pass "include list, build and lint commands"

reset; mkdir -p "$work/m/.github"; echo '{"lint":"false"}' > "$work/m/.github/foundry-module.json"
expect_fail "failing lint command fails the check" 'Lint (false)'

reset; jq 'del(.languages)' "$work/m/module.json" > "$work/t" && mv "$work/t" "$work/m/module.json"
mkdir -p "$work/m/.github"; echo '{"requireLanguages":false,"importTest":false}' > "$work/m/.github/foundry-module.json"
expect_pass "requireLanguages and importTest can be turned off"

for tag in v1.2 v1.2.3-beta.1 1.2.3 v01.2.3; do
  reset
  if (cd "$work/m" && bash "$here/../scripts/package.sh" "$tag") >/dev/null 2>&1; then
    echo "FAIL package.sh accepted $tag"; failures=$((failures + 1)); else echo "ok   package.sh rejects $tag"; fi
done
reset
if (cd "$work/m" && bash "$here/../scripts/package.sh" v1.2.3) >/dev/null 2>&1 \
  && [ "$(jq -r .version "$work/m/module.json")" = 1.2.3 ] \
  && [ "$(jq -r .download "$work/m/module.json")" = "https://github.com/$GITHUB_REPOSITORY/releases/download/v1.2.3/module.zip" ] \
  && unzip -l "$work/m/module.zip" | grep -q "lang/en.json"; then
  echo "ok   package.sh v1.2.3 stamps the manifest and builds the zip"
else echo "FAIL package.sh v1.2.3"; failures=$((failures + 1)); fi

echo
if [ "$failures" -eq 0 ]; then echo "All tests passed."; else echo "$failures test(s) failed."; exit 1; fi

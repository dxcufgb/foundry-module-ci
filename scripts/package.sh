#!/usr/bin/env bash
# Packages a Foundry VTT module the way a release ships it.
#
#   package.sh v1.2.3
#
# Run from the module's repository root. Stamps version and URLs into module.json from the tag,
# builds module.zip and checks that everything module.json references is in the zip and that no
# git/CI/development files are.
#
# What goes into module.zip:
#   - by default the whole repository except development files (see EXCLUDES below);
#   - or, if .github/foundry-module.json has "include": ["module.json", "scripts", ...], only those paths.
#
# Needs GITHUB_REPOSITORY (owner/repo), jq, zip and unzip.
set -euo pipefail

TAG="${1:?usage: package.sh <tag like v1.2.3>}"
# Plain releases only: Foundry installs from .../releases/latest/, which skips pre-releases, so a
# pre-release tag would produce a manifest that points somewhere else.
if ! [[ "$TAG" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "::error::Tag '$TAG' must look like v1.2.3 (no pre-release suffix)." >&2
  exit 1
fi
VERSION="${TAG#v}"
REPO_URL="https://github.com/${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"
CONFIG=.github/foundry-module.json
TMP="${RUNNER_TEMP:-/tmp}"

[ -f module.json ] || { echo "::error::module.json not found in $(pwd)" >&2; exit 1; }

jq \
  --arg version  "$VERSION" \
  --arg url      "$REPO_URL" \
  --arg manifest "${REPO_URL}/releases/latest/download/module.json" \
  --arg download "${REPO_URL}/releases/download/${TAG}/module.zip" \
  '.version = $version | .url = $url | .manifest = $manifest | .download = $download
   | .bugs = ($url + "/issues") | .readme = ($url + "#readme")' \
  module.json > module.tmp.json
jq -e --arg v "$VERSION" '.version == $v' module.tmp.json >/dev/null
mv module.tmp.json module.json

# Never shipped, whatever "include" says.
EXCLUDES=(".git/*" ".github/*" ".githooks/*" ".claude/*" ".vscode/*" "node_modules/*"
  ".gitignore" ".gitattributes" ".editorconfig" "CLAUDE.md" "module.zip" "*.tmp.json"
  "*/LOCK" "*/LOG" "*/LOG.old")

rm -f module.zip
if [ -f "$CONFIG" ] && jq -e '.include | type == "array" and length > 0' "$CONFIG" >/dev/null; then
  mapfile -t INCLUDE < <(jq -r '.include[]' "$CONFIG")
  for p in "${INCLUDE[@]}"; do
    [ -e "$p" ] || { echo "::error::$CONFIG includes \"$p\", which does not exist (did the build step run?)" >&2; exit 1; }
  done
  zip -qr module.zip "${INCLUDE[@]}" -x "${EXCLUDES[@]}"
else
  zip -qr module.zip . -x "${EXCLUDES[@]}"
fi
echo "Contents of module.zip:"
unzip -l module.zip

zipinfo -1 module.zip > "$TMP/zip-contents.txt"
missing=0
grep -qx "module.json" "$TMP/zip-contents.txt" || { echo "::error::module.json is missing from module.zip"; missing=1; }
while IFS= read -r f; do
  [ -n "$f" ] || continue
  grep -qx -- "$f" "$TMP/zip-contents.txt" || grep -q -- "^$f/" "$TMP/zip-contents.txt" || { echo "::error::missing from module.zip: $f"; missing=1; }
done < <(jq -r '[.esmodules[]?, .scripts[]?, (.styles[]? | if type == "object" then .src else . end), .languages[]?.path, .packs[]?.path] | .[]' module.json)
if grep -qE '^(\.git|\.github|node_modules)/' "$TMP/zip-contents.txt"; then echo "::error::development files ended up in module.zip"; missing=1; fi
exit $missing

#!/usr/bin/env bash
# CI for a Foundry VTT module. Called by the "check" action; run from the module's repository root.
# Runs the optional build and lint commands from .github/foundry-module.json, the module checks,
# and a dry run of the release packaging (module.json is restored afterwards).
#
# Environment (set by the action): ACTION_PATH, GITHUB_REPOSITORY.
set -euo pipefail

CONFIG=.github/foundry-module.json
cfg() {
  if [ -f "$CONFIG" ]; then jq -r --arg k "$1" '.[$k] // empty' "$CONFIG"; fi
}

build="$(cfg build)"
if [ -n "$build" ]; then
  echo "::group::Build ($build)"
  bash -euo pipefail -c "$build"
  echo "::endgroup::"
fi

lint="$(cfg lint)"
if [ -n "$lint" ]; then
  echo "::group::Lint ($lint)"
  bash -euo pipefail -c "$lint"
  echo "::endgroup::"
fi

echo "::group::Check module"
node "$ACTION_PATH/../scripts/check-module.mjs"
echo "::endgroup::"

echo "::group::Dry run of the release packaging"
cp module.json "${RUNNER_TEMP:-/tmp}/module.json.orig"
status=0
bash "$ACTION_PATH/../scripts/package.sh" v0.0.0 || status=$?
cp "${RUNNER_TEMP:-/tmp}/module.json.orig" module.json
rm -f module.zip
echo "::endgroup::"
exit $status

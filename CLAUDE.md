# foundry-module-ci

Shared CI and release for every dxcufgb Foundry VTT module repository. It is not a module: it holds two composite
actions (`check/`, `release/`) and the scripts they run, plus the two workflow files every module copies. Module
repositories pin it by commit SHA (`dxcufgb/foundry-module-ci/check@<sha> # vX.Y.Z`) and Dependabot proposes the
update when a new tag is made here. No build step and no npm dependencies (Node built-ins, bash, `jq`, `zip`,
`unzip`, `gh`).

## Layout
- `check/action.yml` – composite action: `actions/setup-node` (Node 22), then `scripts/check.sh` in the input
  `working-directory` (default `.`).
- `release/action.yml` – composite action: setup-node, then `scripts/release.sh` with `GH_TOKEN` (input
  `github-token`), `VERSION_INPUT` (input `version`), `EVENT_NAME`, `EVENT_TAG`, `DEFAULT_BRANCH` from the event.
- `scripts/check.sh` – the optional `build` and `lint` commands from `.github/foundry-module.json`, then
  `check-module.mjs`, then a dry run of `package.sh v0.0.0` (`module.json` restored, `module.zip` removed).
- `scripts/check-module.mjs` – the module checks: (1) `module.json` fields, id characters, every referenced file
  exists, relationships have `id`/`type`; (2) every script under the `esmodules` folders passes `node --check`,
  language files are valid JSON (other languages missing keys is only a note), this module's own
  `modules/<id>/….hbs|html` template references exist; (3) imports each esmodule with stubbed Foundry globals
  (`autoStub` Proxy, `Hooks`, `game.settings`, ...), runs the `init`/`i18nInit`/`setup` hooks, checks an exported
  `MODULE_ID`/`MODULE`/`ID` equals the manifest id, settings are registered under the id and not twice, and every
  visible setting's `name`/`hint` key exists in `lang/en.json`. Config keys `requireLanguages`, `importTest`.
- `scripts/package.sh <vX.Y.Z>` – stamps `version`, `url`, `manifest`, `download`, `bugs`, `readme` into
  `module.json`, builds `module.zip` (whole repository minus `EXCLUDES`, or only the `include` paths) and checks
  that every referenced file is in it and no `.git`/`.github`/`node_modules` is.
- `scripts/release.sh` – `workflow_dispatch`: only on the default branch, version `X.Y.Z` (leading `v` stripped),
  refused if the tag or a release/draft of that name exists; builds, checks, packages, then
  `gh release create --draft --target $GITHUB_SHA` with both files and publishes it as latest. `release` event
  (published by hand): builds and `gh release upload --clobber` the two files to that release.
- `templates/ci.yml`, `templates/release.yml` – the workflow files every module copies unchanged, with `__SHA__` /
  `__VERSION__` replaced by this repository's release commit and tag. Job name **Check module** is a required check
  in the module rulesets.
- `test/run.sh` – runs `check.sh`/`package.sh` against `test/fixture-module` (module id `fmc-fixture`): one passing
  case, failure cases each with the expected message, tag validation of `package.sh`.
- `.github/workflows/ci.yml` (shellcheck, `test/run.sh`, the `./check` action on the fixture), `workflow-lint.yml`
  (actionlint, zizmor; `.github/zizmor.yml` disables `self-repository`), `dependabot.yml` (`/`, `/check`, `/release`).

## Commands
- `bash test/run.sh` (needs `jq`, `zip`, `unzip`, Node), `shellcheck scripts/*.sh test/*.sh`.

## Conventions
- Bash with `set -euo pipefail`, errors as `::error::` annotations, output grouped with `::group::`.
- `check-module.mjs` stays dependency-free and network-free.
- After merging a change, tag a release `vX.Y.Z` here so module repositories get a Dependabot update.
- `README.md` documents the actions, the checks and `.github/foundry-module.json`; keep it in step.

## Review focus
- **Blast radius**: every module repository runs this code. Flag breaking changes to action inputs, to the
  `.github/foundry-module.json` keys, to the check rules (a new failing check fails CI in every module at the next
  Dependabot bump), and to the job name `Check module` (a required status check).
- **Release safety**: nothing may be published from an unchecked commit: build, `check-module.mjs` and
  `package.sh` must all run before `gh release create`, which stays a draft until both files are on it. Keep the
  default-branch check, the exact `^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$` tag rule in both
  `release.sh` and `package.sh` (Foundry installs from `releases/latest`, which skips pre-releases), and the refusal
  of an existing tag or release. Never overwrite an existing release on `workflow_dispatch`.
- **Manifest contract**: the URLs `package.sh` stamps (`.../releases/latest/download/module.json`,
  `.../releases/download/<tag>/module.zip`) are what Foundry and the dxcufgb private GitHub proxy use; the proxy
  serves exactly the files `module.json` and `module.zip`. Do not rename them.
- **Untrusted input**: `build`/`lint` come from the module's own repository and run as shell; the action inputs and
  event values reach scripts only through `env:` (never `${{ }}` inside `run:`). Keep it that way.
- **Templates**: pins stay full commit SHAs with the version comment; `persist-credentials: false`, `lfs: true`;
  release permissions only `contents: write` on the job. A change to `templates/` must be applied to every module
  repository too (say so in the PR).
- **Tests**: a new or changed check needs a passing and a failing case in `test/run.sh` with the exact message; the
  fixture must keep exercising every check. The import test must stay deterministic (no timers, no network).
- `module.zip` must never contain development files: the `EXCLUDES` list in `package.sh` applies whatever
  `include` says. It names specific dotfiles only, so a new repository-level dotfile in the modules (for example a
  tool config) needs an entry there.

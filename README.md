# foundry-module-ci

Shared CI and release for dxcufgb's Foundry VTT modules. Every module repository has the same two
small workflow files; the work happens here, in two composite actions:

| Action | What it does |
|---|---|
| `dxcufgb/foundry-module-ci/check` | CI: optional build and lint commands, the module checks, and a dry run of the release packaging |
| `dxcufgb/foundry-module-ci/release` | Release: checks and builds everything, then creates and publishes `vX.Y.Z` with `module.json` and `module.zip` |

## Releasing a module (the same in every repository)

1. Merge what you want to release into `main`.
2. **Actions → Release module → Run workflow**, type the version (for example `1.2.3`), click **Run workflow**.

That's it. The workflow:

- refuses a version that is not `X.Y.Z`, that already exists, or a run that is not on `main`;
- runs the build (if the module has one), the module checks and the packaging **before** anything is published;
- stamps `version`, `url`, `manifest`, `download`, `bugs` and `readme` into `module.json` from the version;
- creates the release `v1.2.3` on the commit it built, with generated release notes, `module.json` and `module.zip`.

If any step fails, nothing is published: fix the cause and run it again with the same version.

Fallback: publishing a release by hand on GitHub (tag `v1.2.3`) still works. The files are attached to it
afterwards, but if that build fails the release stays without files, so prefer **Run workflow**.

People install a public module from `https://github.com/dxcufgb/<repo>/releases/latest/download/module.json`.
Private modules are installed through the Foundry private GitHub proxy, which serves the same two files.

### Updating the Workshop site on release

The [Workshop site](https://github.com/dxcufgb/FVTT-dev-showcase) rebuilds every 6 hours on its own. When the
module repository has the secret `SITE_DISPATCH_TOKEN`, the release workflow also asks it to rebuild right after
the release is published (a `module-released` repository dispatch), so the new version shows up within minutes.
Without the secret nothing changes. A failed ping (expired token, missing permission) is a warning on the run; the
release itself is already out.

The token: a [fine-grained personal access token](https://github.com/settings/personal-access-tokens/new) with
**Repository access: only `dxcufgb/FVTT-dev-showcase`** and **Contents: Read and write** (what a repository
dispatch needs), nothing else. Save it as the repository secret `SITE_DISPATCH_TOKEN` in each module, e.g.
`gh secret set SITE_DISPATCH_TOKEN -R dxcufgb/<repo>` (it reads the value from the prompt). The action inputs are
`site-dispatch-token` (empty = no ping) and `site-repository` (default `dxcufgb/FVTT-dev-showcase`).

## The checks

`scripts/check-module.mjs` (no dependencies):

1. `module.json` is valid, has the fields Foundry needs, and every file it points at exists.
2. Every script parses; every language file is valid JSON; every template of this module that a script
   references exists (templates of other modules, `modules/<other-id>/...`, are skipped).
3. The module imports with stubbed Foundry globals, its `init`/`i18nInit`/`setup` hooks run without
   throwing, settings are registered under the module id, and every visible setting has its Name and
   Hint in `lang/en.json`.

`scripts/package.sh` builds `module.zip` and checks that everything `module.json` references is in it and
that no development files are.

## Per-module settings: `.github/foundry-module.json`

Optional. Most modules need none. All keys are optional:

```json
{
  "build": "npm ci && npm run pack",
  "lint": "npx eslint .",
  "include": ["module.json", "scripts", "packs", "Icons"],
  "requireLanguages": true,
  "importTest": true
}
```

| Key | Default | Meaning |
|---|---|---|
| `build` | none | Shell command run before the checks and the packaging (CI and release), e.g. building compendium packs |
| `lint` | none | Shell command run in CI only |
| `include` | everything except development files | Paths that go into `module.zip` |
| `requireLanguages` | `true` | `false` if the module has no language files |
| `importTest` | `true` | `false` to skip the import test (part 3) |

Never shipped, whatever `include` says: `.git`, `.github`, `.githooks`, `.claude`, `.vscode`,
`node_modules`, `CLAUDE.md`, `.coderabbit.yaml`, `.gitignore`, `.gitattributes`, `.editorconfig`, pack `LOCK`/`LOG` files.

## The workflow files in each module

Copy [`templates/ci.yml`](templates/ci.yml) and [`templates/release.yml`](templates/release.yml) to
`.github/workflows/` unchanged. The job name **Check module** is a required status check in the module
rulesets. Both pin this repository to a commit SHA; Dependabot (github-actions) proposes the update when a
new version is tagged here, so a fix here reaches every module through one PR each.

## Changing this repository

- `bash test/run.sh` runs the tests (fixture module in `test/fixture-module`); CI also runs shellcheck,
  actionlint and zizmor.
- After merging a change, tag a release (`vX.Y.Z`) so module repositories get a Dependabot update.

# foundry-module-ci

Shared CI and release for dxcufgb's Foundry VTT modules. Every module repository has the same
small workflow files; the work happens here, in composite actions

| Action | What it does |
|---|---|
| `dxcufgb/foundry-module-ci/check` | CI: optional build and lint commands, the module checks, and a dry run of the release packaging |
| `dxcufgb/foundry-module-ci/release` | Release: checks and builds everything, then creates and publishes `vX.Y.Z` with `module.json` and `module.zip` |
| `dxcufgb/foundry-module-ci/coderabbit` | Asks CodeRabbit to review a pull request (any repository, not only modules) |

and one shared (reusable) workflow, `.github/workflows/claude-reusable.yml`: the Claude review (see
[Claude reviews](#claude-reviews)).

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

## CodeRabbit reviews

CodeRabbit no longer reviews pull requests automatically on repositories with fewer than 10 stars, but it still
answers a `@coderabbitai review` comment. [`templates/coderabbit.yml`](templates/coderabbit.yml) posts that comment
for you when a pull request is opened, updated, reopened or marked ready for review (drafts, bot-opened PRs and PRs
from forks are skipped; comment by hand on those). Copy it to `.github/workflows/coderabbit.yml` in every repository
CodeRabbit reviews; it needs no checkout and works in repositories that are not modules too.

CodeRabbit ignores the command when `github-actions[bot]` posts it, so the comment is posted as you, with the
repository secret `CODERABBIT_TRIGGER_TOKEN`:

1. Create a [fine-grained personal access token](https://github.com/settings/personal-access-tokens/new):
   **Repository access: All repositories** (or the ones CodeRabbit reviews), **Permissions → Pull requests: Read
   and write**, nothing else.
2. Save it in each repository, e.g. `gh secret set CODERABBIT_TRIGGER_TOKEN -R dxcufgb/<repo>` (it reads the value
   from the prompt).

Without the secret, or with an expired token, the run is only a warning and nothing is commented.

## Claude reviews

[`.github/workflows/claude-reusable.yml`](.github/workflows/claude-reusable.yml) holds both Claude jobs:

- **Review**: every pull request that is opened, updated, reopened or marked ready for review gets an automatic
  review (drafts, bot-opened PRs and PRs from forks are skipped). Ask for a fresh one with `@claude review`.
- **Respond to @claude**: a PR or issue comment (or a PR review comment) that mentions `@claude` gets an answer
  or a change. Only the owner, members and collaborators start it, never bots (`contains()` ignores case, so a bot
  quoting `@CLAUDE.md` would otherwise start it, and the action fails on bot actors).

Every repository, modules or not, has the same caller, [`templates/claude.yml`](templates/claude.yml), as
`.github/workflows/claude.yml`. A shared workflow cannot declare the caller's triggers, so the caller keeps them,
grants the permissions (each job here asks for less) and passes the repository secret `CLAUDE_CODE_OAUTH_TOKEN`
(created with `claude setup-token`). The check names become `claude / Review` and `claude / Respond to @claude`.
Comment events always run the default branch's `claude.yml`, so a change to the respond job takes effect once the
caller's pin is bumped on `main`. This repository calls the file locally (`./.github/workflows/claude-reusable.yml`),
so a pull request here reviews itself with its own version.

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

Copy [`templates/ci.yml`](templates/ci.yml), [`templates/release.yml`](templates/release.yml),
[`templates/coderabbit.yml`](templates/coderabbit.yml) and [`templates/claude.yml`](templates/claude.yml) to
`.github/workflows/` unchanged (`coderabbit.yml` and `claude.yml` go to the other repositories too). The job name **Check module** is a required status check in the module
rulesets. They pin this repository to a commit SHA; Dependabot (github-actions) proposes the update when a
new version is tagged here, so a fix here reaches every module through one PR each.

## Changing this repository

- `bash test/run.sh` runs the tests (fixture module in `test/fixture-module`); CI also runs shellcheck,
  actionlint and zizmor.
- After merging a change, tag a release (`vX.Y.Z`) so module repositories get a Dependabot update.

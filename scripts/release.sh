#!/usr/bin/env bash
# Releases a Foundry VTT module. Called by the "release" action; run from the module's repository root.
#
# Two ways in:
#   - workflow_dispatch ("Run workflow" with a version such as 1.2.3): checks and builds everything first,
#     then creates the release v1.2.3 on the commit that was built and publishes it. Nothing is published
#     if any step fails. Only allowed on the default branch, and refused if v1.2.3 already exists.
#   - release published (a release created by hand in the GitHub UI): builds and attaches module.json and
#     module.zip to that release. Kept as a fallback; a failure here leaves the release without files.
#
# Environment (set by the action): GH_TOKEN, VERSION_INPUT, EVENT_NAME, EVENT_TAG, DEFAULT_BRANCH,
# GITHUB_REPOSITORY, GITHUB_REF, GITHUB_SHA, ACTION_PATH.
set -euo pipefail

CONFIG=.github/foundry-module.json
cfg() { [ -f "$CONFIG" ] && jq -r --arg k "$1" '.[$k] // empty' "$CONFIG" || true; }

# --- which version ----------------------------------------------------------------------------
case "$EVENT_NAME" in
  workflow_dispatch)
    VERSION="${VERSION_INPUT#v}"
    TAG="v$VERSION"
    if [ "$GITHUB_REF" != "refs/heads/$DEFAULT_BRANCH" ]; then
      echo "::error::Run the release on the default branch ($DEFAULT_BRANCH), not ${GITHUB_REF#refs/heads/}."
      exit 1
    fi
    ;;
  release)
    TAG="$EVENT_TAG"
    VERSION="${TAG#v}"
    ;;
  *)
    echo "::error::Unsupported event '$EVENT_NAME'."
    exit 1
    ;;
esac
if ! [[ "$TAG" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "::error::Version '$VERSION' must look like 1.2.3 (no 'v', no pre-release suffix)."
  exit 1
fi
if [ "$EVENT_NAME" = workflow_dispatch ]; then
  if gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$TAG" >/dev/null 2>&1; then
    echo "::error::$TAG already exists. Pick a higher version."
    exit 1
  fi
  if gh release view "$TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
    echo "::error::A release (or draft) named $TAG already exists. Delete it or pick a higher version."
    exit 1
  fi
fi
echo "Releasing $TAG from $GITHUB_SHA"

# --- build, check, package ----------------------------------------------------------------------
build="$(cfg build)"
if [ -n "$build" ]; then
  echo "::group::Build ($build)"
  bash -euo pipefail -c "$build"
  echo "::endgroup::"
fi
echo "::group::Check module"
node "$ACTION_PATH/../scripts/check-module.mjs"
echo "::endgroup::"
echo "::group::Package"
bash "$ACTION_PATH/../scripts/package.sh" "$TAG"
echo "::endgroup::"

# --- publish ------------------------------------------------------------------------------------
if [ "$EVENT_NAME" = workflow_dispatch ]; then
  # A draft first: the tag only appears when the release is published, and only after both files are on it.
  gh release create "$TAG" --repo "$GITHUB_REPOSITORY" --draft --target "$GITHUB_SHA" \
    --title "$TAG" --generate-notes module.json module.zip
  gh release edit "$TAG" --repo "$GITHUB_REPOSITORY" --draft=false --latest
else
  gh release upload "$TAG" --repo "$GITHUB_REPOSITORY" --clobber module.json module.zip
fi
manifest="https://github.com/$GITHUB_REPOSITORY/releases/latest/download/module.json"
{
  echo "### Released $TAG"
  echo
  echo "- Release: https://github.com/$GITHUB_REPOSITORY/releases/tag/$TAG"
  echo "- Manifest URL: $manifest"
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

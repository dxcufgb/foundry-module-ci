#!/usr/bin/env bash
# Asks the Workshop site (dxcufgb/FVTT-dev-showcase) to rebuild after a release, so the new version shows up
# there at once instead of at the site's next scheduled build. Runs only when the module passes a
# site-dispatch-token. The release is already published when this runs, so a failed ping is a warning, never an
# error: the site's schedule picks the release up anyway.
# Env: GH_TOKEN (the dispatch token), SITE_REPOSITORY (owner/repo), GITHUB_REPOSITORY, and the tag from EVENT_TAG
# (a release published by hand) or VERSION_INPUT (Run workflow).
set -euo pipefail

if [ -n "${EVENT_TAG:-}" ]; then tag="$EVENT_TAG"; elif [ -n "${VERSION_INPUT:-}" ]; then tag="v${VERSION_INPUT#v}"; else tag=""; fi

if [[ ! ${SITE_REPOSITORY:-} =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "::warning::site-repository must be owner/repo; not asking the site to rebuild."
  exit 0
fi

err="$(mktemp)"
trap 'rm -f "$err"' EXIT
if gh api --method POST "repos/$SITE_REPOSITORY/dispatches" \
  -f event_type=module-released \
  -f "client_payload[repository]=$GITHUB_REPOSITORY" \
  -f "client_payload[tag]=$tag" >/dev/null 2>"$err"; then
  echo "Asked $SITE_REPOSITORY to rebuild."
  echo "- Workshop site: asked $SITE_REPOSITORY to rebuild" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
else
  # gh's message names the HTTP status (404 = the token cannot see the site repository, 403 = it lacks
  # Contents: write); it never contains the token.
  echo "::warning::Could not ask $SITE_REPOSITORY to rebuild: $(head -c 300 "$err" | tr '\n' ' ')- the site picks the release up at its next scheduled build. Check that SITE_DISPATCH_TOKEN can write Contents of $SITE_REPOSITORY and has not expired."
fi

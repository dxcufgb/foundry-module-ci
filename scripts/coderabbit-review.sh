#!/usr/bin/env bash
# Asks CodeRabbit to review a pull request by commenting "@coderabbitai review" on it. CodeRabbit skips automatic
# reviews on repositories with fewer than 10 stars, but still answers this command. The review is optional, so a
# comment that cannot be posted is a warning, never an error.
# Env: GH_TOKEN (needs pull-requests: write), GITHUB_REPOSITORY, PR_NUMBER.
set -euo pipefail

if [[ ! ${PR_NUMBER:-} =~ ^[1-9][0-9]*$ ]]; then
  echo "::warning::No pull request number (run this from a pull_request workflow); not asking CodeRabbit for a review."
  exit 0
fi

err="$(mktemp)"
trap 'rm -f "$err"' EXIT
if gh api --method POST "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" \
  -f body='@coderabbitai review' >/dev/null 2>"$err"; then
  echo "Asked CodeRabbit to review #$PR_NUMBER."
  echo "- CodeRabbit: asked for a review of #$PR_NUMBER" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
else
  # gh's message names the HTTP status (403 = the token lacks pull-requests: write); it never contains the token.
  echo "::warning::Could not ask CodeRabbit to review #$PR_NUMBER: $(head -c 300 "$err" | tr '\n' ' ')- comment \"@coderabbitai review\" on the pull request instead."
fi

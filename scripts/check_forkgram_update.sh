#!/usr/bin/env bash
# Propose a reviewed source pin update. NEVER change Gozar's shipped branch
# or automatically merge an untested Forkgram release.
set -euo pipefail

BASE_BRANCH="${FORKGRAM_BASE_BRANCH:-feature/forkgram-embedded-telegram}"
UPSTREAM_REPO="forkgram/TelegramAndroid"
SUBMODULE="third_party/forkgram"

for executable in git gh jq; do
  command -v "$executable" >/dev/null || {
    echo "Missing required executable: $executable" >&2
    exit 2
  }
done
[[ -n "${GH_TOKEN:-}" ]] || {
  echo "GH_TOKEN is required for reading release metadata and creating a PR" >&2
  exit 2
}
[[ -f .gitmodules ]] || { echo "No submodule declaration" >&2; exit 2; }
grep -Fq 'https://github.com/forkgram/TelegramAndroid.git' .gitmodules ||
  { echo "Unexpected upstream repository" >&2; exit 2; }
[[ "$(git ls-files --stage "$SUBMODULE" | awk '{print $1}')" == "160000" ]] ||
  { echo "Forkgram must remain an isolated source submodule" >&2; exit 2; }

# The selected release should resolve to a commit, including annotated tags.
LATEST_TAG="$(gh api "repos/$UPSTREAM_REPO/releases/latest" --jq '.tag_name')"
[[ "$LATEST_TAG" =~ ^[A-Za-z0-9._-]+$ ]] ||
  { echo "Unexpected release tag" >&2; exit 2; }
tag_json="$(gh api "repos/$UPSTREAM_REPO/git/ref/tags/$LATEST_TAG")"
LATEST_SHA="$(jq -r '.object.sha' <<< "$tag_json")"
object_type="$(jq -r '.object.type' <<< "$tag_json")"
for _ in 1 2 3; do
  [[ "$object_type" != "tag" ]] && break
  tag_json="$(gh api "repos/$UPSTREAM_REPO/git/tags/$LATEST_SHA")"
  LATEST_SHA="$(jq -r '.object.sha' <<< "$tag_json")"
  object_type="$(jq -r '.object.type' <<< "$tag_json")"
done
[[ "$object_type" == "commit" && "$LATEST_SHA" =~ ^[a-fA-F0-9]{40}$ ]] ||
  { echo "Could not resolve upstream release to a commit" >&2; exit 2; }

CURRENT_SHA="$(git ls-files --stage "$SUBMODULE" | awk '{print $2}')"
if [[ "$CURRENT_SHA" == "$LATEST_SHA" ]]; then
  echo "Forkgram pin is already current at release $LATEST_TAG ($CURRENT_SHA)"
  exit 0
fi

# An upstream check is not a migration: integration/API/NDK compatibility must
# be reviewed and tested before anyone merges the proposed pointer change.
BOT_BRANCH="bot/forkgram-release-${LATEST_TAG//./-}"
if git ls-remote --exit-code --heads origin "$BOT_BRANCH" >/dev/null 2>&1; then
  echo "Candidate branch already exists: $BOT_BRANCH"
  exit 0
fi
BASE_REMOTE="$(git ls-remote origin "refs/heads/$BASE_BRANCH" | awk '{print $1}')"
[[ -n "$BASE_REMOTE" && "$BASE_REMOTE" == "$(git rev-parse HEAD)" ]] ||
  { echo "Checkout does not match latest integration branch; refusing update" >&2; exit 2; }

git switch -c "$BOT_BRANCH"
git update-index --add --cacheinfo "160000,$LATEST_SHA,$SUBMODULE"
printf '{\n  "upstream": "%s",\n  "release_tag": "%s",\n  "commit": "%s"\n}\n' \
  "$UPSTREAM_REPO" "$LATEST_TAG" "$LATEST_SHA" > third_party/FORKGRAM_PIN.json
git add third_party/FORKGRAM_PIN.json
git -c user.name='gozar-forkgram-update[bot]' \
    -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
    commit -m "chore(forkgram): propose upstream release $LATEST_TAG"
git push origin "HEAD:refs/heads/$BOT_BRANCH"
gh pr create --base "$BASE_BRANCH" --head "$BOT_BRANCH" \
  --title "Review Forkgram upstream release $LATEST_TAG" \
  --body "Source-only pin update to forkgram/TelegramAndroid@$LATEST_SHA (release $LATEST_TAG).

DO NOT AUTO-MERGE. Review upstream diff; rebuild the embedded host using our own API credentials; run Flutter, Android and native tests on a real device; verify VPN, login, messages, media, notifications and notes. No installed APK is changed by this pull request."

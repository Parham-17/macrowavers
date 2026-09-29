#!/usr/bin/env bash
# Creates the GitHub repository and applies the team's settings. One person runs this once.
#   scripts/github-setup.sh <owner>/<repo> [public|private]
# Needs: gh auth login (done), and both `main` and `develop` existing locally.
set -euo pipefail
cd "$(dirname "$0")/.."

full="${1:?usage: scripts/github-setup.sh <owner>/<repo> [public|private]}"
visibility="${2:-private}"
[[ "$visibility" =~ ^(public|private)$ ]] || { echo "visibility must be public or private"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Not logged in. Run: gh auth login"; exit 1; }

step() { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }

step "Repository $full ($visibility)"
if gh repo view "$full" >/dev/null 2>&1; then
  echo "Already exists, reusing."
else
  gh repo create "$full" "--$visibility" \
    --description "Macrowavers: a native visionOS game on the theme Sky and the Planets, built in 40 days (Arte-1 challenge)" \
    --disable-wiki --disable-issues
fi
# Use the protocol chosen in `gh auth login` (ssh or https).
if [ "$(gh config get git_protocol -h github.com 2>/dev/null)" = ssh ]; then
  url="git@github.com:$full.git"
else
  url="https://github.com/$full.git"
fi
git remote get-url origin >/dev/null 2>&1 || git remote add origin "$url"
echo "origin: $(git remote get-url origin)"

step "CI: macOS builds go to the self-hosted runner"
# Hosted macOS images have no Xcode 27 yet (docs/ci.md). Without this, the first push shows a failed build.
# Remove later with: gh variable delete CI_MACOS_RUNNER --repo <owner>/<repo>
gh variable set CI_MACOS_RUNNER --repo "$full" --body self-hosted
echo "ok"

step "Push main and develop"
git push -u origin main develop

step "Repository settings (default branch develop, squash titles from PR, auto-delete branches, Jira is the tracker)"
gh api -X PATCH "repos/$full" \
  -f default_branch=develop \
  -F delete_branch_on_merge=true \
  -F allow_squash_merge=true \
  -F allow_merge_commit=true \
  -F allow_rebase_merge=false \
  -f squash_merge_commit_title=PR_TITLE \
  -f squash_merge_commit_message=PR_BODY \
  -F allow_update_branch=true \
  -F has_issues=false -F has_projects=false -F has_wiki=false >/dev/null
echo "ok"

step "Rulesets (branch protection for develop, main and release tags)"
existing="$(gh api "repos/$full/rulesets" --jq '.[].name' 2>/dev/null || true)"
for f in scripts/rulesets/*.json; do
  name="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$f")"
  if grep -qxF "$name" <<<"$existing"; then
    echo "exists: $name"
  else
    gh api -X POST "repos/$full/rulesets" --input "$f" >/dev/null && echo "added:  $name"
  fi
done
if [ "$visibility" = private ]; then
  cat <<'NOTE'

NOTE: rulesets on a PRIVATE repository are only enforced on GitHub Pro, Team or Enterprise.
On a Free plan they are saved but inactive. Check: Settings -> Rules -> Rulesets.
Options: make the repo public, or upgrade the owner's plan.
NOTE
fi

step "Next steps"
cat <<NEXT
1. Invite the team:   gh api -X PUT repos/$full/collaborators/<github-user> -f permission=push   (repeat per person)
2. CI runner:         docs/ci.md  (builds wait for a self-hosted runner; register one Mac, about 10 minutes)
3. Jira link:         Jira -> Apps -> GitHub for Jira -> connect this repository, so AR126-nn keys link branches and PRs.
4. Open it:           gh repo view $full --web
NEXT

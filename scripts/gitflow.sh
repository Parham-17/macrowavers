#!/usr/bin/env bash
# GitFlow helpers used by the Makefile. Branch rules live in CONTRIBUTING.md; this only automates them.
#   gitflow.sh feature <AR126-12-slug>   branch from develop
#   gitflow.sh spike   <AR126-12-slug>   throwaway branch from develop
#   gitflow.sh release <x.y.z>           branch from develop, bump version, commit
#   gitflow.sh hotfix  <x.y.z>           branch from main, bump version, commit
#   gitflow.sh bump    <x.y.z>           only bump project.yml + CHANGELOG on the current branch
set -euo pipefail
cd "$(dirname "$0")/.."

JIRA_KEY="AR126"
cmd="${1:-}"; arg="${2:-}"

die() { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
note() { printf '\033[36m%s\033[0m\n' "$*"; }

require_clean() {
  git diff --quiet && git diff --cached --quiet || die "Commit or stash your changes first."
}

start_from() { # <base> <branch>
  local base="$1" branch="$2"
  require_clean
  git fetch origin --prune 2>/dev/null || note "(no origin yet, using local $base)"
  git switch "$base"
  git pull --ff-only 2>/dev/null || true
  git switch -c "$branch"
  note "On $branch (from $base)."
}

bump() { # <x.y.z>
  local v="$1"
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION must look like 0.2.0"
  local build; build="$(grep -E '^\s*CURRENT_PROJECT_VERSION:' project.yml | grep -oE '[0-9]+')"
  perl -pi -e "s/^(\s*MARKETING_VERSION:\s*)\"[^\"]*\"/\${1}\"$v\"/; s/^(\s*CURRENT_PROJECT_VERSION:\s*)\"[^\"]*\"/\${1}\"$((build + 1))\"/" project.yml
  local today; today="$(date +%Y-%m-%d)"
  if grep -q "^## \[$v\]" CHANGELOG.md; then
    note "CHANGELOG already has $v"
  else
    perl -0pi -e "s/^## \[Unreleased\]\n/## [Unreleased]\n\n## [$v] - $today\n/m" CHANGELOG.md
  fi
  note "project.yml -> $v (build $((build + 1))), CHANGELOG section [$v] added. Move the Unreleased notes under it."
}

case "$cmd" in
  feature|spike)
    [[ "$arg" =~ ^$JIRA_KEY-[0-9]+-[a-z0-9-]+$ ]] || die "NAME must look like $JIRA_KEY-12-orbit-gesture (Jira key, dash, lowercase slug)"
    start_from develop "$cmd/$arg"
    ;;
  release)
    [[ "$arg" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION must look like 0.2.0"
    start_from develop "release/$arg"
    bump "$arg"
    git add project.yml CHANGELOG.md
    git commit -q -m "chore(release): start $arg"
    note "Next: fix only, then open two PRs from release/$arg: into main (merge commit) and into develop."
    ;;
  hotfix)
    [[ "$arg" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION must look like 0.2.1"
    start_from main "hotfix/$arg"
    bump "$arg"
    git add project.yml CHANGELOG.md
    git commit -q -m "chore(hotfix): start $arg"
    note "Next: fix, then open two PRs from hotfix/$arg: into main (merge commit) and into develop."
    ;;
  bump)
    bump "$arg"
    ;;
  *)
    sed -n '2,8p' "$0"; exit 1
    ;;
esac

#!/usr/bin/env bash
# One-time setup for a fresh clone. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }

step "Homebrew tools (Brewfile)"
command -v brew >/dev/null || { echo "Homebrew is missing. Install it from https://brew.sh and re-run."; exit 1; }
brew bundle --file=Brewfile

step "Git LFS"
git lfs install            # global filters + hooks for this repo
git lfs pull || true       # fetch binary assets if any exist yet

step "Git hooks (commit message format, LFS guard, SwiftLint)"
chmod +x .githooks/* scripts/*.sh
hooks_dir="$(git rev-parse --git-path hooks)"
for hook in commit-msg pre-commit; do
  ln -sf "$(pwd)/.githooks/$hook" "$hooks_dir/$hook"
done

step "Git settings for this repository"
git config pull.rebase true          # keep feature branches linear when pulling
git config fetch.prune true          # drop remote branches deleted after merge
git config rerere.enabled true       # remember conflict resolutions
git config push.autoSetupRemote true # first `git push` needs no -u

step "Local Xcode config"
if [ ! -f Configs/Local.xcconfig ]; then
  cp Configs/Local.xcconfig.example Configs/Local.xcconfig
  echo "Created Configs/Local.xcconfig. Add your DEVELOPMENT_TEAM there for device builds."
fi

step "Xcode project"
xcodegen generate

printf '\n\033[32m✓ Ready.\033[0m  Next: make open   (or: make test)\n'

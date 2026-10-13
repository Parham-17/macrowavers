# Macrowavers

A native visionOS game for Apple Vision Pro on the theme "Sky and the Planets", built in 40 days by a team of five
for the Arte-1 challenge.

Stack: Swift 6, SwiftUI, RealityKit, Reality Composer Pro 3. Target: visionOS 27.

## Requirements

- macOS 26 or later, Xcode 27 with the visionOS 27 simulator runtime
- Reality Composer Pro 3 (separate beta download from Apple)
- Homebrew (for `brew bundle`: GitHub CLI, Git LFS, SwiftLint)
- Vision Pro in Developer Mode, paired in Xcode's Device Hub, for anything with hands, room sensing or comfort

## Quick start

```bash
git clone <repo-url> game && cd game
brew bundle                                   # gh, git-lfs, swiftlint
git lfs install && git lfs pull               # binary assets
git config core.hooksPath .githooks           # commit message, LFS and SwiftLint checks
git config pull.rebase true && git config fetch.prune true && git config push.autoSetupRemote true
cp Configs/Local.xcconfig.example Configs/Local.xcconfig   # then set DEVELOPMENT_TEAM for device builds
open Macrowavers.xcodeproj
```

Then: Cmd-U runs the unit tests on the simulator and `swiftlint lint --strict` runs SwiftLint like CI does.
New files under `Sources/` and `Tests/` join the targets automatically (synced folders, see `docs/decisions/0004`).

## How we work

The workflow is GitFlow with one release per sprint. **Read [CONTRIBUTING.md](CONTRIBUTING.md) before your first branch.**
In short:

```
main     ──●────────────────●─────────────●──   tagged v0.1.0, v0.2.0 ... v1.0.0 (one per sprint)
            \              /↑\           /↑
develop  ────●───●───●───●──●───●───●───●──●─   integration branch, PRs only
              \     /     \         /
feature/       ●───●       ●───●───●             feature/AR126-12-orbit-gesture, squash-merged
```

- Branch from `develop`: `git switch develop && git pull && git switch -c feature/AR126-12-orbit-gesture`
- Open a PR into `develop`. CI must be green and one teammate approves. Squash merge.
- Sprint end: `release/0.2.0` from `develop`, fix only, PR into `main` and `develop`, tag.
- Tracker: Jira project AR126. GitHub Issues are off on purpose.

## Layout

| Path | What |
|---|---|
| `Macrowavers.xcodeproj` | Committed Xcode project; `Sources/Macrowavers` and `Tests/` are synced folders |
| `Sources/Macrowavers/` | App code: `App/`, `Model/` (testable game rules), `Views/`, `Resources/` (`.reality` exports, asset catalogs) |
| `Tests/` | Unit tests (Swift Testing) |
| `RealityComposerPro/` | RCP 3 projects, one owner per scene at a time, stored in Git LFS |
| `Assets/` | Blender, texture and audio sources, stored in Git LFS |
| `Configs/` | `Local.xcconfig.example`: copy holds your signing team, gitignored |
| `.github/` | CI, release automation, PR template, CODEOWNERS, `rulesets/` (branch protection definitions) |
| `docs/` | `ci.md` (runner setup), `decisions/` (why we work this way), `features/` (one README per feature) |

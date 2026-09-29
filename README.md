# Sky and the Planets

A native visionOS game for Apple Vision Pro, built in 40 days by a team of five for the Arte-1 challenge.
Concept: to be chosen in the concept workshop; this README and `project.yml` get the real name then.

Stack: Swift 6, SwiftUI, RealityKit, Reality Composer Pro 3. Target: visionOS 27.

## Requirements

- macOS 26 or later, Xcode 27 with the visionOS 27 simulator runtime
- Reality Composer Pro 3 (separate beta download from Apple)
- Homebrew (the rest is installed by `make bootstrap`)
- Vision Pro in Developer Mode, paired in Xcode's Device Hub, for anything with hands, room sensing or comfort

## Quick start

```bash
git clone <repo-url> game && cd game
make bootstrap    # brew tools, Git LFS, git hooks, local config, generates the Xcode project
make open         # opens SkyAndPlanets.xcodeproj
```

Then: `make test` runs the unit tests on the simulator, `make lint` runs SwiftLint like CI does, `make` lists everything.

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

- Branch from `develop`: `make feature NAME=AR126-12-orbit-gesture`
- Open a PR into `develop`. CI must be green and one teammate approves. Squash merge.
- Sprint end: `make release VERSION=0.2.0`, fix only, PR into `main` and `develop`, tag.
- Tracker: Jira project AR126. GitHub Issues are off on purpose.

## Layout

| Path | What |
|---|---|
| `project.yml` | XcodeGen spec. The `.xcodeproj` is generated and never committed |
| `Sources/SkyAndPlanets/` | App code: `App/`, `Model/` (testable game rules), `Views/`, `Resources/` (`.reality` exports, asset catalogs) |
| `Tests/` | Unit tests (Swift Testing) |
| `RealityComposerPro/` | RCP 3 projects, one owner per scene at a time, stored in Git LFS |
| `Assets/` | Blender, texture and audio sources, stored in Git LFS |
| `Configs/` | `Local.xcconfig.example`: copy holds your signing team, gitignored |
| `scripts/`, `Makefile` | Bootstrap, GitFlow helpers, GitHub setup, rulesets |
| `.github/` | CI, release automation, PR template, CODEOWNERS |
| `docs/` | `ci.md` (runner setup), `decisions/` (why we work this way) |

## Renaming once the concept is chosen

1. In `project.yml`: `name`, target names, `CFBundleDisplayName`, `PRODUCT_BUNDLE_IDENTIFIER`.
2. Rename `Sources/SkyAndPlanets`, `Tests/SkyAndPlanetsTests` and the `@main` struct to match.
3. Update `PROJECT` and `SCHEME` in `Makefile` and `.github/workflows/ci.yml`.
4. `make generate`, `make test`, one PR: `chore: rename project to <Name>`.

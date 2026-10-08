# Macrowavers

A native visionOS game for Apple Vision Pro inspired by a Persian fairy tale, built in 40 days by a team of five
for the Arte-1 challenge.

Stack: Swift 6, SwiftUI, RealityKit, Reality Composer Pro 3. Target: visionOS 27.

## Features

### Untangle the Dragon

Branch `feature/AR126-100-untangle-dragon` · Jira AR126-100 · full docs in
[docs/features/untangle-dragon/README.md](docs/features/untangle-dragon/README.md)

A mixed-reality puzzle. The dragon of the tale lies on a floating platform in front of the player, its long body
tied in a knot. The player has to set it free:

- **Untangle it with your hands.** Pinch and drag any part of the body, even two parts at once (one per hand), and
  lift them to pass them over or under the rest. The part you look at glows; red pulsing spheres mark every
  crossing and the panel counts how many are left.
- **The dragon fights back.** If you stop making progress it warns you (it stares at you, growls, smoke rises
  from its nostrils), then it has a fit: it turns around, rears up and roars with a burst of fire, lashes its tail
  and coils. Every fit adds at least one new crossing, and fits come sooner each time.
- **Set it free.** At zero crossings the dragon turns gold, celebrates, then takes off and flies around the room
  on its own: it circles you, dives past you, hovers in front of you roaring and loops in the air.
- **Comfortable seated or standing.** The platform can be moved, raised, rotated and tilted.

Open it from the main window with **Untangle the Dragon**. It uses a placeholder dragon built in code until the
design team's asset (`DragonBody` / `DragonHead`) is added; the asset specification is in the feature docs.

## Requirements

- macOS 26 or later, Xcode 27 with the visionOS 27 simulator runtime
- Reality Composer Pro 3 (separate beta download from Apple)
- Homebrew (the rest is installed by `make bootstrap`)
- Vision Pro in Developer Mode, paired in Xcode's Device Hub, for anything with hands, room sensing or comfort

## Quick start

```bash
git clone <repo-url> game && cd game
make bootstrap    # brew tools, Git LFS, git hooks, local config, generates the Xcode project
make open         # opens Macrowavers.xcodeproj
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
| `Sources/Macrowavers/` | App code: `App/`, `Model/` (testable game rules), `Views/`, `Resources/` (`.reality` exports, asset catalogs) |
| `Tests/` | Unit tests (Swift Testing) |
| `RealityComposerPro/` | RCP 3 projects, one owner per scene at a time, stored in Git LFS |
| `Assets/` | Blender, texture and audio sources, stored in Git LFS |
| `Configs/` | `Local.xcconfig.example`: copy holds your signing team, gitignored |
| `scripts/`, `Makefile` | Bootstrap, GitFlow helpers, GitHub setup, rulesets |
| `.github/` | CI, release automation, PR template, CODEOWNERS |
| `docs/` | `ci.md` (runner setup), `decisions/` (why we work this way) |

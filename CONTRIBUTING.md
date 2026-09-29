# How we work

Five people, 40 days, one-week sprints, one Vision Pro each. This document is the contract that keeps `develop`
buildable every day and `main` shippable at every sprint end. Ask in the team chat if anything here is unclear,
then fix the document in a PR.

## 1. Branches

GitFlow with two long-lived branches and three kinds of short-lived ones.

| Branch | Lives | Comes from | Goes into | Merge style |
|---|---|---|---|---|
| `main` | Forever | | | Only `release/*` and `hotfix/*`, merge commit, tagged `vX.Y.Z` |
| `develop` | Forever | `main` at day 0 | | Default branch. PRs only |
| `feature/AR126-<n>-<slug>` | Days | `develop` | `develop` | Squash merge |
| `spike/AR126-<n>-<slug>` | Days | `develop` | Nowhere | Throwaway. Rename to `feature/` to keep it |
| `release/X.Y.Z` | 1 or 2 days | `develop` | `main` and `develop` | Merge commit |
| `hotfix/X.Y.Z` | Hours | `main` | `main` and `develop` | Merge commit |

Names are checked by CI. The Jira key (`AR126-12`) in the branch name is what links the branch, its commits and the
PR to the ticket once GitHub for Jira is connected. Slugs are lowercase with dashes: `feature/AR126-12-orbit-gesture`.

Never push directly to `main` or `develop`. The rulesets refuse it, and so should you.

## 2. A feature, start to finish

```bash
make feature NAME=AR126-12-orbit-gesture   # updates develop, creates the branch
# ...work, commit small, push often...
git push                                   # first push sets the upstream
gh pr create --base develop --fill         # or use the GitHub UI; the template asks the right questions
```

1. **Keep it small.** Aim for a PR a teammate can review in 15 minutes: under about 400 changed lines, one thing.
   Split big features into steps that each leave `develop` working (a flag or an unused type is fine).
2. **Rebase, don't merge, to catch up:** `git pull --rebase origin develop` on your branch. Bootstrap sets
   `pull.rebase` for you. Never rebase a branch someone else has checked out.
3. **Open the PR early** as a draft if you want eyes on the direction. Mark it ready when CI is green.
4. **Review within one working day.** One approval is required. Reviewers pull the branch and run it for anything
   visual or spatial; the simulator is fine unless the PR touches hands, world sensing, immersion or comfort, in which
   case the reviewer runs it on a headset.
5. **The author merges,** with "Squash and merge". The PR title becomes the commit on `develop`, so it follows the
   commit format below. The branch is deleted automatically.
6. Move the Jira ticket. Done means merged into `develop` and the checklist in the PR template ticked.

Spikes (Sprint 1 research, "does hand tracking feel OK for this?") are `spike/` branches. They can be messy, they
are never merged, and their findings go into the Jira ticket or a doc, not into `develop`.

## 3. Commits

[Conventional Commits](https://www.conventionalcommits.org): `type(scope): summary`, summary in the imperative,
under 72 characters. The `commit-msg` hook checks this locally and CI checks PR titles.

| Type | Use for |
|---|---|
| `feat` | Something the player can notice |
| `fix` | A bug fix |
| `perf` | Frame time, memory, load time |
| `refactor` | Code change with no behaviour change |
| `test`, `docs`, `style`, `build`, `ci`, `chore` | The usual |

Scopes are free-form but keep them consistent: `orbit`, `input`, `scene`, `audio`, `ui`, `rcp`, `assets`.
Examples: `feat(orbit): snap released moons to a stable orbit`, `fix(input): ignore pinches while paused`,
`perf(scene): share planet materials`, `chore(rcp): re-export solar_system.reality`.

Commit messages describe the change; the PR describes the why and how to test.

## 4. Releases: one per sprint

Sprints end on Thursdays. Sprint 1 is research; the first release is the end of Sprint 2.

| Sprint end | Version | Meaning |
|---|---|---|
| Sprint 2 | `v0.1.0` | First playable loop |
| Sprint 3 | `v0.2.0` | |
| Sprint 4 | `v0.3.0` | |
| Sprint 5 | `v0.4.0` | Feature and content complete |
| Sprint 6 | `v1.0.0` | Release. Fixes only during this sprint |

Release captain rotates each sprint. On the last sprint day:

```bash
make release VERSION=0.2.0        # branch from develop, bumps project.yml, opens a CHANGELOG section, commits
git push
```

1. Move the `Unreleased` notes in `CHANGELOG.md` under the new version. Only bug fixes land on the release branch,
   as normal PRs into `release/0.2.0`. Features keep flowing into `develop` in the meantime.
2. Build the release branch on every headset. The sprint review demo runs from this build.
3. Open two PRs from `release/0.2.0`: into `main` (use "Create a merge commit") and into `develop`.
   Merge `main` first.
4. Tag `main`: `git switch main && git pull && git tag -a v0.2.0 -m "Sprint 2" && git push origin v0.2.0`.
   The Release workflow turns the tag into a GitHub Release with the changelog notes.
5. Delete the release branch. Hand the captain role to the next person.

**Hotfix**: something on `main` is broken and the demo is tomorrow. `make hotfix VERSION=0.2.1`, fix, two PRs
(into `main` and `develop`), tag `v0.2.1`.

## 5. The Xcode project is generated

`project.yml` is the source of truth. The `.xcodeproj` is generated by XcodeGen, gitignored, and refused by the
`pre-commit` hook. This removes the most common merge conflict on iOS teams. Consequences:

- Adding a file: just add it under `Sources/` or `Tests/`, Xcode shows it after `make generate` (or run
  `xcodegen generate` from the Xcode project's folder; keep a terminal tab open for it).
- New target, build setting, capability, framework, package: edit `project.yml`, run `make generate`, commit
  `project.yml`.
- Signing team: in `Configs/Local.xcconfig` (created by bootstrap, gitignored). Never in `project.yml`.
- After `git pull`, if Xcode looks stale, run `make generate`.

## 6. Assets, Git LFS and Reality Composer Pro

Every binary format in `.gitattributes` is stored in Git LFS. The `pre-commit` hook blocks files over 5 MB that
are not. Clone size stays small and history stays fast.

- Keep single files under 25 MB. Textures at 2K by default. Ask before adding a 4K texture or a long audio file.
- Sources go in `Assets/` (Blender, PSD, WAV). Exports the app loads go in `Sources/SkyAndPlanets/Resources/`.
- **RCP 3 projects cannot be merged.** The bundle holds an opaque store. The rule is one owner per scene at a
  time: write "editing SolarSystem scene" on the Jira ticket or in chat before you open it, commit and push in
  your own PR when done, then release it. If two people need the same scene, split it into two scenes.
- RCP 3 remembers the Xcode project by absolute path. Re-link on your own Mac; never commit link files.
- Default hand-off from RCP to Xcode is exporting `.reality` files into `Resources/`. If the team prefers the
  "linked project" route, first check what RCP writes into the `.xcodeproj` and mirror it in `project.yml`,
  because the generated project is thrown away on every `make generate`.
- Designers commit too. `make bootstrap` sets everything up, and the PR template applies to art PRs as well.

## 7. Definition of done

A PR can be merged when:

- CI is green: SwiftLint strict, build and unit tests on the visionOS simulator, title and branch name checks.
- One approval, all review threads resolved.
- Ran on a headset if it touches hands, world sensing, immersive spaces, or anything that could cause discomfort.
- No new warnings. Frame time still 90 fps on device for anything in the render loop (RealityKit Trace).
- Game rules under `Model/` have unit tests. Views and RealityKit code are tested by running them.
- `CHANGELOG.md` has a line under `Unreleased` for anything a player or the team would notice.

## 8. Everyday commands

| Command | What |
|---|---|
| `make bootstrap` | Once per machine |
| `make open` | Regenerate the project and open Xcode |
| `make test`, `make lint`, `make lint-fix` | What CI runs |
| `make feature NAME=AR126-12-slug` | New feature branch from a fresh `develop` |
| `make spike NAME=AR126-27-slug` | New throwaway branch |
| `make release VERSION=0.2.0` | Cut the sprint release |
| `make hotfix VERSION=0.2.1` | Fix on `main` |
| `gh pr create --base develop --fill` | Open a PR from the terminal |
| `gh pr checkout 42` | Review a teammate's PR locally |

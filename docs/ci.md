# CI

`.github/workflows/ci.yml` runs on every PR into `develop`, `main`, `release/*`, `hotfix/*` and on every push to
`develop` and `main`:

| Job | Runner | What |
|---|---|---|
| PR title | ubuntu | Conventional Commits format |
| Branch name | ubuntu | GitFlow naming, spikes cannot merge, only release/hotfix into main |
| Lint | ubuntu (SwiftLint container) | `swiftlint lint --strict` |
| Build and test | macOS | XcodeGen, `xcodebuild test` on the visionOS simulator |

`.github/workflows/release.yml` turns a `vX.Y.Z` tag into a GitHub Release with that version's CHANGELOG section.

## The macOS runner problem (as of 2026-09-29)

GitHub's hosted `macos-26` image ships Xcode 26.6 and visionOS simulators up to 26.5. It cannot build a project
targeting visionOS 27. Until the image adds Xcode 27, the build job runs on a **self-hosted runner** on one of the
team's Macs. Check the image status at
https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md.

Hosted minutes, for later: macOS minutes count 10x. GitHub Free gives 2,000 minutes per month on private repos,
so about 200 macOS minutes, roughly 20 to 40 builds. Public repositories get unlimited minutes.

## Self-hosted runner setup (about 10 minutes, one Mac)

Pick a Mac that stays on and plugged in during work hours. Xcode 27, the visionOS 27 simulator runtime and Homebrew
must be installed. `xcodegen` and `git-lfs` should be installed too (`brew install xcodegen git-lfs`).

1. GitHub: repository **Settings → Actions → Runners → New self-hosted runner**, choose macOS / ARM64.
2. Run the shown commands in a terminal: download, `./config.sh --url ... --token ...` (accept the default labels
   `self-hosted, macOS, ARM64`), then install it as a service so it survives reboots:
   ```bash
   ./svc.sh install && ./svc.sh start
   ```
3. Keep the Mac awake: System Settings → Energy → prevent sleeping when the display is off, or run
   `caffeinate -s` in a terminal during work hours.
4. CI already points at it: `scripts/github-setup.sh` sets the repository variable `CI_MACOS_RUNNER=self-hosted`.
   Until a runner is registered, the **Build and test** job waits in the queue, and PRs cannot merge.
5. Open a test PR and watch **Build and test** run on the machine.

To go back to hosted runners once they have Xcode 27: `gh variable delete CI_MACOS_RUNNER`.

Notes:
- Only trusted people can open PRs on this repository, which is what makes a self-hosted runner acceptable.
  GitHub advises against self-hosted runners on public repositories that accept PRs from forks.
- The runner builds in its own working folder; it does not touch the developer's checkout on that Mac.
- If the Mac is also someone's dev machine, builds slow it down for a minute or two. Fine for a team of five.

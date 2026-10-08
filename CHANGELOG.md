# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com)
and versions follow [Semantic Versioning](https://semver.org). One release per sprint; see CONTRIBUTING.md.

## [Unreleased]

### Added
- Repository with GitFlow workflow, CI, Git LFS, XcodeGen project and an empty visionOS 27 app skeleton.

### Changed
- The Xcode project is committed with synced folders; removed XcodeGen (`project.yml`), the `Makefile` and
  `scripts/`. Ruleset definitions moved to `.github/rulesets/`.
- Renamed the project from the placeholder SkyAndPlanets to Macrowavers (app, targets, bundle ID com.arte1.macrowavers).

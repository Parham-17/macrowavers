# 4. The Xcode project is committed and uses synced folders

Date: 2026-10-08. Status: accepted. Supersedes [0002](0002-xcodegen.md).

## Context

XcodeGen (decision 0002) avoided `.pbxproj` merge conflicts, but it added tooling every machine needed
(`project.yml`, `make generate`, a `Makefile` and bootstrap scripts) and every pull meant regenerating the project.
Since Xcode 16, a target can reference a **synced folder** (`PBXFileSystemSynchronizedRootGroup`): every file under
the folder belongs to the target automatically and adding a file does not touch `project.pbxproj`.

## Decision

`Macrowavers.xcodeproj` is committed. `Sources/Macrowavers` and `Tests/MacrowaversTests` are synced folders.
`project.yml`, the `Makefile` and `scripts/` are removed; the GitHub ruleset definitions moved to
`.github/rulesets/`. Per-developer settings stay in the gitignored `Configs/Local.xcconfig`.

## Consequences

- Adding, moving or deleting files under `Sources/` or `Tests/` needs no project edit, so feature branches do not
  conflict on the project file.
- Changing targets, build settings or capabilities is done in Xcode and shows up as a `project.pbxproj` diff;
  keep those changes in their own small PR.
- Tools that write into the `.xcodeproj` (Reality Composer Pro 3's linked-project mode) now keep their edits.
- No extra tool on CI or on developer Macs besides Xcode, SwiftLint and Git LFS.
- Per-user Xcode state (`xcuserdata/`, `*.xcuserstate`) stays gitignored and is refused by the pre-commit hook.

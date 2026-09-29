# 3. Binary assets live in Git LFS

Date: 2026-09-29. Status: accepted.

## Context

A game repository fills up with USDZ, `.reality`, Blender, texture and audio files. Reality Composer Pro 3 keeps
its project state in an opaque store inside a bundle. Plain Git stores every version of every binary forever, so
clones and fetches slow down within weeks.

## Decision

All binary formats listed in `.gitattributes` go through Git LFS, including RCP 3 bundles. The pre-commit hook
blocks non-LFS files above 5 MB. RCP scenes have a single owner at a time because they cannot be merged.

## Consequences

- Clones stay small; history stays fast.
- Every machine, including CI, needs `git lfs install` (done by bootstrap). CI caches LFS objects to save
  bandwidth.
- LFS quota on GitHub Free is 10 GiB storage and 10 GiB bandwidth per month per account, metered beyond that
  (checked 2026-09-29). Keep files small and re-export sparingly.

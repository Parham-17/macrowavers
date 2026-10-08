# 1. GitFlow with one release per sprint

Date: 2026-09-29. Status: accepted.

## Context

Five people (three developers, two designers) build a visionOS game in 40 days with one-week sprints. Each sprint
ends in a review demo on real headsets. Work needs to integrate daily without breaking the demo build, and the
team wants a workflow that reads as professional to mentors and reviewers.

## Decision

GitFlow, kept lean: `main` (tagged releases), `develop` (integration, default branch), `feature/*` squash-merged
through reviewed PRs, `release/*` cut at each sprint end, `hotfix/*` from `main`. `spike/*` branches for research
that is never merged. Branch names carry the Jira key. Conventional Commits, enforced by a hook and CI.

## Consequences

- `main` always holds the last demo build; `develop` is what the next demo will be. Release branches let fixes
  land for the review while features keep flowing.
- Two long-lived branches cost a back-merge per sprint. CONTRIBUTING.md makes it a checklist.
- Trunk-based development would be lighter. We chose GitFlow because sprint reviews are fixed dates with real
  builds, and the release branch gives the team a calm day before each one. If the process gets in the way, the
  fallback is dropping release branches and tagging `develop` directly.

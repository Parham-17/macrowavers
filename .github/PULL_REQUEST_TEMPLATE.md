<!-- Title = squash commit on develop. Format: type(scope): summary   e.g. feat(orbit): snap moons to a stable orbit -->

## What

<!-- One or two sentences. What changes for the player or the team? -->

## Why

Jira: AR126-

## How to test

<!-- Steps a teammate can follow. Say if the headset is required. -->

## Evidence

<!-- Screenshot or a 10-second screen recording for anything visual. Frame-time numbers for anything in the render loop. -->

## Checklist

- [ ] Ran on the simulator
- [ ] Ran on a Vision Pro (required for hands, world sensing, immersion and comfort changes)
- [ ] `swiftlint lint --strict` and the unit tests (Cmd-U) pass locally
- [ ] Project changes (targets, settings, capabilities) are intended; no `xcuserdata` committed
- [ ] New binary assets show up in `git lfs ls-files`
- [ ] RCP scene edits: I was the scene's owner and said so in the ticket

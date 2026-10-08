# Untangle the Dragon (AR126-100)

A mixed-reality mini-game: a dragon lies on a floating platform in front of the player with its body tied
in a knot. The player grabs the body with their hands and untangles it. Once free, the dragon takes off and
flies around the room.

Branch: `feature/AR126-100-untangle-dragon`. Status: playable with a code-generated placeholder dragon,
waiting for the design team's asset.

## How to try it

1. Generate the project as usual (`make generate` or `xcodegen generate`) and run on the visionOS simulator
   or on a Vision Pro.
2. In the main window tap **Untangle the Dragon**: a control panel opens.
3. Tap **Start**: an `ImmersiveSpace` in `.mixed` style opens, with the platform and the dragon in front of you.
4. Pinch and drag the dragon's body (one part per hand), lift parts to pass them over or under the others.

Two-handed grabbing and the dragon looking at you need a real device; the simulator only does one hand and
uses a seated eye height of 1.15 m.

## What the player sees

| Moment | Behaviour |
|---|---|
| Start | Dragon tied in a trefoil knot (3 crossings), red pulsing spheres on every crossing, crossings left in the panel |
| Grab | The part you look at glows; pinch to grab, up to two parts at once; the dragon turns to your hand and growls if pulled hard |
| No progress (8 s, shorter each time, min 5 s) | 2 s warning: it stares at you, smoke from the nostrils, red eyes. Then a fit: it **turns around**, rears up and roars with a burst of fire, lashes its tail and coils, **always adding at least one new crossing** |
| Solved (0 crossings, body released for 0.6 s) | Turns gold, celebrates for 1.5 s, then **takes off and flies around the room**: circles, dives past you, hovers in front of you roaring, loops |
| Platform | Drag it (or its handle) to move it, also in height; rotate it with two hands or the panel buttons; tilt it with the slider. Default is tuned for a seated player |

All user-facing text is in English. Code comments are in Italian.

## Code layout

```
Sources/Macrowavers/
├── App/MacrowaversApp.swift          + control panel window and the ImmersiveSpace (.mixed)
├── Views/ContentView.swift           + "Untangle the Dragon" button
├── Model/Untangle/                   Pure game logic: Foundation + simd only, unit-tested
│   ├── TangleSimulation.swift          Rope physics of the body (PBD/Verlet) and crossing count
│   ├── TangleShapes.swift              Initial knots from parametric curves (trefoil, figure-eight)
│   ├── DragonBehavior.swift            Difficulty: idle timer → fit (choreography of DragonAction), DragonMood
│   ├── DragonFlight.swift              Free flight after the win (manoeuvres + "follow the leader" body)
│   ├── PlayAreaPlacement.swift         Platform position, rotation, tilt
│   └── UntangleViewModel.swift         @Observable @MainActor view model shared by panel and immersive space
└── Views/Untangle/
    ├── ControlPanelView.swift          Panel: state, Start/Close, platform controls
    ├── DragonImmersiveView.swift       RealityView, grab events, platform gestures
    └── RealityKit/                     Draws, never decides
        ├── DragonScene.swift             Components, System, scene building, grabbable colliders, crossing markers
        ├── DragonRig.swift               DragonRig protocol, DragonFrame, DragonPose, DragonLifeAnimator
        ├── DragonEffects.swift           Smoke, fire, optional spatial audio, placeholder wings
        ├── ViewerTracker.swift           Player head position (ARKit world tracking, no permission needed)
        ├── ProceduralDragonRig.swift     Placeholder dragon built from primitives
        └── SkeletalDragonRig.swift       Rig for the real asset, picked automatically when it is in the bundle
Tests/MacrowaversTests/UntangleTests.swift
```

MVVM: the Model does not import SwiftUI or RealityKit; the view model does not import RealityKit;
SwiftUI views and the RealityKit layer only read state and forward user actions.

### One frame

`DragonBodySystem.update` (RealityKit, every frame):
1. reads where the hands moved the grabbed colliders and passes them to the view model as targets;
2. `viewModel.update(...)` runs the dragon's behaviour, the physics step, crossings, mood, win and flight;
3. moves the other colliders to the simulated (or flying) positions;
4. `rig.update(DragonFrame)` draws the dragon; `CrossingMarkers` moves the red spheres.

Grab start/end comes from `ManipulationEvents.WillBegin/WillRelease/WillEnd`, subscribed in `DragonImmersiveView`.

## Design decisions (and why)

- **The body is a custom rope simulation, not RealityKit physics.** 48 nodes 5 cm apart, 3 cm radius;
  distance, bending, self-collision and friction constraints at a fixed 60 Hz with sub-steps. We need exact
  control over what is over/under and no interpenetration; long jointed rigid-body chains are unstable.
  The simulation is deterministic and testable without a headset.
- **Friction, anchored head and a tension limit.** Without friction the knot slipped loose by itself; with
  both ends free a single pull solved the puzzle; without a tension limit a taut body tunnels through itself.
- **Win = zero crossings seen from above.** Segments are projected on the platform plane and intersections
  are counted. Simple, robust and it matches what the player sees.
- **`ManipulationComponent` for grabbing (visionOS 26+).** A SwiftUI `DragGesture` handles one interaction at
  a time; `ManipulationComponent` gives one grab per hand, so the player can hold a loop up with one hand and
  thread the tail under it with the other.
- **Colliders are separate from the visuals.** One invisible collider per node handles input; the visuals are
  a swappable `DragonRig`. When the asset arrives only the rig changes, not the game.
- **Hover highlights the part you look at.** visionOS highlights the children of the looked-at entity, so the
  placeholder rig parents each body segment to its collider.
- **"Alive" animations are visual only** (`DragonLifeAnimator`): breathing, neck, gaze, jaw, wings, smoke,
  fire. They never touch the simulation, so the puzzle stays fair.
- **Fits always add a crossing.** Tail lash and coil aim at a reachable body segment and land just past it;
  after the fit the crossings are compared with the start and the dragon retries (up to 8 times). The turn is
  a rigid rotation: spectacular, but it does not change the puzzle. In headless runs 39–40 fits out of 41 added
  crossings; the rest were already very dense knots.
- **Flight uses "follow the leader".** The head flies to a target that depends on the manoeuvre; each vertebra
  sits on the head's trail at a fixed distance, so the body snakes exactly along the path like an eastern
  dragon. Comfort: never closer than 0.7 m to the player's head, 0.9–2.1 m altitude, within ~2 m horizontally.

## Asset specification (for the design team)

`SkeletalDragonRig` is used automatically when `DragonBody` is in the app bundle (put exports under
`Sources/Macrowavers/Resources/`); otherwise the placeholder is used.

**`DragonBody`** (required; USDZ or Reality Composer Pro scene)
- One skinned mesh: neck + body + tail.
- Bone chain `spine_00` (neck, near the head) … `spine_NN` (tail tip), each child of the previous one,
  names sortable alphabetically (two digits). 24–48 bones, straight rest pose, equal bone lengths.
- **No animation on the spine bones**: code drives them every frame.
- Any scale: code scales the asset so the spine matches the simulated body (~2.35 m). Body thickness about
  1/30 of its length.
- Wings (recommended): joints `wing_L` and `wing_R`, children of a shoulder vertebra (~10% down the spine),
  **folded** in the rest pose. Code opens them around their local Z axis (`SkeletalDragonRig.Asset.wingFlareAxis`).

**`DragonHead`** (recommended)
- Separate head so its animations never fight the spine. Origin at the neck joint, snout towards **+Z**.
- Named animations (Reality Composer Pro Animation Library or named USD clips).
  Looping, per mood: `idle`, `annoyed`, `restless`, `wriggle`, `happy`.
  One-shot, per move: `roar` (~1.6 s, mouth wide open between 35% and 75%), `turn`, `lash`, `coil`.
  Missing clips fall back to `idle`.
- Two empty child entities: `nostrils` (smoke) and `mouth` (fire, pointing +Z).

**Sounds** (optional; wav/m4a/mp3/caf in the bundle): `DragonGrowl`, `DragonRoar`, `DragonRumble`,
`DragonWhoosh`. Played as spatial audio from the head.

**General**: PBR materials (they pick up the real room light), moderate polygon count (passthrough is on).
Per-part hover on a single skinned mesh needs a ShaderGraph material using the hover input.

`SkeletalDragonRig` compiles but has never run against a real asset: validate with a first test export
(even a tube with 20 bones).

## Tuning

| Where | Parameter | Effect |
|---|---|---|
| `TangleConfig` | `selfFriction` | higher = harder knot |
| `TangleConfig` | `anchorHead` | `false` = much easier |
| `TangleConfig` | `maxTension` | lower = fewer glitches when pulling hard, softer grab |
| `TangleShape` | `.trefoil` / `.figureEight` | starting knot (3 / 4 crossings) |
| `DifficultySettings` | delays, `maxExtraTangles` | how often and how hard the dragon fights back |
| `DragonFlight.Settings` | `speed`, `orbitRadius`, `altitude`, `personalSpace` | flight feel and room size |
| `PlayAreaPlacement.seated` | default placement | comfort for a seated player |

## Tests

`Tests/MacrowaversTests/UntangleTests.swift` (Swift Testing) covers the Model and the view model: initial
crossings, the knot not untying by itself, rigid turns keeping crossings, the anchored head, two-handed grabs,
the fit starting with a turn after the delay, the dragon waiting while held, flight keeping its distance from
the player, platform clamping and reset.

## Known limits

- Pulling very hard can make one part clip through another for a moment (see `maxTension`).
- The direction of the two-handed platform rotation is not verified on device (flip the sign in
  `DragonImmersiveView.rotateGesture` if needed).
- While rearing up the neck is raised only visually; colliders stay on the platform for ~1 s.
- Smoke and fire sizes are eyeballed and need tuning on device.
- Flight does not know the real walls: in small rooms reduce `DragonFlight.Settings.orbitRadius`
  (or use `SceneReconstructionProvider` later).

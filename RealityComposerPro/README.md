# Reality Composer Pro 3 projects

Source projects for scenes, materials, particles and Script Graphs live here, one RCP 3 project per scene family.

Rules (details in `../CONTRIBUTING.md`):

- RCP 3 stores project state in an opaque store inside the `.realitycomposerpro` bundle. Git cannot merge it.
  **One owner per scene at a time.** Say in the Jira ticket who holds a scene before you open it for edits.
- The bundle is tracked by Git LFS (see `../.gitattributes`). Commit RCP changes in their own PR.
- RCP 3 stores the link to the Xcode project as an absolute path. Every teammate re-links on their own Mac; never commit link files.
- Exports the app loads (`.reality`) go to `Sources/Macrowavers/Resources/`, which XcodeGen adds to the app bundle.
- Blender sources (`.blend`) stay in `Assets/Blender/`; export USDZ from Blender into the RCP project.

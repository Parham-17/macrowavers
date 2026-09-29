# Source assets

Working files that are not loaded by the app directly. Everything here is stored in Git LFS.

| Folder | What | Naming |
|---|---|---|
| `Blender/` | `.blend` sources | `planet_mars.blend`, `ship_v2.blend` (snake_case, versions as a suffix) |
| `Textures/` | Source textures, HDRIs | `mars_albedo_2k.png`, `space_hdri_4k.exr` |
| `Audio/` | Source audio before conversion | `impact_soft.wav` |

Guidelines: keep single files under 25 MB, textures at 2K unless a close-up needs 4K, and share materials between
entities. Many unique materials and large textures are the most common frame-rate killers on Vision Pro.

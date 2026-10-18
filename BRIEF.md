# Frame Demo — team brief

A 20-second, non-interactive, 3DMark / NVIDIA-ATI tech-demo style realtime showcase (think 2004–2007:
"Nalu", "Luna", "Ruby: The Assassin", 3DMark06 "Canyon Flight"/"Deep Freeze") — but the bar is
**photorealism**: every shot must look plausible enough that the eye accepts it as real. Eye candy yes,
gimmicks no. Setting can be any era.

Target: Godot 4.7.2 (`godot` on PATH), **Forward+ renderer on Android (Vulkan)**, Valve **Steam Frame**
(Snapdragon 8 Gen 3 / Adreno 750, runs sideloaded Android APKs; shown as a flat window, not VR).
Develop/verify on desktop (Radeon RX 9070), but budget for mobile: modest draw calls, no SDFGI,
no LightmapGI/VoxelGI baking (needs editor GUI) — prefer ReflectionProbes (update_mode once), SSAO,
SSIL sparingly, volumetric fog OK at low density settings, 2k textures max, CC0 assets only.

## Timeline (director/director.gd)
| time        | shot                     | dir                 |
|-------------|--------------------------|---------------------|
| 0.0 – 7.0   | Coast at dawn            | shots/coast/        |
| 7.0 – 13.5  | Macro still life         | shots/macro/        |
| 13.5 – 20.0 | Cathedral light shafts   | shots/cathedral/    |
Titles/post/transitions/audio are layered on top by the director.

## Shot contract
- Root of `shots/<name>/<name>.tscn` is a Node3D with a script that `extends DemoShot` (shared/demo_shot.gd).
- Set `duration` and `camera` exports. Own your WorldEnvironment + lights inside your scene.
- Animate ONLY in `update_shot(t, u)`, deterministically from t (no accumulated state) — shaders
  may use TIME. Camera moves should be slow, smooth, cinematic (ease in/out, slight handheld noise ok).
- The scene must run standalone: `godot --path . res://shots/coast/coast.tscn`.

## Ownership — touch only your own files
- coast agent: shots/coast/**, assets/coast/**
- macro agent: shots/macro/**, assets/macro/**
- cathedral agent: shots/cathedral/**, assets/cathedral/**
- director agent: director/**, post/**, assets/director/**
- platform agent: project.godot, export_presets.cfg, tools/**, shared/** , android/**, README.md
Need a project setting changed? Write it in NOTES-<yourname>.md at repo root; platform agent applies.

## Assets
Poly Haven (CC0) is reachable: https://api.polyhaven.com (assets?t=hdris|textures|models, files/<id>).
Download to your assets/<name>/ dir; prefer 1k–2k JPG/PNG maps and glTF models. Keep total per shot
under ~40 MB. Record sources in assets/<name>/CREDITS.md. Procedural shaders are fine too.

## Verify visually (mandatory)
`tools/render_frames.sh res://shots/<name>/<name>.tscn <outdir> [fps] [seconds]` renders a PNG
sequence (always 1920x1080) via Movie Maker. Put output in your scratchpad dir, then LOOK at several frames
with the Read tool and iterate until it is convincing. Before rendering after adding assets run
`godot --headless --path . --import` (other agents may be importing concurrently — retry if it errors).
Check the output log for script/shader errors.

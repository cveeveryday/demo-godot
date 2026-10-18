# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A 20-second, non-interactive realtime "tech demo" (coast at dawn → macro still life → cathedral light shafts) in **Godot 4.7.2, Forward+ / Vulkan**. Its purpose is to show the most eye candy Claude can get out of Godot on the **Valve Steam Frame VR headset** (Snapdragon 8 Gen 3 / Adreno 750). Claude agents built the whole thing, one agent per area (see Ownership below). The goal is photorealism on a mobile GPU budget.

It runs on the headset as a sideloaded Android APK. Lepton shows it as a **flat window inside the headset**. **The project stays flat 3D by decision.** Don't add OpenXR, stereo rendering or head tracking. Keep `xr_features/xr_mode=0` and the non-Gradle template, and keep the scripted cinematic cameras and the 2D post/title stack.

`BRIEF.md` is the team brief and shot contract. `README.md` has the platform and Steam Frame details. Read both before you make non-trivial changes.

## Commands

```bash
godot --path .                                      # full demo (director/main.tscn)
godot --path . res://shots/coast/coast.tscn         # one shot standalone (it quits itself after duration+0.5s)
godot --path . -- --quality=med                     # preview the Android quality tier on desktop
godot --path . -- --perf --loop                     # director perf overlay / loop forever
godot --headless --path . --import                  # (re)import assets; retry if it errors (concurrent imports)

# Visual verification: PNG sequence via Movie Maker
tools/render_frames.sh <scene> <outdir> [fps=4] [seconds=7] [WxH=1280x720]
#   e.g. tools/render_frames.sh res://shots/macro/macro.tscn $SCRATCH/macro 4 6.5 1920x1080

tools/build_apk.sh [debug|release] [out.apk]        # -> build/framedemo.apk (imports first)
tools/install.sh [apk] [--quality=low]              # adb install -r + launch (FRAME_HOST=frame for Wi-Fi adb connect)
adb logcat -s godot                                 # check the "Quality: tier=… renderer=…" startup line

python3 tools/fix_texture_imports.py [--apply] [assets/<dir>]   # set VRAM compression + mipmaps on 3D textures
python3 director/tools/gen_score.py [out.wav]       # regenerate assets/director/score.wav (stdlib only)
python3 shots/coast/tools/gen_tscn.py [sun_az] [sun_elev]       # regenerates shots/coast/coast.tscn
```

There is no test suite or linter. To verify, render frames, **look at them** with the Read tool, and check the log for script and shader errors. The brief makes this step mandatory for visual work. Put render output in the scratchpad, not the repo.

## Architecture

- **`director/director.gd`** (root of `director/main.tscn`) owns the timeline. The `SHOTS` constant holds each shot's scene, its start/end times and its incoming transition (`dissolve` uses a frozen readback of the outgoing frame; `dip` goes through black). The director:
  - preloads all shots, using threaded loading in realtime runs and synchronous loading under `--fixed-fps` / `--write-movie`.
  - runs a warm-up pass: each shot sits in the tree for about 12 black frames so pipelines and probes are ready before its cut.
  - drives the current shot through `DemoShot.drive(t)`.
  - stacks CanvasLayers on top: film post (`post/film.gdshader`: grain, vignette, CA, halation, 2.39:1 letterbox, `fade` uniform) at 50, freeze frame at 60, titles (`director/titles.gd`) at 70, perf overlay at 100.
  - keeps audio locked to `t`.
  - falls back to `director/test/test_shot.tscn` (a placeholder with a `variant`) when a shot is missing or invalid.
- **Determinism is a hard rule.** Under Movie Maker, time is `frame_index / fps`. Shots animate only inside `update_shot(t, u)` and compute everything from `t`, with no accumulated state (shaders may use `TIME`). Titles are also a pure function of `t`, with no tweens. Offline mode is detected from `Engine.get_write_movie_path()` or `/proc/self/cmdline`, because engine args don't appear in `OS.get_cmdline_args()`.
- **Shot contract** (`shared/demo_shot.gd`, `class_name DemoShot`):
  - The root of `shots/<name>/<name>.tscn` is a Node3D whose script extends `DemoShot`. It sets the `duration` and `camera` exports.
  - The scene owns its own WorldEnvironment and lights. One-time procedural work goes in `setup()`.
  - When the scene is the current scene, it drives itself.
  - How each shot is built:
    - `coast.tscn` is **generated** by `shots/coast/tools/gen_tscn.py`. Edit the generator, then rerun it. Don't edit the `.tscn` by hand.
    - `cathedral` builds almost everything procedurally in `cathedral.gd`.
    - `macro` is a hand-authored scene with a MultiMesh dust shader driven by a `shot_t` uniform.
- **Quality tiers** (`shared/quality.gd`, autoload `Quality`): low/med/high. Android, `mobile` and `steam_frame` default to med; everything else defaults to high. Override with `--quality=` or `FRAMEDEMO_QUALITY`. The autoload sets *global* RenderingServer and viewport knobs: scale/FSR1+TAA, shadow atlases, SSAO/SSIL/SSR/fog/SSS quality, aniso and LOD. `project.godot` repeats these values as `.mobile`/`.android` overrides so the first frame already uses them. Shots keep per-Environment toggles (enable SSAO, fog density, etc.) but must not touch global quality knobs.
- **Forward+ on Android**: the exporter refuses `rendering_method.mobile=forward_plus`. The preset therefore passes `--rendering-method forward_plus` in `command_line/extra_args`, and `rendering_method.android` is also set. Keep both as they are.

## Ownership and conventions (from BRIEF.md)

The project is split across agents, and each one edits only its own files:
- shots: `shots/<name>/**` and `assets/<name>/**`
- director: `director/**`, `post/**`, `assets/director/**`
- platform: `project.godot`, `export_presets.cfg`, `tools/**`, `shared/**`, `android/**`, `README.md`

To request a change in another agent's area, write it in `NOTES-<yourname>.md` at the repo root. Open requests already live in `NOTES-*.md`. Example: macro asks for circle bokeh, high quality and jitter for DOF, and currently applies these only when run standalone.

Constraints:
- **Not allowed:** SDFGI, VoxelGI, LightmapGI, physical light units.
- **Use instead:** ReflectionProbes (update once), SSAO, sparing SSIL, low-density volumetric fog.
- **Textures:** 2k max. Run `fix_texture_imports.py` on new textures, because headless import leaves them Lossless with no mipmaps.
- **Assets:** CC0 only (Poly Haven API). Record each source in `assets/<name>/CREDITS.md`. Keep each shot under about 40 MB and the APK under about 150 MB.
- **Camera:** slow, smooth, eased moves.
- **Layout:** authored for a 1920×1080 canvas (`canvas_items` stretch).

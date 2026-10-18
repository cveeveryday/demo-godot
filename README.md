# Frame Demo 2026

A 20-second, non-interactive realtime realism demo (coast at dawn → macro still life →
cathedral light shafts) in Godot 4.7.2, Forward+ / Vulkan, targeting the Valve Steam Frame
(Snapdragon 8 Gen 3 / Adreno 750) as a sideloaded Android APK shown as a flat window.
See `BRIEF.md` for the team brief and shot contract.

## Run on desktop

    godot --path .                                   # full demo (director/main.tscn)
    godot --path . res://shots/coast/coast.tscn      # single shot
    godot --path . -- --quality=med                  # preview the Android tier on desktop
    tools/render_frames.sh res://shots/coast/coast.tscn /tmp/out 4 7   # PNG sequence

## Build & install the APK

    tools/build_apk.sh                 # -> build/framedemo.apk (debug, signed w/ debug keystore)
    tools/build_apk.sh release out.apk # needs a release keystore in the preset / env vars
    tools/install.sh                   # adb install -r + launch on the attached device
    tools/install.sh build/framedemo.apk --quality=low   # launch with extra Godot args

Requirements: Godot 4.7.2 + 4.7.2.stable export templates, Android SDK (build-tools, platform-tools),
JDK 17, debug keystore configured in the editor settings (`export/android/*`).

Export presets (`export_presets.cfg`):

| preset | what |
|---|---|
| **Steam Frame (arm64)** | Android APK, arm64-v8a only, non-Gradle (prebuilt template), Vulkan, landscape, immersive fullscreen, package `com.demo.framedemo`, ASTC/ETC2 textures, extra args `--rendering-method forward_plus` |
| **Linux Desktop (x86_64)** | convenience desktop build, BPTC/S3TC, embedded PCK |
| **Steam Frame Linux (arm64)** | native SteamOS arm64 build (alternative to the APK), ETC2/ASTC, feature tag `steam_frame` (→ `med` quality tier) |

All presets exclude `tools/*`, `*.md`, `scratch/*`, `build/*` and source-art formats.
Min/target SDK are the template defaults (min 24, target 36): Godot only lets you override
them with a Gradle build, which we don't need.

### Forward+ on Android
Godot's Android exporter refuses to export when `rendering_method.mobile` is `forward_plus`
("designed for Desktop devices"). We keep the Mobile default for that key and instead:
1. pass `--rendering-method forward_plus` via the preset's `command_line/extra_args`
   (baked into the APK's `assets/_cl_`, parsed before the renderer is chosen), and
2. set `rendering/renderer/rendering_method.android="forward_plus"` as a belt-and-braces override.

The `Quality` autoload prints `Quality: tier=… renderer=…` at startup, so `adb logcat -s godot`
shows which renderer actually came up.

## Quality tiers (`shared/quality.gd`, autoload `Quality`)

Auto: Android / `mobile` / `steam_frame` feature → **med**, otherwise **high**.
Override: `--quality=low|med|high` (engine arg or after `--`), or env `FRAMEDEMO_QUALITY`.

| | low | med (Android default) | high (desktop default) |
|---|---|---|---|
| 3D scale / upscaler | 0.60 FSR1 + TAA | 0.75 FSR1 + TAA | 1.0 + TAA |
| Directional / positional shadow atlas | 2048 / 1024 | 2048 / 2048 | 4096 / 4096 |
| Soft shadow filter | very low | low | medium |
| SSAO / SSIL | very low / very low (half) | low / low (half) | high / medium |
| SSR | half size | half size | full size |
| Volumetric fog froxels | 32×32×32 | 48×48×48 | 64×64×64 |
| Anisotropic filter | 2× | 4× | 16× |
| Mesh LOD threshold | 2.0 px | 1.5 px | 1.0 px |

The same values are mirrored as `.mobile`/`.android` feature overrides in `project.godot` so the
first frame (before the autoload runs) already uses mobile-sized buffers. FSR1+TAA was chosen over
FSR2 because FSR2's compute passes cost several ms on Adreno-class GPUs; TAA is used at all tiers
(MSAA is off: it is expensive with Forward+ on tilers and doesn't fix shader aliasing).
Physical light units, SDFGI, VoxelGI and LightmapGI are intentionally not used.

## Texture imports

Headless `--import` never runs Godot's "detect 3D" step, so downloaded textures stay
Lossless without mipmaps (huge APK, uncompressed VRAM, shimmering). Run
`python3 tools/fix_texture_imports.py [--apply] [assets/<dir>]` then `godot --headless --path . --import`
to switch material textures to VRAM-compressed (BPTC/S3TC desktop, ASTC/ETC2 Android) with mipmaps.

## Steam Frame notes (researched Oct 2026)

- **Hardware/OS**: Snapdragon 8 Gen 3 (arm64), SteamOS (Arch Linux). Vulkan is the native graphics API.
- **How APKs run**: through **Lepton**, Valve's Android compatibility layer (Waydroid/Anbox-derived
  rootless container, open-sourced under MIT for Valve's code). It mounts the *host* Mesa Vulkan
  drivers (Turnip for Adreno) plus Valve Vulkan layers (a foveation injector and a render-pass
  optimizer) into the container. It strips Android services that games don't need, so apps relying
  on Google services / heavy Android APIs may break — this demo uses none.
- **ABI**: ship **arm64-v8a only**. Valve's docs say mobile/Quest-style builds target Android Arm64.
- **Flat window**: Lepton hides its flat Android window by default (it is built mainly for VR APKs);
  the "Lepton Development" app shows a floating window with an Android home screen, and that is
  where a non-XR APK like this one appears. We export with `xr_features/xr_mode=0` (regular), so the
  demo runs as a flat landscape window, immersive fullscreen inside that window. The window size is
  whatever Lepton gives the surface; `canvas_items` stretch at 1920×1080 base keeps framing intact.
  This is the least-documented part of the platform. Validate it on hardware.
- **Sideloading / dev loop** (needs Developer Mode: Settings → System → Developer Mode):
  1. In the Steam library, start **Lepton Development** (or any Android game) so a container runs.
  2. `adb connect frame` (Wi-Fi; or the headset IP), or over USB:
     `adb forward tcp:5555 tcp:5555 && adb connect localhost:5555`.
  3. `tools/install.sh` (= `adb install -r` + launch). Logs: `adb logcat` or `lepton dev logcat`.
  - Alternative: SteamOS Devkit Client → Title Upload with Runtime **Android** and the APK as the start
    command. It then shows up under Library → Non-Steam as "Devkit Game: …".
  - USB power from a PC may not be enough to keep the headset running. Use external power.
  - "protocol fault / connection reset" adb errors usually mean another tool (Android Studio)
    holds the adb server.
- **Godot specifics from Valve's docs**: their Godot guide covers OpenXR (Gradle build + XR mode
  OpenXR + vendors plugin for foveation). None of that applies to this flat demo, so we use the
  simpler prebuilt (non-Gradle) template. A native **Linux arm64** export is the other supported
  path (preset "Steam Frame Linux (arm64)") if Lepton's flat-window handling is a problem.
- **Unverified / caveats**: no public Vulkan version/extension list or API-level requirement for
  Lepton; Forward+ on Turnip-in-Lepton has not been tested on hardware here (no device attached
  during development). If the Vulkan driver can't start, Godot tries OpenGL ES next
  (`rendering_device/fallback_to_opengl3` is on by default), which looks much worse, so check the
  startup line in logcat. To compare against the Mobile renderer, rebuild with that extra arg changed.

Sources: Steamworks docs, [Steam Frame compatibility](https://partner.steamgames.com/doc/steamhardware/steamframe/compatibility),
[debugging](https://partner.steamgames.com/doc/steamhardware/steamframe/debugging),
[adb ↔ Lepton](https://partner.steamgames.com/doc/steamhardware/steamframe/adb_lepton),
[load games](https://partner.steamgames.com/doc/steamhardware/steamframe/loadgames),
[Godot](https://partner.steamgames.com/doc/steamhardware/steamframe/engines/godot);
[GamingOnLinux on Lepton](https://www.gamingonlinux.com/2026/09/lepton-from-valve-to-run-android-games-on-linux-is-now-open-source/).

## Layout

    director/   timeline, transitions, titles, audio (director agent)
    shots/      coast/, macro/, cathedral/ — each a DemoShot scene (shot agents)
    assets/     per-shot CC0 assets + CREDITS.md
    shared/     DemoShot base class, Quality autoload, icon
    tools/      render_frames.sh, build_apk.sh, install.sh, fix_texture_imports.py

## License

Code, shaders, scenes and procedural assets: MIT (see `LICENSE`). Third-party assets keep their
own licenses (Poly Haven CC0, fonts SIL OFL 1.1); see `assets/*/CREDITS.md`.

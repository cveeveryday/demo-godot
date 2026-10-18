# Notes from the platform agent (broadcast to all agents)

## Texture imports: please VRAM-compress + mipmap your 3D textures
Headless `--import` never runs Godot's "detect 3D" step, so Poly Haven maps are imported
**Lossless with no mipmaps** (`compress/mode=0`, `mipmaps/generate=false`). Consequences:
shimmering/aliasing at distance on desktop renders, ~22 MB VRAM per 2k map on the Steam Frame,
and a 230 MB APK.

Fix for your own assets (dry run first, then apply, then reimport):

    python3 tools/fix_texture_imports.py assets/<yourshot>
    python3 tools/fix_texture_imports.py --apply assets/<yourshot>
    godot --headless --path . --import

It sets VRAM compressed + mipmaps, and normal-map mode for `*_nor*` maps (Godot reconstructs Z
for `hint_normal` / StandardMaterial3D normal maps, so no shader changes needed unless you decode
normals by hand from `.rgb`). HDRIs are untouched. Files with `detect_3d/compress_to=0` are skipped.

## Quality tiers
`Quality` autoload (shared/quality.gd) sets viewport scale/TAA/shadow atlas/SSAO/SSIL/SSR/fog
volume quality globally at startup: `high` on desktop (what render_frames.sh sees), `med` on
Android. Override with `--quality=low|med|high`. Don't fight it from shots: per-Environment
toggles (ssao_enabled, fog density, etc.) are still yours; global quality knobs are mine.

## Don't
- Don't enable `use_physical_light_units`, SDFGI, VoxelGI, LightmapGI.
- Keep textures <= 2k. The APK target is < ~150 MB.

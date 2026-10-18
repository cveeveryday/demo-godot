#!/usr/bin/env python3
"""Switch 3D material textures to VRAM compression + mipmaps.

Godot only auto-detects "used in 3D" (detect_3d) when the *editor GUI* loads a
material; headless `--import` leaves Poly Haven maps as Lossless with NO mipmaps.
That means shimmering/aliasing on desktop and ~22 MB of uncompressed VRAM per 2k
map on Android (and a huge APK). This rewrites the [params] of .import files:

  compress/mode=2 (VRAM compressed: BPTC/S3TC on desktop, ASTC/ETC2 on Android)
  mipmaps/generate=true
  compress/normal_map=1 for *_nor_* / *normal* maps (enables RGTC/normal-aware compression)
  compress/high_quality=true for normal maps (BPTC/ASTC 4x4 instead of DXT/ETC2)
  detect_3d/compress_to=0 (decision made explicitly)

Only textures with detect_3d/compress_to != 0 and compress/mode=0 (i.e. still
undecided) are touched, and only under the given dirs. HDRIs (.hdr/.exr) are
left alone (panorama skies sample them without mips; VRAM-compressing HDR is lossy).

usage: tools/fix_texture_imports.py [--apply] [dir ...]   (default dir: assets)
then:  godot --headless --path . --import
"""
import pathlib
import re
import sys

apply = "--apply" in sys.argv
dirs = [a for a in sys.argv[1:] if not a.startswith("--")] or ["assets"]
root = pathlib.Path(__file__).resolve().parent.parent

changed = 0
for d in dirs:
    for imp in sorted((root / d).rglob("*.import")):
        src = imp.with_suffix("")
        if src.suffix.lower() not in (".png", ".jpg", ".jpeg", ".webp", ".tga", ".bmp"):
            continue
        text = imp.read_text()
        if 'importer="texture"' not in text:
            continue
        if not re.search(r"^compress/mode=0$", text, re.M):
            continue
        if re.search(r"^detect_3d/compress_to=0$", text, re.M):
            continue  # someone explicitly chose "don't touch"
        name = src.name.lower()
        is_normal = "_nor" in name or "normal" in name
        new = re.sub(r"^compress/mode=0$", "compress/mode=2", text, flags=re.M)
        new = re.sub(r"^mipmaps/generate=false$", "mipmaps/generate=true", new, flags=re.M)
        new = re.sub(r"^detect_3d/compress_to=\d+$", "detect_3d/compress_to=0", new, flags=re.M)
        if is_normal:
            new = re.sub(r"^compress/normal_map=0$", "compress/normal_map=1", new, flags=re.M)
            new = re.sub(r"^compress/high_quality=false$", "compress/high_quality=true", new, flags=re.M)
        if new != text:
            changed += 1
            print(("fix " if apply else "would fix ") + str(imp.relative_to(root)))
            if apply:
                imp.write_text(new)

print(f"{changed} texture(s) {'updated' if apply else 'need updating (dry run; pass --apply)'}")

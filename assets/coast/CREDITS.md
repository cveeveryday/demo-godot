# Coast shot — asset credits

All third-party assets are CC0 (public domain) from Poly Haven (https://polyhaven.com).

| File(s) | Source | Notes |
|---|---|---|
| hdri/belfast_sunset_puresky_2k.hdr | https://polyhaven.com/a/belfast_sunset_puresky | 2k HDR, sky + water reflections |
| models/cliff04.res, textures/coastal_cliff_04_*_2k.jpg | https://polyhaven.com/a/coastal_cliff_04 | mesh decimated from 1.54M to 96k tris (+4 LODs) |
| models/rocks05.res, textures/coast_rocks_05_*_2k.jpg | https://polyhaven.com/a/coast_rocks_05 | decimated 772k -> 48k tris (+5 LODs) |
| models/landrocks02.res, textures/coast_land_rocks_02_*_2k.jpg | https://polyhaven.com/a/coast_land_rocks_02 | decimated 1.29M -> 40k tris (+4 LODs) |

Textures were re-encoded as JPEG q85 (from the 2k Poly Haven maps) to save space.
Meshes were reduced with shots/coast/tools/decimate.gd.txt (uses the LOD chain Godot's
importer generates, then compacts vertices and keeps the remaining LODs).

Procedural (made for this project, CC0):
- textures/ocean_nrm.png, ocean_height.png — tileable ocean detail normal/height from a
  Phillips-like spectrum (shots/coast/tools/ocean_tex.py)
- textures/foam.png — tileable multi-octave Worley foam lace (shots/coast/tools/foam_tex.py)

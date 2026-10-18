# Generates shots/coast/coast.tscn (layout, environment, materials). Edit here, then run:
#   python3 shots/coast/tools/gen_tscn.py [sun_azimuth_deg=-30] [sun_elev_deg=3]
import math, os, sys
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'coast.tscn')

def tf(pos, yaw_deg=0.0, scale=1.0, pitch_deg=0.0, roll_deg=0.0):
    # basis = Ry(yaw) * Rx(pitch) * Rz(roll) * scale ; emitted as column vectors
    y, p, r = map(math.radians, (yaw_deg, pitch_deg, roll_deg))
    def mul(A, B): return [[sum(A[i][k]*B[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    Ry = [[math.cos(y),0,math.sin(y)],[0,1,0],[-math.sin(y),0,math.cos(y)]]
    Rx = [[1,0,0],[0,math.cos(p),-math.sin(p)],[0,math.sin(p),math.cos(p)]]
    Rz = [[math.cos(r),-math.sin(r),0],[math.sin(r),math.cos(r),0],[0,0,1]]
    M = mul(mul(Ry, Rx), Rz)
    cols = [[M[i][j]*scale for i in range(3)] for j in range(3)]
    v = cols[0]+cols[1]+cols[2]+list(pos)
    return 'Transform3D(' + ', '.join('%.5f' % x for x in v) + ')'

def look_basis(z):
    l = math.sqrt(sum(c*c for c in z)); z = [c/l for c in z]
    up = [0,1,0]
    x = [up[1]*z[2]-up[2]*z[1], up[2]*z[0]-up[0]*z[2], up[0]*z[1]-up[1]*z[0]]
    l = math.sqrt(sum(c*c for c in x)); x = [c/l for c in x]
    yv = [z[1]*x[2]-z[2]*x[1], z[2]*x[0]-z[0]*x[2], z[0]*x[1]-z[1]*x[0]]
    return 'Transform3D(' + ', '.join('%.5f' % c for c in x+yv+z+[0,50,0]) + ')'

# --- sun: azimuth from HDRI (u=0.604 -> 37.6 deg right of -Z), raised a little for lighting
SUN_AZ = math.radians(float(sys.argv[1]) if len(sys.argv) > 1 else -30.0)
SUN_EL = math.radians(float(sys.argv[2]) if len(sys.argv) > 2 else 3.0)
sun_dir = [math.sin(SUN_AZ)*math.cos(SUN_EL), math.sin(SUN_EL), -math.cos(SUN_AZ)*math.cos(SUN_EL)]

ROCKS = {
  'cliff04': ('coastal_cliff_04', 'res://assets/coast/models/cliff04.res'),
  'rocks05': ('coast_rocks_05', 'res://assets/coast/models/rocks05.res'),
  'landrocks02': ('coast_land_rocks_02', 'res://assets/coast/models/landrocks02.res'),
}
# name, asset, pos, yaw, scale, tint, pitch, roll
PLACE = [
  ('CliffMid', 'cliff04', (25, -9.0, -250), -78, 3.0, (0.95,0.92,0.88), 0, 0),
  ('CliffFar', 'cliff04', (-150, -8.0, -950), -20, 4.5, (0.9,0.9,0.9), 0, 0),
  ('StackMid', 'rocks05', (18, -2.0, -105), -30, 7.0, (1,1,1), 0, 0),
  ('StackMid2', 'rocks05', (2, -4.0, -372), 160, 11.0, (0.95,0.92,0.9), 0, -6),
  ('ReefNear', 'landrocks02', (13, -0.9, -36), -115, 2.2, (1,1,1), 0, 0),
  ('BoulderNear', 'rocks05', (8, -1.0, -14), 200, 1.6, (1,1,1), 0, 0),
]
USE_PROBE = False
SKY_ROT = float(sys.argv[3]) if len(sys.argv) > 3 else -85.0

ext = []; sub = []; nodes = []
def add_ext(typ, path):
    i = len(ext) + 1
    ext.append('[ext_resource type="%s" path="%s" id="%d"]' % (typ, path, i))
    return i

scr = add_ext('Script', 'res://shots/coast/coast.gd')
wsh = add_ext('Shader', 'res://shots/coast/water.gdshader')
rsh = add_ext('Shader', 'res://shots/coast/rock.gdshader')
skysh = add_ext('Shader', 'res://shots/coast/sky.gdshader')
hdr = add_ext('Texture2D', 'res://assets/coast/hdri/belfast_sunset_puresky_2k.hdr')
onrm = add_ext('Texture2D', 'res://assets/coast/textures/ocean_nrm.png')
ohgt = add_ext('Texture2D', 'res://assets/coast/textures/ocean_height.png')
foam = add_ext('Texture2D', 'res://assets/coast/textures/foam.png')

mats = {}
for key, (tex, mesh) in ROCKS.items():
    m = add_ext('ArrayMesh', mesh)
    a = add_ext('Texture2D', 'res://assets/coast/textures/%s_diff_2k.jpg' % tex)
    r = add_ext('Texture2D', 'res://assets/coast/textures/%s_arm_2k.jpg' % tex)
    n = add_ext('Texture2D', 'res://assets/coast/textures/%s_nor_gl_2k.jpg' % tex)
    mats[key] = (m, a, r, n)

def subres(typ, sid, body):
    sub.append('[sub_resource type="%s" id="%s"]\n%s\n' % (typ, sid, body))

sky_sun = [math.sin(SUN_AZ)*math.cos(math.radians(2.1)), math.sin(math.radians(2.1)), -math.cos(SUN_AZ)*math.cos(math.radians(2.1))]
U_OFF = 0.6045 - 0.5 - math.degrees(SUN_AZ) / 360.0
subres('ShaderMaterial', 'skymat', 'shader = ExtResource("%d")\nshader_parameter/panorama = ExtResource("%d")\nshader_parameter/u_offset = %.5f\nshader_parameter/exposure = 0.85\nshader_parameter/sun_dir = Vector3(%.5f, %.5f, %.5f)' % (skysh, hdr, U_OFF, *sky_sun))
subres('Sky', 'sky', 'sky_material = SubResource("skymat")\nradiance_size = 3')
subres('Environment', 'env', '''background_mode = 2
sky = SubResource("sky")
ambient_light_source = 3
ambient_light_sky_contribution = 1.0
reflected_light_source = 2
tonemap_mode = 4
tonemap_exposure = 0.2
tonemap_white = 8.0
ssao_enabled = true
ssao_radius = 2.0
ssao_intensity = 1.5
glow_enabled = true
glow_intensity = 0.35
glow_strength = 0.9
glow_bloom = 0.04
glow_blend_mode = 1
glow_hdr_threshold = 1.2
fog_enabled = true
fog_mode = 0
fog_light_color = Color(0.62, 0.55, 0.52, 1)
fog_light_energy = 1.0
fog_sun_scatter = 0.35
fog_density = 0.0006
fog_aerial_perspective = 0.75
fog_sky_affect = 0.0
volumetric_fog_enabled = true
volumetric_fog_density = 0.0015
volumetric_fog_albedo = Color(0.95, 0.9, 0.85, 1)
volumetric_fog_anisotropy = 0.7
volumetric_fog_length = 220.0
volumetric_fog_detail_spread = 2.0
volumetric_fog_sky_affect = 0.0
adjustment_enabled = true
adjustment_contrast = 1.1
adjustment_saturation = 1.05''')
subres('Environment', 'env_refl', '''background_mode = 1
background_color = Color(0, 0, 0, 0)
sky = SubResource("sky")
ambient_light_source = 3
reflected_light_source = 2
tonemap_mode = 0
tonemap_exposure = 1.0
fog_enabled = true
fog_mode = 0
fog_light_color = Color(0.62, 0.55, 0.52, 1)
fog_sun_scatter = 0.35
fog_density = 0.0016
fog_aerial_perspective = 0.75
fog_sky_affect = 0.0''')
subres('ShaderMaterial', 'watermat', '''render_priority = 0
shader = ExtResource("%d")
shader_parameter/detail_nrm = ExtResource("%d")
shader_parameter/detail_height = ExtResource("%d")
shader_parameter/foam_tex = ExtResource("%d")
shader_parameter/sky_pano = ExtResource("%d")
shader_parameter/sky_u_offset = %.5f
shader_parameter/sky_sun_dir = Vector3(%.5f, %.5f, %.5f)''' % (wsh, onrm, ohgt, foam, hdr, U_OFF, *sky_sun))
for key, (m, a, r, n) in mats.items():
    pass

rock_mat_ids = {}
for name, key, pos, yaw, sc, tint, pitch, roll in PLACE:
    mid = 'rock_' + key + '_' + ('%.2f_%.2f_%.2f' % tint).replace('.', 'p')
    if mid not in rock_mat_ids:
        m, a, r, n = mats[key]
        subres('ShaderMaterial', mid, '''render_priority = 0
shader = ExtResource("%d")
shader_parameter/albedo_tex = ExtResource("%d")
shader_parameter/arm_tex = ExtResource("%d")
shader_parameter/nrm_tex = ExtResource("%d")
shader_parameter/breakup_tex = ExtResource("%d")
shader_parameter/tint = Color(%.3f, %.3f, %.3f, 1)''' % (rsh, a, r, n, ohgt, *tint))
        rock_mat_ids[mid] = 1

# spray particles
subres('Gradient', 'spraygrad', 'offsets = PackedFloat32Array(0, 0.15, 1)\ncolors = PackedColorArray(1, 1, 1, 0, 1, 1, 1, 0.45, 1, 1, 1, 0)')
subres('GradientTexture1D', 'spraygradtex', 'gradient = SubResource("spraygrad")')
subres('Curve', 'spraycurve', '_data = [Vector2(0, 0.3), 0.0, 0.0, 0, 0, Vector2(1, 1), 0.0, 0.0, 0, 0]\npoint_count = 2')
subres('CurveTexture', 'spraycurvetex', 'curve = SubResource("spraycurve")')
subres('ParticleProcessMaterial', 'sprayproc', '''emission_shape = 3
emission_box_extents = Vector3(6, 0.4, 2)
direction = Vector3(0.3, 1, 0.4)
spread = 25.0
initial_velocity_min = 2.0
initial_velocity_max = 5.5
gravity = Vector3(0, -6, 0)
damping_min = 0.6
damping_max = 1.2
scale_min = 0.8
scale_max = 2.2
scale_curve = SubResource("spraycurvetex")
color_ramp = SubResource("spraygradtex")''')
subres('Gradient', 'puffgrad', 'offsets = PackedFloat32Array(0, 1)\ncolors = PackedColorArray(1, 1, 1, 1, 1, 1, 1, 0)')
subres('GradientTexture2D', 'pufftex', 'gradient = SubResource("puffgrad")\nwidth = 64\nheight = 64\nfill = 1\nfill_from = Vector2(0.5, 0.5)\nfill_to = Vector2(1, 0.5)')
subres('StandardMaterial3D', 'spraymat', '''transparency = 1
depth_draw_mode = 0
shading_mode = 2
vertex_color_use_as_albedo = true
albedo_color = Color(0.95, 0.93, 0.9, 0.6)
albedo_texture = SubResource("pufftex")
billboard_mode = 3
billboard_keep_scale = true
particles_anim_h_frames = 1
particles_anim_v_frames = 1
proximity_fade_enabled = true
proximity_fade_distance = 1.5''')
subres('QuadMesh', 'sprayquad', 'material = SubResource("spraymat")\nsize = Vector2(0.9, 0.9)')

nodes.append('''[node name="Coast" type="Node3D" node_paths=PackedStringArray("sun", "water", "reflection_viewport", "reflection_camera", "camera")]
script = ExtResource("%d")
sun = NodePath("Sun")
water = NodePath("Water")
reflection_viewport = NodePath("Reflection")
reflection_camera = NodePath("Reflection/ReflectionCamera")
duration = 7.0
camera = NodePath("Camera3D")
''' % scr)
nodes.append('''[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("env")
''')
nodes.append('''[node name="Sun" type="DirectionalLight3D" parent="."]
transform = %s
light_color = Color(1, 0.62, 0.38, 1)
light_energy = 3.0
light_specular = 0.6
light_angular_distance = 1.2
shadow_enabled = true
shadow_bias = 0.04
shadow_normal_bias = 1.5
directional_shadow_mode = 2
directional_shadow_max_distance = 700.0
directional_shadow_split_1 = 0.05
directional_shadow_split_2 = 0.18
directional_shadow_split_3 = 0.45
directional_shadow_blend_splits = true
volumetric_fog_energy = 1.2
''' % look_basis(sun_dir))
nodes.append('''[node name="Camera3D" type="Camera3D" parent="."]
transform = %s
fov = 42.0
near = 0.1
far = 16000.0
''' % tf((6, 2.3, 14)))
nodes.append('''[node name="Water" type="MeshInstance3D" parent="."]
layers = 2
cast_shadow = 0
material_override = SubResource("watermat")
''')
nodes.append('''[node name="Reflection" type="SubViewport" parent="."]
transparent_bg = true
use_hdr_2d = true
msaa_3d = 0
positional_shadow_atlas_size = 0
size = Vector2i(640, 360)
render_target_update_mode = 0
''')
nodes.append('''[node name="ReflectionCamera" type="Camera3D" parent="Reflection"]
cull_mask = 1
environment = SubResource("env_refl")
fov = 42.0
near = 0.1
far = 16000.0
''')
nodes.append('[node name="Rocks" type="Node3D" parent="."]\n')
for name, key, pos, yaw, sc, tint, pitch, roll in PLACE:
    m = mats[key][0]
    mid = 'rock_' + key + '_' + ('%.2f_%.2f_%.2f' % tint).replace('.', 'p')
    nodes.append('''[node name="%s" type="MeshInstance3D" parent="Rocks"]
transform = %s
mesh = ExtResource("%d")
material_override = SubResource("%s")
''' % (name, tf(pos, yaw, sc, pitch, roll), m, mid))
if USE_PROBE: nodes.append('''[node name="ReflectionProbe" type="ReflectionProbe" parent="."]
transform = %s
update_mode = 0
size = Vector3(3000, 600, 3000)
max_distance = 3000.0
cull_mask = 1
ambient_mode = 0
intensity = 1.0
''' % tf((0, 3, -40)))
for i, (p, delay) in enumerate([((16, 0.0, -100), 0.0), ((12, 0.0, -33), 0.6), ((7.5, 0.0, -12), 1.3)]):
    nodes.append('''[node name="Spray%d" type="GPUParticles3D" parent="."]
transform = %s
amount = 96
lifetime = 1.8
explosiveness = 0.55
randomness = 0.4
preprocess = %.2f
use_fixed_seed = true
seed = %d
fixed_fps = 30
visibility_aabb = AABB(-12, -4, -8, 24, 20, 16)
layers = 4
process_material = SubResource("sprayproc")
draw_pass_1 = SubResource("sprayquad")
''' % (i, tf(p), 2.0 + delay, 1234 + i))

with open(OUT, 'w') as f:
    f.write('[gd_scene load_steps=%d format=3]\n\n' % (len(ext) + len(sub) + 1))
    f.write('\n'.join(ext) + '\n\n')
    f.write('\n'.join(sub) + '\n')
    f.write('\n'.join(nodes))
print('wrote', OUT, 'sun_dir', sun_dir)

extends DemoShot
## Finale: low sun pouring through the lancets of an abandoned gothic nave.
## Architecture is procedural (CSG), surfaces use Poly Haven CC0 PBR scans.

const TEX := "res://assets/cathedral/tex/"
const MOD := "res://assets/cathedral/models/"

# --- layout (metres). Nave runs along -Z, camera looks east (-Z). ---
const NAVE_HALF := 5.0        # pillar line
const WALL_T := 0.8           # arcade / clerestory wall thickness
const AISLE_OUT := 9.6        # outer aisle wall centre
const PILLAR_Z0 := 2.5
const BAY := 5.0
const N_PILLARS := 8
const WEST_Z := 5.5
const EAST_Z := -36.0
const ARCADE_SPRING := 5.0
const AISLE_CEIL := 8.3
const VAULT_SPRING := 12.0
const VAULT_TOP := 19.0

@onready var sun: DirectionalLight3D = $Sun
var _stone: ShaderMaterial
var _stone_dark: ShaderMaterial
var _plaster: ShaderMaterial
var _floor: ShaderMaterial
var _glass_sun: ShaderMaterial
var _glass_shade: ShaderMaterial
var _dust_mat: ShaderMaterial
var _candles: Array[OmniLight3D] = []
var _candle_base: Array[Vector3] = []
var _built := false


func _ready() -> void:
	_build()
	super._ready()


func setup() -> void:
	_build()


# ---------------------------------------------------------------- materials
func _macro_noise() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.012
	n.fractal_octaves = 4
	n.seed = 7
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.generate_mipmaps = true
	t.noise = n
	return t


func _stone_mat(id: String, res: String, scale: float, tint: Color, macro: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shots/cathedral/stone.gdshader")
	m.set_shader_parameter("albedo_tex", load(TEX + id + "/" + id + "_diff_" + res + ".jpg"))
	m.set_shader_parameter("normal_tex", load(TEX + id + "/" + id + "_nor_gl_" + res + ".jpg"))
	m.set_shader_parameter("arm_tex", load(TEX + id + "/" + id + "_arm_" + res + ".jpg"))
	m.set_shader_parameter("macro_tex", macro)
	m.set_shader_parameter("scale", scale)
	m.set_shader_parameter("tint", tint)
	return m


func _make_materials() -> void:
	var macro := _macro_noise()
	_stone = _stone_mat("sandstone_blocks_08", "2k", 0.42, Color(0.93, 0.88, 0.80), macro)
	_stone_dark = _stone_mat("sandstone_blocks_08", "2k", 0.9, Color(0.80, 0.76, 0.70), macro)
	_stone_dark.set_shader_parameter("normal_strength", 1.8)
	_stone.set_shader_parameter("normal_strength", 1.6)
	_stone.set_shader_parameter("rough_mul", 1.5)
	_stone_dark.set_shader_parameter("rough_mul", 1.5)
	_plaster = _stone_mat("white_plaster_rough_01", "1k", 0.25, Color(0.80, 0.75, 0.66), macro)
	_plaster.set_shader_parameter("soot_start", 13.0)
	_plaster.set_shader_parameter("macro_amount", 0.6)

	_floor = ShaderMaterial.new()
	_floor.shader = load("res://shots/cathedral/floor.gdshader")
	var f := "monastery_stone_floor"
	_floor.set_shader_parameter("albedo_tex", load(TEX + f + "/" + f + "_diff_2k.jpg"))
	_floor.set_shader_parameter("normal_tex", load(TEX + f + "/" + f + "_nor_gl_2k.jpg"))
	_floor.set_shader_parameter("arm_tex", load(TEX + f + "/" + f + "_arm_2k.jpg"))
	_floor.set_shader_parameter("macro_tex", macro)
	_floor.set_shader_parameter("tint", Color(0.9, 0.86, 0.8))

	var gs := load("res://shots/cathedral/glass.gdshader") as Shader
	_glass_sun = ShaderMaterial.new()
	_glass_sun.shader = gs
	_glass_sun.set_shader_parameter("sky_color", Color(1.0, 0.9, 0.74))
	_glass_sun.set_shader_parameter("energy", 9.0)
	_glass_shade = ShaderMaterial.new()
	_glass_shade.shader = gs
	_glass_shade.set_shader_parameter("sky_color", Color(0.72, 0.82, 1.0))
	_glass_shade.set_shader_parameter("energy", 2.2)


# ---------------------------------------------------------------- geometry helpers
## Two-centred (pointed) arch from (-w/2, spring) over the apex to (w/2, spring).
## ratio = radius / span (0.5 = round, 1.0 = equilateral).
func _arch(w: float, spring: float, ratio: float, segs := 14) -> PackedVector2Array:
	var r := ratio * w
	var cx := -w * 0.5 + r
	var th_max := acos(clampf(cx / r, -1.0, 1.0))
	var left := PackedVector2Array()
	for i in segs + 1:
		var th := th_max * float(i) / float(segs)
		left.append(Vector2(cx - r * cos(th), spring + r * sin(th)))
	var pts := PackedVector2Array(left)
	for i in range(segs - 1, -1, -1):
		pts.append(Vector2(-left[i].x, left[i].y))
	return pts


func _arch_opening(w: float, bottom: float, spring: float, ratio: float) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(-w * 0.5, bottom)])
	pts.append_array(_arch(w, spring, ratio))
	pts.append(Vector2(w * 0.5, bottom))
	return pts


## Arched band (vault shell or rib): inner curve + outer curve offset by t.
func _arch_band(w: float, spring: float, ratio: float, t: float, segs := 24) -> PackedVector2Array:
	var inner := _arch(w, spring, ratio, segs)
	var r := ratio * w
	var outer := _arch(w + 2.0 * t, spring, (r + t) / (w + 2.0 * t), segs)
	var pts := PackedVector2Array(inner)
	for i in range(outer.size() - 1, -1, -1):
		pts.append(outer[i])
	return pts


## Basis whose local X runs along world +Z (for walls parallel to the nave) and
## whose extrusion (-local Z) runs along world +X.
const B_ALONG_Z := Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))


func _prism(poly: PackedVector2Array, depth: float, xf: Transform3D, mat: Material = null) -> CSGPolygon3D:
	var p := CSGPolygon3D.new()
	p.polygon = poly
	p.depth = depth
	# centre the extrusion on the transform origin (CSGPolygon extrudes to -Z)
	p.transform = Transform3D(xf.basis, xf.origin + xf.basis.z * depth * 0.5)
	if mat:
		p.material = mat
	return p


## Add a subtractive child given in world space.
func _sub(parent: CSGShape3D, child: CSGShape3D) -> void:
	child.material = _stone_dark
	child.transform = parent.transform.affine_inverse() * child.transform
	parent.add_child(child)


func _box(size: Vector3, pos: Vector3, mat: Material) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	b.material = mat
	return b


func _mesh(mesh: Mesh, pos: Vector3, mat: Material, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _cyl(r: float, h: float, segs := 20) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


func _glass(w: float, bottom: float, top: float, center: Vector3, along_z: bool, mat: Material, parent: Node) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(w + 0.1, top - bottom + 0.1)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = center + Vector3(0, (bottom + top) * 0.5, 0)
	if along_z:
		mi.rotation.y = PI * 0.5
	parent.add_child(mi)


func _pillar_z(i: int) -> float:
	return PILLAR_Z0 - BAY * i


# ---------------------------------------------------------------- build
func _build() -> void:
	if _built:
		return
	_built = true
	_make_materials()
	var arch := Node3D.new()
	arch.name = "Architecture"
	add_child(arch)

	# Floor
	var fl := PlaneMesh.new()
	fl.size = Vector2(AISLE_OUT * 2.0 + 1.0, WEST_Z - EAST_Z + 1.0)
	_mesh(fl, Vector3(0, 0, (WEST_Z + EAST_Z) * 0.5), _floor, arch)

	var arc_ratio := 0.72
	var arc_span := BAY - 0.9
	var nave_len := WEST_Z - EAST_Z
	var zc := (WEST_Z + EAST_Z) * 0.5

	for side in [-1.0, 1.0]:
		# --- arcade + clerestory wall
		var wall := _box(Vector3(WALL_T, VAULT_SPRING + 0.3, nave_len), Vector3(side * NAVE_HALF, (VAULT_SPRING + 0.3) * 0.5, zc), _stone)
		arch.add_child(wall)
		var under := _box(Vector3(3.0, ARCADE_SPRING - 0.25 + 1.0, nave_len - 7.0), Vector3(side * NAVE_HALF, (ARCADE_SPRING - 0.25 - 1.0) * 0.5, zc - 0.5), null)
		under.operation = CSGShape3D.OPERATION_SUBTRACTION
		_sub(wall, under)
		for i in N_PILLARS - 1:
			var zm := _pillar_z(i) - BAY * 0.5
			var op := _prism(_arch_opening(arc_span, -1.0, ARCADE_SPRING, arc_ratio), 3.0,
				Transform3D(B_ALONG_Z, Vector3(side * NAVE_HALF, 0, zm)))
			op.operation = CSGShape3D.OPERATION_SUBTRACTION
			_sub(wall, op)
			# arch moulding: an inner recessed order following the arch curve
			var t_in := 0.16
			var w_in := arc_span - 2.0 * t_in
			var ring := _prism(_arch_band(w_in, ARCADE_SPRING, (arc_ratio * arc_span - t_in) / w_in, t_in + 0.02, 18), WALL_T * 0.6,
				Transform3D(B_ALONG_Z, Vector3(side * NAVE_HALF, 0, zm)), _stone_dark)
			arch.add_child(ring)
			# clerestory window
			var cw := _prism(_arch_opening(1.5, AISLE_CEIL + 0.6, 10.6, 0.8), 3.0,
				Transform3D(B_ALONG_Z, Vector3(side * NAVE_HALF, 0, zm)))
			cw.operation = CSGShape3D.OPERATION_SUBTRACTION
			_sub(wall, cw)
			_glass(1.5, AISLE_CEIL + 0.6, 11.9, Vector3(side * NAVE_HALF, 0, zm), true,
				_glass_sun if side > 0 else _glass_shade, arch)
		# --- outer aisle wall with tall lancets
		var ow := _box(Vector3(WALL_T, AISLE_CEIL + 0.6, nave_len), Vector3(side * AISLE_OUT, (AISLE_CEIL + 0.6) * 0.5, zc), _stone)
		arch.add_child(ow)
		for i in N_PILLARS - 1:
			var zm := _pillar_z(i) - BAY * 0.5
			var wo := _prism(_arch_opening(1.7, 1.9, 5.6, 0.75), 3.0,
				Transform3D(B_ALONG_Z, Vector3(side * AISLE_OUT, 0, zm)))
			wo.operation = CSGShape3D.OPERATION_SUBTRACTION
			_sub(ow, wo)
			_glass(1.7, 1.9, 7.0, Vector3(side * AISLE_OUT, 0, zm), true,
				_glass_sun if side > 0 else _glass_shade, arch)
		# --- aisle ceiling slab
		arch.add_child(_box(Vector3(AISLE_OUT - NAVE_HALF + 0.4, 0.4, nave_len),
			Vector3(side * (NAVE_HALF + AISLE_OUT) * 0.5, AISLE_CEIL + 0.2, zc), _plaster))

		# --- pillars (compound piers)
		for i in N_PILLARS:
			var p := Vector3(side * NAVE_HALF, 0, _pillar_z(i))
			_mesh(_cyl(0.7, 0.45, 8), p + Vector3(0, 0.225, 0), _stone_dark, arch)
			_mesh(_cyl(0.6, 0.12, 16), p + Vector3(0, 0.51, 0), _stone_dark, arch)
			_mesh(_cyl(0.46, ARCADE_SPRING - 0.6, 24), p + Vector3(0, 0.57 + (ARCADE_SPRING - 0.6) * 0.5 - 0.0, 0), _stone, arch)
			for k in 4:
				var o := Vector3(cos(k * PI * 0.5), 0, sin(k * PI * 0.5)) * 0.47
				_mesh(_cyl(0.13, ARCADE_SPRING - 0.6, 10), p + o + Vector3(0, 0.57 + (ARCADE_SPRING - 0.6) * 0.5, 0), _stone_dark, arch)
			# capital: flared necking + abacus
			var cap := CylinderMesh.new()
			cap.bottom_radius = 0.6
			cap.top_radius = 0.82
			cap.height = 0.4
			cap.radial_segments = 16
			_mesh(cap, p + Vector3(0, ARCADE_SPRING - 0.25, 0), _stone_dark, arch)
			var ab := BoxMesh.new()
			ab.size = Vector3(1.6, 0.18, 1.6)
			_mesh(ab, p + Vector3(0, ARCADE_SPRING + 0.04, 0), _stone_dark, arch)
			# vaulting shaft rising on the nave face to the vault springing
			var vs_h := VAULT_SPRING - ARCADE_SPRING
			_mesh(_cyl(0.13, vs_h, 10), p + Vector3(-side * (WALL_T * 0.5 + 0.1), ARCADE_SPRING + vs_h * 0.5, 0), _stone_dark, arch)
			var vcap := BoxMesh.new()
			vcap.size = Vector3(0.45, 0.25, 0.45)
			_mesh(vcap, p + Vector3(-side * (WALL_T * 0.5 + 0.15), VAULT_SPRING - 0.1, 0), _stone_dark, arch)
			# wall-shaft on aisle side
			_mesh(_cyl(0.18, AISLE_CEIL, 10), Vector3(side * (AISLE_OUT - WALL_T * 0.5 - 0.12), AISLE_CEIL * 0.5, _pillar_z(i)), _stone_dark, arch)

		# string course under clerestory
		var sc := BoxMesh.new()
		sc.size = Vector3(0.25, 0.22, nave_len)
		_mesh(sc, Vector3(side * (NAVE_HALF - WALL_T * 0.5 - 0.1), AISLE_CEIL + 0.4, zc), _stone_dark, arch)

	# --- vault (pointed barrel with transverse ribs)
	var vw := NAVE_HALF * 2.0 - WALL_T
	var vault := _prism(_arch_band(vw, VAULT_SPRING, 0.62, 0.6), nave_len, Transform3D(Basis.IDENTITY, Vector3(0, 0, zc)), _plaster)
	vault.smooth_faces = true
	arch.add_child(vault)
	for i in N_PILLARS:
		var rib := _prism(_arch_band(vw - 0.5, VAULT_SPRING, 0.62 * (vw) / (vw - 0.5) - 0.02, 0.4, 24), 0.42,
			Transform3D(Basis.IDENTITY, Vector3(0, 0, _pillar_z(i))), _stone_dark)
		arch.add_child(rib)

	# --- east wall with three lancets and a rose window
	var ew := _box(Vector3(AISLE_OUT * 2.0 + WALL_T, VAULT_TOP + 1.0, 1.2), Vector3(0, (VAULT_TOP + 1.0) * 0.5, EAST_Z), _stone)
	arch.add_child(ew)
	var ewins := [[0.0, 2.3, 1.8, 9.6, 0.78], [-2.7, 1.5, 3.0, 8.0, 0.8], [2.7, 1.5, 3.0, 8.0, 0.8],
		[-7.3, 1.7, 1.9, 5.6, 0.75], [7.3, 1.7, 1.9, 5.6, 0.75]]
	for wdef in ewins:
		var x: float = wdef[0]
		var o := _prism(_arch_opening(wdef[1], wdef[2], wdef[3], wdef[4]), 3.0, Transform3D(Basis.IDENTITY, Vector3(x, 0, EAST_Z)))
		o.operation = CSGShape3D.OPERATION_SUBTRACTION
		_sub(ew, o)
		var top: float = wdef[3] + wdef[1] * 0.9
		_glass(wdef[1], wdef[2], top, Vector3(x, 0, EAST_Z), false, _glass_sun, arch)
	var rose := CSGCylinder3D.new()
	rose.radius = 1.7
	rose.height = 3.0
	rose.sides = 32
	rose.rotation.x = PI * 0.5
	rose.position = Vector3(0, 14.6, EAST_Z)
	rose.operation = CSGShape3D.OPERATION_SUBTRACTION
	_sub(ew, rose)
	_glass(3.5, 12.8, 16.4, Vector3(0, 0, EAST_Z), false, _glass_sun, arch)
	# rose tracery: radial mullions
	for k in 8:
		var mul := BoxMesh.new()
		mul.size = Vector3(0.12, 3.4, 0.25)
		var mm := _mesh(mul, Vector3(0, 14.6, EAST_Z), _stone_dark, arch)
		mm.rotation.z = k * PI / 8.0
	var ring := TorusMesh.new()
	ring.inner_radius = 0.45
	ring.outer_radius = 0.6
	var rm := _mesh(ring, Vector3(0, 14.6, EAST_Z), _stone_dark, arch)
	rm.rotation.x = PI * 0.5
	# central lancet mullion
	var mul2 := BoxMesh.new()
	mul2.size = Vector3(0.16, 9.3, 0.3)
	_mesh(mul2, Vector3(0, 1.8 + 4.65, EAST_Z), _stone_dark, arch)

	# --- west wall (behind camera)
	arch.add_child(_box(Vector3(AISLE_OUT * 2.0 + WALL_T, VAULT_TOP + 1.0, 1.2), Vector3(0, (VAULT_TOP + 1.0) * 0.5, WEST_Z), _stone))

	# --- light-tight roof shell (shadow only)
	var roof := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(AISLE_OUT * 2.0 + 3.0, 1.0, nave_len + 3.0)
	roof.mesh = rb
	roof.position = Vector3(0, VAULT_TOP + 0.5, zc)
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	arch.add_child(roof)
	for side in [-1.0, 1.0]:
		var ar := MeshInstance3D.new()
		var arb := BoxMesh.new()
		arb.size = Vector3(AISLE_OUT - NAVE_HALF + 1.0, 0.6, nave_len + 2.0)
		ar.mesh = arb
		ar.position = Vector3(side * (NAVE_HALF + AISLE_OUT) * 0.5, AISLE_CEIL + 0.9, zc)
		ar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		arch.add_child(ar)

	_build_props()
	_build_dust()
	_build_lights()


func _place_model(path: String, pos: Vector3, rot_y: float, scale_f := 1.0) -> Node3D:
	var scn := load(path) as PackedScene
	var n := scn.instantiate() as Node3D
	n.position = pos
	n.rotation.y = rot_y
	n.scale = Vector3.ONE * scale_f
	add_child(n)
	return n


func _build_props() -> void:
	var props := Node3D.new()
	props.name = "Props"
	add_child(props)
	# fallen masonry blocks + a stone chest/altar for candles
	var blocks := [
		[Vector3(3.6, 0.16, -5.6), Vector3(0.7, 0.34, 0.45), 0.3],
		[Vector3(4.1, 0.11, -4.8), Vector3(0.4, 0.24, 0.32), -0.5],
		[Vector3(3.2, 0.09, -4.5), Vector3(0.28, 0.2, 0.4), 1.1],
		[Vector3(-6.8, 0.25, -14.0), Vector3(1.0, 0.5, 0.6), 0.2],
		[Vector3(1.5, 0.12, -18.5), Vector3(0.5, 0.24, 0.35), 0.7],
	]
	for b in blocks:
		var bm := BoxMesh.new()
		bm.size = b[1]
		var mi := _mesh(bm, b[0], _stone_dark, props)
		mi.rotation = Vector3(b[2] * 0.12, b[2], -b[2] * 0.1)
	# candle table: a stone plinth against the left pier
	var pl := BoxMesh.new()
	pl.size = Vector3(1.4, 0.9, 0.7)
	var plinth := _mesh(pl, Vector3(-3.7, 0.45, -7.4), _stone_dark, props)
	plinth.rotation.y = 0.15
	var c := _place_model(MOD + "brass_candleholders/brass_candleholders_1k.gltf", Vector3(-3.7, 0.9, -7.4), 0.15 + PI, 0.95)
	_fix_flames(c)
	# statue on a plinth by the right pier
	var sp := BoxMesh.new()
	sp.size = Vector3(1.2, 0.6, 1.2)
	_mesh(sp, Vector3(3.5, 0.3, -12.5), _stone_dark, props)
	_place_model(MOD + "gothic_statue/gothic_statue_1k.gltf", Vector3(3.5, 0.6, -12.0), -PI * 0.5 - 0.3, 1.0)
	# rows of old painted benches, slightly disordered
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var bench := load(MOD + "painted_wooden_bench/painted_wooden_bench_1k.gltf") as PackedScene
	for row in 7:
		for x in [-3.6, -2.35, 1.75, 3.0]:
			if rng.randf() < 0.12:
				continue
			var b := bench.instantiate() as Node3D
			b.position = Vector3(x + rng.randf_range(-0.12, 0.12), 0.0, -14.8 - row * 1.25 + rng.randf_range(-0.1, 0.1))
			b.rotation.y = PI + rng.randf_range(-0.08, 0.08) + (0.35 if row == 1 and x > 0.0 else 0.0)
			props.add_child(b)
	# workman's ladder left in the south aisle
	var lad := _place_model(MOD + "wooden_ladder/wooden_ladder_1k.gltf", Vector3(7.6, 0.0, -9.0), 0.4, 1.0)
	lad.rotation.z = 0.0


func _fix_flames(root: Node) -> void:
	var flame := StandardMaterial3D.new()
	flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame.albedo_texture = load(MOD + "brass_candleholders/textures/brass_candleholders_flame_diff_1k.jpg")
	flame.albedo_color = Color(4.0, 2.2, 0.9)
	flame.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			if mat and "flame" in mat.resource_name:
				(mi as MeshInstance3D).set_surface_override_material(s, flame)
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _build_dust() -> void:
	_dust_mat = ShaderMaterial.new()
	_dust_mat.shader = load("res://shots/cathedral/dust.gdshader")
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = _dust_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	var count := 2400
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for i in count:
		# concentrated near the camera path, thinning with distance
		var z := lerpf(4.0, -26.0, pow(rng.randf(), 1.6))
		var p := Vector3(rng.randf_range(-6.5, 6.5), rng.randf_range(0.2, 7.5) * (0.4 + 0.6 * rng.randf()), z)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, p))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Dust"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _build_lights() -> void:
	# low late-afternoon sun from the south-east, raking through the lancets
	var d := Vector3(-0.72, -0.40, 0.56).normalized()
	sun.transform = Transform3D(Basis.looking_at(d, Vector3.UP), Vector3(0, 20, 0))
	sun.light_color = Color(1.0, 0.82, 0.62)
	sun.light_energy = 6.0
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.light_volumetric_fog_energy = 3.0

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.58, 0.52)
	env.ambient_light_energy = 0.2
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.ssr_enabled = true
	env.ssr_max_steps = 56
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.3
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssil_enabled = true
	env.ssil_radius = 6.0
	env.ssil_intensity = 1.6
	env.ssil_sharpness = 0.9
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.4
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.024
	env.volumetric_fog_albedo = Color(0.92, 0.88, 0.82)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 56.0
	env.volumetric_fog_detail_spread = 1.6
	env.volumetric_fog_ambient_inject = 0.06
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	$WorldEnvironment.environment = env
	var dbg := OS.get_environment("CATH_DBG")
	if "nosun" in dbg: sun.visible = false
	for k in [1, 2, 3]:
		if ("dm%d" % k) in dbg:
			for m in [_stone, _stone_dark, _plaster]: m.set_shader_parameter("debug_mode", k)
	if "nossil" in dbg: env.ssil_enabled = false
	if "nossao" in dbg: env.ssao_enabled = false
	if "nofog" in dbg: env.volumetric_fog_enabled = false
	if "noshadowbias" in dbg: sun.shadow_normal_bias = 0.0

	# candle light
	for o in [Vector3(-3.7, 1.35, -7.25)]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.6, 0.28)
		l.light_energy = 1.6
		l.omni_range = 7.0
		l.omni_attenuation = 1.2
		l.shadow_enabled = true
		l.light_volumetric_fog_energy = 0.4
		l.position = o
		add_child(l)
		_candles.append(l)
		_candle_base.append(o)

	var probe := ReflectionProbe.new()
	probe.size = Vector3(NAVE_HALF * 2.0 + 8.0, 18.0, 44.0)
	probe.position = Vector3(0, 9.0, -15.0)
	probe.origin_offset = Vector3(0, -7.0, 8.0)
	probe.box_projection = true
	probe.interior = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	probe.max_distance = 60.0
	probe.intensity = 0.4
	if not "noprobe" in OS.get_environment("CATH_DBG"):
		add_child.call_deferred(probe)


# ---------------------------------------------------------------- animation
func _smoother(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


func update_shot(t: float, _u: float) -> void:
	if camera:
		# forward glide + gentle crane up, settling into the final frame by ~5.4 s
		var s := _smoother(t / 5.6)
		var s2 := 1.0 - pow(1.0 - clampf(t / 6.5, 0.0, 1.0), 2.0)
		var pos := Vector3(0.9, 1.5, 3.2).lerp(Vector3(0.15, 2.5, -4.5), s * 0.85 + s2 * 0.15)
		var tgt := Vector3(0.4, 3.2, -30.0).lerp(Vector3(0.0, 6.4, -36.0), s)
		# subtle handheld float
		pos += Vector3(sin(t * 0.9 + 1.0) * 0.012 + sin(t * 2.3) * 0.004,
			sin(t * 1.3) * 0.01 + sin(t * 3.1 + 2.0) * 0.003, 0.0)
		camera.look_at_from_position(pos, tgt, Vector3.UP)
		camera.rotate_object_local(Vector3(0, 0, 1), sin(t * 0.7) * 0.004)
	for i in _candles.size():
		var l := _candles[i]
		var f := 1.0 + 0.10 * sin(t * 11.3 + i) + 0.06 * sin(t * 23.7 + 2.0 * i) + 0.04 * sin(t * 37.1)
		l.light_energy = 1.6 * f
		l.position = _candle_base[i] + Vector3(sin(t * 7.1) * 0.01, 0.0, cos(t * 9.3) * 0.01)
	if _dust_mat:
		_dust_mat.set_shader_parameter("shot_time", t)

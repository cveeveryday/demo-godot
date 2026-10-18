extends DemoShot
## Macro still life: weathered table, window light, brass + glass props,
## slow dolly with a rack focus from the pocket watch to the old camera.

const M := "res://assets/macro/models/"
const PROPS := {
	"watch": preload(M + "pocket_watch/pocket_watch_2k.gltf"),
	"specs": preload(M + "round_spectacles/round_spectacles_1k.gltf"),
	"apple": preload(M + "food_apple_01/food_apple_01_2k.gltf"),
	"camera": preload(M + "Camera_01/Camera_01_1k.gltf"),
	"lamp": preload(M + "vintage_oil_lamp/vintage_oil_lamp_1k.gltf"),
	"jug": preload(M + "jug_01/jug_01_1k.gltf"),
	"book": preload(M + "binder_notebook/binder_notebook_1k.gltf"),
}

# name, position, euler degrees (applied YXZ)
const LAYOUT := [
	["watch", Vector3(0.02, 0.0079, 0.05), Vector3(-90, 0, 0), Vector3(0, -28, 0)],
	["specs", Vector3(-0.15, 0.0232, 0.0), Vector3(0, 0, 0), Vector3(0, 55, 0)],
	["book", Vector3(-0.42, 0.0021, -0.02), Vector3(0, 0, 0), Vector3(0, 74, 0)],
	["apple", Vector3(0.15, 0.0, -0.11), Vector3(0, 0, 0), Vector3(0, 40, 0)],
	["camera", Vector3(-0.07, 0.0, -0.25), Vector3(0, 0, 0), Vector3(0, 28, 0)],
	["jug", Vector3(-0.30, 0.0, -0.52), Vector3(0, 0, 0), Vector3(0, 120, 0)],
	["lamp", Vector3(0.17, 0.0, -0.58), Vector3(0, 0, 0), Vector3(0, 0, 0)],
]

@onready var _cam_attr: CameraAttributesPractical = camera.attributes
@onready var _flame_light: OmniLight3D = $FlameLight
@onready var _dust: MultiMeshInstance3D = $Dust

var _nodes := {}
var _sec_hand: Node3D
var _min_hand: Node3D
var _flame: Node3D
var _dust_mat: ShaderMaterial


func setup() -> void:
	for e in LAYOUT:
		var n: Node3D = PROPS[e[0]].instantiate()
		# local pre-rotation (lay object down), then yaw on the table
		var pre := Basis.from_euler(e[2] * PI / 180.0)
		var yaw := Basis.from_euler(e[3] * PI / 180.0)
		n.transform = Transform3D(yaw * pre, e[1])
		$Props.add_child(n)
		_nodes[e[0]] = n
	_fix_materials()
	_build_dust()
	if get_tree().current_scene == self:
		# standalone preview: round bokeh (project-wide setting requested in NOTES-macro.md)
		RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(RenderingServer.DOF_BOKEH_CIRCLE)
		RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_HIGH, true)
	$Sun.look_at_from_position(Vector3(-1.0, 0.55, -0.35), Vector3.ZERO)
	update_shot(0.0, 0.0)


func _mats(root: Node, fn: Callable) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if m:
				var r = fn.call(mi, m.duplicate())
				if r:
					mi.set_surface_override_material(s, r)


func _glass(m: StandardMaterial3D, alpha: float) -> StandardMaterial3D:
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = null
	m.albedo_color = Color(0.9, 0.92, 0.9, alpha)
	m.metallic = 0.0
	m.metallic_texture = null
	m.roughness = 0.03
	m.roughness_texture = null
	m.metallic_specular = 0.6
	m.normal_enabled = false
	return m


func _fix_materials() -> void:
	_mats(_nodes.watch, func(mi: MeshInstance3D, m: StandardMaterial3D):
		if m.resource_name.ends_with("glass"):
			return _glass(m, 0.06)
		return null)
	_mats(_nodes.specs, func(mi: MeshInstance3D, m: StandardMaterial3D):
		if m.resource_name.ends_with("glass"):
			return _glass(m, 0.05)
		return null)
	_mats(_nodes.lamp, func(mi: MeshInstance3D, m: StandardMaterial3D):
		if m.resource_name.ends_with("flame"):
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.albedo_color = Color(4.0, 2.2, 0.8)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_flame = mi
			return m
		if m.resource_name.ends_with("glass"):
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color.a = 0.12
			m.roughness = 0.04
			m.roughness_texture = null
			m.metallic = 0.0
			m.metallic_texture = null
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			return m
		return null)
	_mats(_nodes.camera, func(mi: MeshInstance3D, m: StandardMaterial3D):
		if m.resource_name == "Camera_01_lens":
			# coated optical glass: near-black, glossy, faint violet/amber coating
			m.albedo_texture = null
			m.albedo_color = Color(0.015, 0.012, 0.02)
			m.metallic = 0.0
			m.metallic_texture = null
			m.roughness = 0.04
			m.roughness_texture = null
			m.metallic_specular = 0.8
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			m.clearcoat_roughness = 0.02
			return m
		return null)
	var bk: Node = _nodes.book
	bk.get_node("binder_notebook").visible = false
	for n in _nodes.watch.get_children():
		if n.name == "pocket_watch_hand_secondes":
			_sec_hand = n
		elif n.name == "pocket_watch_hand_minutes":
			_min_hand = n


func _build_dust() -> void:
	var count := 900
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = qm
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var bmin := Vector3(-0.22, 0.0, -0.35)
	var bsize := Vector3(0.5, 0.22, 0.62)
	for i in count:
		var p := bmin + Vector3(rng.randf(), rng.randf(), rng.randf()) * bsize
		mm.set_instance_transform(i, Transform3D(Basis(), p))
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
	_dust.multimesh = mm
	_dust_mat = _dust.material_override
	_dust_mat.set_shader_parameter("box_min", bmin)
	_dust_mat.set_shader_parameter("box_size", bsize)
	_dust.custom_aabb = AABB(bmin - Vector3.ONE * 0.05, bsize + Vector3.ONE * 0.1)


static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func _smoother(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


func update_shot(t: float, u: float) -> void:
	if not is_node_ready() or _nodes.is_empty():
		return
	# --- camera: slow lateral dolly + slight push, gentle handheld breathing
	var k := _ease(u)
	var p0 := Vector3(-0.035, 0.062, 0.30)
	var p1 := Vector3(0.065, 0.078, 0.265)
	var pos := p0.lerp(p1, k)
	pos += Vector3(sin(t * 0.9) * 0.0012, sin(t * 1.3 + 1.0) * 0.0008, 0.0)
	var focus_w := _smoother((t - 2.0) / 2.2) # 0 = watch, 1 = camera
	var watch_p: Vector3 = _nodes.watch.position
	var cam_p: Vector3 = _nodes.camera.position + Vector3(0.0, 0.04, 0.0)
	var look := watch_p.lerp(cam_p, 0.25 + 0.35 * focus_w)
	look += Vector3(sin(t * 0.7) * 0.0008, cos(t * 0.8) * 0.0006, 0.0)
	camera.look_at_from_position(pos, look)
	# --- rack focus
	var d_watch := pos.distance_to(watch_p)
	var d_cam := pos.distance_to(cam_p)
	var fd := lerpf(d_watch, d_cam, focus_w)
	var depth := fd * 0.06 # shallow macro depth of field
	_cam_attr.dof_blur_near_distance = maxf(fd - depth, 0.01)
	_cam_attr.dof_blur_near_transition = fd * 0.35
	_cam_attr.dof_blur_far_distance = fd + depth
	_cam_attr.dof_blur_far_transition = fd * 0.9
	# --- watch hands tick (seconds hand steps at 1 Hz with a tiny settle)
	var base_sec := 37.0
	var s := floorf(t) + _ease(fract_(t) * 8.0)
	if _sec_hand:
		_sec_hand.rotation.z = -TAU * (base_sec + s) / 60.0
	if _min_hand:
		_min_hand.rotation.z = -TAU * (12.0 + (base_sec + t) / 60.0) / 60.0
	# --- oil lamp flame flicker
	var fl := 1.0 + 0.06 * sin(t * 13.0) + 0.04 * sin(t * 23.7 + 1.3) + 0.03 * sin(t * 41.0)
	_flame_light.light_energy = 0.35 * fl
	# --- dust
	_dust_mat.set_shader_parameter("shot_t", t)


static func fract_(x: float) -> float:
	return x - floorf(x)

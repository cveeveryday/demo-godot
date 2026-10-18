extends DemoShot
## Coast at dawn: low camera skimming over the sea toward backlit cliffs.

@export var sun: DirectionalLight3D
@export var water: MeshInstance3D
@export var cam_start := Vector3(-6.0, 2.3, 14.0)
@export var cam_end := Vector3(3.0, 1.7, -26.0)
@export var water_time_offset := 37.0
## Planar reflection (mirrored camera into a low-res HDR SubViewport).
@export var reflection_viewport: SubViewport
@export var reflection_camera: Camera3D
@export_range(0.15, 1.0) var reflection_scale := 0.33

var _water_mat: ShaderMaterial


func setup() -> void:
	if water:
		water.mesh = _build_water_mesh()
		_water_mat = water.material_override as ShaderMaterial
	if sun and _water_mat:
		_water_mat.set_shader_parameter("sun_dir", sun.global_transform.basis.z.normalized())
	if reflection_viewport and reflection_camera and _water_mat:
		var vs := Vector2(1920, 1080)
		if is_inside_tree() and get_viewport():
			vs = get_viewport().get_visible_rect().size
		if vs.x < 16.0:
			vs = Vector2(1920, 1080)
		reflection_viewport.size = Vector2i(maxi(64, int(vs.x * reflection_scale)), maxi(36, int(vs.y * reflection_scale)))
		reflection_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		reflection_camera.make_current()
		_water_mat.set_shader_parameter("refl_tex", reflection_viewport.get_texture())
	update_shot(0.0, 0.0)


## Polar grid: dense under the camera, exponentially coarser out to the horizon.
func _build_water_mesh() -> ArrayMesh:
	var segs := 256
	var growth := 1.055
	var dr := 0.3
	var radii := PackedFloat32Array([0.0])
	var r := 0.0
	while r < 15000.0:
		r += dr
		dr *= growth
		radii.append(r)
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.append(Vector3.ZERO)
	for i in range(1, radii.size()):
		for s in segs:
			var a := TAU * float(s) / segs
			verts.append(Vector3(cos(a) * radii[i], 0.0, sin(a) * radii[i]))
	# centre fan
	for s in segs:
		idx.append_array([0, 1 + s, 1 + (s + 1) % segs])
	for i in range(1, radii.size() - 1):
		var b0 := 1 + (i - 1) * segs
		var b1 := 1 + i * segs
		for s in segs:
			var s1 := (s + 1) % segs
			idx.append_array([b0 + s, b1 + s, b0 + s1, b1 + s, b1 + s1, b0 + s1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.custom_aabb = AABB(Vector3(-16000, -5, -16000), Vector3(32000, 10, 32000))
	return m


func update_shot(t: float, u: float) -> void:
	if not camera:
		return
	var e := u * u * (3.0 - 2.0 * u)            # smoothstep ease in/out
	var e2 := lerpf(u, e, 0.6)                    # keep some motion at the ends
	var pos := cam_start.lerp(cam_end, e2)
	# gentle swell bob + tiny handheld noise (all deterministic in t)
	pos.y += 0.16 * sin(t * 1.05 + 0.4) + 0.05 * sin(t * 2.3 + 1.3)
	pos.x += 0.06 * sin(t * 0.8 + 2.0)
	var yaw := deg_to_rad(lerpf(22.0, 8.0, e) + 0.35 * sin(t * 0.9))
	var pitch := deg_to_rad(2.2 + 0.35 * sin(t * 1.05 - 0.6) + 0.12 * sin(t * 2.7))
	var roll := deg_to_rad(0.7 * sin(t * 0.95 + 0.9) + 0.2 * sin(t * 2.1))
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, roll), EULER_ORDER_YXZ), pos)
	_update_reflection_camera()
	if water:
		water.global_position = Vector3(pos.x, 0.0, pos.z)
	if _water_mat:
		_water_mat.set_shader_parameter("wave_time", water_time_offset + t)


## Mirror the main camera about the sea plane (y = 0). Basis (Mx, -My, Mz) keeps it a proper
## rotation; the water shader samples the result with a flipped V.
func _update_reflection_camera() -> void:
	if not reflection_camera or not camera:
		return
	var b := camera.global_transform.basis
	var m := Vector3(1, -1, 1)
	var rb := Basis(b.x * m, -(b.y * m), b.z * m)
	var p := camera.global_position * m
	reflection_camera.global_transform = Transform3D(rb, p)
	reflection_camera.fov = camera.fov
	reflection_camera.near = camera.near
	reflection_camera.far = camera.far

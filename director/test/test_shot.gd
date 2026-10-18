extends DemoShot
## Throwaway placeholder shot used by the director while (or if) a real shot is missing.
## variant 0/1/2 roughly mimic coast / macro / cathedral lighting so transitions and
## titles can be judged against something plausible.

@export var variant := 0

var _objs: Array[Node3D] = []


func _init() -> void:
	camera = Camera3D.new()
	camera.name = "Cam"
	add_child(camera)


func setup() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var psky := ProceduralSkyMaterial.new()
	sky.sky_material = psky
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ssao_enabled = true
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	add_child(sun)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.roughness = 0.85
	ground.material_override = gmat
	add_child(ground)

	var palette := [Color(0.75, 0.72, 0.66), Color(0.55, 0.12, 0.08), Color(0.9, 0.9, 0.92), Color(0.2, 0.25, 0.3)]
	for i in 7:
		var m := MeshInstance3D.new()
		if i % 2 == 0:
			var s := SphereMesh.new()
			s.radius = 0.5 + 0.15 * i
			s.height = s.radius * 2.0
			m.mesh = s
			m.position = Vector3(-4.0 + i * 1.4, s.radius, -2.0 - (i % 3) * 1.5)
		else:
			var b := BoxMesh.new()
			b.size = Vector3(0.8, 1.6 + i * 0.3, 0.8)
			m.mesh = b
			m.position = Vector3(-4.0 + i * 1.4, b.size.y * 0.5, -2.5 - (i % 3) * 1.2)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = palette[i % palette.size()]
		mat.roughness = 0.25 + 0.1 * (i % 4)
		mat.metallic = 1.0 if i == 2 else 0.0
		m.material_override = mat
		add_child(m)
		_objs.append(m)

	match variant:
		0: # dawn coast: low warm sun, blue-ish water-coloured ground
			psky.sky_top_color = Color(0.28, 0.42, 0.66)
			psky.sky_horizon_color = Color(0.95, 0.66, 0.45)
			sun.rotation_degrees = Vector3(-8, -30, 0)
			sun.light_color = Color(1.0, 0.72, 0.5)
			sun.light_energy = 2.0
			gmat.albedo_color = Color(0.08, 0.16, 0.2)
			gmat.roughness = 0.15
		1: # macro: neutral studio-ish, shallow DOF
			psky.sky_top_color = Color(0.35, 0.35, 0.38)
			psky.sky_horizon_color = Color(0.6, 0.58, 0.55)
			sun.rotation_degrees = Vector3(-35, 40, 0)
			sun.light_energy = 1.6
			gmat.albedo_color = Color(0.35, 0.24, 0.16)
			var attr := CameraAttributesPractical.new()
			attr.dof_blur_far_enabled = true
			attr.dof_blur_far_distance = 6.0
			attr.dof_blur_near_enabled = true
			attr.dof_blur_near_distance = 1.5
			camera.attributes = attr
		_: # cathedral: dark, steep shafty light, fog
			psky.sky_top_color = Color(0.05, 0.05, 0.06)
			psky.sky_horizon_color = Color(0.1, 0.09, 0.08)
			sun.rotation_degrees = Vector3(-55, 120, 0)
			sun.light_color = Color(1.0, 0.86, 0.7)
			sun.light_energy = 3.0
			sun.light_volumetric_fog_energy = 2.0
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.03
			gmat.albedo_color = Color(0.4, 0.38, 0.35)


func update_shot(t: float, u: float) -> void:
	var e := u * u * (3.0 - 2.0 * u)
	match variant:
		0:
			camera.position = Vector3(lerpf(-6.0, 2.0, e), 1.6, 6.0)
			camera.look_at(Vector3(lerpf(-2.0, 1.0, e), 0.8, -3.0))
		1:
			camera.position = Vector3(lerpf(0.6, -0.4, e), 0.9, 2.2)
			camera.look_at(Vector3(0.0, 0.7, -2.5))
		_:
			camera.position = Vector3(0.0, lerpf(1.2, 2.6, e), lerpf(9.0, 6.0, e))
			camera.look_at(Vector3(0.0, 1.8, -3.0))
	# a little deterministic handheld
	camera.rotate_object_local(Vector3.RIGHT, 0.004 * sin(t * 1.3))
	camera.rotate_object_local(Vector3.UP, 0.003 * sin(t * 0.9 + 1.0))

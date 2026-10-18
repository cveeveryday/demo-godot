shader_type spatial;
// Dust motes: camera-facing soft discs that only show where light actually
// reaches them (shadowed attenuation), with forward-scattering phase.
// Motion is a pure function of `shot_t`, set by macro.gd (deterministic).
render_mode blend_add, depth_draw_never, cull_disabled, skip_vertex_transform,
	ambient_light_disabled;

uniform float shot_t = 0.0;
uniform vec3 box_min = vec3(-0.3, 0.0, -0.4);
uniform vec3 box_size = vec3(0.6, 0.35, 0.6);
uniform float size = 0.0009;
uniform float brightness = 6.0;
uniform float g = 0.6; // Henyey-Greenstein anisotropy

varying float v_bright;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void vertex() {
	vec4 c = INSTANCE_CUSTOM; // random seeds
	vec3 base = MODEL_MATRIX[3].xyz;
	float t = shot_t + c.x * 50.0;
	vec3 drift = vec3(
		sin(t * (0.35 + c.y * 0.3) + c.z * 6.28) * 0.012 + t * 0.002,
		t * (0.0015 + c.w * 0.003) + sin(t * 0.5 + c.x * 9.0) * 0.004,
		cos(t * (0.27 + c.z * 0.3) + c.y * 6.28) * 0.012);
	vec3 p = base + drift - box_min;
	p = mod(p, box_size) + box_min;
	float s = size * (0.8 + c.w * 1.0);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = p + (right * VERTEX.x + up * VERTEX.y) * s;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
	// slow twinkle as flakes tumble
	v_bright = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(shot_t * (1.0 + c.z * 3.0) + c.y * 40.0), 2.0);
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float m = clamp(1.0 - r, 0.0, 1.0);
	m = m * m;
	ALBEDO = vec3(m * v_bright);
}

void light() {
	float cosv = dot(VIEW, -LIGHT);
	float hg = (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * cosv, 1.5);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * hg * brightness * 0.08;
}

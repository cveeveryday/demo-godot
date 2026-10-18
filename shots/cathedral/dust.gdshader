shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, diffuse_lambert, specular_disabled, shadows_disabled;
// Dust motes: billboarded, drift deterministically from shot_time, lit only by
// shadowed sunlight with a strong forward-scattering lobe.
uniform float shot_time = 0.0;
uniform float size = 0.024;
uniform vec3 dust_color : source_color = vec3(0.9, 0.86, 0.8);
varying float seed;

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	seed = fract(sin(dot(base, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float t = shot_time;
	vec3 drift = vec3(
		0.06 * sin(t * (0.25 + seed * 0.3) + seed * 40.0) + 0.02 * t,
		0.05 * sin(t * (0.2 + seed * 0.25) + seed * 17.0) - 0.008 * t,
		0.06 * cos(t * (0.22 + seed * 0.3) + seed * 23.0));
	mat4 m = MODEL_MATRIX;
	m[3].xyz = base + drift;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], m[3]);
	VERTEX *= size * (0.5 + seed);
	MODELVIEW_NORMAL_MATRIX = mat3(1.0);
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	ALPHA = (1.0 - smoothstep(0.0, 1.0, d));
	ALBEDO = vec3(0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void light() {
	float fwd = max(dot(-LIGHT, VIEW), 0.0);
	float phase = 0.3 + 4.0 * pow(fwd, 6.0) + 1.0 * pow(fwd, 2.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * phase * dust_color / 3.14159;
}

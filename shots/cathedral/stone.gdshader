shader_type spatial;
// World-space triplanar PBR stone with macro variation and grime.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float scale = 0.5;
uniform vec3 tint : source_color = vec3(1.0);
uniform float normal_strength = 1.0;
uniform float rough_mul = 1.0;
uniform float grime_height = 1.5;
uniform float soot_start = 8.0;
uniform float macro_amount = 0.35;
uniform int debug_mode = 0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 b = pow(abs(n), vec3(6.0));
	b /= (b.x + b.y + b.z);
	vec2 ux = vec2(wpos.z, -wpos.y) * scale;
	vec2 uy = vec2(wpos.x, wpos.z) * scale;
	vec2 uz = vec2(wpos.x, -wpos.y) * scale;
	vec3 a = texture(albedo_tex, ux).rgb * b.x + texture(albedo_tex, uy).rgb * b.y + texture(albedo_tex, uz).rgb * b.z;
	vec3 arm = texture(arm_tex, ux).rgb * b.x + texture(arm_tex, uy).rgb * b.y + texture(arm_tex, uz).rgb * b.z;
	vec2 tx = texture(normal_tex, ux).xy * 2.0 - 1.0;
	vec2 ty = texture(normal_tex, uy).xy * 2.0 - 1.0;
	vec2 tz = texture(normal_tex, uz).xy * 2.0 - 1.0;
	vec3 d = vec3(0.0, tx.y, tx.x) * b.x + vec3(ty.x, 0.0, -ty.y) * b.y + vec3(tz.x, tz.y, 0.0) * b.z;
	vec3 wn = normalize(n + d * normal_strength);

	// macro variation breaks tiling
	float m1 = texture(macro_tex, wpos.xz * 0.045 + wpos.y * 0.03).r;
	float m2 = texture(macro_tex, vec2(wpos.x + wpos.z, wpos.y) * 0.11).r;
	float macro = mix(1.0, 0.7 + 0.6 * (m1 * 0.6 + m2 * 0.4), macro_amount);
	// rising damp near floor, soot/grime high up
	float damp = 1.0 - smoothstep(0.0, grime_height * (0.6 + 0.8 * m2), wpos.y);
	float soot = smoothstep(soot_start, soot_start + 6.0, wpos.y) * 0.35;
	a = pow(a, vec3(1.25)) * 1.15;
	vec3 col = a * tint * macro;
	col = mix(col, col * vec3(0.55, 0.52, 0.45), damp * 0.8);
	col *= 1.0 - soot;
	ALBEDO = col;
	ROUGHNESS = clamp(arm.g * rough_mul * mix(1.0, 0.8, damp), 0.62, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.28;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	if (debug_mode == 1) { ALBEDO = vec3(0.0); EMISSION = wn * 0.5 + 0.5; }
	if (debug_mode == 2) { ALBEDO = vec3(0.0); EMISSION = col; }
	if (debug_mode == 3) { ALBEDO = vec3(0.0); EMISSION = n * 0.5 + 0.5; }
}

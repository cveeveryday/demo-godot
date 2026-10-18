shader_type spatial;
// Worn flagstone floor with puddles and polished walking path.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float scale = 0.33;
uniform vec3 tint : source_color = vec3(1.0);
uniform float puddle_level = 0.62;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz * scale;
	vec3 a = texture(albedo_tex, uv).rgb;
	vec3 arm = texture(arm_tex, uv).rgb;
	vec3 nm = texture(normal_tex, uv).xyz;
	float m1 = texture(macro_tex, wpos.xz * 0.06).r;
	float m2 = texture(macro_tex, wpos.xz * 0.21 + 0.37).r;
	float macro = 0.75 + 0.5 * m1;
	// polished path down the nave centre (worn by feet)
	float path = 1.0 - smoothstep(1.2, 3.2, abs(wpos.x + 0.4 * sin(wpos.z * 0.15)));
	// puddles: low-frequency noise + texture cavity (AO / dark grout fill first)
	float cav = (1.0 - arm.r) * 0.6 + (1.0 - a.g) * 0.25;
	float wet_field = m1 * 0.8 + m2 * 0.35 + cav * 0.35;
	float puddle = smoothstep(puddle_level, puddle_level + 0.03, wet_field);
	float damp = smoothstep(puddle_level - 0.12, puddle_level, wet_field);
	vec3 col = a * tint * macro;
	col = mix(col, col * 0.55, damp * 0.7);
	col = mix(col, col * 0.35, puddle);
	float rough = arm.g * mix(1.0, 0.55, path) * (0.85 + 0.3 * m2);
	rough = mix(rough, rough * 0.45, damp);
	rough = mix(rough, 0.03, puddle);
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	SPECULAR = mix(0.5, 0.45, puddle);
	AO = mix(arm.r, 1.0, puddle);
	AO_LIGHT_AFFECT = 0.3;
	NORMAL_MAP = mix(nm, vec3(0.5, 0.5, 1.0), puddle * 0.97);
	NORMAL_MAP_DEPTH = 1.2;
}

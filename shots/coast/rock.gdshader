shader_type spatial;
// Photoscan rock with a wet / intertidal band near the waterline.
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic; // AO, rough, metal
uniform sampler2D nrm_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D breakup_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float normal_strength = 1.0;
uniform float wet_height = 0.7;      // world Y of the wet line
uniform float wet_soft = 1.0;
uniform float algae_height = 0.2;    // world Y below which rock is algae-dark

varying vec3 v_wpos;
varying vec3 v_wnrm;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Rendered by the (below-sea) planar reflection camera: drop the underwater part.
	if (CAMERA_POSITION_WORLD.y < 0.0 && v_wpos.y < 0.0) {
		discard;
	}
	vec3 alb = texture(albedo_tex, UV).rgb * tint;
	vec3 arm = texture(arm_tex, UV).rgb;
	float br = texture(breakup_tex, v_wpos.xz * 0.11 + v_wpos.y * 0.05).r;
	float h = v_wpos.y + (br - 0.5) * 0.8;
	float wet = 1.0 - smoothstep(wet_height - wet_soft, wet_height + 0.2, h);
	float algae = 1.0 - smoothstep(algae_height - 0.6, algae_height + 0.3, h);
	// wet rock: darker, more saturated, glossy
	vec3 wet_alb = pow(alb, vec3(1.35)) * 0.55;
	alb = mix(alb, wet_alb, wet);
	alb = mix(alb, alb * vec3(0.45, 0.5, 0.38), algae * 0.8);
	ALBEDO = alb;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.3;
	ROUGHNESS = mix(arm.g, 0.32, wet * 0.8);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	NORMAL_MAP = texture(nrm_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength * mix(1.0, 0.7, wet);
}

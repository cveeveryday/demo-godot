shader_type spatial;
// Ocean surface: Gerstner swell in the vertex stage (distance-faded per wavelength),
// spectrum-generated tileable detail normals in the fragment stage, depth-based
// absorption/refraction, wave-crest subsurface glow, crest + shoreline foam.
// Specular/Fresnel reflections come from Godot's PBR (sky radiance / reflection probe / sun).
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx, ambient_light_disabled;

uniform float wave_time = 0.0;          // driven deterministically from the shot script
uniform float choppiness : hint_range(0.0, 1.0) = 0.75;
uniform float wave_scale = 1.0;

uniform sampler2D detail_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_height : filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D refl_tex : filter_linear, repeat_disable;   // planar reflection (HDR, linear)
uniform float refl_distort = 0.12;
uniform sampler2D sky_pano : filter_linear_mipmap, repeat_enable;  // same HDRI as the sky
uniform float sky_u_offset = 0.0;
uniform vec3 sky_sun_dir = vec3(0.0, 0.04, -1.0);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.62, 0.32);
uniform float sun_glint = 900.0;     // reflected sun disk/aureole strength (HDR)
uniform float refl_strength = 0.8;
uniform vec3 ambient_color = vec3(1.5, 1.25, 1.15);   // HDR sky irradiance for body/foam

uniform float detail_strength = 0.3;
uniform vec3 scatter_color : source_color = vec3(0.018, 0.06, 0.065);
uniform vec3 sss_color : source_color = vec3(0.10, 0.42, 0.36);
uniform float sss_strength = 1.0;
uniform vec3 absorption = vec3(0.45, 0.075, 0.055);   // 1/m, red dies first
uniform vec3 sun_dir = vec3(0.6, 0.05, -0.8);         // direction TOWARD the sun (world)
uniform vec3 sun_color : source_color = vec3(1.0, 0.55, 0.3);
uniform float foam_amount = 1.0;
uniform float shore_foam_width = 1.1;
uniform float rough_near = 0.05;
uniform float rough_far = 0.16;

varying vec3 v_wpos;
varying float v_height;

// dir.xy, amplitude (m), wavelength (m)
const int NW = 8;
const vec4 W[NW] = vec4[](
	vec4( 0.93, -0.37, 0.65, 74.0),
	vec4( 0.70, -0.71, 0.38, 41.0),
	vec4( 0.99,  0.12, 0.2, 23.0),
	vec4( 0.55, -0.84, 0.10, 13.5),
	vec4( 0.98, -0.20, 0.06, 8.1),
	vec4( 0.30, -0.95, 0.035, 5.2),
	vec4( 0.88,  0.47, 0.022, 3.3),
	vec4( 0.62, -0.78, 0.012, 2.1)
);

varying vec2 v_base;

// Sum of Gerstner waves at undisplaced position p. fade_mul widens the distance fade.
void gerstner(vec2 p, float dist, float fade_mul, out vec3 off, out vec3 T, out vec3 B) {
	off = vec3(0.0);
	T = vec3(1.0, 0.0, 0.0);
	B = vec3(0.0, 0.0, 1.0);
	for (int i = 0; i < NW; i++) {
		vec4 w = W[i];
		vec2 d = normalize(w.xy);
		float k = TAU / w.w;
		float c = sqrt(9.81 / k);
		float fade = 1.0 - smoothstep(w.w * 5.0 * fade_mul, w.w * 16.0 * fade_mul, dist);
		float a = w.z * wave_scale * fade;
		float f = k * (dot(d, p) - c * wave_time) + float(i) * 1.7;
		float sf = sin(f);
		float cf = cos(f);
		float s = k * a;
		float q = choppiness;
		off += vec3(q * a * d.x * cf, a * sf, q * a * d.y * cf);
		T += vec3(-q * d.x * d.x * s * sf, d.x * s * cf, -q * d.x * d.y * s * sf);
		B += vec3(-q * d.x * d.y * s * sf, d.y * s * cf, -q * d.y * d.y * s * sf);
	}
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = length(wp.xz - CAMERA_POSITION_WORLD.xz);
	vec3 off; vec3 T; vec3 B;
	gerstner(wp.xz, dist, 1.0, off, T, B);
	VERTEX += off;
	v_base = wp.xz;
	v_height = off.y;
	v_wpos = wp + off;
	NORMAL = normalize(cross(B, T));
}

vec2 slope(vec2 uv) {
	vec3 t = texture(detail_nrm, uv).rgb * 2.0 - 1.0;
	return vec2(t.x, -t.y) / max(t.z, 0.25);
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 to_cam = cam - v_wpos;
	float dist = length(to_cam);
	vec3 V = to_cam / dist;

	// --- swell normal per pixel (a polar grid interpolating vertex normals streaks radially)
	vec3 goff; vec3 gT; vec3 gB;
	gerstner(v_base, dist, 1.6, goff, gT, gB);
	vec3 swell_n = normalize(cross(gB, gT));
	float crest = clamp(1.0 - (gT.x * gB.z - gT.z * gB.x), 0.0, 2.0);

	// --- detail normals: three scales, scrolling against each other
	vec2 uv = v_wpos.xz;
	float tt = wave_time;
	vec2 s = vec2(0.0);
	s += slope(uv / 23.0 + tt * vec2(0.012, -0.005)) * 0.35;
	mat2 r1 = mat2(vec2(0.966, 0.259), vec2(-0.259, 0.966));
	s += slope(r1 * uv / 7.7 + tt * vec2(-0.025, 0.016)) * 0.6;
	mat2 r2 = mat2(vec2(0.94, -0.342), vec2(0.342, 0.94));
	s += slope(r2 * uv / 2.6 + tt * vec2(0.045, 0.05)) * 0.5;
	s += slope(r1 * uv / 0.9 - tt * vec2(0.08, 0.03)) * 0.35 * (1.0 - smoothstep(4.0, 25.0, dist));
	float dfade = 1.0 - 0.55 * smoothstep(40.0, 900.0, dist);
	vec3 n = normalize(swell_n + vec3(s.x, 0.0, s.y) * detail_strength * dfade);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float ndv = clamp(dot(n, V), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);

	// --- refraction + depth absorption
	float d0 = texture(depth_tex, SCREEN_UV).r;
	vec4 vp0 = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d0, 1.0);
	vp0.xyz /= vp0.w;
	float thick0 = max(length(vp0.xyz) - length(VERTEX), 0.0);
	vec2 ruv = SCREEN_UV + n.xz * 0.025 * clamp(thick0 * 0.3, 0.0, 1.0) / max(1.0, dist * 0.05);
	float d1 = texture(depth_tex, ruv).r;
	vec4 vp1 = INV_PROJECTION_MATRIX * vec4(ruv * 2.0 - 1.0, d1, 1.0);
	vp1.xyz /= vp1.w;
	float thick1 = length(vp1.xyz) - length(VERTEX);
	if (thick1 < 0.0) { ruv = SCREEN_UV; thick1 = thick0; }
	vec3 refr = textureLod(screen_tex, ruv, 0.0).rgb;
	vec3 trans = exp(-absorption * thick1);
	float vert_depth = thick0 * max(V.y, 0.05);

	// --- foam: wave crests (Jacobian) + contact with rocks
	float fh = texture(detail_height, uv / 11.0 + tt * vec2(-0.02, 0.01)).r;
	float foam_pat = texture(foam_tex, uv / 6.5 + vec2(tt * 0.015, 0.0)).r;
	float foam_pat2 = texture(foam_tex, uv / 2.3 - vec2(0.0, tt * 0.02)).r;
	float crest_f = smoothstep(0.38, 0.8, crest + (fh - 0.5) * 0.35) * smoothstep(0.0, 0.25, v_height + 0.1);
	float sd = vert_depth + (foam_pat2 - 0.5) * 0.5;
	float shore_core = (1.0 - smoothstep(0.0, 0.06, sd)) * smoothstep(0.2, 0.6, foam_pat2 + 0.3);
	float lace_wave = 0.6 + 0.4 * sin(sd * 8.0 - tt * 1.8);
	float shore_lace = (1.0 - smoothstep(0.0, shore_foam_width, sd)) * smoothstep(0.3, 0.75, foam_pat * lace_wave + 0.15);
	float crest_foam = crest_f * foam_pat * 1.6 * (1.0 - smoothstep(150.0, 600.0, dist));
	float shore_foam = (shore_core * 0.85 + shore_lace * 0.7 * (1.0 - shore_core)) * (1.0 - smoothstep(400.0, 1500.0, dist));
	float foam = clamp(crest_foam + shore_foam, 0.0, 1.0) * foam_amount;

	// --- subsurface glow through backlit wave crests
	float back = pow(clamp(dot(-V, sun_dir) * 0.5 + 0.5, 0.0, 1.0), 6.0);
	float lift = clamp(v_height * 1.6 + 0.35, 0.0, 1.5);
	float side = pow(1.0 - clamp(dot(n, V), 0.0, 1.0), 2.0);
	vec3 sss = sss_color * sun_color * back * lift * (0.4 + side) * sss_strength;
	sss *= 1.0 - smoothstep(200.0, 1500.0, dist);

	vec3 body = scatter_color * (vec3(1.0) - trans);
	// --- planar reflection, distorted by the surface normal (view space)
	vec3 nv = (VIEW_MATRIX * vec4(n - vec3(0.0, 1.0, 0.0), 0.0)).xyz;
	vec2 rr = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y) + vec2(nv.x, -nv.z) * refl_distort;
	rr = clamp(rr, vec2(0.001), vec2(0.999));
	// vertical smear: rough water stretches reflections toward the viewer
	float bl = 0.004 + 0.012 * smoothstep(5.0, 300.0, dist);
	vec4 planar = textureLod(refl_tex, rr + vec2(0.0, -1.5 * bl), 0.0) * 0.2
		+ textureLod(refl_tex, rr + vec2(0.3 * bl, -0.5 * bl), 0.0) * 0.3
		+ textureLod(refl_tex, rr + vec2(-0.3 * bl, 0.5 * bl), 0.0) * 0.3
		+ textureLod(refl_tex, rr + vec2(0.0, 1.5 * bl), 0.0) * 0.2;
	// sky part: exact per-pixel reflection vector into the HDRI (keeps detail-normal glitter)
	vec3 rd = reflect(-V, n);
	rd.y = abs(rd.y) + 0.005;
	rd = normalize(rd);
	vec2 suv = vec2(atan(rd.x, -rd.z) / TAU + 0.5 + sky_u_offset, acos(rd.y) / PI);
	float slod = clamp(log2(1.0 + dist * 0.02) + 0.5, 0.0, 6.0);
	vec3 sky_refl = textureLod(sky_pano, suv, slod).rgb;
	// reflected sun: a widened lobe (stands in for sub-pixel facets) -> glitter path
	float sc = max(dot(rd, normalize(sky_sun_dir)), 0.0);
	float glint_w = mix(4000.0, 900.0, smoothstep(10.0, 600.0, dist));
	sky_refl += sun_tint * (pow(sc, glint_w) * sun_glint + pow(sc, 200.0) * 4.0) * smoothstep(-0.02, 0.03, sky_sun_dir.y);
	vec3 refl = mix(sky_refl, planar.rgb, clamp(planar.a, 0.0, 1.0)) * refl_strength;

	vec3 foam_col = vec3(0.82, 0.84, 0.82);
	ALBEDO = mix(body, foam_col, foam);
	EMISSION = (refr * trans + sss) * (1.0 - fres) * (1.0 - foam)
		+ refl * fres * (1.0 - foam)
		+ ambient_color * mix(body, foam_col, foam);
	ROUGHNESS = mix(mix(rough_near, rough_far, smoothstep(15.0, 1200.0, dist)), 0.65, foam);
	METALLIC = 0.0;
	SPECULAR = mix(0.25, 0.5, foam);
}

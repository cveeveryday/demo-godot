shader_type canvas_item;
render_mode unshaded, blend_disabled;
// Film-look finishing pass for the whole demo (drawn by a full-screen ColorRect on a CanvasLayer
// above the 3D image). Intentionally subtle: the shots carry the realism, this only adds the
// "photographed" layer — grain, lens falloff, a whisper of lateral CA and halation — plus the
// 2.39:1 letterbox and the director's fade.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;

uniform float fade : hint_range(0.0, 1.0) = 1.0;          // exposure fade (0 = black)
uniform float seed = 0.0;                                   // director time -> deterministic grain
uniform float grain_amount : hint_range(0.0, 0.2) = 0.03;
uniform float grain_size : hint_range(1.0, 3.0) = 1.4;      // in 1080p pixels
uniform float vignette : hint_range(0.0, 1.0) = 0.32;
uniform float ca_amount : hint_range(0.0, 0.01) = 0.0008;   // lateral CA at the corners (uv units)
uniform float halation : hint_range(0.0, 1.0) = 0.12;
uniform vec3 halation_tint = vec3(1.0, 0.42, 0.22);
uniform float halation_threshold : hint_range(0.0, 1.0) = 0.7;
uniform float target_aspect = 2.39;                        // letterbox aspect (<= 0 disables)
uniform float bars : hint_range(0.0, 1.0) = 1.0;           // 0..1 bar slide-in amount

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// value noise on a slightly-larger-than-pixel lattice: softer, more "silver" than per-pixel white noise
float grain(vec2 px, float s) {
	vec2 q = px / grain_size;
	vec2 i = floor(q);
	vec2 f = fract(q);
	f = f * f * (3.0 - 2.0 * f);
	vec2 o = vec2(fract(s * 0.6180339) * 913.0, fract(s * 0.4142135) * 577.0);
	float a = hash12(i + o);
	float b = hash12(i + o + vec2(1.0, 0.0));
	float c = hash12(i + o + vec2(0.0, 1.0));
	float d = hash12(i + o + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y) - 0.5;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	float aspect = res.x / res.y;

	// --- lateral chromatic aberration: grows with r^2, zero in the centre
	vec2 dc = uv - 0.5;
	vec2 dir = dc * vec2(aspect, 1.0);
	float r2 = dot(dir, dir);
	vec2 off = dc * ca_amount * r2 * 4.0;
	vec3 col;
	col.r = textureLod(screen_tex, uv - off, 0.0).r;
	col.g = textureLod(screen_tex, uv, 0.0).g;
	col.b = textureLod(screen_tex, uv + off, 0.0).b;

	// --- halation: wide soft glow of the highlights, tinted red-orange like light scattering
	// back through the film base. Two mip taps of the screen texture are cheap on mobile.
	vec3 h = textureLod(screen_tex, uv, 4.0).rgb * 0.6 + textureLod(screen_tex, uv, 6.0).rgb * 0.4;
	float hl = max(max(h.r, h.g), h.b);
	float hk = smoothstep(halation_threshold, 1.0, hl);
	col += h * halation_tint * hk * halation;

	// --- lens vignette (cos^4-ish falloff, gentle)
	float vr = length(dc * vec2(1.0, 0.82)) * 1.35;
	float vig = mix(1.0, pow(clamp(1.0 - vr * vr * 0.55, 0.0, 1.0), 1.6), vignette);
	col *= vig;

	// --- exposure fade
	col *= fade;

	// --- film grain: luminance-weighted, strongest in the mid-tones, slightly chromatic
	float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
	float w = clamp(4.0 * l * (1.0 - l) + 0.18, 0.0, 1.0);
	vec2 px = uv * vec2(1080.0 * aspect, 1080.0);
	float gm = grain(px, seed);
	vec3 g = vec3(gm) + vec3(grain(px + 37.0, seed + 1.7), 0.0, grain(px + 91.0, seed + 3.1)) * 0.25;
	col += g * grain_amount * w * fade;

	// --- 2.39:1 letterbox (pure black bars, 1px soft edge)
	if (target_aspect > 0.0) {
		float img_h = min(1.0, aspect / target_aspect);
		float bar = (1.0 - img_h) * 0.5 * bars;
		float e = SCREEN_PIXEL_SIZE.y;
		float m = smoothstep(bar - e, bar + e, uv.y) * smoothstep(bar - e, bar + e, 1.0 - uv.y);
		col *= m;
	}
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}

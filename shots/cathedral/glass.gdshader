shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
// Old leaded clear/amber glass seen against a bright overcast-sun sky.
uniform vec3 sky_color : source_color = vec3(1.0, 0.92, 0.8);
uniform float energy = 6.0;
uniform float pane = 0.32;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	// horizontal coordinate along the wall plane
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float u = abs(n.x) > abs(n.z) ? wpos.z : wpos.x;
	vec2 p = vec2(u, wpos.y) / pane;
	// diamond quarries
	vec2 q = vec2(p.x + p.y, p.y - p.x) * 0.7071;
	vec2 f = abs(fract(q) - 0.5);
	float lead = smoothstep(0.43, 0.47, max(f.x, f.y));
	vec2 id = floor(q);
	float r = h21(id);
	vec3 tintc = mix(vec3(1.0, 0.97, 0.88), vec3(0.85, 0.95, 0.85), step(0.8, r));
	tintc = mix(tintc, vec3(1.0, 0.85, 0.6), step(0.93, r));
	// slight brightness wobble = old uneven glass
	float wob = 0.75 + 0.35 * r;
	// vertical saddle bars
	float bar = 1.0 - smoothstep(0.02, 0.035, abs(fract(wpos.y / 0.9) - 0.5) - 0.465);
	bar = 1.0 - step(0.47, abs(fract(wpos.y / 0.9) - 0.5));
	vec3 c = sky_color * tintc * wob * energy * (1.0 - lead) * bar;
	c *= 0.8 + 0.4 * smoothstep(0.0, 18.0, wpos.y);
	// large-scale variation: grime, uneven exterior (sky above, distant trees/buildings low)
	vec2 cell = floor(vec2(u, wpos.y) * 1.3);
	float g = 0.82 + 0.3 * h21(cell + 3.1);
	c *= g;
	c = mix(c * vec3(0.55, 0.6, 0.5), c, smoothstep(2.0, 4.5, wpos.y));
	ALBEDO = c;
}

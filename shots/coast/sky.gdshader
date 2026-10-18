shader_type sky;
// Equirectangular HDRI with an explicit azimuth mapping, so the sun position in the
// panorama is known exactly: u = 0.5 + atan(x, -z) / TAU + u_offset.
// Adds a veiled sun disk + aureole on top of the (very hazy) HDRI sun.
uniform sampler2D panorama : filter_linear, repeat_enable;
uniform float u_offset = 0.0;
uniform float exposure = 1.0;
uniform vec3 sun_dir = vec3(0.0, 0.04, -1.0);     // toward the sun
uniform vec3 sun_tint : source_color = vec3(1.0, 0.62, 0.32);
uniform float sun_disk_intensity = 40.0;
uniform float sun_disk_cos = 0.99997;             // ~0.45 deg radius
uniform float aureole_intensity = 2.5;

void sky() {
	vec3 d = normalize(EYEDIR);
	vec2 uv = vec2(atan(d.x, -d.z) / TAU + 0.5 + u_offset, acos(clamp(d.y, -1.0, 1.0)) / PI);
	// textureLod avoids the derivative seam at the atan wrap
	vec3 col = textureLod(panorama, uv, 0.0).rgb * exposure;
	vec3 sd = normalize(sun_dir);
	float c = dot(d, sd);
	float disk = smoothstep(sun_disk_cos - 0.00002, sun_disk_cos + 0.00001, c);
	float aur = pow(max(c, 0.0), 900.0) + 0.25 * pow(max(c, 0.0), 90.0);
	// horizon extinction: the disk sinks into the haze band
	float ext = smoothstep(-0.005, 0.05, d.y);
	col += sun_tint * (disk * sun_disk_intensity + aur * aureole_intensity) * ext;
	COLOR = col;
}

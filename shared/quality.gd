extends Node
## Quality-tier autoload (registered as `Quality` in project.godot).
##
## Picks a tier at startup and applies it to the root viewport and the global
## RenderingServer state:
##   * auto: Android / mobile feature tag -> "med", everything else -> "high".
##   * override from the command line: `--quality=low|med|high`
##     (either as an engine arg or a user arg after `--`), or the
##     FRAMEDEMO_QUALITY environment variable.
##   * Android: pass it through export_presets.cfg `command_line/extra_args`.
##
## "high" keeps the desktop project settings (full res, TAA, big shadow maps).
## Shots that want to react can read `Quality.tier` or connect to `tier_changed`.
## Per-Environment settings (SSAO/SSIL/SSR/fog quality) are global RenderingServer
## state, so they apply to every WorldEnvironment the shots create.

signal tier_changed(tier: String)

const TIERS := {
	"low": {
		"scale": 0.6, "scaling_mode": Viewport.SCALING_3D_MODE_FSR, "taa": true,
		"msaa": Viewport.MSAA_DISABLED, "aniso": Viewport.ANISOTROPY_2X, "lod_threshold": 2.0,
		"dir_shadow": 2048, "pos_shadow": 1024, "soft_shadow": RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		"ssao": RenderingServer.ENV_SSAO_QUALITY_VERY_LOW, "ssil": RenderingServer.ENV_SSIL_QUALITY_VERY_LOW,
		"ssr_half": true, "fog_size": 32, "fog_depth": 32, "sss": RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_DISABLED,
	},
	"med": {
		"scale": 0.75, "scaling_mode": Viewport.SCALING_3D_MODE_FSR, "taa": true,
		"msaa": Viewport.MSAA_DISABLED, "aniso": Viewport.ANISOTROPY_4X, "lod_threshold": 1.5,
		"dir_shadow": 2048, "pos_shadow": 2048, "soft_shadow": RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		"ssao": RenderingServer.ENV_SSAO_QUALITY_LOW, "ssil": RenderingServer.ENV_SSIL_QUALITY_LOW,
		"ssr_half": true, "fog_size": 48, "fog_depth": 48, "sss": RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_LOW,
	},
	"high": {
		"scale": 1.0, "scaling_mode": Viewport.SCALING_3D_MODE_BILINEAR, "taa": true,
		"msaa": Viewport.MSAA_DISABLED, "aniso": Viewport.ANISOTROPY_16X, "lod_threshold": 1.0,
		"dir_shadow": 4096, "pos_shadow": 4096, "soft_shadow": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
		"ssao": RenderingServer.ENV_SSAO_QUALITY_HIGH, "ssil": RenderingServer.ENV_SSIL_QUALITY_MEDIUM,
		"ssr_half": false, "fog_size": 64, "fog_depth": 64, "sss": RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_MEDIUM,
	},
}

var tier := "high"
var is_mobile := false


func _ready() -> void:
	is_mobile = OS.has_feature("android") or OS.has_feature("mobile") or OS.has_feature("steam_frame")
	var t := _requested_tier()
	if t == "":
		t = "med" if is_mobile else "high"
	apply(t)


func apply(new_tier: String) -> void:
	if not TIERS.has(new_tier):
		push_warning("Quality: unknown tier '%s', using 'high'" % new_tier)
		new_tier = "high"
	tier = new_tier
	var q: Dictionary = TIERS[tier]
	var vp := get_viewport()
	vp.scaling_3d_mode = q.scaling_mode
	vp.scaling_3d_scale = q.scale
	vp.use_taa = q.taa
	vp.msaa_3d = q.msaa
	vp.anisotropic_filtering_level = q.aniso
	vp.mesh_lod_threshold = q.lod_threshold
	vp.positional_shadow_atlas_size = q.pos_shadow
	vp.use_debanding = true
	RenderingServer.directional_shadow_atlas_set_size(q.dir_shadow, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(q.soft_shadow)
	RenderingServer.positional_soft_shadow_filter_set_quality(q.soft_shadow)
	RenderingServer.environment_set_ssao_quality(q.ssao, true, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(q.ssil, true, 0.5, 4, 50.0, 300.0)
	RenderingServer.environment_set_ssr_half_size(q.ssr_half)
	RenderingServer.environment_set_volumetric_fog_volume_size(q.fog_size, q.fog_depth)
	RenderingServer.sub_surface_scattering_set_quality(q.sss)
	print("Quality: tier=%s mobile=%s scale=%.2f renderer=%s" % [
		tier, is_mobile, q.scale, RenderingServer.get_current_rendering_method()])
	tier_changed.emit(tier)


func _requested_tier() -> String:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--quality="):
			return _normalize(a.get_slice("=", 1))
	return _normalize(OS.get_environment("FRAMEDEMO_QUALITY"))


func _normalize(s: String) -> String:
	match s.strip_edges().to_lower():
		"low", "l", "0":
			return "low"
		"med", "medium", "m", "1":
			return "med"
		"high", "h", "2", "ultra":
			return "high"
	return ""

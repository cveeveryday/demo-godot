extends Node
## FRAME demo director.
##
## Plays the three shots on a fixed 20 s timeline and layers the "presentation" on top:
##   - transitions (filmic dissolve via a frozen frame of the outgoing shot, or dip-to-black)
##   - film-look post (post/film.gdshader: grain, vignette, CA, halation, 2.39:1 letterbox, fades)
##   - titles (director/titles.gd), score (assets/director/score.wav), optional perf overlay.
##
## Time is deterministic: under --fixed-fps / --write-movie the clock is frame_index / fps,
## and shots are driven only through DemoShot.drive(t).
##
## Command line (after `--` or anywhere):  --perf  perf overlay,  --loop  loop forever,
##   --speed=<f>  timeline speed (0.5 = everything on screen at half speed, same frame rate).
##   At any speed other than 1 the score is decoupled: it loops at normal speed, unsynced.
## Project settings (optional, read if present): demo/perf_overlay, demo/loop.

const SHOTS := [
	{"scene": "res://shots/coast/coast.tscn", "start": 0.0, "end": 7.0},
	# in: how this shot is entered. "dissolve" = cross-dissolve from a frozen frame of the
	# previous shot; "dip" = short dip through black centred on the cut.
	{"scene": "res://shots/macro/macro.tscn", "start": 7.0, "end": 13.5, "in": "dissolve", "in_dur": 0.9},
	{"scene": "res://shots/cathedral/cathedral.tscn", "start": 13.5, "end": 20.0, "in": "dip", "in_dur": 0.7},
]
const END := 20.0
const FALLBACK_SHOT := "res://director/test/test_shot.tscn"
const SCORE := "res://assets/director/score.wav"
const POST_SHADER := "res://post/film.gdshader"
const TITLES := preload("res://director/titles.gd")

enum State { LOADING, WARMUP, PLAYING, DONE }

var t := 0.0  ## director (timeline) time in seconds

var _state := State.LOADING
var _fixed_fps := 0.0
var _frame := 0
var _loop := false
var _perf := false
var _speed := 1.0

var _packed: Array = []        # PackedScene per SHOTS entry (or null)
var _instances: Array = []     # pre-instantiated DemoShot per entry (or null)
var _idx := -1
var _shot: DemoShot
var _preroll_t := 0.0
var _warm_i := 0
var _warm_frames := 0

var _post_mat: ShaderMaterial
var _freeze: TextureRect
var _freeze_t0 := -1.0
var _freeze_dur := 0.0
var _titles: Control
var _audio: AudioStreamPlayer
var _perf_label: Label
var _perf_hist: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	process_priority = -100  # drive shots before anything else this frame
	_parse_args()
	_build_layers()
	_set_fade(0.0)
	if _fixed_fps != 0.0:
		# Offline render: load synchronously inside _ready so frame 0 is timeline 0.0.
		for s in SHOTS:
			_packed.append(_load_sync(s.scene))
		_instantiate_all()
		_start()
	else:
		# Realtime: threaded load behind a black pre-roll, then a warm-up pass.
		for s in SHOTS:
			if ResourceLoader.exists(s.scene):
				ResourceLoader.load_threaded_request(s.scene, "PackedScene", true)
			_packed.append(null)


func _parse_args() -> void:
	# Engine args (--fixed-fps, --write-movie) are not visible in OS.get_cmdline_args(), so
	# offline mode is detected from Movie Maker, or from the raw process cmdline on Linux.
	if Engine.get_write_movie_path() != "":
		_fixed_fps = -1.0  # rate taken from the (constant) first delta
	elif FileAccess.file_exists("/proc/self/cmdline"):
		var raw := FileAccess.get_file_as_bytes("/proc/self/cmdline")
		var parts := _split_nul(raw)
		for i in parts.size():
			if parts[i] == "--fixed-fps" and i + 1 < parts.size():
				_fixed_fps = parts[i + 1].to_float()
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for a in args:
		if a == "--perf":
			_perf = true
		elif a == "--loop":
			_loop = true
		elif a.begins_with("--speed="):
			var sp := a.trim_prefix("--speed=").to_float()
			if sp > 0.0:
				_speed = sp
	if ProjectSettings.has_setting("demo/perf_overlay"):
		_perf = _perf or bool(ProjectSettings.get_setting("demo/perf_overlay"))
	if ProjectSettings.has_setting("demo/loop"):
		_loop = _loop or bool(ProjectSettings.get_setting("demo/loop"))


static func _split_nul(raw: PackedByteArray) -> PackedStringArray:
	var out := PackedStringArray()
	var start := 0
	for i in raw.size():
		if raw[i] == 0:
			out.append(raw.slice(start, i).get_string_from_utf8())
			start = i + 1
	return out


func _build_layers() -> void:
	# 50: film post over the 3D image
	var post_layer := CanvasLayer.new()
	post_layer.layer = 50
	add_child(post_layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = load(POST_SHADER)
	rect.material = _post_mat
	post_layer.add_child(rect)

	# 60: frozen frame of the outgoing shot (already post-processed) for dissolves
	var freeze_layer := CanvasLayer.new()
	freeze_layer.layer = 60
	add_child(freeze_layer)
	_freeze = TextureRect.new()
	_freeze.set_anchors_preset(Control.PRESET_FULL_RECT)
	_freeze.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_freeze.stretch_mode = TextureRect.STRETCH_SCALE
	_freeze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_freeze.visible = false
	freeze_layer.add_child(_freeze)

	# 70: titles
	var title_layer := CanvasLayer.new()
	title_layer.layer = 70
	add_child(title_layer)
	_titles = TITLES.new()
	title_layer.add_child(_titles)

	# 100: perf overlay
	if _perf:
		var perf_layer := CanvasLayer.new()
		perf_layer.layer = 100
		add_child(perf_layer)
		_perf_label = Label.new()
		var ls := LabelSettings.new()
		ls.font = load("res://assets/director/fonts/Barlow-Regular.ttf")
		ls.font_size = 18
		ls.font_color = Color(0.85, 1.0, 0.85, 0.9)
		ls.outline_size = 4
		ls.outline_color = Color(0, 0, 0, 0.6)
		_perf_label.label_settings = ls
		_perf_label.position = Vector2(24, 18)
		perf_layer.add_child(_perf_label)

	_audio = AudioStreamPlayer.new()
	if ResourceLoader.exists(SCORE):
		_audio.stream = load(SCORE)
	_audio.bus = &"Master"
	add_child(_audio)
	if _free_audio():
		_audio.finished.connect(_audio.play)


func _exit_tree() -> void:
	# pre-instantiated shots that never entered the tree are not freed by the tree
	for s in _instances:
		if is_instance_valid(s) and not s.is_inside_tree():
			s.free()
	_instances.clear()


func _load_sync(path: String) -> PackedScene:
	if ResourceLoader.exists(path):
		var r := load(path)
		if r is PackedScene:
			return r
	push_warning("director: missing shot %s, using placeholder" % path)
	return null


func _instantiate_all() -> void:
	for s in _instances:
		if is_instance_valid(s) and not s.is_inside_tree():
			s.free()
	_instances.clear()
	for i in SHOTS.size():
		_instances.append(_instantiate(i))


func _instantiate(i: int) -> DemoShot:
	var ps: PackedScene = _packed[i]
	if ps:
		var n := ps.instantiate()
		if n is DemoShot:
			return n
		push_warning("director: %s root does not extend DemoShot, using placeholder" % SHOTS[i].scene)
		n.free()
	if not ResourceLoader.exists(FALLBACK_SHOT):
		return null
	var fb: DemoShot = (load(FALLBACK_SHOT) as PackedScene).instantiate()
	fb.set("variant", i)
	fb.name = "Placeholder%d" % i
	return fb


func _start() -> void:
	t = 0.0
	_frame = 0
	_idx = -1
	_state = State.PLAYING
	if _audio.stream and not (_free_audio() and _audio.playing):
		_audio.play(0.0)


func _process(delta: float) -> void:
	match _state:
		State.LOADING:
			_process_loading(delta)
		State.WARMUP:
			_process_warmup()
		State.PLAYING:
			_process_playing(delta)
	if _perf_label:
		_update_perf(delta)


# ------------------------------------------------------------------ realtime pre-roll
func _process_loading(delta: float) -> void:
	_preroll_t += delta
	_set_fade(0.0)
	var all_done := true
	for i in SHOTS.size():
		if _packed[i] != null:
			continue
		var p: String = SHOTS[i].scene
		if not ResourceLoader.exists(p):
			continue
		var st := ResourceLoader.load_threaded_get_status(p)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			all_done = false
		elif st == ResourceLoader.THREAD_LOAD_LOADED:
			_packed[i] = ResourceLoader.load_threaded_get(p)
	if all_done and _preroll_t > 0.25:
		for i in SHOTS.size():
			if _packed[i] == null:
				push_warning("director: missing shot %s, using placeholder" % SHOTS[i].scene)
		_instantiate_all()
		_state = State.WARMUP
		_warm_i = 0
		_warm_frames = 0


## Each shot is put in the tree for a couple of black frames so pipelines, textures and
## reflection probes are ready before its cut (avoids hitches on mobile). setup() runs here,
## once per instance, as the contract requires.
func _process_warmup() -> void:
	_set_fade(0.0)
	if _warm_i >= _instances.size():
		_start()
		_process_playing(0.0)
		return
	var s: DemoShot = _instances[_warm_i]
	if s == null:
		_warm_i += 1
		return
	if _warm_frames == 0:
		add_child(s)
		s.set_meta(&"_activated", true)
		s.activate()
		s.drive(0.0)
	_warm_frames += 1
	if _warm_frames > 12:
		remove_child(s)
		_warm_frames = 0
		_warm_i += 1


# ------------------------------------------------------------------ timeline
func _process_playing(delta: float) -> void:
	if _fixed_fps != 0.0:
		if _fixed_fps < 0.0:
			_fixed_fps = roundf(1.0 / delta) if delta > 0.0 else 60.0
		t = _frame / _fixed_fps * _speed
		_frame += 1
	else:
		t += delta * _speed
		# keep the score locked to the picture; resync only on real drift (hitches)
		if _audio.playing and not _free_audio():
			var at := _audio.get_playback_position() + AudioServer.get_time_since_last_mix()
			if absf(at - t) > 0.08 and t < END - 0.2:
				_audio.seek(t)

	if t >= END:
		if _loop:
			_shot_out()
			_instantiate_all()
			_set_fade(0.0)
			_titles.update(0.0)
			if _fixed_fps != 0.0:
				_start()
			else:
				if not _free_audio():
					_audio.stop()
				_state = State.WARMUP
				_warm_i = 0
				_warm_frames = 0
				return
		else:
			_set_fade(0.0)
			_state = State.DONE
			get_tree().quit()
			return

	var want := SHOTS.size() - 1
	for i in SHOTS.size():
		if t >= SHOTS[i].start and t < SHOTS[i].end:
			want = i
			break
	if want != _idx:
		_switch(want)
	if _shot:
		_shot.drive(t - SHOTS[_idx].start)

	_update_transitions()
	_post_mat.set_shader_parameter(&"seed", t)
	_titles.update(t)


func _switch(i: int) -> void:
	var entry: Dictionary = SHOTS[i]
	# Freeze the outgoing picture for a dissolve. Readback of the last presented frame,
	# done once per cut; the frame already contains post + letterbox, so the freeze layer
	# sits above the post layer and is shown untouched.
	if _idx >= 0 and entry.get("in", "") == "dissolve":
		var img := get_viewport().get_texture().get_image()
		if img:
			_freeze.texture = ImageTexture.create_from_image(img)
			_freeze_t0 = entry.start
			_freeze_dur = entry.get("in_dur", 0.8)
	_shot_out()
	_idx = i
	_shot = _instances[i] if i < _instances.size() else null
	if _shot:
		if not _shot.is_inside_tree():
			add_child(_shot)
		if not _shot.has_meta(&"_activated"):
			_shot.set_meta(&"_activated", true)
			_shot.activate()
		elif _shot.camera:
			_shot.camera.make_current()


func _shot_out() -> void:
	if _shot and is_instance_valid(_shot):
		remove_child(_shot)
		_shot.queue_free()
	_shot = null


func _update_transitions() -> void:
	# exposure: fade up from black, dips on "dip" cuts, dim + fade under the end card
	var f := _s(t / 1.6)
	for e in SHOTS:
		if e.get("in", "") == "dip":
			var h: float = e.get("in_dur", 0.7) * 0.5
			var d: float = t - e.start
			if d < 0.0 and d > -h:
				f = minf(f, _s(-d / h))
			elif d >= 0.0 and d < h * 1.6:  # come up a little slower than we went down
				f = minf(f, _s(d / (h * 1.6)))
	var end_card: float = _titles.end_t
	f *= lerpf(1.0, 0.28, _s((t - (end_card - 0.2)) / 0.9))
	f *= 1.0 - _s((t - 19.4) / 0.55)
	_set_fade(f)

	# dissolve: frozen outgoing frame fades out with a slight continued push-in
	if _freeze_t0 >= 0.0:
		var k := (t - _freeze_t0) / _freeze_dur
		if k >= 1.0 or k < 0.0:
			_freeze.visible = false
			_freeze.texture = null
			_freeze_t0 = -1.0
		else:
			_freeze.visible = true
			_freeze.modulate.a = 1.0 - _s(k)
			var sc := 1.0 + 0.008 * k
			_freeze.pivot_offset = _freeze.size * 0.5
			_freeze.scale = Vector2(sc, sc)


func _set_fade(f: float) -> void:
	if _post_mat:
		_post_mat.set_shader_parameter(&"fade", f)


## Score runs on its own (looping, normal speed) instead of following the timeline.
func _free_audio() -> bool:
	return _speed != 1.0


static func _s(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _update_perf(delta: float) -> void:
	_perf_hist.append(delta * 1000.0)
	if _perf_hist.size() > 120:
		_perf_hist = _perf_hist.slice(_perf_hist.size() - 120)
	var avg := 0.0
	var mx := 0.0
	for v in _perf_hist:
		avg += v
		mx = maxf(mx, v)
	avg /= maxf(1.0, _perf_hist.size())
	var r3d: Vector2i = get_viewport().get_texture().get_size()
	_perf_label.text = "%d fps   %.2f ms avg   %.2f ms max   %d draws   %d prims   %dx%d   t %.2f" % [
		Engine.get_frames_per_second(), avg, mx,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		r3d.x, r3d.y, t]

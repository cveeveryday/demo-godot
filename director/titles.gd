extends Control
## Title graphics (opening card, per-shot lower thirds, end card) in a restrained
## 2005-era tech-demo style. Everything is a pure function of director time `t`
## via update(t) — no tweens, no accumulated state — so --fixed-fps renders are exact.
## Layout is authored for the 1920x1080 canvas (stretch mode canvas_items).

const FONT_DISPLAY := preload("res://assets/director/fonts/Michroma-Regular.ttf")
const FONT_LIGHT := preload("res://assets/director/fonts/Barlow-Light.ttf")
const FONT_REG := preload("res://assets/director/fonts/Barlow-Regular.ttf")

const W := 1920.0
const H := 1080.0
const BAR := (H - W / 2.39) * 0.5  # letterbox bar height (~138 px)

## Lower thirds: [index, name, tech, t_in, t_out]
var captions: Array = [
	["01", "COAST AT DAWN", "Gerstner ocean  ·  volumetric atmosphere", 4.0, 6.2],
	["02", "STILL LIFE", "Physically based materials  ·  depth of field", 8.1, 12.75],
	["03", "CATHEDRAL", "Volumetric light  ·  screen-space reflections", 14.7, 17.95],
]
var title_text := "FRAME"
var subtitle_text := "realtime  ·  Godot 4.7  ·  Steam Frame"
var end_sub_text := "Godot 4.7  ·  Forward+  ·  rendered in realtime"
var end_t := 18.5

# opening card
var _title: Label
var _title_fv: FontVariation
var _rule: ColorRect
var _sub: Label
var _sub_fv: FontVariation
# lower third
var _lt_accent: ColorRect
var _lt_head: Label
var _lt_head_fv: FontVariation
var _lt_tech: Label
var _lt_tech_fv: FontVariation
var _mark: Label
# end card
var _end_title: Label
var _end_fv: FontVariation
var _end_rule: ColorRect
var _end_sub: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_title_fv = _fv(FONT_DISPLAY)
	_title = _label(title_text, _title_fv, 112, Color(1, 1, 1), true)
	_title.position = Vector2(0, H * 0.5 - 118)
	_title.size = Vector2(W, 150)

	_rule = _rect(Color(1, 1, 1, 0.55))
	_sub_fv = _fv(FONT_LIGHT)
	_sub = _label(subtitle_text, _sub_fv, 28, Color(0.92, 0.93, 0.95), true)
	_sub.position = Vector2(0, H * 0.5 + 52)
	_sub.size = Vector2(W, 44)

	_lt_accent = _rect(Color(0.86, 0.66, 0.42))  # warm brass accent
	_lt_head_fv = _fv(FONT_DISPLAY)
	_lt_head = _label("", _lt_head_fv, 15, Color(1, 1, 1, 0.82), false)
	_lt_tech_fv = _fv(FONT_LIGHT)
	_lt_tech = _label("", _lt_tech_fv, 27, Color(0.95, 0.95, 0.96), false)
	_lt_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_lt_tech.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	var mfv := _fv(FONT_DISPLAY)
	mfv.spacing_glyph = 6
	_mark = _label(title_text, mfv, 13, Color(1, 1, 1, 0.32), false)
	_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mark.position = Vector2(W - 96 - 400, H - BAR * 0.5 - 10)
	_mark.size = Vector2(400, 20)

	_end_fv = _fv(FONT_DISPLAY)
	_end_title = _label(title_text, _end_fv, 84, Color(1, 1, 1), true)
	_end_title.position = Vector2(0, H * 0.5 - 92)
	_end_title.size = Vector2(W, 120)
	_end_rule = _rect(Color(1, 1, 1, 0.5))
	var efv := _fv(FONT_LIGHT)
	efv.spacing_glyph = 3
	_end_sub = _label(end_sub_text, efv, 24, Color(0.9, 0.9, 0.92), true)
	_end_sub.position = Vector2(0, H * 0.5 + 42)
	_end_sub.size = Vector2(W, 40)
	update(0.0)


func _fv(base: Font) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = base
	return fv


func _label(text: String, font: Font, size: int, color: Color, centered: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = size
	ls.font_color = color
	# soft, barely-there shadow so white type survives over bright sky without a visible box
	ls.shadow_color = Color(0, 0, 0, 0.28)
	ls.shadow_size = 10
	ls.shadow_offset = Vector2.ZERO
	l.label_settings = ls
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	return l


func _rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


static func _s(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func _eo(x: float) -> float:  # ease-out cubic
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


## Fade-in at a over din, fade-out at b over dout.
static func _win(t: float, a: float, din: float, b: float, dout: float) -> float:
	return _s((t - a) / din) * (1.0 - _s((t - b) / dout))


func _set_spacing(l: Label, fv: FontVariation, sp: float, base_x: float) -> void:
	fv.spacing_glyph = int(round(sp))
	# trailing spacing after the last glyph shifts centred text left; compensate
	if l.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
		l.position.x = base_x + round(sp) * 0.5


func update(t: float) -> void:
	# ---------------- opening card (0 - ~3.9 s)
	var a_title := _win(t, 0.55, 1.1, 3.0, 0.9)
	_title.visible = a_title > 0.001
	_title.modulate.a = a_title
	_set_spacing(_title, _title_fv, lerpf(30.0, 48.0, _eo(t / 4.0)), 0.0)

	var a_rule := _win(t, 1.0, 0.6, 3.0, 0.8)
	var rw := 620.0 * _eo((t - 0.95) / 1.6)
	_rule.visible = a_rule > 0.001
	_rule.modulate.a = a_rule
	_rule.size = Vector2(rw, 1)
	_rule.position = Vector2((W - rw) * 0.5, H * 0.5 + 40)

	var a_sub := _win(t, 1.4, 0.9, 3.05, 0.8)
	_sub.visible = a_sub > 0.001
	_sub.modulate.a = a_sub * 0.9
	_set_spacing(_sub, _sub_fv, lerpf(9.0, 4.0, _eo((t - 1.4) / 2.2)), 0.0)

	# ---------------- lower thirds (inside the bottom letterbox bar)
	var cap = null
	for c in captions:
		if t >= c[3] - 0.01 and t <= c[4] + 0.6:
			cap = c
	if cap == null:
		_lt_accent.visible = false
		_lt_head.visible = false
		_lt_tech.visible = false
	else:
		var a: float = cap[3]
		var b: float = cap[4]
		var k := t - a
		var out := 1.0 - _s((t - b) / 0.5)
		var y0 := H - BAR + (BAR - 64.0) * 0.5  # vertically centred block in the bar
		var x0 := 112.0
		var acc_h := 64.0 * _eo(k / 0.45)
		_lt_accent.visible = true
		_lt_accent.modulate.a = out
		_lt_accent.position = Vector2(x0 - 22.0, y0 + (64.0 - acc_h) * 0.5)
		_lt_accent.size = Vector2(2, acc_h)

		_lt_head.visible = true
		_lt_head.text = "%s   %s" % [cap[0], cap[1]]
		_lt_head.modulate.a = _s((k - 0.15) / 0.5) * out
		_lt_head_fv.spacing_glyph = int(round(lerpf(9.0, 4.0, _eo((k - 0.15) / 1.2))))
		_lt_head.position = Vector2(x0 + 10.0 * (1.0 - _eo((k - 0.15) / 0.8)), y0 - 2.0)
		_lt_head.size = Vector2(900, 22)

		_lt_tech.visible = true
		_lt_tech.text = cap[2]
		_lt_tech.modulate.a = _s((k - 0.35) / 0.6) * out
		_lt_tech_fv.spacing_glyph = int(round(lerpf(4.0, 1.0, _eo((k - 0.35) / 1.4))))
		_lt_tech.position = Vector2(x0 + 14.0 * (1.0 - _eo((k - 0.35) / 0.9)), y0 + 26.0)
		_lt_tech.size = Vector2(1100, 38)

	# corner wordmark in the bar while shots play
	var a_mark := _win(t, 4.0, 1.0, end_t - 0.6, 0.6)
	_mark.visible = a_mark > 0.001
	_mark.modulate.a = a_mark

	# ---------------- end card
	var a_end := _win(t, end_t, 0.9, 19.55, 0.4)
	_end_title.visible = a_end > 0.001
	_end_title.modulate.a = a_end
	_set_spacing(_end_title, _end_fv, lerpf(24.0, 36.0, _eo((t - end_t) / 1.6)), 0.0)
	var erw := 420.0 * _eo((t - end_t - 0.3) / 1.0)
	_end_rule.visible = a_end > 0.001
	_end_rule.modulate.a = a_end
	_end_rule.size = Vector2(erw, 1)
	_end_rule.position = Vector2((W - erw) * 0.5, H * 0.5 + 30)
	var a_es := _win(t, end_t + 0.25, 0.6, 19.55, 0.4)
	_end_sub.visible = a_es > 0.001
	_end_sub.modulate.a = a_es * 0.85

class_name DemoShot
extends Node3D
## Contract for every shot in the demo.
## The director instances the shot, calls activate(), then drives update_shot()
## every frame. When the scene is run standalone it drives itself, so each
## shot can be previewed / rendered on its own.

@export var duration := 6.5
@export var camera: Camera3D

var _driven := false
var _standalone_t := 0.0


func _ready() -> void:
	# Standalone preview if we are the scene root.
	if get_tree().current_scene == self:
		activate()


func activate() -> void:
	if camera:
		camera.make_current()
	setup()


## Called by the director every frame. t = seconds since shot start, u = t / duration.
func drive(t: float) -> void:
	_driven = true
	update_shot(t, clampf(t / duration, 0.0, 1.0))


func _process(delta: float) -> void:
	if _driven:
		return
	_standalone_t += delta
	update_shot(_standalone_t, clampf(_standalone_t / duration, 0.0, 1.0))
	if _standalone_t > duration + 0.5 and get_tree().current_scene == self:
		get_tree().quit()


## Override: one-time setup (spawn procedural content, etc).
func setup() -> void:
	pass


## Override: animate camera / effects. Must be deterministic in t (no accumulated state)
## so --fixed-fps renders and the director scrubbing give identical results.
func update_shot(_t: float, _u: float) -> void:
	pass

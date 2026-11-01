class_name CameraRig
extends Camera3D
## Angled isometric-style camera that smoothly follows the cursor target.

@export var distance: float = 18.0
@export var pitch_deg: float = 52.0
@export var min_distance: float = 8.0
@export var max_distance: float = 34.0

var yaw_deg: float = 0.0
var target: Vector3 = Vector3.ZERO

var _smoothed: Vector3 = Vector3.ZERO
var _distance: float = 18.0
var _target_distance: float = 18.0


func _ready() -> void:
	fov = 48.0
	_smoothed = target
	_distance = distance
	_target_distance = distance
	_update()


func snap() -> void:
	_smoothed = target
	_update()


func focus_on(pos: Vector3) -> void:
	target = pos


func rotate_step(dir: int) -> void:
	yaw_deg = fposmod(yaw_deg + 90.0 * dir, 360.0)


func zoom_step(amount: float) -> void:
	_target_distance = clampf(_target_distance + amount, min_distance, max_distance)


func _process(delta: float) -> void:
	var t := 1.0 - pow(0.0005, delta)
	_smoothed = _smoothed.lerp(target, t)
	_distance = lerpf(_distance, _target_distance, t)
	_update()


func _update() -> void:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * _distance
	position = _smoothed + offset
	look_at(_smoothed, Vector3.UP)
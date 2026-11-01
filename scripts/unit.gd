class_name TacticalUnit
extends Node3D
## A tactical combatant: stats, team visuals, grid movement and damage feedback.

enum Team { PLAYER, ENEMY }

@export var team: Team = Team.PLAYER
@export var unit_name: String = "Soldier"
@export var max_hp: int = 24
@export var attack_power: int = 7
@export var defense: int = 3
@export var move_range: int = 5
@export var min_attack_range: int = 1
@export var max_attack_range: int = 1

var hp: int = 0
var grid_pos: Vector2i = Vector2i.ZERO
var has_acted: bool = false
var is_alive: bool = true

# Battle stance and per-battle ability use counts.
var _is_defending: bool = false
var ability_uses: Dictionary = {}

## Per-battle use counts for the command-menu abilities.
const ABILITY_USES := {"bash": 2, "pierce": 1, "fire": 3, "heal": 2, "potion": 2}

@onready var body: MeshInstance3D = $Body
@onready var base_ring: MeshInstance3D = $BaseRing

var _color: Color


func initialize() -> void:
	hp = max_hp
	ability_uses = ABILITY_USES.duplicate(true)
	_is_defending = false
	_apply_visuals()


func _apply_visuals() -> void:
	if team == Team.PLAYER:
		_color = Color(0.24, 0.46, 0.95)
	else:
		_color = Color(0.90, 0.28, 0.24)

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = _color
	body_mat.roughness = 0.6
	body.material_override = body_mat

	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = _color.lightened(0.35)
	ring_mat.emission_enabled = true
	ring_mat.emission = _color
	ring_mat.emission_energy_multiplier = 0.5
	base_ring.material_override = ring_mat

	if team == Team.ENEMY:
		rotation.y = PI  # face the player side


func set_selected(on: bool) -> void:
	var mat := body.get_active_material(0) as StandardMaterial3D
	if mat == null:
		return
	if on:
		mat.emission_enabled = true
		mat.emission = Color(1, 1, 1)
		mat.emission_energy_multiplier = 0.35
	else:
		mat.emission_enabled = false


func distance_to(other: Vector2i) -> int:
	return GridPathfinder.manhattan(grid_pos, other)


func can_attack_from(from: Vector2i, target: Vector2i) -> bool:
	var d := GridPathfinder.manhattan(from, target)
	return d >= min_attack_range and d <= max_attack_range


func can_attack(target: Vector2i) -> bool:
	return can_attack_from(grid_pos, target)


## Move step-by-step along a computed path, awaiting each step.
func move_along_path(grid: TacticalGrid, path: Array[Vector2i]) -> void:
	if path.size() <= 1:
		return
	for i in range(1, path.size()):
		var step := path[i]
		var prev := path[i - 1]
		var dir := Vector3(step.x - prev.x, 0.0, step.y - prev.y)
		if dir.length_squared() > 0.0:
			rotation.y = atan2(dir.x, dir.z)
		var target := grid.tile_to_world(step)
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(self, "position", target, 0.16)
		await tw.finished
	grid_pos = path[path.size() - 1]


func take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)
	if hp == 0:
		is_alive = false


func show_damage(amount: int, color: Color) -> void:
	_popup(str(amount), color)


## Restore HP and show a green "+N" popup.
func heal(amount: int) -> void:
	var recovered := mini(amount, max_hp - hp)
	hp += recovered
	_popup("+%d" % recovered, Color(0.35, 1.0, 0.45))


func _popup(text: String, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.font_size = 96
	label.outline_size = 20
	label.outline_modulate = Color(0, 0, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.006
	label.position = Vector3(0, 2.0, 0)
	add_child(label)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", 3.0, 0.8)
	tw.tween_property(label, "modulate:a", 0.0, 0.8)
	tw.chain().tween_callback(label.queue_free)


func die() -> void:
	is_alive = false
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.35)
	tw.tween_property(self, "position:y", position.y - 0.4, 0.35)
	await tw.finished
	queue_free()
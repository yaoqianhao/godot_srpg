# BROKEN BACKUP - do not use. Superseded by clean game.gd.
# class_name SRPGGame  (removed to avoid global class conflict)
extends Node3D
## Main tactical controller: turn flow, player command flow, combat resolution, enemy AI.

enum State { IDLE, MOVE_SELECT, ACTION_MENU, TARGET_SELECT, BUSY, ENEMY_TURN, GAME_OVER }

const UNIT_SCENE := preload("res://scenes/unit.tscn")

const COLOR_MOVE := Color(0.20, 0.50, 1.0, 0.38)
const COLOR_ATTACK := Color(1.0, 0.25, 0.20, 0.38)
const COLOR_PATH := Color(1.0, 1.0, 1.0, 0.60)
const COLOR_TARGET := Color(1.0, 0.6, 0.1, 0.55)

@onready var grid: TacticalGrid = $Grid
@onready var units_root: Node3D = $Units
@onready var camera: CameraRig = $Camera
@onready var hud: HUD = $HUD

var state: State = State.IDLE
var cursor_pos: Vector2i = Vector2i.ZERO
var turn: int = 1
var current_team: TacticalUnit.Team = TacticalUnit.Team.PLAYER

var units: Array[TacticalUnit] = []
var occupied: Dictionary = {}  # Vector2i -> TacticalUnit

var active_unit: TacticalUnit = null
var active_origin: Vector2i = Vector2i.ZERO
var reachable: Dictionary = {}
var valid_destinations: Array[Vector2i] = []
var attack_tiles: Array[Vector2i] = []
var _command_menu: Control  # declared to satisfy parse of broken backup


func _ready() -> void:
	grid.build()
	_spawn_armies()
	camera.current = true
	var center := Vector2i(int(grid.width * 0.5), int(grid.depth * 0.5))
	camera.focus_on(grid.tile_to_world(center))
	camera.snap()
	cursor_pos = center
	hud.action_selected.connect(_on_action_selected)
	_begin_player_turn()


# --------------------------------------------------------------------------
# Setup
# --------------------------------------------------------------------------

func _spawn_unit(data: Dictionary) -> void:
	var u: TacticalUnit = UNIT_SCENE.instantiate()
	u.team = data["team"]
	u.unit_name = data["name"]
	u.max_hp = data["hp"]
	u.attack_power = data["atk"]
	u.defense = data["def"]
	u.move_range = data["mov"]
	u.min_attack_range = data["minrng"]
	u.max_attack_range = data["maxrng"]
	units_root.add_child(u)
	u.grid_pos = data["pos"]
	u.position = grid.tile_to_world(u.grid_pos)
	u.initialize()
	units.append(u)
	occupied[u.grid_pos] = u


func _spawn_armies() -> void:
	var P := TacticalUnit.Team.PLAYER
	var E := TacticalUnit.Team.ENEMY
	# Player army (bottom rows)
	_spawn_unit({"team": P, "name": "Knight", "hp": 32, "atk": 9, "def": 6, "mov": 4, "minrng": 1, "maxrng": 1, "pos": Vector2i(3, 8)})
	_spawn_unit({"team": P, "name": "Archer", "hp": 22, "atk": 8, "def": 2, "mov": 5, "minrng": 1, "maxrng": 2, "pos": Vector2i(6, 8)})
	_spawn_unit({"team": P, "name": "Mage", "hp": 20, "atk": 11, "def": 1, "mov": 4, "minrng": 1, "maxrng": 3, "pos": Vector2i(9, 8)})
	# Enemy army (top rows)
	_spawn_unit({"team": E, "name": "Goblin", "hp": 24, "atk": 7, "def": 3, "mov": 4, "minrng": 1, "maxrng": 1, "pos": Vector2i(2, 1)})
	_spawn_unit({"team": E, "name": "Goblin", "hp": 24, "atk": 7, "def": 3, "mov": 4, "minrng": 1, "maxrng": 1, "pos": Vector2i(5, 1)})
	_spawn_unit({"team": E, "name": "Goblin", "hp": 24, "atk": 7, "def": 3, "mov": 4, "minrng": 1, "maxrng": 1, "pos": Vector2i(8, 1)})
	_spawn_unit({"team": E, "name": "Sniper", "hp": 26, "atk": 9, "def": 3, "mov": 4, "minrng": 1, "maxrng": 2, "pos": Vector2i(10, 1)})


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func get_unit_at(pos: Vector2i) -> TacticalUnit:
	return occupied.get(pos, null)


func alive_units(team: int) -> Array[TacticalUnit]:
	var out: Array[TacticalUnit] = []
	for u in units:
		if u.is_alive and u.team == team:
			out.append(u)
	return out


func tiles_in_range(center: Vector2i, minr: int, maxr: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for z in grid.depth:
		for x in grid.width:
			var d := GridPathfinder.manhattan(center, Vector2i(x, z))
			if d >= minr and d <= maxr:
				out.append(Vector2i(x, z))
	return out


func _blocked_for(u: TacticalUnit) -> Dictionary:
	var d: Dictionary = {}
	if u.team == TacticalUnit.Team.PLAYER:
		# Enemies block movement & passage; allies may be passed through.
		for pos in occupied:
			if occupied[pos].team == TacticalUnit.Team.ENEMY:
				d[pos] = true
	else:
		for pos in occupied:
			if occupied[pos] != u:
				d[pos] = true
	return d


# --------------------------------------------------------------------------
# Turn flow
# --------------------------------------------------------------------------

func _begin_player_turn() -> void:
	current_team = TacticalUnit.Team.PLAYER
	for u in units:
		if u.team == TacticalUnit.Team.PLAYER:
			u.has_acted = false
	active_unit = null
	state = State.IDLE
	hud.set_turn_text("PLAYER TURN   -   Turn %d" % turn)
	hud.set_message("Select one of your units.")
	_refresh()


func _begin_enemy_turn() -> void:
	current_team = TacticalUnit.Team.ENEMY
	for u in units:
		if u.team == TacticalUnit.Team.ENEMY:
			u.has_acted = false
	active_unit = null
	state = State.ENEMY_TURN
	hud.hide_action_menu()
	hud.set_turn_text("ENEMY TURN")
	_refresh()
	_run_enemy_turn()


func _maybe_end_player_turn() -> void:
	for u in units:
		if u.team == TacticalUnit.Team.PLAYER and u.is_alive and not u.has_acted:
			return
	_begin_enemy_turn()


func _finish_unit_action() -> void:
	if active_unit != null and is_instance_valid(active_unit):
		active_unit.has_acted = true
	active_unit = null
	state = State.IDLE
	hud.hide_action_menu()
	_refresh()
	_maybe_end_player_turn()


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------

func _refresh() -> void:
	grid.clear_overlays()

	match state:
		State.MOVE_SELECT:
			grid.draw_overlay(valid_destinations, COLOR_MOVE, 0.05, 0.9)
			if cursor_pos in valid_destinations:
				var path := GridPathfinder.build_path(reachable, cursor_pos)
				grid.draw_overlay(path, COLOR_PATH, 0.07, 0.42)
		State.ACTION_MENU, State.TARGET_SELECT:
			grid.draw_overlay(attack_tiles, COLOR_ATTACK, 0.05, 0.9)
			if state == State.TARGET_SELECT:
				for pos in attack_tiles:
					var tu := get_unit_at(pos)
					if tu != null and tu.team == TacticalUnit.Team.ENEMY:
						grid.draw_overlay([pos], COLOR_TARGET, 0.06, 0.7)

	grid.draw_cursor(cursor_pos)
	_update_info_panel()


func _update_info_panel() -> void:
	var u: TacticalUnit = null
	if active_unit != null and (state == State.MOVE_SELECT or state == State.ACTION_MENU or state == State.TARGET_SELECT):
		u = active_unit
	else:
		u = get_unit_at(cursor_pos)
	if u != null:
		hud.show_unit_info(u)
	else:
		hud.show_terrain_info(grid.get_elevation(cursor_pos.x, cursor_pos.y))


# --------------------------------------------------------------------------
# Input
# --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if state == State.GAME_OVER or state == State.BUSY or state == State.ENEMY_TURN:
		return

	if event.is_action_pressed("cam_rot_left"):
		camera.rotate_step(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("cam_rot_right"):
		camera.rotate_step(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("end_turn"):
		if current_team == TacticalUnit.Team.PLAYER:
			_begin_enemy_turn()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom_step(-2.0)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom_step(2.0)
			return
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var t: Variant = _mouse_tile()
			if t != null:
				cursor_pos = t
				_on_confirm()
			return

	# Cursor movement only where it makes sense.
	if state == State.ACTION_MENU:
		if event.is_action_pressed("ui_cancel"):
			_on_cancel()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		var t: Variant = _mouse_tile()
		if t != null and t != cursor_pos:
			cursor_pos = t
			_refresh()
		return

	if event.is_action_pressed("ui_up"):
		_move_cursor(_snap_axis(camera.global_transform.basis.z))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_move_cursor(-_snap_axis(camera.global_transform.basis.z))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_move_cursor(-_snap_axis(camera.global_transform.basis.x))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_move_cursor(_snap_axis(camera.global_transform.basis.x))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_on_confirm()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_on_cancel()
		get_viewport().set_input_as_handled()


func _snap_axis(v: Vector3) -> Vector2i:
	if absf(v.x) >= absf(v.z):
		return Vector2i(1 if v.x > 0.0 else -1, 0)
	return Vector2i(0, 1 if v.z > 0.0 else -1)


func _move_cursor(dir: Vector2i) -> void:
	cursor_pos = grid.clamp_tile(cursor_pos + dir)
	camera.focus_on(grid.tile_to_world(cursor_pos))
	_refresh()


func _mouse_tile() -> Variant:
	var space := get_world_3d().direct_space_state
	var mp := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var to := from + camera.project_ray_normal(mp) * 2000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	var body = hit["collider"]
	if body != null and body.has_meta("grid_pos"):
		return body.get_meta("grid_pos")
	return null


# --------------------------------------------------------------------------
# Confirm / cancel
# --------------------------------------------------------------------------

func _on_confirm() -> void:
	match state:
		State.IDLE:
			var u := get_unit_at(cursor_pos)
			# 玩家点击己方单位
			if u != null and u.team == TacticalUnit.Team.PLAYER and not u.has_acted:
				_enter_move_select(u)
		State.MOVE_SELECT:
			if cursor_pos in valid_destinations:
				_perform_move(cursor_pos)
		State.TARGET_SELECT:
			var target := get_unit_at(cursor_pos)
			if target != null and target.team == TacticalUnit.Team.ENEMY and active_unit.can_attack(cursor_pos):
				_do_attack(active_unit, target)


func _show_command_menu(u: TacticalUnit) -> void:
	# 创建指令面板
	_command_menu = PanelContainer.new()
	_command_menu.add_theme_stylebox_override("panel", _panel_style())
	_command_menu.anchor_left = 0.5
	_command_menu.anchor_right = 0.5
	_command_menu.anchor_top = 0.5
	_command_menu.anchor_bottom = 0.5
	_command_menu.offset_left = -280
	_command_menu.offset_right = 280
	_command_menu.offset_top = -200
	_command_menu.offset_bottom = 200
	_command_menu.visible = true
	add_child(_command_menu)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	_command_menu.add_child(vbox)

	var title := Label.new()
	title.text = "选择行动"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 8)
	vbox.add_child(title)

	var info := Label.new()
	info.text = "%s 移动 %d格 攻击 %d-%d格" % [u.unit_name, u.move_range, u.min_attack_range, u.max_attack_range]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0, 0.9))
	vbox.add_child(info)

	var sep := HBoxContainer.new()
	sep.add_theme_constant_override("separation", 8)
	vbox.add_child(sep)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 12)
	vbox.add_child(row1)

	var btn_move := Button.new()
	btn_move.text = "移动"
	btn_move.custom_minimum_size = Vector2(120, 48)
	btn_move.add_theme_font_size_override("font_size", 16)
	btn_move.pressed.connect(func(): _on_command_move(u))
	row1.add_child(btn_move)

	var btn_attack := Button.new()
	btn_attack.text = "攻击"
	btn_attack.custom_minimum_size = Vector2(120, 48)
	btn_attack.add_theme_font_size_override("font_size", 16)
	btn_attack.pressed.connect(func(): _on_command_attack(u))
	row1.add_child(btn_attack)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	vbox.add_child(row2)

	var btn_defend := Button.new()
	btn_defend.text = "防御"
	btn_defend.custom_minimum_size = Vector2(120, 48)
	btn_defend.add_theme_font_size_override("font_size", 16)
	btn_defend.pressed.connect(func(): _on_command_defend(u))
	row2.add_child(btn_defend)

	var btn_skill := Button.new()
	btn_skill.text = "技能"
	btn_skill.custom_minimum_size = Vector2(120, 48)
	btn_skill.add_theme_font_size_override("font_size", 16)
	btn_skill.pressed.connect(func(): _on_command_skill(u))
	row2.add_child(btn_skill)

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 12)
	vbox.add_child(row3)

	var btn_magic := Button.new()
	btn_magic.text = "魔法"
	btn_magic.custom_minimum_size = Vector2(120, 48)
	btn_magic.add_theme_font_size_override("font_size", 16)
	btn_magic.pressed.connect(func(): _on_command_magic(u))
	row3.add_child(btn_magic)

	var btn_item := Button.new()
	btn_item.text = "道具"
	btn_item.custom_minimum_size = Vector2(120, 48)
	btn_item.add_theme_font_size_override("font_size", 16)
	btn_item.pressed.connect(func(): _on_command_item(u))
	row3.add_child(btn_item)

	var row4 := HBoxContainer.new()
	row4.add_theme_constant_override("separation", 12)
	vbox.add_child(row4)

	var btn_wait := Button.new()
	btn_wait.text = "等待"
	btn_wait.custom_minimum_size = Vector2(120, 48)
	btn_wait.add_theme_font_size_override("font_size", 16)
	btn_wait.pressed.connect(func(): _on_command_wait(u))
	row4.add_child(btn_wait)

	var btn_close := Button.new()
	btn_close.text = "关闭"
	btn_close.custom_minimum_size = Vector2(120, 48)
	btn_close.add_theme_font_size_override("font_size", 16)
	btn_close.pressed.connect(func(): _hide_command_menu())
	row4.add_child(btn_close)


func _hide_command_menu() -> void:
	if has_node("_command_menu"):
		_command_menu.queue_free()


func _on_command_move(u: TacticalUnit) -> void:
	_hide_command_menu()
	_enter_move_select(u)


func _on_command_attack(u: TacticalUnit) -> void:
	_hide_command_menu()
	active_unit = u
	state = State.TARGET_SELECT
	cursor_pos = u.grid_pos
	camera.focus_on(grid.tile_to_world(u.grid_pos))
	_refresh()


func _on_command_defend(u: TacticalUnit) -> void:
	_hide_command_menu()
	u._is_defending = true
	hud.set_message("%s 进入防御状态！" % u.unit_name)
	await get_tree().create_timer(1.0).timeout
	u._is_defending = false
	hud.set_message("")


func _on_command_skill(u: TacticalUnit) -> void:
	_hide_command_menu()
	active_unit = u
	state = State.TARGET_SELECT
	cursor_pos = u.grid_pos
	camera.focus_on(grid.tile_to_world(u.grid_pos))
	_refresh()


func _on_command_magic(u: TacticalUnit) -> void:
	_hide_command_menu()
	active_unit = u
	state = State.TARGET_SELECT
	cursor_pos = u.grid_pos
	camera.focus_on(grid.tile_to_world(u.grid_pos))
	_refresh()


func _on_command_item(u: TacticalUnit) -> void:
	_hide_command_menu()
	hud.set_message("道具功能待开发")
	await get_tree().create_timer(1.0).timeout
	hud.set_message("")


func _on_command_wait(u: TacticalUnit) -> void:
	_hide_command_menu()
	_finish_unit_action()


func _show_move_action_menu(u: TacticalUnit, can_attack: bool) -> void:
	# 创建选择菜单 panel
	var menu_panel := PanelContainer.new()
	menu_panel.add_theme_stylebox_override("panel", _panel_style())
	menu_panel.anchor_left = 0.5
	menu_panel.anchor_right = 0.5
	menu_panel.anchor_top = 0.5
	menu_panel.anchor_bottom = 0.5
	menu_panel.offset_left = -180
	menu_panel.offset_right = 180
	menu_panel.offset_top = -120
	menu_panel.offset_bottom = 120
	menu_panel.visible = true
	add_child(menu_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	menu_panel.add_child(vbox)

	var title := Label.new()
	title.text = "选择行动"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 8)
	vbox.add_child(title)

	var info := Label.new()
	info.text = "%s 可移动范围 %d 格，攻击范围 %d-%d 格" % [u.unit_name, u.move_range, u.min_attack_range, u.max_attack_range]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 15)
	info.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0, 0.9))
	vbox.add_child(info)

	if can_attack:
		var btn_move := Button.new()
		btn_move.text = "移动"
		btn_move.custom_minimum_size = Vector2(180, 52)
		btn_move.add_theme_font_size_override("font_size", 20)
		btn_move.pressed.connect(func(): _on_choice_move(u))
		vbox.add_child(btn_move)

		var btn_attack := Button.new()
		btn_attack.text = "攻击"
		btn_attack.custom_minimum_size = Vector2(180, 52)
		btn_attack.add_theme_font_size_override("font_size", 20)
		btn_attack.pressed.connect(func(): _on_choice_attack(u))
		vbox.add_child(btn_attack)
	else:
		var btn_move := Button.new()
		btn_move.text = "移动"
		btn_move.custom_minimum_size = Vector2(180, 52)
		btn_move.add_theme_font_size_override("font_size", 20)
		btn_move.pressed.connect(func(): _on_choice_move(u))
		vbox.add_child(btn_move)

	# 关闭按钮
	var btn_close := Button.new()
	btn_close.text = "关闭"
	btn_close.custom_minimum_size = Vector2(180, 52)
	btn_close.add_theme_font_size_override("font_size", 20)
	btn_close.pressed.connect(func(): _hide_move_action_menu())
	vbox.add_child(btn_close)


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.09, 0.92)
	sb.border_color = Color(0.75, 0.68, 0.45, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(20)
	return sb


func _on_choice_move(u: TacticalUnit) -> void:
	_hide_move_action_menu()
	_enter_move_select(u)


func _on_choice_attack(u: TacticalUnit) -> void:
	_hide_move_action_menu()
	# 直接进入攻击目标选择
	active_unit = u
	state = State.TARGET_SELECT
	cursor_pos = u.grid_pos
	camera.focus_on(grid.tile_to_world(u.grid_pos))
	_refresh()


func _hide_move_action_menu() -> void:
	queue_free()


func _on_cancel() -> void:
	match state:
		State.MOVE_SELECT:
			active_unit = null
			state = State.IDLE
			hud.set_message("Select one of your units.")
			_refresh()
		State.ACTION_MENU:
			_undo_move()
		State.TARGET_SELECT:
			state = State.ACTION_MENU
			_open_action_menu()
			_refresh()


# --------------------------------------------------------------------------
# Move / act
# --------------------------------------------------------------------------

func _enter_move_select(u: TacticalUnit) -> void:
	active_unit = u
	active_origin = u.grid_pos
	reachable = GridPathfinder.compute(grid, u.grid_pos, u.move_range, _blocked_for(u))
	valid_destinations = []
	for t in GridPathfinder.tiles(reachable):
		if not occupied.has(t):
			valid_destinations.append(t)
	state = State.MOVE_SELECT
	hud.set_message("Choose a destination, then confirm.")
	_refresh()


func _perform_move(dest: Vector2i) -> void:
	state = State.BUSY
	var path := GridPathfinder.build_path(reachable, dest)
	occupied.erase(active_unit.grid_pos)
	await active_unit.move_along_path(grid, path)
	occupied[active_unit.grid_pos] = active_unit
	state = State.ACTION_MENU
	_open_action_menu()
	_refresh()


func _undo_move() -> void:
	occupied.erase(active_unit.grid_pos)
	active_unit.grid_pos = active_origin
	active_unit.position = grid.tile_to_world(active_origin)
	occupied[active_origin] = active_unit
	state = State.MOVE_SELECT
	hud.hide_action_menu()
	hud.set_message("Choose a destination, then confirm.")
	_refresh()


func _open_action_menu() -> void:
	attack_tiles = tiles_in_range(active_unit.grid_pos, active_unit.min_attack_range, active_unit.max_attack_range)
	var enemies_in_range := false
	for t in attack_tiles:
		var tu := get_unit_at(t)
		if tu != null and tu.team == TacticalUnit.Team.ENEMY:
			enemies_in_range = true
			break
	var options: Array = []
	if enemies_in_range:
		options.append({"id": "attack", "label": "Attack"})
	options.append({"id": "wait", "label": "Wait"})
	hud.set_message("Choose an action.")
	hud.show_action_menu(options)


func _on_action_selected(id: String) -> void:
	if state != State.ACTION_MENU:
		return
	if id == "attack":
		state = State.TARGET_SELECT
		hud.set_message("Choose a target, then confirm.")
		# Snap the cursor toward the first available enemy.
		for t in attack_tiles:
			var tu := get_unit_at(t)
			if tu != null and tu.team == TacticalUnit.Team.ENEMY:
				cursor_pos = t
				camera.focus_on(grid.tile_to_world(t))
				break
		_refresh()
	elif id == "wait":
		_finish_unit_action()


# --------------------------------------------------------------------------
# Combat
# --------------------------------------------------------------------------

func _do_attack(attacker: TacticalUnit, defender: TacticalUnit) -> void:
	state = State.BUSY
	hud.hide_action_menu()
	await _resolve_combat(attacker, defender)
	_finish_unit_action()


func _resolve_combat(attacker: TacticalUnit, defender: TacticalUnit) -> void:
	# Lunge animation.
	var start := attacker.position
	var dir := (defender.position - start)
	dir.y = 0.0
	if dir.length_squared() > 0.0:
		dir = dir.normalized()
		attacker.rotation.y = atan2(dir.x, dir.z)
	var tw := create_tween()
	tw.tween_property(attacker, "position", start + dir * 0.7, 0.12)
	tw.tween_property(attacker, "position", start, 0.12)
	await tw.finished

	var dmg := maxi(1, attacker.attack_power - defender.defense)
	defender.take_damage(dmg)
	defender.show_damage(dmg, Color(1, 0.85, 0.25))
	hud.set_message("%s hits %s for %d damage!" % [attacker.unit_name, defender.unit_name, dmg])
	await get_tree().create_timer(0.35).timeout

	if not defender.is_alive:
		await _kill(defender)
		_check_game_over()
		return

	# Counter-attack.
	if defender.can_attack(attacker.grid_pos):
		var cdmg := maxi(1, defender.attack_power - attacker.defense)
		attacker.take_damage(cdmg)
		attacker.show_damage(cdmg, Color(0.9, 0.4, 0.3))
		hud.set_message("%s counters %s for %d damage!" % [defender.unit_name, attacker.unit_name, cdmg])
		await get_tree().create_timer(0.35).timeout
		if not attacker.is_alive:
			await _kill(attacker)
	_check_game_over()


func _kill(u: TacticalUnit) -> void:
	occupied.erase(u.grid_pos)
	units.erase(u)
	await u.die()


func _check_game_over() -> bool:
	if state == State.GAME_OVER:
		return true
	if alive_units(TacticalUnit.Team.ENEMY).is_empty():
		state = State.GAME_OVER
		hud.hide_action_menu()
		hud.set_message("")
		hud.show_game_over("VICTORY")
		return true
	if alive_units(TacticalUnit.Team.PLAYER).is_empty():
		state = State.GAME_OVER
		hud.hide_action_menu()
		hud.set_message("")
		hud.show_game_over("DEFEAT")
		return true
	return false


# --------------------------------------------------------------------------
# Enemy AI
# --------------------------------------------------------------------------

func _run_enemy_turn() -> void:
	await get_tree().create_timer(0.4).timeout
	for u in units.duplicate():
		if state == State.GAME_OVER or state != State.ENEMY_TURN:
			return
		if not u.is_alive or u.team != TacticalUnit.Team.ENEMY:
			continue
		await _enemy_act(u)
		await get_tree().create_timer(0.18).timeout
	if state == State.GAME_OVER:
		return
	turn += 1
	_begin_player_turn()


func _enemy_act(u: TacticalUnit) -> void:
	var targets := alive_units(TacticalUnit.Team.PLAYER)
	if targets.is_empty():
		return
	var target := _nearest(u, targets)
	cursor_pos = u.grid_pos
	_refresh()

	if u.can_attack(target.grid_pos):
		await get_tree().create_timer(0.15).timeout
		await _resolve_combat(u, target)
		return

	# Move toward a tile from which the target can be attacked.
	var reach := GridPathfinder.compute(grid, u.grid_pos, u.move_range, _blocked_for(u))
	var best: Vector2i = u.grid_pos
	var best_score := 1 << 30
	for t in GridPathfinder.tiles(reach):
		var d := GridPathfinder.manhattan(t, target.grid_pos)
		var score := d
		if u.can_attack_from(t, target.grid_pos):
			score = d - 100  # strongly prefer an attacking tile
		if score < best_score:
			best_score = score
			best = t

	if best != u.grid_pos:
		var path := GridPathfinder.build_path(reach, best)
		occupied.erase(u.grid_pos)
		await u.move_along_path(grid, path)
		occupied[u.grid_pos] = u
		cursor_pos = u.grid_pos
		_refresh()

	if u.can_attack(target.grid_pos):
		await get_tree().create_timer(0.15).timeout
		await _resolve_combat(u, target)


func _nearest(from: TacticalUnit, options: Array[TacticalUnit]) -> TacticalUnit:
	var best := options[0]
	var best_d := from.distance_to(best.grid_pos)
	for o in options:
		var d := from.distance_to(o.grid_pos)
		if d < best_d:
			best = o
			best_d = d
	return best
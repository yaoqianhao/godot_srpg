class_name SRPGGame
extends Node3D
## Main tactical controller: turn flow, player command flow, combat resolution, enemy AI.

enum State { IDLE, COMMAND_MENU, MOVE_SELECT, ACTION_MENU, TARGET_SELECT, BUSY, ENEMY_TURN, GAME_OVER }

const UNIT_SCENE := preload("res://scenes/unit.tscn")
const WORLD_MAP_SCENE := "res://scenes/world_map.tscn"

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

# Command-menu and targeting bookkeeping
var _submenu: String = ""                # "" | "skill" | "magic" | "item"
var _target_action: String = ""          # attack | bash | pierce | fire | heal | potion
var _target_mode: String = "enemy"       # "enemy" | "ally"
var _target_return: String = "command"   # command | action | skill | magic | item


func _ready() -> void:
	grid.build()
	_spawn_armies()
	camera.current = true
	var center := Vector2i(int(grid.width * 0.5), int(grid.depth * 0.5))
	camera.focus_on(grid.tile_to_world(center))
	camera.snap()
	cursor_pos = center
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
			u._is_defending = false
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
			u._is_defending = false
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
	_submenu = ""
	_target_action = ""
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
		State.COMMAND_MENU:
			pass  # no overlays while the command menu is open
		State.MOVE_SELECT:
			grid.draw_overlay(valid_destinations, COLOR_MOVE, 0.05, 0.9)
			if cursor_pos in valid_destinations:
				var path := GridPathfinder.build_path(reachable, cursor_pos)
				grid.draw_overlay(path, COLOR_PATH, 0.07, 0.42)
		State.ACTION_MENU, State.TARGET_SELECT:
			grid.draw_overlay(attack_tiles, COLOR_ATTACK, 0.05, 0.9)
			if state == State.TARGET_SELECT:
				var want_enemy := _target_mode == "enemy"
				for pos in attack_tiles:
					var tu := get_unit_at(pos)
					if tu == null:
						continue
					if (tu.team == TacticalUnit.Team.ENEMY) == want_enemy:
						grid.draw_overlay([pos], COLOR_TARGET, 0.06, 0.7)

	grid.draw_cursor(cursor_pos)
	_update_info_panel()


func _update_info_panel() -> void:
	var u: TacticalUnit = null
	if active_unit != null and (state == State.COMMAND_MENU or state == State.MOVE_SELECT or state == State.ACTION_MENU or state == State.TARGET_SELECT):
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

func _input(event: InputEvent) -> void:
	# Manual hit-testing for the HUD menus (their buttons are visual-only).
	# Runs before GUI propagation and before _unhandled_input tile picking;
	# consumes what it handles so there is no double activation.
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var id := hud.menu_option_at(event.position)
			if id != "":
				_on_action_selected(id)
				get_viewport().set_input_as_handled()
				return
			if hud.is_game_over_visible():
				var choice := hud.game_over_option_at(event.position)
				if choice != "":
					# Consume BEFORE the scene change: reload/change frees this
					# node mid-_input, after which get_viewport() is null.
					get_viewport().set_input_as_handled()
					match choice:
						"restart":
							get_tree().reload_current_scene()
						"menu":
							get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
						"map":
							_go_world_map()
				return
		elif event.button_index == MOUSE_BUTTON_RIGHT and hud.is_menu_visible():
			_on_cancel()
			get_viewport().set_input_as_handled()
			return
	elif event is InputEventMouseMotion:
		var hover := hud.menu_option_at(event.position)
		hud.highlight_option(hover)
		if hover != "":
			get_viewport().set_input_as_handled()


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
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_on_cancel()
			get_viewport().set_input_as_handled()
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
			# 玩家点击己方未行动单位 → 打开指令菜单
			if u != null and u.team == TacticalUnit.Team.PLAYER and not u.has_acted:
				_enter_command_menu(u)
		State.COMMAND_MENU:
			# 点击另一个己方未行动单位 → 切换选中
			var u2 := get_unit_at(cursor_pos)
			if u2 != null and u2.team == TacticalUnit.Team.PLAYER and not u2.has_acted and u2 != active_unit:
				_enter_command_menu(u2)
		State.MOVE_SELECT:
			if cursor_pos in valid_destinations:
				_perform_move(cursor_pos)
		State.TARGET_SELECT:
			_confirm_target()


func _on_cancel() -> void:
	match state:
		State.COMMAND_MENU:
			if _submenu != "":
				_back_to_command_menu()
			else:
				active_unit = null
				state = State.IDLE
				hud.hide_action_menu()
				hud.set_message("Select one of your units.")
				_refresh()
		State.MOVE_SELECT:
			_enter_command_menu(active_unit)
		State.ACTION_MENU:
			_undo_move()
			_enter_command_menu(active_unit)
		State.TARGET_SELECT:
			_reopen_after_target_cancel()


# --------------------------------------------------------------------------
# Move / act
# --------------------------------------------------------------------------

func _enter_command_menu(u: TacticalUnit) -> void:
	active_unit = u
	active_origin = u.grid_pos
	_submenu = ""
	_target_action = ""
	state = State.COMMAND_MENU
	hud.set_message("%s：请选择指令" % u.unit_name)
	_show_command_menu()
	_refresh()


func _show_command_menu() -> void:
	_submenu = ""
	hud.show_action_menu([
		{"id": "move", "label": "移动 Move"},
		{"id": "attack", "label": "攻击 Attack"},
		{"id": "defend", "label": "防御 Defend"},
		{"id": "skill", "label": "技能 Skill"},
		{"id": "magic", "label": "魔法 Magic"},
		{"id": "item", "label": "道具 Item"},
		{"id": "wait", "label": "等待 Wait"},
	], "指令 Command")


func _choose_move() -> void:
	hud.hide_action_menu()
	reachable = GridPathfinder.compute(grid, active_unit.grid_pos, active_unit.move_range, _blocked_for(active_unit))
	valid_destinations = []
	for t in GridPathfinder.tiles(reachable):
		if not occupied.has(t):
			valid_destinations.append(t)
	state = State.MOVE_SELECT
	hud.set_message("选择移动位置，然后确认（Esc 返回指令菜单）")
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
	# Restore the unit to its pre-move tile; the caller decides what to show next.
	occupied.erase(active_unit.grid_pos)
	active_unit.grid_pos = active_origin
	active_unit.position = grid.tile_to_world(active_origin)
	occupied[active_origin] = active_unit


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
		options.append({"id": "attack", "label": "攻击 Attack"})
	options.append({"id": "defend", "label": "防御 Defend"})
	options.append({"id": "wait", "label": "等待 Wait"})
	hud.set_message("选择行动")
	hud.show_action_menu(options, "行动 Action")


func _on_action_selected(id: String) -> void:
	if state != State.COMMAND_MENU and state != State.ACTION_MENU:
		return
	match id:
		"move":
			_choose_move()
		"attack":
			_choose_attack()
		"defend":
			_do_defend()
		"skill":
			_open_submenu("skill")
		"magic":
			_open_submenu("magic")
		"item":
			_open_submenu("item")
		"wait":
			_finish_unit_action()
		"back":
			_back_to_command_menu()
		"skill_bash":
			_choose_target("bash")
		"skill_pierce":
			_choose_target("pierce")
		"magic_fire":
			_choose_target("fire")
		"magic_heal":
			_choose_target("heal")
		"item_potion":
			_choose_target("potion")


# --------------------------------------------------------------------------
# Command menu
# --------------------------------------------------------------------------

func _choose_attack() -> void:
	attack_tiles = tiles_in_range(active_unit.grid_pos, active_unit.min_attack_range, active_unit.max_attack_range)
	if not _enemies_in(attack_tiles):
		hud.set_message("攻击范围内没有敌人。")
		if state == State.COMMAND_MENU:
			_show_command_menu()
		else:
			_open_action_menu()
		return
	_target_action = "attack"
	_target_mode = "enemy"
	_target_return = "command" if state == State.COMMAND_MENU else "action"
	hud.hide_action_menu()
	_enter_target_select()


func _enemies_in(tiles: Array[Vector2i]) -> bool:
	for t in tiles:
		var tu := get_unit_at(t)
		if tu != null and tu.team == TacticalUnit.Team.ENEMY:
			return true
	return false


func _enter_target_select() -> void:
	state = State.TARGET_SELECT
	hud.set_message("选择目标，然后确认（Esc 返回）")
	var first: Variant = null
	for t in attack_tiles:
		var tu := get_unit_at(t)
		if tu == null:
			continue
		var ok := (tu.team == TacticalUnit.Team.ENEMY) if _target_mode == "enemy" else (tu.team == TacticalUnit.Team.PLAYER)
		if ok:
			first = t
			break
	if first != null:
		cursor_pos = first
		camera.focus_on(grid.tile_to_world(first))
	_refresh()


func _confirm_target() -> void:
	var target := get_unit_at(cursor_pos)
	if target == null:
		return
	if _target_mode == "enemy":
		if target.team != TacticalUnit.Team.ENEMY or not active_unit.can_attack(cursor_pos):
			return
		match _target_action:
			"attack":
				_do_attack(active_unit, target)
			"bash", "pierce":
				_do_skill_attack(_target_action, target)
			"fire":
				_do_magic_attack(target)
	else:
		var is_self := target == active_unit
		if target.team != TacticalUnit.Team.PLAYER or not (is_self or active_unit.can_attack(cursor_pos)):
			return
		if _target_action == "heal":
			_do_heal(target, "heal", 12, "治疗术")
		elif _target_action == "potion":
			_do_heal(target, "potion", 15, "药水")


func _do_defend() -> void:
	active_unit._is_defending = true
	hud.set_message("%s 进入防御状态：受到伤害减半，持续到下次行动。" % active_unit.unit_name)
	_finish_unit_action()


func _open_submenu(kind: String) -> void:
	_submenu = kind
	var options: Array = []
	if kind == "skill":
		if active_unit.ability_uses["bash"] > 0:
			options.append({"id": "skill_bash", "label": "猛击 Bash（+5 伤害，剩 %d）" % active_unit.ability_uses["bash"]})
		if active_unit.ability_uses["pierce"] > 0:
			options.append({"id": "skill_pierce", "label": "破甲 Pierce（无视防御，剩 %d）" % active_unit.ability_uses["pierce"]})
	elif kind == "magic":
		if active_unit.ability_uses["fire"] > 0:
			options.append({"id": "magic_fire", "label": "火球术 Fireball（剩 %d）" % active_unit.ability_uses["fire"]})
		if active_unit.ability_uses["heal"] > 0:
			options.append({"id": "magic_heal", "label": "治疗术 Heal（友军 +12，剩 %d）" % active_unit.ability_uses["heal"]})
	elif kind == "item":
		if active_unit.ability_uses["potion"] > 0:
			options.append({"id": "item_potion", "label": "药水 Potion（友军 +15，剩 %d）" % active_unit.ability_uses["potion"]})
	options.append({"id": "back", "label": "返回 Back"})
	var title := "技能 Skill" if kind == "skill" else ("魔法 Magic" if kind == "magic" else "道具 Item")
	hud.set_message("选择%s" % title.split(" ")[0])
	hud.show_action_menu(options, title)


func _back_to_command_menu() -> void:
	_submenu = ""
	state = State.COMMAND_MENU
	_show_command_menu()
	_refresh()


func _choose_target(action: String) -> void:
	_target_action = action
	if action == "heal" or action == "potion":
		# Allies (including self) within attack range.
		_target_mode = "ally"
		attack_tiles = tiles_in_range(active_unit.grid_pos, active_unit.min_attack_range, active_unit.max_attack_range)
		if not attack_tiles.has(active_unit.grid_pos):
			attack_tiles.append(active_unit.grid_pos)
	else:
		_target_mode = "enemy"
		attack_tiles = tiles_in_range(active_unit.grid_pos, active_unit.min_attack_range, active_unit.max_attack_range)
		if not _enemies_in(attack_tiles):
			hud.set_message("范围内没有可施放的目标。")
			_open_submenu(_submenu)
			return
	_target_return = _submenu
	hud.hide_action_menu()
	_enter_target_select()


func _do_skill_attack(which: String, target: TacticalUnit) -> void:
	state = State.BUSY
	var label := "猛击" if which == "bash" else "破甲"
	var override := active_unit.attack_power
	if which == "bash":
		override = active_unit.attack_power + 5 - target.defense
	# pierce ignores defense entirely: override stays attack_power
	override = maxi(1, override)
	active_unit.ability_uses[which] -= 1
	hud.set_message("%s 使用 %s！" % [active_unit.unit_name, label])
	await _resolve_combat(active_unit, target, override)
	_finish_unit_action()


func _do_magic_attack(target: TacticalUnit) -> void:
	state = State.BUSY
	active_unit.ability_uses["fire"] -= 1
	hud.set_message("%s 施放火球术！" % active_unit.unit_name)
	await _resolve_combat(active_unit, target, maxi(1, active_unit.attack_power + 3 - target.defense))
	_finish_unit_action()


func _do_heal(target: TacticalUnit, kind: String, amount: int, label: String) -> void:
	state = State.BUSY
	active_unit.ability_uses[kind] -= 1
	hud.set_message("%s 对 %s 使用%s！" % [active_unit.unit_name, target.unit_name, label])
	target.heal(amount)
	await get_tree().create_timer(0.4).timeout
	_finish_unit_action()


func _reopen_after_target_cancel() -> void:
	match _target_return:
		"command":
			_enter_command_menu(active_unit)
		"action":
			state = State.ACTION_MENU
			_open_action_menu()
			_refresh()
		"skill", "magic", "item":
			state = State.COMMAND_MENU
			_open_submenu(_target_return)
			_refresh()


# --------------------------------------------------------------------------
# Combat
# --------------------------------------------------------------------------

func _do_attack(attacker: TacticalUnit, defender: TacticalUnit) -> void:
	state = State.BUSY
	hud.hide_action_menu()
	await _resolve_combat(attacker, defender)
	_finish_unit_action()


func _resolve_combat(attacker: TacticalUnit, defender: TacticalUnit, damage_override: int = -1) -> void:
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

	var dmg := damage_override if damage_override >= 0 else maxi(1, attacker.attack_power - defender.defense)
	if defender._is_defending:
		dmg = maxi(1, dmg >> 1)  # 防御姿态：伤害减半
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
		hud.show_game_over("胜利 VICTORY", true)
		return true
	if alive_units(TacticalUnit.Team.PLAYER).is_empty():
		state = State.GAME_OVER
		hud.hide_action_menu()
		hud.set_message("")
		hud.show_game_over("败北 DEFEAT", false)
		return true
	return false


# --------------------------------------------------------------------------
# Chapter handoff (victory -> world map)
# --------------------------------------------------------------------------

## Package the surviving player army and travel to the world map.
func _go_world_map() -> void:
	WorldMap.incoming_party = _export_party()
	WorldMap.incoming_chapter = 1
	WorldMap.incoming_turns = turn
	get_tree().change_scene_to_file(WORLD_MAP_SCENE)


func _export_party() -> Array:
	var out: Array = []
	for u in units:
		if u.team == TacticalUnit.Team.PLAYER and u.is_alive:
			out.append({
				"name": u.unit_name,
				"hp": u.hp,
				"max_hp": u.max_hp,
				"atk": u.attack_power,
				"def": u.defense,
				"mov": u.move_range,
				"minrng": u.min_attack_range,
				"maxrng": u.max_attack_range,
				"uses": u.ability_uses.duplicate(true),
			})
	return out


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
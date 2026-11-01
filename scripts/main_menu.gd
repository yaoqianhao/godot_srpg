class_name MainMenu
extends Node3D
## Title screen + opening cinematic.
## The backdrop is the real battlefield (TacticalGrid + units) slowly orbiting,
## so the menu and the game share the same world and art.

const UNIT_SCENE := preload("res://scenes/unit.tscn")
const GAME_SCENE := "res://scenes/game.tscn"

enum Phase { MENU, INTRO }

@onready var grid: TacticalGrid = $Diorama
@onready var camera: Camera3D = $Camera
@onready var units_root: Node3D = $Units

var phase: Phase = Phase.MENU
var _orbit: float = 0.0
var _center: Vector3 = Vector3(11, 0, 9)
var _look_target: Node3D

# UI (built in code)
var _ui: CanvasLayer
var _title: Label
var _subtitle: Label
var _menu_box: HBoxContainer
var _options_panel: PanelContainer
var _volume_slider: HSlider
var _start_btn: Button
var _options_btn: Button
var _quit_btn: Button
var _back_btn: Button
var _fullscreen_check: CheckButton
var _focus_index: int = 0
var _caption: Label
var _title_card: Label
var _fade: ColorRect
var _hint: Label


func _ready() -> void:
	grid.build()
	_center = Vector3(
		(grid.width - 1) * TacticalGrid.TILE_SIZE * 0.5,
		0.0,
		(grid.depth - 1) * TacticalGrid.TILE_SIZE * 0.5
	)
	_look_target = Node3D.new()
	add_child(_look_target)
	_look_target.global_position = _center
	_spawn_diorama()
	_build_ui()
	_update_orbit()
	_refresh_button_visuals()


func _process(delta: float) -> void:
	if phase == Phase.MENU:
		_orbit += delta * 0.14
		_update_orbit()
	elif phase == Phase.INTRO:
		camera.look_at(_look_target.global_position, Vector3.UP)


func _update_orbit() -> void:
	var r := 20.0
	camera.global_position = _center + Vector3(sin(_orbit) * r, 19.0, cos(_orbit) * r)
	camera.look_at(_center + Vector3(0.0, 0.5, 0.0), Vector3.UP)


func _spawn_diorama() -> void:
	var data := [
		{"team": 0, "pos": Vector2i(3, 8), "name": "Knight"},
		{"team": 0, "pos": Vector2i(6, 8), "name": "Archer"},
		{"team": 0, "pos": Vector2i(9, 8), "name": "Mage"},
		{"team": 1, "pos": Vector2i(2, 1), "name": "Goblin"},
		{"team": 1, "pos": Vector2i(5, 1), "name": "Goblin"},
		{"team": 1, "pos": Vector2i(9, 1), "name": "Sniper"},
	]
	for d in data:
		var u: TacticalUnit = UNIT_SCENE.instantiate()
		u.team = TacticalUnit.Team.PLAYER if d["team"] == 0 else TacticalUnit.Team.ENEMY
		u.unit_name = d["name"]
		units_root.add_child(u)
		u.grid_pos = d["pos"]
		u.position = grid.tile_to_world(d["pos"])
		u.initialize()


# --------------------------------------------------------------------------
# UI construction
# --------------------------------------------------------------------------

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.09, 0.88)
	sb.border_color = Color(0.75, 0.68, 0.45, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(20)
	return sb


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(210, 56)
	b.add_theme_font_size_override("font_size", 22)
	# Purely visual: menu input is driven manually in _input().
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.focus_mode = Control.FOCUS_NONE
	return b


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)

	# Title + subtitle
	_title = Label.new()
	_title.anchor_left = 0.0
	_title.anchor_right = 1.0
	_title.offset_top = 64
	_title.offset_bottom = 158
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.text = "战 术 传 奇"
	_title.add_theme_font_size_override("font_size", 72)
	_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_title.add_theme_constant_override("outline_size", 10)
	_ui.add_child(_title)

	_subtitle = Label.new()
	_subtitle.anchor_left = 0.0
	_subtitle.anchor_right = 1.0
	_subtitle.offset_top = 160
	_subtitle.offset_bottom = 196
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.text = "T A C T I C A L   L E G A C Y"
	_subtitle.add_theme_font_size_override("font_size", 22)
	_subtitle.add_theme_color_override("font_color", Color(0.82, 0.88, 1.0, 0.9))
	_subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_subtitle.add_theme_constant_override("outline_size", 6)
	_ui.add_child(_subtitle)

	# Menu buttons
	_menu_box = HBoxContainer.new()
	_menu_box.anchor_left = 0.5
	_menu_box.anchor_right = 0.5
	_menu_box.anchor_top = 1.0
	_menu_box.anchor_bottom = 1.0
	_menu_box.offset_left = -360
	_menu_box.offset_right = 360
	_menu_box.offset_top = -156
	_menu_box.offset_bottom = -96
	_menu_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_box.add_theme_constant_override("separation", 20)
	_menu_box.mouse_filter = Control.MOUSE_FILTER_PASS
	_ui.add_child(_menu_box)

	_start_btn = _make_button("开始游戏")
	_start_btn.pressed.connect(_on_start_pressed)
	_menu_box.add_child(_start_btn)

	_options_btn = _make_button("设置")
	_options_btn.pressed.connect(func(): _set_options_visible(true))
	_menu_box.add_child(_options_btn)

	_quit_btn = _make_button("退出游戏")
	_quit_btn.pressed.connect(_quit_game)
	_menu_box.add_child(_quit_btn)

	# Options panel
	_options_panel = PanelContainer.new()
	_options_panel.add_theme_stylebox_override("panel", _panel_style())
	_options_panel.anchor_left = 0.5
	_options_panel.anchor_right = 0.5
	_options_panel.anchor_top = 0.5
	_options_panel.anchor_bottom = 0.5
	_options_panel.offset_left = -220
	_options_panel.offset_right = 220
	_options_panel.offset_top = -150
	_options_panel.offset_bottom = 150
	_options_panel.visible = false
	_ui.add_child(_options_panel)

	var opt_box := VBoxContainer.new()
	opt_box.add_theme_constant_override("separation", 18)
	_options_panel.add_child(opt_box)

	var opt_title := Label.new()
	opt_title.text = "设置"
	opt_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opt_title.add_theme_font_size_override("font_size", 30)
	opt_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	opt_box.add_child(opt_title)

	var vol_label := Label.new()
	vol_label.text = "主音量"
	vol_label.add_theme_font_size_override("font_size", 20)
	opt_box.add_child(vol_label)

	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.01
	_volume_slider.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	_volume_slider.custom_minimum_size = Vector2(360, 28)
	_volume_slider.value_changed.connect(_on_volume_changed)
	opt_box.add_child(_volume_slider)

	var fs_row := HBoxContainer.new()
	fs_row.add_theme_constant_override("separation", 16)
	opt_box.add_child(fs_row)

	var fs_label := Label.new()
	fs_label.text = "全屏"
	fs_label.add_theme_font_size_override("font_size", 20)
	fs_row.add_child(fs_label)

	_fullscreen_check = CheckButton.new()
	_fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	fs_row.add_child(_fullscreen_check)

	_back_btn = _make_button("返回")
	_back_btn.pressed.connect(func(): _set_options_visible(false))
	opt_box.add_child(_back_btn)

	# Intro caption + title card
	_caption = Label.new()
	_caption.anchor_left = 0.0
	_caption.anchor_right = 1.0
	_caption.anchor_top = 0.78
	_caption.anchor_bottom = 0.78
	_caption.offset_top = -34
	_caption.offset_bottom = 34
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 34)
	_caption.add_theme_color_override("font_color", Color(1, 1, 1))
	_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_caption.add_theme_constant_override("outline_size", 8)
	_caption.modulate.a = 0.0
	_ui.add_child(_caption)

	_title_card = Label.new()
	_title_card.anchor_left = 0.0
	_title_card.anchor_right = 1.0
	_title_card.anchor_top = 0.0
	_title_card.anchor_bottom = 1.0
	_title_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_card.add_theme_font_size_override("font_size", 96)
	_title_card.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))
	_title_card.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_title_card.add_theme_constant_override("outline_size", 12)
	_title_card.modulate.a = 0.0
	_ui.add_child(_title_card)

	# Hint + version
	_hint = Label.new()
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = -300
	_hint.offset_right = 300
	_hint.offset_top = -52
	_hint.offset_bottom = -20
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.text = "方向键 / 鼠标：选择     Enter / 左键：确认"
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 0.7))
	_ui.add_child(_hint)

	# Non-interactive labels must not swallow mouse input for the buttons.
	for lbl in [_title, _subtitle, _caption, _title_card, _hint]:
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Fade layer (last = on top)
	_fade = ColorRect.new()
	_fade.anchor_right = 1.0
	_fade.anchor_bottom = 1.0
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_fade)


# --------------------------------------------------------------------------
# Behaviour
# --------------------------------------------------------------------------

func _set_options_visible(on: bool) -> void:
	_options_panel.visible = on
	_menu_box.visible = not on
	_title.visible = not on
	_subtitle.visible = not on
	_hint.visible = not on
	if on:
		_volume_slider.grab_focus()
	else:
		_refresh_button_visuals()


func _on_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(value, 0.0001)))


func _on_fullscreen_toggled(on: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
	)


func _quit_game() -> void:
	get_tree().quit()


## Menu input is driven manually from _input() so it never depends on Godot's
## GUI mouse picking / mouse-filter layering. Runs before the GUI, and consumes
## what it handles, so there is no double activation.
func _input(event: InputEvent) -> void:
	if phase != Phase.MENU:
		return

	if _options_panel.visible:
		if event.is_action_pressed("ui_cancel"):
			_set_options_visible(false)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _back_btn.get_global_rect().has_point(event.position):
				_set_options_visible(false)
				get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		var hovered := _button_at(event.position)
		if hovered != -1 and hovered != _focus_index:
			_focus_index = hovered
			_refresh_button_visuals()
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := _button_at(event.position)
		if i != -1:
			_focus_index = i
			_refresh_button_visuals()
			_activate_menu(i)
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_down") or event.is_action_pressed("ui_right"):
		_focus_index = (_focus_index + 1) % _menu_buttons().size()
		_refresh_button_visuals()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_left"):
		_focus_index = (_focus_index - 1 + _menu_buttons().size()) % _menu_buttons().size()
		_refresh_button_visuals()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_activate_menu(_focus_index)
		get_viewport().set_input_as_handled()


func _menu_buttons() -> Array:
	return [_start_btn, _options_btn, _quit_btn]


func _button_at(pos: Vector2) -> int:
	var btns := _menu_buttons()
	for i in btns.size():
		if btns[i].get_global_rect().has_point(pos):
			return i
	return -1


func _activate_menu(i: int) -> void:
	match i:
		0:
			_on_start_pressed()
		1:
			_set_options_visible(true)
		2:
			_quit_game()


func _refresh_button_visuals() -> void:
	var btns := _menu_buttons()
	for i in btns.size():
		btns[i].modulate = Color(1.3, 1.3, 1.25, 1.0) if i == _focus_index else Color(1, 1, 1, 1)


func _on_start_pressed() -> void:
	if phase != Phase.MENU:
		return
	_play_intro()


func _play_intro() -> void:
	phase = Phase.INTRO
	_menu_box.visible = false
	_title.visible = false
	_subtitle.visible = false
	_options_panel.visible = false
	_hint.visible = false

	_fade.color.a = 1.0
	await _fade_to(0.0, 0.9)
	_start_camera_timeline()
	await _caption_line("边境烽烟再起……", 1.9)
	await _caption_line("敌军已在山丘之上列阵。", 1.9)
	await _caption_line("击溃他们，守住这最后的防线。", 2.1)
	await _show_title_card("战 术 传 奇", 2.0)
	await _fade_to(1.0, 0.8)
	get_tree().change_scene_to_file(GAME_SCENE)


func _start_camera_timeline() -> void:
	# (eye position, look-at target, duration) keyframes.
	var kfs := [
		{"eye": Vector3(6.0, 4.5, 27.0), "look": Vector3(12.0, 1.0, 15.0), "t": 2.4},
		{"eye": Vector3(12.0, 8.5, 21.0), "look": Vector3(11.0, 1.0, 6.0), "t": 2.4},
		{"eye": Vector3(27.0, 17.0, 24.0), "look": Vector3(11.0, 0.5, 9.0), "t": 3.0},
		{"eye": Vector3(12.0, 14.0, 23.0), "look": Vector3(11.0, 1.0, 9.0), "t": 2.2},
	]
	camera.global_position = kfs[0]["eye"]
	_look_target.global_position = kfs[0]["look"]

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for kf in kfs:
		tw.set_parallel(true)
		tw.tween_property(camera, "global_position", kf["eye"], kf["t"])
		tw.tween_property(_look_target, "global_position", kf["look"], kf["t"])
		tw.chain()


func _fade_to(target: float, dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", target, dur)
	await tw.finished


func _caption_line(text: String, hold: float) -> void:
	_caption.text = text
	var tin := create_tween()
	tin.tween_property(_caption, "modulate:a", 1.0, 0.35)
	await tin.finished
	await get_tree().create_timer(hold).timeout
	var tout := create_tween()
	tout.tween_property(_caption, "modulate:a", 0.0, 0.35)
	await tout.finished


func _show_title_card(text: String, hold: float) -> void:
	_title_card.text = text
	var tin := create_tween()
	tin.tween_property(_title_card, "modulate:a", 1.0, 0.5)
	await tin.finished
	await get_tree().create_timer(hold).timeout
	var tout := create_tween()
	tout.tween_property(_title_card, "modulate:a", 0.0, 0.5)
	await tout.finished
class_name HUD
extends CanvasLayer
## All on-screen UI, built in code: turn banner, unit info, command menu, game-over.

var _turn_label: Label
var _help_label: Label
var _info_label: Label
var _message_label: Label
var _menu_panel: PanelContainer
var _menu_box: VBoxContainer
var _overlay: Control
var _overlay_label: Label

# Battle command menu: visual-only buttons; input via manual hit-testing (game.gd _input).
var _menu_buttons: Array[Button] = []
var _menu_ids: Array[String] = []
var _menu_hover: String = ""
var _overlay_buttons: Array[Button] = []
var _overlay_ids: Array[String] = []
var _overlay_box: VBoxContainer = null


func _ready() -> void:
	_build()


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.10, 0.18, 0.9)
	sb.border_color = Color(0.7, 0.5, 0.3, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	return sb


func _place(c: Control, l: float, t: float, r: float, b: float) -> void:
	c.anchor_left = l
	c.anchor_top = t
	c.anchor_right = r
	c.anchor_bottom = b


func _build() -> void:
	# --- Turn banner (top center) ---
	_turn_label = Label.new()
	_place(_turn_label, 0.0, 0.0, 1.0, 0.0)
	_turn_label.offset_top = 16
	_turn_label.offset_bottom = 66
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_label.add_theme_font_size_override("font_size", 30)
	_turn_label.add_theme_color_override("font_color", Color(1, 0.96, 0.8))
	_turn_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_turn_label.add_theme_constant_override("outline_size", 6)
	add_child(_turn_label)

	# --- Help / controls (top right) ---
	_help_label = Label.new()
	_place(_help_label, 1.0, 0.0, 1.0, 0.0)
	_help_label.offset_left = -340
	_help_label.offset_right = -16
	_help_label.offset_top = 16
	_help_label.offset_bottom = 150
	_help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_help_label.text = "左键 / Enter：确认\nEsc / 右键：取消\n方向键：移动光标\nQ / E：旋转视角\n滚轮：缩放\nT：结束回合"
	_help_label.add_theme_font_size_override("font_size", 15)
	_help_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 0.8))
	add_child(_help_label)

	# --- Unit info (bottom left) ---
	var info_panel := PanelContainer.new()
	info_panel.add_theme_stylebox_override("panel", _panel_style())
	_place(info_panel, 0.0, 1.0, 0.0, 1.0)
	info_panel.offset_left = 20
	info_panel.offset_right = 340
	info_panel.offset_top = -186
	info_panel.offset_bottom = -20
	add_child(info_panel)

	_info_label = Label.new()
	_info_label.custom_minimum_size = Vector2(300, 0)
	_info_label.add_theme_font_size_override("font_size", 17)
	_info_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	info_panel.add_child(_info_label)

	# --- Action menu (bottom right) ---
	_menu_panel = PanelContainer.new()
	_menu_panel.add_theme_stylebox_override("panel", _panel_style())
	_place(_menu_panel, 1.0, 1.0, 1.0, 1.0)
	_menu_panel.offset_left = -344
	_menu_panel.offset_right = -16
	_menu_panel.offset_top = -220
	_menu_panel.offset_bottom = -20
	_menu_panel.visible = false
	add_child(_menu_panel)

	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 10)
	_menu_panel.add_child(_menu_box)

	# --- Message (bottom center) ---
	_message_label = Label.new()
	_place(_message_label, 0.5, 1.0, 0.5, 1.0)
	_message_label.offset_left = -340
	_message_label.offset_right = 340
	_message_label.offset_top = -58
	_message_label.offset_bottom = -16
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_size_override("font_size", 19)
	_message_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_message_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_message_label.add_theme_constant_override("outline_size", 6)
	add_child(_message_label)

	# --- Game-over overlay (full screen) ---
	_overlay = ColorRect.new()
	_place(_overlay, 0.0, 0.0, 1.0, 1.0)
	_overlay.color = Color(0, 0, 0, 0.65)
	_overlay.visible = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var center := CenterContainer.new()
	_place(center, 0.0, 0.0, 1.0, 1.0)
	_overlay.add_child(center)

	_overlay_box = VBoxContainer.new()
	_overlay_box.add_theme_constant_override("separation", 24)
	center.add_child(_overlay_box)

	_overlay_label = Label.new()
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.add_theme_font_size_override("font_size", 52)
	_overlay_label.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	_overlay_box.add_child(_overlay_label)
	# Buttons are rebuilt by show_game_over() (defeat: Restart; victory: world map).



# --------------------------------------------------------------------------
# Public API
# --------------------------------------------------------------------------

func set_turn_text(text: String) -> void:
	_turn_label.text = text


func set_message(text: String) -> void:
	_message_label.text = text


func show_unit_info(u: TacticalUnit) -> void:
	var team_name := "Ally" if u.team == TacticalUnit.Team.PLAYER else "Enemy"
	var status := "Ready" if not u.has_acted else "Acted"
	_info_label.text = "%s  [%s]\nHP   %d / %d\nATK %d     DEF %d\nMOV %d     RNG %d-%d\nStatus: %s" % [
		u.unit_name, team_name, u.hp, u.max_hp,
		u.attack_power, u.defense, u.move_range,
		u.min_attack_range, u.max_attack_range, status
	]


func show_terrain_info(elev: int) -> void:
	_info_label.text = "Open ground\nElevation: %d\n\nMove the cursor onto a unit\nto see its stats." % elev


func show_action_menu(options: Array, title := "Action") -> void:
	for c in _menu_box.get_children():
		_menu_box.remove_child(c)
		c.queue_free()
	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	_menu_box.add_child(title_label)
	_menu_buttons.clear()
	_menu_ids.clear()
	_menu_hover = ""
	for opt in options:
		var b := Button.new()
		b.text = opt["label"]
		b.custom_minimum_size = Vector2(300, 42)
		b.add_theme_font_size_override("font_size", 17)
		# Visual-only: input is driven by manual hit-testing in game.gd _input().
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.focus_mode = Control.FOCUS_NONE
		_menu_box.add_child(b)
		_menu_buttons.append(b)
		_menu_ids.append(opt["id"])
	# Grow the panel upward so every option fits on screen.
	var needed := 24.0 + 34.0 + options.size() * 52.0
	_menu_panel.offset_top = -20.0 - needed
	_menu_panel.visible = true


func hide_action_menu() -> void:
	_menu_panel.visible = false


## Manual hit-testing: returns the option id at viewport position, or "".
func menu_option_at(pos: Vector2) -> String:
	if not _menu_panel.visible:
		return ""
	for i in _menu_buttons.size():
		if _menu_buttons[i].get_global_rect().has_point(pos):
			return _menu_ids[i]
	return ""


func is_menu_visible() -> bool:
	return _menu_panel.visible


func highlight_option(id: String) -> void:
	if id == _menu_hover:
		return
	_menu_hover = id
	for i in _menu_buttons.size():
		var on := _menu_ids[i] == id
		_menu_buttons[i].modulate = Color(1.35, 1.3, 1.2, 1.0) if on else Color(1, 1, 1, 1)


## `victory` swaps the primary button to the world-map handoff.
func show_game_over(text: String, victory := false) -> void:
	_overlay_label.text = text
	for c in _overlay_box.get_children():
		_overlay_box.remove_child(c)
		c.queue_free()
	_overlay_buttons.clear()
	_overlay_ids.clear()
	var options: Array = []
	if victory:
		options.append({"id": "map", "label": "进入大地图"})
	else:
		options.append({"id": "restart", "label": "Restart"})
	options.append({"id": "menu", "label": "返回主菜单"})
	for opt in options:
		var b := Button.new()
		b.text = opt["label"]
		b.custom_minimum_size = Vector2(220, 52)
		b.add_theme_font_size_override("font_size", 22)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.focus_mode = Control.FOCUS_NONE
		_overlay_box.add_child(b)
		_overlay_buttons.append(b)
		_overlay_ids.append(opt["id"])
	_overlay.visible = true


## Manual hit-testing for the game-over overlay buttons.
func game_over_option_at(pos: Vector2) -> String:
	if not _overlay.visible:
		return ""
	for i in _overlay_buttons.size():
		if _overlay_buttons[i].get_global_rect().has_point(pos):
			return _overlay_ids[i]
	return ""


func is_game_over_visible() -> bool:
	return _overlay.visible
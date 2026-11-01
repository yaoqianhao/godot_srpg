class_name WorldMap
extends Node3D
## World map + chapter-end flow: cinematic flyover intro (route reveal),
## then the party management phase (整理队伍).
## Data handoff from the battle: SRPGGame._go_world_map() fills the static
## `incoming_*` fields before changing scenes.

enum Phase { INTRO, PARTY, DONE }

const ROUTE := [
	{"name": "边陲营地", "kind": "camp", "pos": Vector3(-72.0, 0.0, -38.0)},
	{"name": "鹰愁关隘", "kind": "fort", "pos": Vector3(-28.0, 0.0, -6.0)},
	{"name": "镜湖畔", "kind": "lake", "pos": Vector3(10.0, 0.0, -36.0)},
	{"name": "古墟遗迹", "kind": "ruins", "pos": Vector3(40.0, 0.0, 4.0)},
	{"name": "魔王城", "kind": "castle", "pos": Vector3(78.0, 0.0, 36.0)},
]
const OBJECTIVE_INDEX := 1
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

# Flyover camera keyframes: {eye, look, t}.
const KFS := [
	{"eye": Vector3(0.0, 120.0, -170.0), "look": Vector3(0.0, 0.0, 0.0), "t": 2.4},
	{"eye": Vector3(-95.0, 18.0, -80.0), "look": Vector3(-50.0, 0.0, -22.0), "t": 2.6},
	{"eye": Vector3(25.0, 16.0, -75.0), "look": Vector3(12.0, 0.0, -12.0), "t": 2.4},
	{"eye": Vector3(100.0, 24.0, 65.0), "look": Vector3(55.0, 0.0, 20.0), "t": 2.8},
	{"eye": Vector3(0.0, 70.0, -120.0), "look": Vector3(0.0, 0.0, 0.0), "t": 2.4},
]

# Chapter data passed in by the battle (statics survive the scene change).
static var incoming_party: Array = []
static var incoming_chapter: int = 1
static var incoming_turns: int = 1

@onready var camera3d: Camera3D = $Camera3D

var phase: Phase = Phase.INTRO
var _look_target: Node3D
var _skip := false
var _intro_tweens: Array[Tween] = []
var _route_root: Node3D
var _markers: Array = []          # [{root, orb, beacon, kind, index}]
var _segments: Array[Node3D] = []
var _orbit: float = 0.6

# Shared meshes / materials
var _trunk_mesh: CylinderMesh
var _foliage_mesh: CylinderMesh  # top radius 0 -> cone
var _base_mesh: CylinderMesh
var _orb_mesh: SphereMesh
var _beacon_mesh: CylinderMesh
var _grass_mat: StandardMaterial3D
var _hill_mat: StandardMaterial3D
var _mountain_mat: StandardMaterial3D
var _water_mat: StandardMaterial3D
var _road_mat: StandardMaterial3D
var _stone_mat: StandardMaterial3D
var _trunk_mat: StandardMaterial3D
var _foliage_mats: Array[StandardMaterial3D] = []
var _orb_mats: Dictionary = {}

# Party UI
var _ui: CanvasLayer
var _fade: ColorRect
var _banner: Label
var _skip_hint: Label
var _party_root: Control
var _header_label: Label
var _summary_label: Label
var _roster_box: VBoxContainer
var _detail_label: Label
var _done_btn: Button
var _party_rows: Array[Button] = []
var _party: Array = []            # normalized roster records
var _sel: int = 0
var _hover_row: int = -1
var _hover_done := false


func _ready() -> void:
	_look_target = Node3D.new()
	add_child(_look_target)
	_build_environment()
	_build_materials()
	_build_terrain()
	_build_route()
	_build_intro_ui()
	_normalize_party()
	camera3d.current = true
	camera3d.near = 0.5
	camera3d.far = 2000.0
	camera3d.global_position = KFS[0]["eye"]
	_look_target.global_position = KFS[0]["look"]
	_play_intro()


# --------------------------------------------------------------------------
# Environment / materials
# --------------------------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.24, 0.44)
	sky_mat.sky_horizon_color = Color(0.88, 0.58, 0.36)
	sky_mat.ground_horizon_color = Color(0.55, 0.38, 0.28)
	sky_mat.ground_bottom_color = Color(0.12, 0.10, 0.10)
	var sky_res := Sky.new()
	sky_res.sky_material = sky_mat
	var env_res := Environment.new()
	env_res.background_mode = Environment.BG_SKY
	env_res.sky = sky_res
	env_res.fog_enabled = true
	env_res.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env_res.fog_density = 0.0022
	env_res.fog_light_color = Color(0.82, 0.56, 0.38)
	env_res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_res.ambient_light_color = Color(0.55, 0.50, 0.50)
	env_res.ambient_light_energy = 0.55
	$WorldEnvironment.environment = env_res


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _orb_mat(c: Color, energy := 1.1) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c * 0.35
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.5
	return m


func _build_materials() -> void:
	_grass_mat = _mat(Color(0.16, 0.30, 0.15))
	_hill_mat = _mat(Color(0.19, 0.34, 0.17))
	_mountain_mat = _mat(Color(0.36, 0.38, 0.46))
	_water_mat = _mat(Color(0.16, 0.42, 0.62))
	_water_mat.roughness = 0.15
	_road_mat = _mat(Color(0.62, 0.52, 0.34))
	_stone_mat = _mat(Color(0.45, 0.42, 0.38))
	_trunk_mat = _mat(Color(0.30, 0.20, 0.12))
	_foliage_mats = [
		_mat(Color(0.13, 0.34, 0.16)),
		_mat(Color(0.17, 0.38, 0.18)),
		_mat(Color(0.11, 0.29, 0.15)),
	]

	_trunk_mesh = CylinderMesh.new()
	_trunk_mesh.top_radius = 0.22
	_trunk_mesh.bottom_radius = 0.34
	_trunk_mesh.height = 1.8
	_foliage_mesh = CylinderMesh.new()  # top radius 0 -> cone
	_foliage_mesh.top_radius = 0.01
	_foliage_mesh.bottom_radius = 1.7
	_foliage_mesh.height = 3.6
	_base_mesh = CylinderMesh.new()
	_base_mesh.top_radius = 2.4
	_base_mesh.bottom_radius = 2.9
	_base_mesh.height = 0.7
	_orb_mesh = SphereMesh.new()
	_orb_mesh.radius = 1.0
	_beacon_mesh = CylinderMesh.new()
	_beacon_mesh.top_radius = 0.35
	_beacon_mesh.bottom_radius = 0.55
	_beacon_mesh.height = 9.0

	_orb_mats = {
		"camp": _orb_mat(Color(0.35, 0.85, 0.45)),
		"fort": _orb_mat(Color(1.0, 0.78, 0.25)),
		"lake": _orb_mat(Color(0.35, 0.75, 1.0)),
		"ruins": _orb_mat(Color(0.72, 0.5, 1.0)),
		"castle": _orb_mat(Color(0.95, 0.32, 0.26)),
	}


func _box(size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	return mi


# --------------------------------------------------------------------------
# Terrain / route construction
# --------------------------------------------------------------------------

func _build_terrain() -> void:
	var ground := _box(Vector3(260.0, 6.0, 200.0), _grass_mat)
	ground.position.y = -3.0
	add_child(ground)

	# Hills (flattened cylinders)
	var hills := [
		{"p": Vector3(-105.0, 0.0, 45.0), "r": 20.0, "h": 7.0},
		{"p": Vector3(62.0, 0.0, -62.0), "r": 16.0, "h": 5.0},
		{"p": Vector3(-42.0, 0.0, 62.0), "r": 22.0, "h": 8.0},
		{"p": Vector3(105.0, 0.0, -28.0), "r": 18.0, "h": 6.0},
		{"p": Vector3(-18.0, 0.0, -78.0), "r": 15.0, "h": 5.0},
	]
	for h in hills:
		var hp: Vector3 = h["p"]
		var m := CylinderMesh.new()
		m.top_radius = float(h["r"]) * 0.55
		m.bottom_radius = float(h["r"])
		m.height = float(h["h"])
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.position = Vector3(hp.x, float(h["h"]) * 0.5 - 0.4, hp.z)
		mi.material_override = _hill_mat
		add_child(mi)

	# Mountains on the borders (cones: cylinder with top radius 0)
	var mounts := [
		{"p": Vector3(-118.0, 0.0, -70.0), "r": 16.0, "h": 24.0},
		{"p": Vector3(-108.0, 0.0, 62.0), "r": 19.0, "h": 30.0},
		{"p": Vector3(118.0, 0.0, -58.0), "r": 17.0, "h": 26.0},
		{"p": Vector3(122.0, 0.0, 30.0), "r": 20.0, "h": 32.0},
		{"p": Vector3(88.0, 0.0, 82.0), "r": 15.0, "h": 22.0},
		{"p": Vector3(-62.0, 0.0, 88.0), "r": 16.0, "h": 24.0},
		{"p": Vector3(8.0, 0.0, -92.0), "r": 18.0, "h": 26.0},
	]
	for mt in mounts:
		var mp: Vector3 = mt["p"]
		var c := CylinderMesh.new()
		c.top_radius = 0.01
		c.bottom_radius = float(mt["r"])
		c.height = float(mt["h"])
		var mi := MeshInstance3D.new()
		mi.mesh = c
		mi.position = Vector3(mp.x, float(mt["h"]) * 0.5 - 0.6, mp.z)
		mi.material_override = _mountain_mat
		add_child(mi)

	# River along the west edge
	var river := _box(Vector3(4.0, 0.5, 210.0), _water_mat)
	river.position = Vector3(-96.0, 0.1, 0.0)
	river.rotation.y = 0.1
	add_child(river)

	# Trees (seeded scatter, kept clear of the road and nodes)
	seed(20260702)
	var placed := 0
	var guard := 0
	while placed < 44 and guard < 500:
		guard += 1
		var x := randf_range(-118.0, 118.0)
		var z := randf_range(-88.0, 88.0)
		if x < -82.0:
			continue  # river strip
		var ok := true
		for i in ROUTE.size():
			var np: Vector3 = ROUTE[i]["pos"]
			if Vector2(x, z).distance_to(Vector2(np.x, np.z)) < 9.0:
				ok = false
				break
		if ok:
			for i in range(ROUTE.size() - 1):
				var a: Vector3 = ROUTE[i]["pos"]
				var b: Vector3 = ROUTE[i + 1]["pos"]
				if _dist_to_seg(Vector2(x, z), Vector2(a.x, a.z), Vector2(b.x, b.z)) < 6.5:
					ok = false
					break
		if not ok:
			continue
		_spawn_tree(Vector3(x, 0.0, z))
		placed += 1


func _spawn_tree(p: Vector3) -> void:
	var g := Node3D.new()
	g.position = p
	var s := randf_range(0.8, 1.5)
	g.scale = Vector3(s, s, s)
	g.rotation.y = randf_range(0.0, TAU)
	var trunk := MeshInstance3D.new()
	trunk.mesh = _trunk_mesh
	trunk.position.y = 0.9
	trunk.material_override = _trunk_mat
	var fol := MeshInstance3D.new()
	fol.mesh = _foliage_mesh
	fol.position.y = 3.0
	fol.material_override = _foliage_mats[randi() % _foliage_mats.size()]
	g.add_child(trunk)
	g.add_child(fol)
	add_child(g)


func _dist_to_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _build_route() -> void:
	_route_root = Node3D.new()
	add_child(_route_root)
	# Road segments: pivot at segment start; scale.z animates the reveal.
	for i in range(ROUTE.size() - 1):
		var a: Vector3 = ROUTE[i]["pos"]
		var b: Vector3 = ROUTE[i + 1]["pos"]
		var d := b - a
		var seg_len := sqrt(d.x * d.x + d.z * d.z)
		var pivot := Node3D.new()
		pivot.position = a
		pivot.rotation.y = atan2(d.x, d.z)
		var seg := _box(Vector3(1.1, 0.14, 1.0), _road_mat)
		seg.scale = Vector3(1.0, 1.0, seg_len)
		seg.position = Vector3(0.0, 0.07, seg_len * 0.5)
		pivot.add_child(seg)
		pivot.scale.z = 0.01
		_route_root.add_child(pivot)
		_segments.append(pivot)
	for i in ROUTE.size():
		_build_node(i)


func _build_node(i: int) -> void:
	var def: Dictionary = ROUTE[i]
	var root := Node3D.new()
	root.position = def["pos"]
	root.scale = Vector3(0.01, 0.01, 0.01)
	var base := MeshInstance3D.new()
	base.mesh = _base_mesh
	base.position.y = 0.35
	base.material_override = _stone_mat
	var orb := MeshInstance3D.new()
	orb.mesh = _orb_mesh
	orb.position.y = 3.4
	orb.material_override = _orb_mats[def["kind"]]
	var label := Label3D.new()
	label.text = def["name"]
	label.font_size = 44
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, 6.6, 0.0)
	root.add_child(base)
	root.add_child(orb)
	root.add_child(label)
	var beacon: MeshInstance3D = null
	if i == OBJECTIVE_INDEX:
		beacon = MeshInstance3D.new()
		beacon.mesh = _beacon_mesh
		beacon.position.y = 4.5
		beacon.material_override = _orb_mats["fort"]
		root.add_child(beacon)
	_route_root.add_child(root)
	_markers.append({"root": root, "orb": orb, "beacon": beacon, "kind": def["kind"], "index": i})


# --------------------------------------------------------------------------
# Intro cinematic (flyover + route reveal)
# --------------------------------------------------------------------------

func _play_intro() -> void:
	phase = Phase.INTRO
	_fade.color.a = 1.0
	await _fade_to(0.0, 1.2)
	if phase != Phase.INTRO:
		return
	await _caption("第一章「边境之战」 完成", 2.2)
	if phase != Phase.INTRO:
		return
	_start_camera_timeline()
	for i in ROUTE.size():
		await get_tree().create_timer(1.05).timeout
		_reveal_node(i)
		if phase != Phase.INTRO:
			return
	await _caption("—— 世界地图 ——", 2.0)
	if phase != Phase.INTRO:
		return
	await get_tree().create_timer(1.0).timeout
	_enter_party()


func _skip_intro() -> void:
	if phase != Phase.INTRO:
		return
	_skip = true
	for tw in _intro_tweens:
		tw.kill()
	_intro_tweens.clear()
	var last: Dictionary = KFS[KFS.size() - 1]
	camera3d.global_position = last["eye"]
	_look_target.global_position = last["look"]
	camera3d.look_at(_look_target.global_position, Vector3.UP)
	for i in ROUTE.size():
		_reveal_node(i, true)
	_banner.modulate.a = 0.0
	_fade_to(0.0, 0.3)
	_enter_party()


func _start_camera_timeline() -> void:
	camera3d.global_position = KFS[0]["eye"]
	_look_target.global_position = KFS[0]["look"]
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for kf in KFS:
		tw.set_parallel(true)
		tw.tween_property(camera3d, "global_position", kf["eye"], float(kf["t"]))
		tw.tween_property(_look_target, "global_position", kf["look"], float(kf["t"]))
		tw.chain()
	_intro_tweens.append(tw)


func _reveal_node(i: int, instant := false) -> void:
	var m: Dictionary = _markers[i]
	var root: Node3D = m["root"]
	if instant:
		root.scale = Vector3.ONE
		if i > 0:
			_segments[i - 1].scale.z = 1.0
	else:
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(root, "scale", Vector3.ONE, 0.5)
		_intro_tweens.append(tw)
		if i > 0:
			var seg: Node3D = _segments[i - 1]
			var tw2 := create_tween()
			tw2.tween_property(seg, "scale:z", 1.0, 0.6)
			_intro_tweens.append(tw2)
	# Ambient life (also for instant reveal).
	var orb: MeshInstance3D = m["orb"]
	var bob := create_tween()
	bob.set_loops()
	bob.tween_property(orb, "position:y", 4.4, 1.3)
	bob.tween_property(orb, "position:y", 3.4, 1.3)
	if i == OBJECTIVE_INDEX:
		var pulse := create_tween()
		pulse.set_loops()
		pulse.tween_property(orb, "scale", Vector3(1.3, 1.3, 1.3), 0.7)
		pulse.tween_property(orb, "scale", Vector3(1.0, 1.0, 1.0), 0.7)
		var beacon: MeshInstance3D = m["beacon"]
		if beacon != null:
			var bp := create_tween()
			bp.set_parallel(true)
			bp.tween_property(beacon, "scale:x", 1.35, 0.8)
			bp.tween_property(beacon, "scale:z", 1.35, 0.8)
			bp.chain()
			bp.tween_property(beacon, "scale:x", 1.0, 0.8)
			bp.tween_property(beacon, "scale:z", 1.0, 0.8)


func _fade_to(target: float, dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", target, dur)
	await tw.finished


func _caption(text: String, hold: float) -> void:
	_banner.text = text
	var tin := create_tween()
	tin.tween_property(_banner, "modulate:a", 1.0, 0.35)
	await tin.finished
	await get_tree().create_timer(hold).timeout
	var tout := create_tween()
	tout.tween_property(_banner, "modulate:a", 0.0, 0.35)
	await tout.finished


func _process(delta: float) -> void:
	if phase == Phase.INTRO:
		camera3d.look_at(_look_target.global_position, Vector3.UP)
	elif phase == Phase.PARTY:
		_orbit += delta * 0.045
		var r := 135.0
		camera3d.global_position = Vector3(sin(_orbit) * r, 88.0, cos(_orbit) * r)
		camera3d.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)


# --------------------------------------------------------------------------
# Party data (chapter handoff)
# --------------------------------------------------------------------------

func _normalize_party() -> void:
	_party = []
	var src: Array = WorldMap.incoming_party
	if src.is_empty():
		src = _default_party()
	for d in src:
		var rec := {
			"name": str(d["name"]),
			"cn": _cn_name(str(d["name"])),
			"level": int(d.get("level", 1)),
			"hp_in": int(d["hp"]),
			"max_hp": int(d["max_hp"]),
			"hp": int(d["hp"]),
			"atk": int(d["atk"]),
			"def": int(d["def"]),
			"mov": int(d["mov"]),
			"minrng": int(d["minrng"]),
			"maxrng": int(d["maxrng"]),
			"uses_in": d.get("uses", {}),
			"uses": TacticalUnit.ABILITY_USES.duplicate(true),
		}
		_party.append(rec)


func _default_party() -> Array:
	return [
		{"name": "Knight", "hp": 32, "max_hp": 32, "atk": 9, "def": 6, "mov": 4, "minrng": 1, "maxrng": 1},
		{"name": "Archer", "hp": 22, "max_hp": 22, "atk": 8, "def": 2, "mov": 5, "minrng": 1, "maxrng": 2},
		{"name": "Mage", "hp": 20, "max_hp": 20, "atk": 11, "def": 1, "mov": 4, "minrng": 1, "maxrng": 3},
	]


func _cn_name(unit_name: String) -> String:
	match unit_name:
		"Knight":
			return "骑士"
		"Archer":
			return "弓箭手"
		"Mage":
			return "法师"
	return name


func _chapter_name(ch: int) -> String:
	if ch == 1:
		return "边境之战"
	return "第 %d 章" % ch


func _skills_of(unit_name: String) -> Array:
	if unit_name == "Mage":
		return [["火球术 Fireball", "fire"], ["治疗术 Heal", "heal"], ["药水 Potion", "potion"]]
	return [["猛击 Bash", "bash"], ["破甲 Pierce", "pierce"], ["药水 Potion", "potion"]]


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


func _place(c: Control, l: float, t: float, r: float, b: float) -> void:
	c.anchor_left = l
	c.anchor_top = t
	c.anchor_right = r
	c.anchor_bottom = b


func _build_intro_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)

	_fade = ColorRect.new()
	_fade.anchor_right = 1.0
	_fade.anchor_bottom = 1.0
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_fade)

	_banner = Label.new()
	_banner.anchor_left = 0.0
	_banner.anchor_right = 1.0
	_banner.anchor_top = 0.3
	_banner.anchor_bottom = 0.3
	_banner.offset_top = -40.0
	_banner.offset_bottom = 40.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 44)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.modulate.a = 0.0
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_banner)

	_skip_hint = Label.new()
	_skip_hint.anchor_left = 0.5
	_skip_hint.anchor_right = 0.5
	_skip_hint.anchor_top = 1.0
	_skip_hint.anchor_bottom = 1.0
	_skip_hint.offset_left = -200.0
	_skip_hint.offset_right = 200.0
	_skip_hint.offset_top = -46.0
	_skip_hint.offset_bottom = -16.0
	_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skip_hint.text = "点击 / Enter 跳过"
	_skip_hint.add_theme_font_size_override("font_size", 16)
	_skip_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	_skip_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_skip_hint)


func _build_party_ui() -> void:
	_party_root = Control.new()
	_party_root.anchor_right = 1.0
	_party_root.anchor_bottom = 1.0
	_ui.add_child(_party_root)

	_header_label = Label.new()
	_place(_header_label, 0.0, 0.0, 1.0, 0.0)
	_header_label.offset_top = 22.0
	_header_label.offset_bottom = 66.0
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_label.text = "第 %d 章「%s」完成 · 战前整备" % [WorldMap.incoming_chapter, _chapter_name(WorldMap.incoming_chapter)]
	_header_label.add_theme_font_size_override("font_size", 32)
	_header_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	_header_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_header_label.add_theme_constant_override("outline_size", 6)
	_header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_party_root.add_child(_header_label)

	_summary_label = Label.new()
	_place(_summary_label, 0.0, 0.0, 1.0, 0.0)
	_summary_label.offset_top = 72.0
	_summary_label.offset_bottom = 102.0
	_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_label.add_theme_font_size_override("font_size", 18)
	_summary_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 0.9))
	_summary_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_summary_label.add_theme_constant_override("outline_size", 4)
	_summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_party_root.add_child(_summary_label)

	# Roster panel (left)
	var roster_panel := PanelContainer.new()
	roster_panel.add_theme_stylebox_override("panel", _panel_style())
	_place(roster_panel, 0.0, 0.0, 0.0, 1.0)
	roster_panel.offset_left = 24.0
	roster_panel.offset_right = 464.0
	roster_panel.offset_top = 120.0
	roster_panel.offset_bottom = -120.0
	_party_root.add_child(roster_panel)

	var roster_outer := VBoxContainer.new()
	roster_outer.add_theme_constant_override("separation", 8)
	roster_panel.add_child(roster_outer)

	var roster_title := Label.new()
	roster_title.text = "队伍 Roster"
	roster_title.add_theme_font_size_override("font_size", 22)
	roster_title.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	roster_outer.add_child(roster_title)

	_roster_box = VBoxContainer.new()
	_roster_box.add_theme_constant_override("separation", 6)
	roster_outer.add_child(_roster_box)

	for i in _party.size():
		var row := Button.new()
		row.text = _row_text(i)
		row.custom_minimum_size = Vector2(380, 62)
		row.add_theme_font_size_override("font_size", 16)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# Visual-only: input is driven by manual hit-testing in _input().
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.focus_mode = Control.FOCUS_NONE
		_roster_box.add_child(row)
		_party_rows.append(row)

	# Detail panel (right)
	var detail_panel := PanelContainer.new()
	detail_panel.add_theme_stylebox_override("panel", _panel_style())
	_place(detail_panel, 1.0, 0.0, 1.0, 1.0)
	detail_panel.offset_left = -640.0
	detail_panel.offset_right = -24.0
	detail_panel.offset_top = 120.0
	detail_panel.offset_bottom = -190.0
	_party_root.add_child(detail_panel)

	_detail_label = Label.new()
	_detail_label.custom_minimum_size = Vector2(576, 0)
	_detail_label.add_theme_font_size_override("font_size", 17)
	_detail_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	detail_panel.add_child(_detail_label)

	# Prompt + done button (bottom center)
	var prompt := Label.new()
	_place(prompt, 0.0, 1.0, 1.0, 1.0)
	prompt.offset_left = -320.0
	prompt.offset_right = 320.0
	prompt.offset_top = -160.0
	prompt.offset_bottom = -124.0
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.text = "↑/↓ 或点击选择队员 · Enter / 点击「完成」结束本章"
	prompt.add_theme_font_size_override("font_size", 16)
	prompt.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 0.8))
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_party_root.add_child(prompt)

	_done_btn = Button.new()
	_done_btn.text = "完成 返回标题"
	_done_btn.custom_minimum_size = Vector2(280, 56)
	_done_btn.add_theme_font_size_override("font_size", 22)
	_done_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_done_btn.focus_mode = Control.FOCUS_NONE
	_done_btn.anchor_left = 0.5
	_done_btn.anchor_right = 0.5
	_done_btn.anchor_top = 1.0
	_done_btn.anchor_bottom = 1.0
	_done_btn.offset_left = -140.0
	_done_btn.offset_right = 140.0
	_done_btn.offset_top = -112.0
	_done_btn.offset_bottom = -56.0
	_party_root.add_child(_done_btn)


# --------------------------------------------------------------------------
# Party phase
# --------------------------------------------------------------------------

func _enter_party() -> void:
	if phase != Phase.INTRO:
		return
	phase = Phase.PARTY
	_skip_hint.visible = false
	_banner.modulate.a = 0.0
	# Between chapters: full heal + ability-use reset.
	for rec in _party:
		rec["hp"] = int(rec["max_hp"])
		rec["uses"] = TacticalUnit.ABILITY_USES.duplicate(true)
	_build_party_ui()
	_refresh_summary()
	_select(0)
	_party_root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_party_root, "modulate:a", 1.0, 0.6)


func _row_text(i: int) -> String:
	var rec: Dictionary = _party[i]
	var status := "完好" if int(rec["hp_in"]) >= int(rec["max_hp"]) else "战中受伤 · 已恢复"
	return "%s %s   Lv.%d\nHP %d/%d · %s" % [rec["cn"], rec["name"], int(rec["level"]), int(rec["hp"]), int(rec["max_hp"]), status]


func _refresh_summary() -> void:
	var wounded := 0
	for rec in _party:
		if int(rec["hp_in"]) < int(rec["max_hp"]):
			wounded += 1
	var note := " · 全员完好" if wounded == 0 else " · 受伤 %d 人，已恢复" % wounded
	_summary_label.text = "回合数： %d · 阵亡： 0%s" % [WorldMap.incoming_turns, note]


func _refresh_detail() -> void:
	if _party.is_empty():
		return
	var rec: Dictionary = _party[_sel]
	var lines: Array[String] = [
		"%s %s    Lv.%d" % [rec["cn"], rec["name"], int(rec["level"])],
		"------------------------------",
		"HP   %d / %d      （入队时 %d / %d）" % [int(rec["hp"]), int(rec["max_hp"]), int(rec["hp_in"]), int(rec["max_hp"])],
		"ATK  %d          DEF  %d" % [int(rec["atk"]), int(rec["def"])],
		"MOV  %d          RNG  %d - %d" % [int(rec["mov"]), int(rec["minrng"]), int(rec["maxrng"])],
		"",
		"技能 / 道具（本章次数已重置）",
	]
	for sk in _skills_of(str(rec["name"])):
		lines.append("· %s ×%d" % [str(sk[0]), int(rec["uses"][str(sk[1])])])
	lines.append("")
	lines.append("状态：已完全恢复，次数已重置。")
	_detail_label.text = "\n".join(lines)


func _refresh_party_visuals() -> void:
	for i in _party_rows.size():
		var row: Button = _party_rows[i]
		if i == _sel:
			row.modulate = Color(1.35, 1.28, 1.05, 1.0)
		elif i == _hover_row:
			row.modulate = Color(1.15, 1.15, 1.1, 1.0)
		else:
			row.modulate = Color(1, 1, 1, 1)
	_done_btn.modulate = Color(1.35, 1.28, 1.05, 1.0) if _hover_done else Color(1, 1, 1, 1)


func _select(i: int) -> void:
	_sel = clampi(i, 0, _party.size() - 1)
	_refresh_detail()
	_refresh_party_visuals()


func _row_at(pos: Vector2) -> int:
	for i in _party_rows.size():
		if _party_rows[i].get_global_rect().has_point(pos):
			return i
	return -1


# --------------------------------------------------------------------------
# Input (manual hit-testing, same architecture as the battle HUD menus)
# --------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if phase == Phase.INTRO:
		if (event is InputEventMouseButton and event.pressed) or event.is_action_pressed("ui_accept"):
			_skip_intro()
			get_viewport().set_input_as_handled()
		return
	if phase != Phase.PARTY:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var row := _row_at(event.position)
		if row != -1:
			_select(row)
			get_viewport().set_input_as_handled()
			return
		if _done_btn.get_global_rect().has_point(event.position):
			_finish()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		var r := _row_at(event.position)
		var over := _done_btn.get_global_rect().has_point(event.position)
		if r != _hover_row or over != _hover_done:
			_hover_row = r
			_hover_done = over
			_refresh_party_visuals()
		if r != -1 or over:
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_up"):
		_select(_sel - 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_select(_sel + 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_finish()
		get_viewport().set_input_as_handled()


func _finish() -> void:
	if phase != Phase.PARTY:
		return
	phase = Phase.DONE
	await _fade_to(1.0, 0.9)
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)



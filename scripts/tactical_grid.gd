class_name TacticalGrid
extends Node3D
## Logical + visual grid for the tactical map.
## Each tile is a box whose top surface sits at (elevation * ELEVATION_STEP).
## Grid coordinates are Vector2i(x, z), world position = tile center on the tile top.

const TILE_SIZE := 2.0
const ELEVATION_STEP := 0.75
const TILE_THICKNESS := 2.5

## Map layout. Each character is one tile:
##   '1'..'5' = elevation level, '#' = blocked obstacle (impassable rock).
const LAYOUT: Array[String] = [
	"111111111111",
	"122222222221",
	"122233332221",
	"122344443221",
	"12344##44321",
	"12344##44321",
	"122344443221",
	"122233332221",
	"122222222221",
	"111111111111",
]

var width: int = 0
var depth: int = 0

var _elevation: Array[int] = []
var _blocked: Array[bool] = []

var _overlays: Node3D
var _tiles_root: Node3D
var _materials: Dictionary = {}


func build() -> void:
	depth = LAYOUT.size()
	width = LAYOUT[0].length()
	var count := width * depth
	_elevation.resize(count)
	_blocked.resize(count)

	for z in depth:
		var row := LAYOUT[z]
		for x in width:
			var idx := _idx(x, z)
			var ch := row[x]
			if ch == "#":
				_blocked[idx] = true
				_elevation[idx] = 3
			else:
				_elevation[idx] = ch.to_int()

	_tiles_root = Node3D.new()
	_tiles_root.name = "Tiles"
	add_child(_tiles_root)

	_overlays = Node3D.new()
	_overlays.name = "Overlays"
	add_child(_overlays)

	_generate_tiles()


# --------------------------------------------------------------------------
# Queries
# --------------------------------------------------------------------------

func _idx(x: int, z: int) -> int:
	return z * width + x


func in_bounds(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < width and z < depth


func get_elevation(x: int, z: int) -> int:
	if not in_bounds(x, z):
		return 0
	return _elevation[_idx(x, z)]


func is_blocked(x: int, z: int) -> bool:
	return in_bounds(x, z) and _blocked[_idx(x, z)]


func is_walkable(x: int, z: int) -> bool:
	if not in_bounds(x, z):
		return false
	return not _blocked[_idx(x, z)]


## Cost to step from one tile onto an adjacent one. Returns -1 if impassable.
func move_cost(from: Vector2i, to: Vector2i) -> int:
	if not is_walkable(to.x, to.y):
		return -1
	var rise := get_elevation(to.x, to.y) - get_elevation(from.x, from.y)
	if rise > 1:
		return -1
	return 1 + maxi(0, rise)


## Top-surface world position of a tile.
func tile_to_world(pos: Vector2i, offset := Vector3.ZERO) -> Vector3:
	return Vector3(
		pos.x * TILE_SIZE,
		get_elevation(pos.x, pos.y) * ELEVATION_STEP,
		pos.y * TILE_SIZE
	) + offset


func clamp_tile(pos: Vector2i) -> Vector2i:
	return Vector2i(clampi(pos.x, 0, width - 1), clampi(pos.y, 0, depth - 1))


# --------------------------------------------------------------------------
# Generation
# --------------------------------------------------------------------------

func _tile_material(elev: int, blocked: bool) -> StandardMaterial3D:
	var key := "b" if blocked else str(elev)
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	if blocked:
		mat.albedo_color = Color(0.34, 0.33, 0.36)
		mat.roughness = 0.95
	else:
		# Green lowlands -> rocky highlands.
		var t := clampf(float(elev - 1) / 4.0, 0.0, 1.0)
		var low := Color(0.30, 0.55, 0.28)
		var high := Color(0.62, 0.58, 0.50)
		mat.albedo_color = low.lerp(high, t)
		mat.roughness = 0.85
	_materials[key] = mat
	return mat


func _generate_tiles() -> void:
	for z in depth:
		for x in width:
			var pos := Vector2i(x, z)
			var elev := get_elevation(x, z)
			var top_y := elev * ELEVATION_STEP
			var h := top_y + TILE_THICKNESS
			var center_y := top_y - h * 0.5

			var box := BoxMesh.new()
			box.size = Vector3(TILE_SIZE, h, TILE_SIZE)

			var mi := MeshInstance3D.new()
			mi.mesh = box
			mi.material_override = _tile_material(elev, is_blocked(x, z))
			mi.position = Vector3(x * TILE_SIZE, center_y, z * TILE_SIZE)
			_tiles_root.add_child(mi)

			# Ray-pickable collider carrying its grid coordinate.
			var body := StaticBody3D.new()
			var shape := BoxShape3D.new()
			shape.size = box.size
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			body.position = mi.position
			body.set_meta("grid_pos", pos)
			_tiles_root.add_child(body)


# --------------------------------------------------------------------------
# Highlight overlays
# --------------------------------------------------------------------------

func _overlay_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = 0.5
	return mat


func clear_overlays() -> void:
	if _overlays == null:
		return
	for c in _overlays.get_children():
		c.queue_free()


func draw_overlay(tiles: Array, color: Color, lift := 0.05, inset := 0.9) -> void:
	var mat := _overlay_material(color)
	var size := TILE_SIZE * inset
	var box := BoxMesh.new()
	box.size = Vector3(size, 0.06, size)
	for t in tiles:
		if not in_bounds(t.x, t.y):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = mat
		mi.position = tile_to_world(t) + Vector3(0, lift, 0)
		_overlays.add_child(mi)


func draw_cursor(pos: Vector2i) -> void:
	var mat := _overlay_material(Color(1.0, 0.9, 0.25, 0.55))
	var box := BoxMesh.new()
	box.size = Vector3(TILE_SIZE, 0.14, TILE_SIZE)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = mat
	mi.position = tile_to_world(pos) + Vector3(0, 0.10, 0)
	_overlays.add_child(mi)
class_name GridPathfinder
extends RefCounted
## Grid movement math for the SRPG: reachable-tile search + path reconstruction.

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Dijkstra search over 4-neighbour tiles.
## `blocked` holds tiles that cannot be *entered* (e.g. enemy-occupied tiles).
## Returns { Vector2i: { "cost": int, "prev": Vector2i-or-null } } including the start.
static func compute(grid: TacticalGrid, start: Vector2i, budget: int, blocked: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	result[start] = {"cost": 0, "prev": null}
	var frontier: Array[Vector2i] = [start]

	while not frontier.is_empty():
		var best_i := 0
		for i in range(1, frontier.size()):
			if result[frontier[i]]["cost"] < result[frontier[best_i]]["cost"]:
				best_i = i
		var current: Vector2i = frontier[best_i]
		frontier.remove_at(best_i)
		var cur_cost: int = result[current]["cost"]

		for dir in DIRS:
			var nxt: Vector2i = current + dir
			if not grid.is_walkable(nxt.x, nxt.y):
				continue
			if blocked.has(nxt):
				continue
			var step := grid.move_cost(current, nxt)
			if step < 0:
				continue
			var nc: int = cur_cost + step
			if nc > budget:
				continue
			if result.has(nxt) and result[nxt]["cost"] <= nc:
				continue
			result[nxt] = {"cost": nc, "prev": current}
			frontier.append(nxt)

	return result


## Reconstruct the ordered path (start -> target) from a `compute` result.
static func build_path(result: Dictionary, target: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not result.has(target):
		return path
	var node: Variant = target
	while node != null:
		var v: Vector2i = node
		path.push_front(v)
		node = result[v]["prev"]
	return path


static func tiles(result: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k in result.keys():
		out.append(k)
	return out
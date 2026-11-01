# AGENTS.md

Conventions for this project: a **3D grid-based tactical SRPG** (Fire Emblem / FFT style) — Godot 4.7, GDScript only, no addons, no C#.

## Project layout

```
res://
  scripts/
	tactical_grid.gd    # map data, terrain meshes, tile picking, highlight overlays
	grid_pathfinder.gd  # pure static math: Dijkstra reach + path rebuild (RefCounted)
  unit.gd             # TacticalUnit: stats, team visuals, tweened movement, damage/heal popups, defend stance, ability uses
	camera_rig.gd       # angled follow camera (rotate/zoom/smoothing)
	hud.gd              # battle HUD (all UI built in code)
	game.gd             # SRPGGame: turn state machine, combat, enemy AI
  main_menu.gd        # title menu + opening cinematic
  world_map.gd        # world map: flyover cinematic, route reveal, party management
  scenes/
	main_menu.tscn      # ENTRY SCENE (application/run/main_scene)
  game.tscn           # battle scene
  world_map.tscn      # world map + chapter-end flow (flyover -> party management)
  unit.tscn           # unit prefab (BaseRing + Body meshes)
```

There is no `assets/` folder — every visual is procedural (BoxMesh / CapsuleMesh / CylinderMesh + StandardMaterial3D). Keep it that way unless asked.

## Code style

- `class_name` at the top of every script; class name matches file name (PascalCase).
- **Type-hint everything**: every `var`, parameter and return type. Use `:=` when the type is inferable.
- Constants `UPPER_SNAKE_CASE`; variables/functions `snake_case`; private members prefixed `_`.
- `##` doc comments on the class and every public function; `# ----` section divider banners.
- Enums for state machines, dispatched with `match` (see `State`, `TacticalUnit.Team`, `Phase`).
- `@export` for tunables, `@onready` for node references, `preload()` for scene constants at file top.
- Gameplay timing/animation is **tween-based** (`create_tween()`, `await tw.finished`) or `get_tree().create_timer().timeout` — no AnimationPlayer. Async game flow is a chain of `await`s (e.g. `_play_intro`, `_resolve_combat`).
- Guard against freed nodes with `is_instance_valid()`.
- Typed containers: `Array[TacticalUnit]`, `Array[Vector2i]`, `Array[String]`.

## Architecture patterns

- **Scene root script is the controller**: `game.tscn` root carries `SRPGGame`, `main_menu.tscn` root carries `MainMenu`. Child systems (Grid, Camera, HUD) are separate nodes with their own scripts.
- **Data-driven spawns**: unit/army definitions are `Dictionary` literals (`{"team": ..., "pos": Vector2i(...)}`).
- **UI is built in code**, never authored in `.tscn` files: `HUD` is a `CanvasLayer`; the menu builds its UI under a `CanvasLayer` child. Style via helper functions returning `StyleBoxFlat`; anchors set by a `_place()` helper.
- **Overlays are redrawn, not updated**: `SRPGGame._refresh()` calls `grid.clear_overlays()` then draws the full highlight set for the current state. Color coding: move=blue, attack=red, path=white, target=orange, cursor=yellow.
- **Occupancy is a Dictionary**: `occupied: Dictionary` maps `Vector2i -> TacticalUnit` and is the single source of truth; units do not query each other.

## Gameplay conventions

- **Grid coordinates are `Vector2i(x, z)`** — note the row is stored in the vector's `.y` field. Convert to world with `TacticalGrid.tile_to_world()`. Tile top height = `elevation * ELEVATION_STEP`.
- **Map layout is a string array** (`TacticalGrid.LAYOUT`): `'1'..'5'` = elevation, `'#'` = impassable rock. Editing the map means editing those strings.
- **Movement**: 4-directional; step cost `1 + elevation rise`; a rise > 1 is impassable. For the player, enemy-occupied tiles block (allies may be passed through); for enemies, all other units block. Range = Dijkstra budget search (`GridPathfinder.compute`), path via `build_path`.
- **Combat**: `dmg = maxi(1, ATK − DEF)`; defender counter-attacks if the attacker is within its range; death = tween scale-down + `queue_free()`, then remove from `occupied`/`units`.
- **Command menu** (opens on selecting an unacted player unit): 移动 Move / 攻击 Attack / 防御 Defend / 技能 Skill / 魔法 Magic / 道具 Item / 等待 Wait, built by `HUD.show_action_menu(options, title)`. 技能 = 猛击 (ATK+5−DEF, 2×/battle) and 破甲 (ignore DEF, 1×); 魔法 = 火球术 (ATK+3−DEF, 3×) and 治疗术 (ally +12 incl. self, 2×); 道具 = 药水 (ally +15 incl. self, 2×). Use counts live in `TacticalUnit.ability_uses` (template `ABILITY_USES`). 防御 sets `TacticalUnit._is_defending` → incoming damage halved in `_resolve_combat` (which takes an optional `damage_override` for skills/magic); stances clear at the start of that unit's team turn. After moving, the post-move menu offers 攻击/防御/等待.
- **Turn flow**: `State { IDLE, COMMAND_MENU, MOVE_SELECT, ACTION_MENU, TARGET_SELECT, BUSY, ENEMY_TURN, GAME_OVER }`. Confirm = `_on_confirm()`, cancel = `_on_cancel()` (Esc or right-click); cancel walks back up the menu chain (target → sub-menu/action menu → command menu) and undoes the move if one was made (unit returns to `active_origin`). Targeting has two modes: `_target_mode` "enemy" (attack/skills/fireball) and "ally" (heal/potion, self allowed).
- **Chapter flow**: battle victory → game-over overlay 「进入大地图」 → `SRPGGame._go_world_map()` packages survivors into `WorldMap.incoming_party` (static handoff, survives the scene change) → `world_map.tscn` plays a flyover cinematic (camera keyframes, staggered route/node reveal, captions; any input skips via `_skip_intro()`) → party management phase (full heal + ability-use reset, roster/detail UI built in code, manual hit-testing) → 完成 fades out and returns to the title screen.
- **Enemy AI**: pick nearest living player unit; compute Dijkstra reach; score tiles by Manhattan distance to target with a −100 bonus for tiles it can attack from; move there, then attack.
- **End conditions**: `alive_units(team).is_empty()` → `GAME_OVER` state + HUD overlay (VICTORY / DEFEAT, Restart, 返回主菜单).

## Input

- Custom actions in `project.godot`: `cam_rot_left` (Q), `cam_rot_right` (E), `end_turn` (T). Built-in `ui_*` actions drive the battle cursor and menu.
- **Battle** listens in `_unhandled_input()` for cursor movement and tile picking; consume events with `get_viewport().set_input_as_handled()`. Never use `accept_event()` — it only exists on `Control`, not `Node3D`.
- **ALL menus** (title screen, battle command/action menus, game-over overlay, world-map party screen) listen in `_input()` and do **manual rect hit-testing** (`HUD.menu_option_at()` / `HUD.game_over_option_at()` + `get_global_rect().has_point()`); menu buttons are visual-only (`MOUSE_FILTER_IGNORE`, `FOCUS_NONE`) and the panel itself is `MOUSE_FILTER_STOP` so background clicks don't leak to tile picking. Do not reintroduce reliance on Godot GUI picking for menus — it was unreliable in this environment.
- Camera-relative cursor movement: snap camera basis axes with `_snap_axis()`.
- **Consume input before scene-changing calls**: `reload_current_scene()` / `change_scene_to_file()` free the current node mid-`_input()`, so `get_viewport()` is null afterwards — call `set_input_as_handled()` BEFORE the switch (see the game-over handler in `game.gd`). This also stops the freshly loaded scene from receiving the same click.

## Scenes (.tscn) format

- `format=3`, `uid` in the header; scripts as `ext_resource`, meshes/materials as `sub_resource`; node sections with `script = ExtResource(...)`.
- `unit.tscn` prefab structure: root `TacticalUnit` (Node3D + script) → `BaseRing` (CylinderMesh) + `Body` (CapsuleMesh). `TacticalUnit.initialize()` must be called after setting `team`/stats/`grid_pos`.
- Each scene sets up its own `WorldEnvironment` + `DirectionalLight3D` (shadows on). The menu has its own plain `Camera3D`; the battle uses `CameraRig` with `current = true`.

## Project settings

- Godot 4.7 stable, renderer `gl_compatibility`, physics Jolt.
- Main scene: `res://scenes/main_menu.tscn`.
- Edit `project.godot` only through the `update_project_setting` tool, never by hand.
- Input actions are added via `update_project_setting` with a `value_literal` of the `InputEventKey` object form (see existing `cam_rot_left` entries in project.godot).

## UI text language

Mixed by design so far: title menu, cinematic, battle command menus and game-over overlay are **Chinese** (often bilingual, e.g. "移动 Move"); the turn banner, terrain info and help block are **English**. When adding strings, match the surface's existing language; if unifying, pick one and apply project-wide.

## Verification (important for this environment)

- After edits, all scripts must report "No problems" in diagnostics.
- **Injected input does not reach a running scene here** (`run_scene` inputs are reported delivered but never arrive in-game). To verify gameplay logic, use `execute_script` headless: `extends SceneTree`, `instantiate()` the scene, `root.add_child()`, `await process_frame` a few times (so `_ready`/`@onready` complete), then call controller methods directly and read `print()` output.
- `run_scene` screenshots still work for visual checks of a given state.
- To test menu actions headlessly, call the handler directly (e.g. `inst._activate_menu(1)`) rather than simulating clicks.

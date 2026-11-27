# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

## Manages sliding ShortcutWall exit barriers for locked event chambers and boss arenas.
class_name RoomBarrierManager
extends RefCounted

var _room_walls: Dictionary[Rect2i, Array] = {}
var _room_cells: Dictionary[Rect2i, Array] = {}
var _locked_room: Rect2i = Rect2i()


func clear() -> void:
	_room_walls.clear()
	_room_cells.clear()
	_locked_room = Rect2i()


func get_locked_room() -> Rect2i:
	return _locked_room


func build_for_ambushes(
	plan: WorldPlan,
	floor_layer: TileMapLayer,
	container: Node2D,
	wall_scene: PackedScene,
) -> void:
	clear()
	for room: Rect2i in plan.wave_ambushes:
		var ambush: WaveAmbush = plan.wave_ambushes[room]
		register_room_exits(room, ambush.exits, plan, floor_layer, container, wall_scene)


func register_room_exits(
	room: Rect2i,
	exits: Array[WaveAmbush.ExitOpening],
	plan: WorldPlan,
	floor_layer: TileMapLayer,
	container: Node2D,
	wall_scene: PackedScene,
) -> void:
	var walls: Array[ShortcutWall] = []
	var cells: Array[Vector2i] = []
	for exit: WaveAmbush.ExitOpening in exits:
		var n: int = exit.cells.size()
		if n <= 0:
			continue
		for c: Vector2i in exit.cells:
			cells.append(c)
		if n == 1:
			var single: ShortcutWall = wall_scene.instantiate() as ShortcutWall
			single.position = floor_layer.map_to_local(exit.cells[0])
			container.add_child(single)
			single.setup(exit.is_horizontal, plan.get_cell_tile_set(exit.cells[0]), true)
			walls.append(single)
			continue
		var idx: int = 0
		while idx + 1 < n:
			var w: ShortcutWall = wall_scene.instantiate() as ShortcutWall
			w.position = (floor_layer.map_to_local(exit.cells[idx]) + floor_layer.map_to_local(exit.cells[idx + 1])) * 0.5
			container.add_child(w)
			w.setup(exit.is_horizontal, plan.get_cell_tile_set(exit.cells[idx]), true)
			walls.append(w)
			idx += 2
		if n % 2 == 1:
			var tail: ShortcutWall = wall_scene.instantiate() as ShortcutWall
			tail.position = (floor_layer.map_to_local(exit.cells[n - 2]) + floor_layer.map_to_local(exit.cells[n - 1])) * 0.5
			container.add_child(tail)
			tail.setup(exit.is_horizontal, plan.get_cell_tile_set(exit.cells[n - 1]), true)
			walls.append(tail)
	_room_walls[room] = walls
	_room_cells[room] = cells


func lock_room(
	room: Rect2i,
	walkable_cells: Dictionary[Vector2i, bool],
	nav_window: NavWindow,
) -> void:
	_locked_room = room
	var walls: Array = _room_walls.get(room, [])
	for w_var: Variant in walls:
		if w_var is ShortcutWall:
			var wall: ShortcutWall = w_var
			wall.close_animated()
	var cells: Array = _room_cells.get(room, [])
	for c_var: Variant in cells:
		if c_var is Vector2i:
			var cell: Vector2i = c_var
			walkable_cells[cell] = false
			nav_window.set_cell_walkable(cell, false)
	Audio.play_sfx(Audio.Sfx.SHORTCUT_OPEN)


func unlock_room(
	room: Rect2i,
	walkable_cells: Dictionary[Vector2i, bool],
	nav_window: NavWindow,
) -> void:
	if _locked_room == room:
		_locked_room = Rect2i()
	var walls: Array = _room_walls.get(room, [])
	for w_var: Variant in walls:
		if w_var is ShortcutWall:
			var wall: ShortcutWall = w_var
			wall.open_animated()
	var cells: Array = _room_cells.get(room, [])
	for c_var: Variant in cells:
		if c_var is Vector2i:
			var cell: Vector2i = c_var
			walkable_cells[cell] = true
			nav_window.set_cell_walkable(cell, true)
	Audio.play_sfx(Audio.Sfx.SHORTCUT_OPEN)

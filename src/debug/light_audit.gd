# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name LightAudit
extends Node2D

const MAP_SCENE: PackedScene = preload("res://map/map.tscn")
const LIGHT_RADIUS_TILES: float = 11.2
const LIGHT_RADIUS_PX: float = 179.2
const LIGHT_BASE_ENERGY: float = 1.1

var _seed: int = 101
var _max_depth: int = 6
var _out_dir: String = "res://debug/output"
var _map_instance: Node2D = null


func _ready() -> void:
	_parse_arguments()
	_run_audit()


func _parse_arguments() -> void:
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in user_args:
		if arg.begins_with(&"--seed="):
			_seed = int(arg.trim_prefix(&"--seed="))
		elif arg.begins_with(&"--depth="):
			_max_depth = int(arg.trim_prefix(&"--depth="))
		elif arg.begins_with(&"--out-dir="):
			_out_dir = arg.trim_prefix(&"--out-dir=")


func _run_audit() -> void:
	print(&"[LightAudit] Starting audit for seed %d, depth %d" % [_seed, _max_depth])
	_map_instance = MAP_SCENE.instantiate() as Node2D
	add_child(_map_instance)

	var map: Map = _map_instance as Map
	map.debug_seed = _seed
	map.plan.generate(_seed, _max_depth)

	var carve_rects: Array[Rect2i] = map.plan.carve_rects
	if carve_rects.is_empty():
		printerr(&"[LightAudit] No carve rects in plan!")
		get_tree().quit(1)
		return

	var full_bounds: Rect2i = carve_rects[0]
	for r: Rect2i in carve_rects:
		full_bounds = full_bounds.merge(r)

	full_bounds = full_bounds.grow(4)
	print(&"[LightAudit] Dungeon bounds: ", full_bounds)

	map.hero_room = map.plan.hero_room
	map.companion_rooms.clear()
	for d: int in range(1, _max_depth + 1):
		map.companion_rooms.append_array(map.plan.get_depth_rooms(d))

	map.light_manager.setup(_seed)
	map.streamer.setup(
		map.plan,
		map.get_node(^"Floor") as TileMapLayer,
		map.get_node(^"Walls") as TileMapLayer,
		map.get_node(^"Decorations") as TileMapLayer,
		map.light_manager,
		null,
		map._walkable_cells,
		_seed
	)

	map.streamer.materialize_rect_immediate(full_bounds)

	var all_rooms: Array[Rect2i] = [map.hero_room]
	all_rooms.append_array(map.companion_rooms)
	map.decorate_rooms(all_rooms)

	var lights: Array[TorchLight] = map.light_manager._all_lights
	print(&"[LightAudit] Total lights materialized: %d" % lights.size())

	_evaluate_and_export(map, full_bounds, lights)
	get_tree().quit(0)


func _evaluate_and_export(map: Map, bounds: Rect2i, lights: Array[TorchLight]) -> void:
	var width: int = bounds.size.x
	var height: int = bounds.size.y
	var img: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 1.0))

	var total_floor_cells: int = 0
	var room_cells: int = 0
	var corridor_cells: int = 0

	var room_lit: int = 0
	var room_dim: int = 0
	var room_dark: int = 0

	var corridor_lit: int = 0
	var corridor_dim: int = 0
	var corridor_dark: int = 0

	var light_positions_tiles: Array[Vector2] = []
	for torch: TorchLight in lights:
		if is_instance_valid(torch):
			light_positions_tiles.append(torch.position / 16.0)

	var floor_grid: Dictionary[Vector2i, float] = {}

	for ly: int in range(height):
		var gy: int = bounds.position.y + ly
		for lx: int in range(width):
			var gx: int = bounds.position.x + lx
			var cell: Vector2i = Vector2i(gx, gy)

			if not map.plan.is_floor(cell):
				var is_wall_near: bool = false
				for dy: int in range(-1, 2):
					for dx: int in range(-1, 2):
						if map.plan.is_floor(cell + Vector2i(dx, dy)):
							is_wall_near = true
							break
					if is_wall_near:
						break
				if is_wall_near:
					img.set_pixel(lx, ly, Color(0.08, 0.08, 0.16, 1.0))
				continue

			total_floor_cells += 1
			var cell_center: Vector2 = Vector2(cell) + Vector2(0.5, 0.5)

			var total_light: float = 0.0
			for lpos: Vector2 in light_positions_tiles:
				var dist: float = cell_center.distance_to(lpos)
				if dist <= LIGHT_RADIUS_TILES:
					var norm_dist: float = dist / LIGHT_RADIUS_TILES
					var alpha: float = _calculate_gradient_alpha(norm_dist)
					total_light += LIGHT_BASE_ENERGY * alpha
					if total_light >= 1.0:
						break

			total_light = clampf(total_light, 0.0, 1.0)
			floor_grid[cell] = total_light

			var room: Rect2i = map.plan.get_room_at(cell)
			var is_room: bool = room != Rect2i()

			if is_room:
				room_cells += 1
				if total_light >= 0.35:
					room_lit += 1
				elif total_light >= 0.15:
					room_dim += 1
				else:
					room_dark += 1
			else:
				corridor_cells += 1
				if total_light >= 0.35:
					corridor_lit += 1
				elif total_light >= 0.15:
					corridor_dim += 1
				else:
					corridor_dark += 1

			var val: float = total_light
			var pixel_col: Color = Color(val, val * 0.85, val * 0.6, 1.0)
			if val < 0.15:
				pixel_col = Color(0.02, 0.02, 0.03, 1.0)
			img.set_pixel(lx, ly, pixel_col)

	for lpos: Vector2 in light_positions_tiles:
		var lx: int = int(roundf(lpos.x)) - bounds.position.x
		var ly: int = int(roundf(lpos.y)) - bounds.position.y
		if lx >= 0 and lx < width and ly >= 0 and ly < height:
			img.set_pixel(lx, ly, Color(1.0, 0.2, 0.2, 1.0))

	_ensure_directory(_out_dir)

	var png_path: String = _out_dir.path_join(&"audit_%d.png" % _seed)
	var real_png_path: String = ProjectSettings.globalize_path(png_path)
	var err: Error = img.save_png(real_png_path)
	if err != OK:
		printerr(&"[LightAudit] Failed to save PNG to: ", real_png_path)

	var room_lit_pct: float = float(room_lit) / float(maxi(1, room_cells)) * 100.0
	var room_dim_pct: float = float(room_dim) / float(maxi(1, room_cells)) * 100.0
	var room_dark_pct: float = float(room_dark) / float(maxi(1, room_cells)) * 100.0

	var corr_lit_pct: float = float(corridor_lit) / float(maxi(1, corridor_cells)) * 100.0
	var corr_dim_pct: float = float(corridor_dim) / float(maxi(1, corridor_cells)) * 100.0
	var corr_dark_pct: float = float(corridor_dark) / float(maxi(1, corridor_cells)) * 100.0

	var metrics: Dictionary = {
		&"seed": _seed,
		&"bounds": {"x": bounds.position.x, "y": bounds.position.y, "w": bounds.size.x, "h": bounds.size.y},
		&"total_lights": lights.size(),
		&"total_floor_cells": total_floor_cells,
		&"room_cells": room_cells,
		&"room_lit_pct": room_lit_pct,
		&"room_dim_pct": room_dim_pct,
		&"room_dark_pct": room_dark_pct,
		&"corridor_cells": corridor_cells,
		&"corridor_lit_pct": corr_lit_pct,
		&"corridor_dim_pct": corr_dim_pct,
		&"corridor_dark_pct": corr_dark_pct,
	}

	var json_path: String = _out_dir.path_join(&"audit_%d.json" % _seed)
	var real_json_path: String = ProjectSettings.globalize_path(json_path)
	var file: FileAccess = FileAccess.open(real_json_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(metrics, "\t"))
		file.close()

	print(&"[LightAudit] Exported audit_%d.png and audit_%d.json to %s" % [_seed, _seed, real_png_path])
	print(&"[LightAudit] Rooms: %.1f%% lit, %.1f%% dim, %.1f%% dark" % [room_lit_pct, room_dim_pct, room_dark_pct])
	print(&"[LightAudit] Corridors: %.1f%% lit, %.1f%% dim, %.1f%% dark" % [corr_lit_pct, corr_dim_pct, corr_dark_pct])


static func _calculate_gradient_alpha(norm_dist: float) -> float:
	if norm_dist >= 1.0:
		return 0.0
	if norm_dist <= 0.25:
		return lerpf(1.0, 0.8, norm_dist / 0.25)
	if norm_dist <= 0.6:
		return lerpf(0.8, 0.2, (norm_dist - 0.25) / 0.35)
	return lerpf(0.2, 0.0, (norm_dist - 0.6) / 0.4)


static func _ensure_directory(dir_path: String) -> void:
	var global_dir: String = ProjectSettings.globalize_path(dir_path)
	if not DirAccess.dir_exists_absolute(global_dir):
		DirAccess.make_dir_recursive_absolute(global_dir)

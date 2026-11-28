# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

## Manages map overlay escapee markers, fallen companion tombstones, and the run summary bar.
class_name MapRunMarkers
extends RefCounted


class EscapeeMarkerEntry:
	extends RefCounted
	var room: Rect2i
	var world_center: Vector2
	var label: Label
	var remaining: int = 0

	func _init(entry_room: Rect2i, entry_center: Vector2, entry_label: Label, entry_remaining: int) -> void:
		room = entry_room
		world_center = entry_center
		label = entry_label
		remaining = entry_remaining


class TombstoneMarkerEntry:
	extends RefCounted
	var world_pos: Vector2
	var node: Node2D

	func _init(entry_pos: Vector2, entry_node: Node2D) -> void:
		world_pos = entry_pos
		node = entry_node


const TILE_SIZE: float = 16.0
const CHUNK_SIZE_TILES: int = 2
const ROOM_AUTO_COMPLETE_RATIO: float = 0.78
const TOMBSTONE_MARKER_SCENE: PackedScene = preload("res://hud/map_overlay/map_tombstone_marker.tscn")
const ESCAPEE_MARKER_SCENE: PackedScene = preload("res://hud/map_overlay/map_escapee_marker.tscn")
const ESCAPEE_LABEL_OFFSET: Vector2 = Vector2(-10.0, -16.0)

var _summary_label: Label = null
var _escapee_container: Node2D = null
var _tombstone_container: Node2D = null
var _room_escapee_counts: Dictionary[Rect2i, int] = {}
var _escapee_markers_by_room: Dictionary[Rect2i, EscapeeMarkerEntry] = {}
var _escapee_label_pool: Array[Label] = []
var _next_escapee_pool_idx: int = 0
var _tombstone_entries: Array[TombstoneMarkerEntry] = []
var _summary_rescued: int = 0
var _summary_total: int = 0
var _summary_fallen: int = 0
var _summary_explored_pct: int = 0
var _summary_elapsed_secs: float = 0.0
var _total_floor_chunks: int = 0
var _explored_floor_chunks: Dictionary[Vector2i, bool] = {}
var _room_chunks: Dictionary[Rect2i, Array] = {}
var _room_explored_counts: Dictionary[Rect2i, int] = {}
var _completed_rooms: Dictionary[Rect2i, bool] = {}
var _chunk_to_rooms: Dictionary[Vector2i, Array] = {}


func bind_ui(summary_label: Label, escapee_container: Node2D, tombstone_container: Node2D) -> void:
	_summary_label = summary_label
	_escapee_container = escapee_container
	_tombstone_container = tombstone_container


func reset() -> void:
	_room_escapee_counts.clear()
	_escapee_markers_by_room.clear()
	_next_escapee_pool_idx = 0
	for label: Label in _escapee_label_pool:
		label.visible = false
	_tombstone_entries.clear()
	for child: Node in _tombstone_container.get_children():
		child.queue_free()
	_summary_rescued = 0
	_summary_total = 0
	_summary_fallen = 0
	_summary_explored_pct = 0
	_summary_elapsed_secs = 0.0
	_total_floor_chunks = 0
	_explored_floor_chunks.clear()
	_room_chunks.clear()
	_room_explored_counts.clear()
	_completed_rooms.clear()
	_chunk_to_rooms.clear()
	_update_summary_label()


func setup_exploration(plan: WorldPlan, floor_chunks: Dictionary[Vector2i, PackedVector2Array]) -> void:
	_total_floor_chunks = floor_chunks.size()
	_explored_floor_chunks.clear()
	_room_chunks.clear()
	_room_explored_counts.clear()
	_completed_rooms.clear()
	_chunk_to_rooms.clear()
	_summary_explored_pct = 0

	var all_rooms: Array[Rect2i] = []
	if plan.hero_room.size != Vector2i.ZERO:
		all_rooms.append(plan.hero_room)
	all_rooms.append_array(plan.rooms)

	for room: Rect2i in all_rooms:
		var min_cx: int = floori(float(room.position.x) / float(CHUNK_SIZE_TILES))
		var max_cx: int = floori(float(room.end.x - 1) / float(CHUNK_SIZE_TILES))
		var min_cy: int = floori(float(room.position.y) / float(CHUNK_SIZE_TILES))
		var max_cy: int = floori(float(room.end.y - 1) / float(CHUNK_SIZE_TILES))
		var chunks: Array[Vector2i] = []
		for cy: int in range(min_cy, max_cy + 1):
			for cx: int in range(min_cx, max_cx + 1):
				var coord: Vector2i = Vector2i(cx, cy)
				if floor_chunks.has(coord):
					chunks.append(coord)
		if chunks.is_empty():
			continue
		_room_chunks[room] = chunks
		_room_explored_counts[room] = 0
		for coord: Vector2i in chunks:
			if not _chunk_to_rooms.has(coord):
				_chunk_to_rooms[coord] = []
			var room_list: Array = _chunk_to_rooms[coord]
			room_list.append(room)

	_update_summary_label()


func record_explored_chunk(coord: Vector2i, floor_chunks: Dictionary[Vector2i, PackedVector2Array]) -> Array[Vector2i]:
	var auto_completed: Array[Vector2i] = []
	if not floor_chunks.has(coord) or _explored_floor_chunks.has(coord):
		return auto_completed

	_explored_floor_chunks[coord] = true
	if _chunk_to_rooms.has(coord):
		var rooms_for_chunk: Array = _chunk_to_rooms[coord]
		for room_var: Variant in rooms_for_chunk:
			if room_var is Rect2i:
				var room: Rect2i = room_var
				var next_count: int = _room_explored_counts.get(room, 0) + 1
				_room_explored_counts[room] = next_count
				if not _completed_rooms.has(room):
					var room_chunk_arr: Array = _room_chunks[room]
					if not room_chunk_arr.is_empty() and float(next_count) / float(room_chunk_arr.size()) >= ROOM_AUTO_COMPLETE_RATIO:
						_completed_rooms[room] = true
						for c_var: Variant in room_chunk_arr:
							if c_var is Vector2i:
								var rc: Vector2i = c_var
								if not _explored_floor_chunks.has(rc):
									_explored_floor_chunks[rc] = true
									auto_completed.append(rc)

	_summary_explored_pct = get_explored_percent()
	_update_summary_label()
	return auto_completed


func sync_explored_chunks(explored_chunks: Dictionary[Vector2i, bool], floor_chunks: Dictionary[Vector2i, PackedVector2Array]) -> void:
	for coord: Vector2i in explored_chunks:
		if floor_chunks.has(coord):
			_explored_floor_chunks[coord] = true
	_summary_explored_pct = get_explored_percent()
	_update_summary_label()


func get_explored_percent() -> int:
	if _total_floor_chunks <= 0:
		return 0
	if _explored_floor_chunks.size() >= _total_floor_chunks:
		return 100
	return clampi(roundi((float(_explored_floor_chunks.size()) / float(_total_floor_chunks)) * 100.0), 0, 99)


func set_run_counts(rescued: int, total: int, fallen: int) -> void:
	_summary_rescued = rescued
	_summary_total = total
	_summary_fallen = fallen
	_update_summary_label()


func set_run_time(elapsed_seconds: float) -> void:
	_summary_elapsed_secs = elapsed_seconds
	_update_summary_label()


func on_room_discovered(room: Rect2i, world_center: Vector2) -> void:
	var unrescued: int = _room_escapee_counts.get(room, 0)
	if unrescued > 0:
		_ensure_escapee_marker(room, world_center, unrescued)


func set_room_escapee_counts(counts: Dictionary[Rect2i, int], discovered_labels: Array[MapOverlay.RoomLabelEntry]) -> void:
	_room_escapee_counts = counts.duplicate()
	for entry: MapOverlay.RoomLabelEntry in discovered_labels:
		var remaining: int = _room_escapee_counts.get(entry.room, 0)
		if remaining > 0 or _escapee_markers_by_room.has(entry.room):
			_ensure_escapee_marker(entry.room, entry.world_center, remaining)


func set_room_unrescued_escapees(room: Rect2i, remaining: int, is_discovered: bool) -> void:
	var clamped: int = maxi(0, remaining)
	_room_escapee_counts[room] = clamped
	if _escapee_markers_by_room.has(room):
		var marker: EscapeeMarkerEntry = _escapee_markers_by_room[room]
		marker.remaining = clamped
		marker.label.text = _format_escapee_marker(clamped)
		if clamped <= 0:
			marker.label.visible = false
	elif clamped > 0 and is_discovered:
		var world_center: Vector2 = (Vector2(room.position) + Vector2(room.size) * 0.5) * TILE_SIZE
		_ensure_escapee_marker(room, world_center, clamped)


func add_tombstone_marker(world_pos: Vector2, class_color: Color) -> void:
	var marker: Node2D = TOMBSTONE_MARKER_SCENE.instantiate() as Node2D
	var accent: Polygon2D = marker.get_node("Accent") as Polygon2D
	accent.color = class_color
	marker.visible = false
	_tombstone_container.add_child(marker)
	_tombstone_entries.append(TombstoneMarkerEntry.new(world_pos, marker))


func update_positions(viewport_center: Vector2, cam_scaled: Vector2, map_scale: float, vp_size: Vector2) -> void:
	for esc_entry: EscapeeMarkerEntry in _escapee_markers_by_room.values():
		if esc_entry.remaining <= 0:
			esc_entry.label.visible = false
			continue
		var esc_pos: Vector2 = viewport_center + (esc_entry.world_center * map_scale).round() - cam_scaled + ESCAPEE_LABEL_OFFSET
		var esc_on_vp: bool = esc_pos.x >= -24.0 and esc_pos.x <= vp_size.x and esc_pos.y >= -16.0 and esc_pos.y <= vp_size.y
		esc_entry.label.visible = esc_on_vp
		if esc_on_vp:
			esc_entry.label.position = esc_pos

	for tomb_entry: TombstoneMarkerEntry in _tombstone_entries:
		var tomb_pos: Vector2 = viewport_center + (tomb_entry.world_pos * map_scale).round() - cam_scaled
		var tomb_on_vp: bool = tomb_pos.x >= -12.0 and tomb_pos.x <= vp_size.x + 12.0 and tomb_pos.y >= -12.0 and tomb_pos.y <= vp_size.y + 12.0
		tomb_entry.node.visible = tomb_on_vp
		if tomb_on_vp:
			tomb_entry.node.position = tomb_pos


func _ensure_escapee_marker(room: Rect2i, world_center: Vector2, remaining: int) -> void:
	if _escapee_markers_by_room.has(room):
		var existing: EscapeeMarkerEntry = _escapee_markers_by_room[room]
		existing.remaining = remaining
		existing.label.text = _format_escapee_marker(remaining)
		if remaining <= 0:
			existing.label.visible = false
		return

	if remaining <= 0:
		return

	var marker_label: Label
	if _next_escapee_pool_idx < _escapee_label_pool.size():
		marker_label = _escapee_label_pool[_next_escapee_pool_idx]
	else:
		marker_label = ESCAPEE_MARKER_SCENE.instantiate() as Label
		_escapee_label_pool.append(marker_label)
		_escapee_container.add_child(marker_label)
	_next_escapee_pool_idx += 1

	marker_label.visible = false
	marker_label.text = _format_escapee_marker(remaining)
	_escapee_markers_by_room[room] = EscapeeMarkerEntry.new(room, world_center, marker_label, remaining)


static func _format_escapee_marker(remaining: int) -> String:
	return "?" if remaining <= 1 else ("?x%d" % remaining)


func _update_summary_label() -> void:
	_summary_label.text = (
		&"Escapees: %d / %d  |  Fallen: %d  |  Explored: %d%%  |  %s"
		% [
			_summary_rescued,
			_summary_total,
			_summary_fallen,
			_summary_explored_pct,
			RunStats.format_duration(_summary_elapsed_secs),
		]
	)

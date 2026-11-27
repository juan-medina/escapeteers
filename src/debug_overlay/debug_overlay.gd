# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

## Editor-only F9 playtest menu for warping to special rooms, building squads, and inspecting encounters.
class_name DebugOverlay
extends CanvasLayer

const SQUAD_PRESET_IDS: Array[StringName] = [
	&"knight",
	&"swordsman",
	&"archer",
	&"priest",
	&"wizard",
	&"armored_axeman",
	&"soldier",
	&"knight_templar",
]

var _game: Game = null
var _warp_indices: Dictionary[int, int] = {}
var _squad_preset_cursor: int = 0

@onready var _status_label: Label = $Center/Panel/VBox/StatusLabel
@onready var _blood_spikes_btn: Button = $Center/Panel/VBox/WarpGrid/BloodSpikesBtn
@onready var _wave_ambush_btn: Button = $Center/Panel/VBox/WarpGrid/WaveAmbushBtn
@onready var _obelisk_btn: Button = $Center/Panel/VBox/WarpGrid/ObeliskBtn
@onready var _god_mode_btn: Button = $Center/Panel/VBox/ToolsGrid/GodModeBtn


func is_debug_enabled() -> bool:
	return OS.has_feature("editor")


func _ready() -> void:
	visible = false
	_game = get_parent() as Game
	if not is_debug_enabled():
		set_process_unhandled_input(false)
		return
	Audio.connect_menu_sounds(self)


func _exit_tree() -> void:
	Hero.god_mode = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F9:
			if visible:
				_close()
				get_viewport().set_input_as_handled()
				return
			if not get_tree().paused and _game._character != null and not _game._character.is_dead:
				_open()
				get_viewport().set_input_as_handled()
				return
	if visible and (event.is_action_pressed(&"pause") or event.is_action_pressed(&"back")):
		_close()
		get_viewport().set_input_as_handled()


func _open() -> void:
	get_tree().paused = true
	visible = true
	_refresh_status()
	Audio.grab_focus_silent(_obelisk_btn)


func _close() -> void:
	get_viewport().gui_release_focus()
	visible = false
	get_tree().paused = false


func _refresh_status() -> void:
	var room_depth: int = _game._map.get_room_depth(_game._current_room) if _game._current_room != Rect2i() else 0
	var god_str: String = "ON" if Hero.god_mode else "OFF"
	_status_label.text = (
		"Depth: %d | Squad: %d | Lv: %d | God: %s"
		% [
			room_depth,
			_game._squad.size(),
			_game._squad_level,
			god_str,
		]
	)
	_god_mode_btn.text = "God Mode: %s" % god_str
	_blood_spikes_btn.text = "Blood Spikes (%d)" % _collect_event_rooms(WorldPlan.RoomEventType.CLOSING_SPIKES).size()
	_wave_ambush_btn.text = "Cursed Ambush (%d)" % _collect_event_rooms(WorldPlan.RoomEventType.WAVE_AMBUSH).size()
	_obelisk_btn.text = "Cursed Obelisks (%d)" % _collect_event_rooms(WorldPlan.RoomEventType.CURSED_OBELISKS).size()


func _collect_event_rooms(event_type: WorldPlan.RoomEventType) -> Array[Rect2i]:
	var uncleared: Array[Rect2i] = []
	var fallback: Array[Rect2i] = []
	var plan: WorldPlan = _game._map.plan
	for room: Rect2i in plan.room_event_types:
		if plan.room_event_types[room] != event_type:
			continue
		fallback.append(room)
		if _is_event_room_uncleared(plan, room, event_type):
			uncleared.append(room)
	var chosen: Array[Rect2i] = uncleared if not uncleared.is_empty() else fallback
	chosen.sort_custom(_compare_room_depth_asc)
	return chosen


func _is_event_room_uncleared(plan: WorldPlan, room: Rect2i, event_type: WorldPlan.RoomEventType) -> bool:
	match event_type:
		WorldPlan.RoomEventType.CLOSING_SPIKES:
			var hazard: ClosingSpikeHazard = plan.closing_spike_hazards.get(room, null)
			return hazard != null and not hazard.is_cleared
		WorldPlan.RoomEventType.WAVE_AMBUSH:
			var ambush: WaveAmbush = plan.wave_ambushes.get(room, null)
			return ambush != null and not ambush.is_cleared
		WorldPlan.RoomEventType.CURSED_OBELISKS:
			var enc: ObeliskEncounter = plan.obelisk_encounters.get(room, null)
			return enc != null and not enc.is_cleared
		_:
			return false


func _compare_room_depth_asc(a: Rect2i, b: Rect2i) -> bool:
	return _game._map.get_room_depth(a) < _game._map.get_room_depth(b)


func _on_warp_blood_spikes_pressed() -> void:
	_warp_to_event_type(WorldPlan.RoomEventType.CLOSING_SPIKES, &"Blood Spike")


func _on_warp_wave_ambush_pressed() -> void:
	_warp_to_event_type(WorldPlan.RoomEventType.WAVE_AMBUSH, &"Cursed Ambush")


func _on_warp_obelisks_pressed() -> void:
	_warp_to_event_type(WorldPlan.RoomEventType.CURSED_OBELISKS, &"Cursed Obelisk")


func _warp_to_event_type(event_type: WorldPlan.RoomEventType, label_name: StringName) -> void:
	var candidates: Array[Rect2i] = _collect_event_rooms(event_type)
	if candidates.is_empty():
		_game._hud.show_event_toast(&"No %s rooms in this dungeon" % label_name, Color(1.0, 0.45, 0.45, 1.0))
		return
	var idx: int = _warp_indices.get(event_type, 0) % candidates.size()
	_warp_indices[event_type] = idx + 1
	_warp_squad_to_room(candidates[idx])
	_close()


func _on_warp_deeper_pressed() -> void:
	var cur_depth: int = _game._map.get_room_depth(_game._current_room) if _game._current_room != Rect2i() else 0
	var candidates: Array[Rect2i] = []
	for room: Rect2i in _game._map.plan.rooms:
		if _game._map.get_room_depth(room) >= cur_depth + 2:
			candidates.append(room)
	if candidates.is_empty():
		candidates = _game._map.plan.rooms.duplicate()
	if candidates.is_empty():
		return
	candidates.sort_custom(_compare_room_depth_asc)
	_warp_squad_to_room(candidates[0])
	_close()


func _warp_squad_to_room(room: Rect2i) -> void:
	var map: Map = _game._map
	map.streamer.materialize_rect_immediate(room.grow(16))
	var landing_cell: Vector2i = _pick_landing_cell(room)
	var landing_pos: Vector2 = map.map_to_local(landing_cell)
	_game._character.position = landing_pos
	_game._character.velocity = Vector2.ZERO
	_game._character.record_step(0.0)
	_game._camera.position = landing_pos
	for i: int in range(1, _game._squad.size()):
		var follower: Hero = _game._squad[i]
		if not follower.is_dead:
			follower.squad_member.teleport_to_leader(follower, map)
	map.update_streaming(landing_pos, Vector2.ZERO)
	_game._update_map_streaming()
	_game._check_room_entry()


func _pick_landing_cell(room: Rect2i) -> Vector2i:
	var map: Map = _game._map
	var plan: WorldPlan = map.plan
	var center: Vector2i = room.get_center()
	var is_event: bool = plan.is_event_room(room)
	var excluded: Dictionary[Vector2i, bool] = {}
	if plan.closing_spike_hazards.has(room):
		excluded[plan.closing_spike_hazards[room].bait_cell] = true
	if plan.wave_ambushes.has(room):
		excluded[plan.wave_ambushes[room].bait_cell] = true
	if plan.obelisk_encounters.has(room):
		var enc: ObeliskEncounter = plan.obelisk_encounters[room]
		excluded[enc.bait_cell] = true
		for c: Vector2i in enc.obelisk_cells:
			excluded[c] = true

	var inner: Rect2i = room.grow(-2)
	var best: Vector2i = center
	var best_score: float = INF
	for y: int in range(inner.position.y, inner.end.y):
		for x: int in range(inner.position.x, inner.end.x):
			var c: Vector2i = Vector2i(x, y)
			if excluded.has(c) or not plan.is_floor(c) or not plan.is_floor(c + Vector2i(0, -1)):
				continue
			if map.is_spike_active_at(c):
				continue
			var d_sq: float = float(c.distance_squared_to(center))
			if is_event and d_sq < 16.0:
				continue
			var score: float = absf(d_sq - 25.0) if is_event else d_sq
			if score < best_score:
				best_score = score
				best = c
	return best


func _on_add_squad_pressed() -> void:
	var added: int = 0
	for _i: int in range(4):
		if _game._squad.size() >= Game.MAX_CHARACTERS:
			break
		var hero_id: StringName = SQUAD_PRESET_IDS[_squad_preset_cursor % SQUAD_PRESET_IDS.size()]
		_squad_preset_cursor += 1
		var data: HeroData = HeroData.get_hero(hero_id)
		if data == null:
			continue
		if not _game._class_levels.has(hero_id):
			_game._class_levels[hero_id] = 1
		_game._spawn_hero(data, _game._character.position, false)
		added += 1
	if added > 0:
		_game._rebalance_escort_slots()
		_game._hud.update_squad(_game._squad)
		_refresh_status()


func _on_level_up_all_pressed() -> void:
	var seen: Dictionary[StringName, bool] = {}
	for member: Hero in _game._squad:
		if member.is_dead or member.hero_data == null:
			continue
		var cid: StringName = member.hero_data.id
		if not seen.has(cid):
			seen[cid] = true
			_game._class_levels[cid] = _game._class_levels.get(cid, 1) + 1
	for member: Hero in _game._squad:
		if member.is_dead or member.hero_data == null:
			continue
		var data: HeroData = member.hero_data
		var new_lv: int = _game._class_levels.get(data.id, 1)
		data.apply_to_hero(member, new_lv)
		member.health = member.max_health
		member.play_level_up_vfx()
	_game._squad_level += 1
	_game._hud.update_xp(_game._current_xp, _game._xp_required, _game._squad_level)
	_game._hud.update_squad(_game._squad)
	_refresh_status()


func _on_heal_squad_pressed() -> void:
	for member: Hero in _game._squad:
		if not member.is_dead:
			member.heal(member.max_health)
	_game._hud.update_squad(_game._squad)
	_refresh_status()


func _on_grant_keys_pressed() -> void:
	var colors: Array[WorldPlan.KeyColor] = [
		WorldPlan.KeyColor.BLUE,
		WorldPlan.KeyColor.GREEN,
		WorldPlan.KeyColor.YELLOW,
		WorldPlan.KeyColor.RED,
	]
	for color: WorldPlan.KeyColor in colors:
		_game._collected_keys[color] = true
		_game._hud.set_key_state(color, true, false)
	for key_node: KeyPickup in _game._keys:
		if is_instance_valid(key_node):
			key_node.queue_free()
	_game._keys.clear()
	_game._hud.show_event_toast(&"All Keys Granted", Color(1.0, 0.85, 0.35, 1.0))


func _on_god_mode_pressed() -> void:
	Hero.god_mode = not Hero.god_mode
	_refresh_status()


func _on_reveal_map_pressed() -> void:
	var overlay: MapOverlay = _game._hud._map_overlay
	var meshes: MapChunkMeshes = overlay._chunk_meshes
	for coord: Vector2i in meshes._chunk_floor_vertices:
		_reveal_and_explore_chunk(overlay, meshes, coord)
	for coord: Vector2i in meshes._chunk_segments:
		_reveal_and_explore_chunk(overlay, meshes, coord)
	for room: Rect2i in _game._map.plan.rooms:
		overlay.mark_room_discovered(room)
	overlay.mark_room_discovered(_game._map.hero_room)
	overlay._update_gate_markers_visibility()
	overlay._dirty = true
	if overlay.visible:
		overlay._rebuild_meshes()
	_game._hud.show_event_toast(&"Full Map Revealed", Color(0.55, 0.90, 1.0, 1.0))


func _reveal_and_explore_chunk(overlay: MapOverlay, meshes: MapChunkMeshes, coord: Vector2i) -> void:
	if not overlay._revealed_chunks.has(coord):
		overlay._record_revealed_chunk(coord)
		meshes.reveal_chunk(coord, true)
	if not overlay._explored_chunks.has(coord):
		overlay._explored_chunks[coord] = true
		meshes.explore_chunk(coord)


func _on_clear_room_pressed() -> void:
	var room: Rect2i = _game._current_room
	if room == Rect2i():
		return
	var obelisks: Array[CursedObelisk] = _game._event_director.get_active_obelisks_in_room(room)
	for obelisk: CursedObelisk in obelisks:
		if not obelisk.is_dead:
			obelisk.take_damage(999999.0, false)
	for enemy: Enemy in _game._enemies.duplicate():
		if is_instance_valid(enemy) and not enemy.is_dead and enemy.home_room == room:
			enemy.is_damage_immune = false
			enemy.take_damage(999999.0, false)
	_close()


func _on_close_pressed() -> void:
	_close()

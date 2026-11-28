# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name EventDirector
extends RefCounted

const EVENT_MUSIC_FADE_IN: float = 0.35
const EVENT_MUSIC_FADE_OUT: float = 0.65
const EVENT_SHAKE_STRENGTH: float = 4.0
const EVENT_SHAKE_DURATION: float = 0.25
const EVENT_WARNING_COLOR: Color = Color(1.0, 0.28, 0.28, 1.0)
const EVENT_WAVE_COLOR: Color = Color(0.82, 0.42, 1.0, 1.0)
const EVENT_CLEAR_COLOR: Color = Color(1.0, 0.85, 0.35, 1.0)
const CURSED_CHEST_SCENE: PackedScene = preload("res://cursed_chest/cursed_chest.tscn")
const CURSED_OBELISK_SCENE: PackedScene = preload("res://cursed_obelisk/cursed_obelisk.tscn")
const RUNE_PLATE_SCENE: PackedScene = preload("res://rune_plate/rune_plate.tscn")

var _hud: Hud
var _fog: Fog
var _camera: Camera2D
var _active_event_room: Rect2i = Rect2i()
var _cursed_chests: Array[CursedChest] = []
var _chests_by_room: Dictionary[Rect2i, CursedChest] = {}
var _obelisks_by_room: Dictionary[Rect2i, Array] = {}
var _active_obelisk_rooms: Array[Rect2i] = []
var _runes_by_room: Dictionary[Rect2i, Array] = {}
var _active_rune_rooms: Array[Rect2i] = []
var _charging_plate_by_room: Dictionary[Rect2i, RunePlate] = {}
var _active_ambush: WaveAmbush = null
var _shake_timer: float = 0.0
var _shake_duration: float = 0.0
var _shake_strength: float = 0.0


func setup(hud: Hud, fog: Fog, camera: Camera2D) -> void:
	_hud = hud
	_fog = fog
	_camera = camera


func on_event_armed(
	room: Rect2i,
	title: StringName = &"Blood Spike Arena",
	subtitle: StringName = &"Clear all enemies to disarm spikes",
) -> void:
	_active_event_room = room
	Audio.play_sfx(Audio.Sfx.EVENT_START)
	Audio.set_music_track(Audio.MusicTrack.EVENT, EVENT_MUSIC_FADE_IN)
	_fog.set_event_atmosphere(true)
	trigger_shake(EVENT_SHAKE_STRENGTH, EVENT_SHAKE_DURATION)
	_hud.show_event_banner(&"! WARNING !", title, subtitle, EVENT_WARNING_COLOR)


func on_event_wave(wave_num: int, total_waves: int) -> void:
	Audio.play_sfx(Audio.Sfx.TELEGRAPH)
	trigger_shake(2.5, 0.18)
	if wave_num >= total_waves:
		_hud.show_event_banner(&"! FINAL WAVE !", &"Wave %d / %d" % [wave_num, total_waves], &"Necromancers have arrived!", EVENT_WAVE_COLOR)
	else:
		_hud.show_event_banner(&"! WAVE %d / %d !" % [wave_num, total_waves], &"Cursed Ambush", &"Reinforcements incoming!", EVENT_WAVE_COLOR)


func on_event_disarmed(room: Rect2i) -> void:
	if room != _active_event_room:
		return
	_active_event_room = Rect2i()
	Audio.set_music_track(Audio.MusicTrack.GAME, EVENT_MUSIC_FADE_OUT)
	_fog.set_event_atmosphere(false)


func on_event_cleared(
	room: Rect2i,
	title: StringName = &"Blood Spike Arena",
	subtitle: StringName = &"Bonus reward dropped!",
) -> void:
	Audio.play_sfx(Audio.Sfx.EVENT_CLEAR)
	if room == _active_event_room:
		_active_event_room = Rect2i()
		Audio.set_music_track(Audio.MusicTrack.GAME, EVENT_MUSIC_FADE_OUT)
		_fog.set_event_atmosphere(false)
	_hud.show_event_banner(&"ARENA CLEARED", title, subtitle, EVENT_CLEAR_COLOR)


func get_room_entry_title(map: Map, room: Rect2i) -> String:
	var room_level: int = clampi(map.get_room_depth(room), 1, 12)
	var event_type: WorldPlan.RoomEventType = map.plan.room_event_types.get(room, WorldPlan.RoomEventType.NONE)
	if event_type == WorldPlan.RoomEventType.CLOSING_SPIKES:
		return &"Blood Spike Arena - Lv. %d" % room_level
	if event_type == WorldPlan.RoomEventType.WAVE_AMBUSH:
		return &"Cursed Ambush - Lv. %d" % room_level
	if event_type == WorldPlan.RoomEventType.CURSED_OBELISKS:
		return &"Cursed Obelisks - Lv. %d" % room_level
	if event_type == WorldPlan.RoomEventType.RUNE_PLATES:
		return &"Rune Plates - Lv. %d" % room_level
	var arch: StringName = RoomLayout.get_archetype_title(map.plan.get_room_archetype(room))
	return &"%s - Lv. %d" % [arch, room_level]


func handle_map_event_armed(room: Rect2i, game: Game) -> void:
	on_event_armed(room)
	if not CombatAction.is_valid_target(game._character):
		return
	for enemy: Enemy in game._enemies:
		if not enemy.is_dead and enemy.home_room == room:
			enemy.set_target_candidate(game._character, true)


func handle_event_room_enemies_cleared(game: Game, room: Rect2i) -> bool:
	var event_type: WorldPlan.RoomEventType = game._map.plan.room_event_types.get(room, WorldPlan.RoomEventType.NONE)
	if event_type == WorldPlan.RoomEventType.CLOSING_SPIKES:
		var hazard: ClosingSpikeHazard = game._map.plan.closing_spike_hazards.get(room, null)
		if hazard != null and not hazard.is_cleared:
			hazard.clear()
			if game._map.active_event_room == room:
				game._map.active_event_room = Rect2i()
			var chest: CursedChest = _chests_by_room.get(room, null)
			if chest != null:
				chest.unlock_reward()
			on_event_cleared(room, &"Blood Spike Arena", &"Open the chest to claim your reward!")
		return true
	if event_type == WorldPlan.RoomEventType.CURSED_OBELISKS:
		_try_clear_obelisk_room(game, room)
		return true
	if event_type == WorldPlan.RoomEventType.RUNE_PLATES:
		return true
	return false


func get_active_obelisks_in_room(room: Rect2i) -> Array[CursedObelisk]:
	var alive: Array[CursedObelisk] = []
	if not _obelisks_by_room.has(room):
		return alive
	for ob_var: Variant in _obelisks_by_room[room]:
		var obelisk: CursedObelisk = ob_var
		if obelisk != null and not obelisk.is_dead and obelisk.obelisk_state == CursedObelisk.ObeliskState.ACTIVE:
			alive.append(obelisk)
	return alive


func get_active_rune_plates_in_room(room: Rect2i) -> Array[RunePlate]:
	var active_plates: Array[RunePlate] = []
	if not _runes_by_room.has(room):
		return active_plates
	for plate_var: Variant in _runes_by_room[room]:
		var plate: RunePlate = plate_var
		if plate != null and plate.state != RunePlate.PlateState.DORMANT and plate.state != RunePlate.PlateState.COMPLETED:
			active_plates.append(plate)
	return active_plates


func is_active_open_event_room(room: Rect2i) -> bool:
	return _active_obelisk_rooms.has(room) or _active_rune_rooms.has(room)


func get_unclaimed_chest_in_room(room: Rect2i) -> CursedChest:
	var chest: CursedChest = _chests_by_room.get(room, null)
	if chest != null and chest.state == CursedChest.ChestState.READY_TO_LOOT:
		return chest
	return null


func on_player_died() -> void:
	_active_event_room = Rect2i()
	_active_ambush = null
	_active_obelisk_rooms.clear()
	_active_rune_rooms.clear()
	_charging_plate_by_room.clear()


func spawn_event_chests(map: Map, parent: Node2D) -> void:
	_cursed_chests.clear()
	_chests_by_room.clear()
	_obelisks_by_room.clear()
	_active_obelisk_rooms.clear()
	_runes_by_room.clear()
	_active_rune_rooms.clear()
	_charging_plate_by_room.clear()
	_active_ambush = null
	for hazard: ClosingSpikeHazard in map.plan.closing_spike_hazards.values():
		_spawn_chest_at(map, parent, hazard.room, hazard.bait_cell)
	for ambush: WaveAmbush in map.plan.wave_ambushes.values():
		_spawn_chest_at(map, parent, ambush.room, ambush.bait_cell)
	for encounter: ObeliskEncounter in map.plan.obelisk_encounters.values():
		_spawn_chest_at(map, parent, encounter.room, encounter.bait_cell)
		_spawn_obelisks_for_encounter(map, parent, encounter)
	for rune_enc: RunePlateEncounter in map.plan.rune_encounters.values():
		_spawn_chest_at(map, parent, rune_enc.room, rune_enc.bait_cell)
		_spawn_runes_for_encounter(map, parent, rune_enc)


func _spawn_runes_for_encounter(map: Map, parent: Node2D, encounter: RunePlateEncounter) -> void:
	var spawned: Array[RunePlate] = []
	for cell: Vector2i in encounter.plate_cells:
		var plate: RunePlate = RUNE_PLATE_SCENE.instantiate() as RunePlate
		parent.add_child(plate)
		plate.position = map.map_to_local(cell)
		plate.room = encounter.room
		spawned.append(plate)
	_runes_by_room[encounter.room] = spawned


func _spawn_obelisks_for_encounter(map: Map, parent: Node2D, encounter: ObeliskEncounter) -> void:
	var spawned: Array[CursedObelisk] = []
	for cell: Vector2i in encounter.obelisk_cells:
		var obelisk: CursedObelisk = CURSED_OBELISK_SCENE.instantiate() as CursedObelisk
		parent.add_child(obelisk)
		obelisk.position = map.map_to_local(cell)
		obelisk.home_room = encounter.room
		spawned.append(obelisk)
	_obelisks_by_room[encounter.room] = spawned


func _spawn_chest_at(map: Map, parent: Node2D, room: Rect2i, cell: Vector2i) -> void:
	var chest: CursedChest = CURSED_CHEST_SCENE.instantiate() as CursedChest
	parent.add_child(chest)
	chest.position = map.map_to_local(cell)
	chest.room = room
	_cursed_chests.append(chest)
	_chests_by_room[room] = chest


func update_events(game: Game, delta: float) -> void:
	for i: int in range(_cursed_chests.size() - 1, -1, -1):
		var chest: CursedChest = _cursed_chests[i]
		if chest.state == CursedChest.ChestState.WAITING:
			if PotionManager.is_squad_touching(game._squad, chest.position, CursedChest.TRIGGER_DISTANCE):
				var ev_type: WorldPlan.RoomEventType = game._map.plan.room_event_types.get(chest.room, WorldPlan.RoomEventType.NONE)
				if ev_type == WorldPlan.RoomEventType.WAVE_AMBUSH:
					_start_wave_ambush(game, chest)
				elif ev_type == WorldPlan.RoomEventType.CLOSING_SPIKES:
					_start_closing_spikes(game, chest)
				elif ev_type == WorldPlan.RoomEventType.CURSED_OBELISKS:
					_start_obelisk_encounter(game, chest)
				elif ev_type == WorldPlan.RoomEventType.RUNE_PLATES:
					_start_rune_encounter(game, chest)
		elif chest.can_claim_reward() and PotionManager.is_squad_touching(game._squad, chest.position, CursedChest.TRIGGER_DISTANCE):
			_claim_chest_reward(game, chest)

	if not _active_obelisk_rooms.is_empty():
		_update_obelisk_rooms(game)
	if not _active_rune_rooms.is_empty():
		_update_rune_rooms(game, delta)

	if _active_ambush == null:
		return

	var ev: Dictionary = _active_ambush.update(delta)
	if ev[&"ready_for_pentagrams"]:
		var roster: Array[StringName] = _active_ambush.build_wave_roster(_active_ambush.current_wave)
		var player_cell: Vector2i = game._map.local_to_map(game._character.global_position)
		var cells: Array[Vector2i] = _active_ambush.pick_spawn_cells(game._map.plan, roster.size(), player_cell)
		var spawns: Array[Dictionary] = []
		var count: int = mini(roster.size(), cells.size())
		for i: int in range(count):
			var pos: Vector2 = game._map.map_to_local(cells[i])
			spawns.append({&"pos": pos, &"id": roster[i]})
			var pentagram: Projectile = Projectile.acquire(Game.SUMMON_PENTAGRAM_SCENE)
			pentagram.global_position = pos
			game._on_projectile_spawn_requested(pentagram)
		Audio.play_sfx(Audio.Sfx.NECRO_SUMMON)
		if _active_ambush.current_wave >= 2:
			on_event_wave(_active_ambush.current_wave, WaveAmbush.TOTAL_WAVES)
		_active_ambush.begin_pentagrams(spawns)
	elif ev[&"ready_to_materialize"]:
		_materialize_ambush_wave(game, _active_ambush)
	elif _active_ambush.state == WaveAmbush.State.WAVE_ACTIVE and _active_ambush.wave_remaining <= 0:
		_check_ambush_wave_clear(game)


func handle_ambush_enemy_died(game: Game, enemy: Enemy, room: Rect2i) -> bool:
	if _active_ambush == null or room != _active_ambush.room:
		return false
	if not enemy.is_minion and not enemy.is_patrol_respawn:
		_active_ambush.wave_remaining = maxi(0, _active_ambush.wave_remaining - 1)
	_check_ambush_wave_clear(game)
	return true


func _start_closing_spikes(game: Game, chest: CursedChest) -> void:
	var room: Rect2i = chest.room
	var hazard: ClosingSpikeHazard = game._map.plan.closing_spike_hazards.get(room, null)
	if hazard == null or hazard.is_cleared or hazard.is_triggered:
		return
	chest.activate()
	hazard.arm()
	game._map.active_event_room = room
	on_event_armed(room, &"Blood Spike Arena", &"Clear all enemies to unlock the chest")

	var quota: int = game._map.get_room_enemy_quota(room)
	var room_center: Vector2 = game._map.map_to_local(room.get_center())
	var free_slots: int = Game.MAX_ENEMIES - game._enemies.size()
	if free_slots < quota:
		var needed_evict: int = quota - free_slots
		var dist_sq: float = game._character.global_position.distance_squared_to(room_center)
		game._reclaim_distant_enemies_for_room(room, dist_sq, needed_evict, game._character.global_position)

	var to_spawn: int = mini(quota, maxi(0, Game.MAX_ENEMIES - game._enemies.size()))
	var player_cell: Vector2i = game._map.local_to_map(game._character.global_position)
	var cells: Array[Vector2i] = WaveAmbush.pick_spawn_cells_in_room(game._map.plan, room, to_spawn, player_cell)
	var depth: int = clampi(game._map.get_room_depth(room), 1, 12)
	for cell: Vector2i in cells:
		var pos: Vector2 = game._map.map_to_local(cell)
		var pentagram: Projectile = Projectile.acquire(Game.SUMMON_PENTAGRAM_SCENE)
		pentagram.global_position = pos
		game._on_projectile_spawn_requested(pentagram)
		var enemy_scene: PackedScene = game._pick_enemy_scene_for_room(room, depth)
		game._spawn_enemy_at(pos, room, enemy_scene, depth, false, false)
	if not cells.is_empty():
		Audio.play_sfx(Audio.Sfx.NECRO_SUMMON)
	game._room_remaining_enemies[room] = cells.size()
	game._room_spawned_enemies[room] = cells.size()
	if cells.is_empty():
		handle_event_room_enemies_cleared(game, room)


func _start_obelisk_encounter(game: Game, chest: CursedChest) -> void:
	var room: Rect2i = chest.room
	var encounter: ObeliskEncounter = game._map.plan.obelisk_encounters.get(room, null)
	if encounter == null or encounter.is_cleared or encounter.is_triggered:
		return
	chest.activate()
	encounter.is_triggered = true
	game._map.active_event_room = room
	if not _active_obelisk_rooms.has(room):
		_active_obelisk_rooms.append(room)

	var depth: int = clampi(encounter.depth, 1, 12)
	var obelisks: Array = _obelisks_by_room.get(room, [])
	for ob_var: Variant in obelisks:
		var obelisk: CursedObelisk = ob_var
		if obelisk != null:
			obelisk.activate(depth, encounter.aura_radius)
			if not obelisk.died.is_connected(_on_obelisk_died):
				obelisk.died.connect(_on_obelisk_died.bind(game, room))

	on_event_armed(room, &"Cursed Obelisk Chamber", &"Shatter all 4 orbs and clear the guards")

	var used_cells: Dictionary[Vector2i, bool] = {encounter.bait_cell: true}
	for cell: Vector2i in encounter.obelisk_cells:
		used_cells[cell] = true

	var spawn_requests: Array[Dictionary] = []
	for i: int in range(encounter.obelisk_cells.size()):
		var roster: Array[StringName] = encounter.build_guard_roster_for_obelisk(i)
		var guard_cells: Array[Vector2i] = encounter.pick_guard_cells_around(game._map.plan, encounter.obelisk_cells[i], roster.size(), used_cells)
		var count: int = mini(roster.size(), guard_cells.size())
		for j: int in range(count):
			spawn_requests.append({&"pos": game._map.map_to_local(guard_cells[j]), &"id": roster[j]})

	var free_slots: int = Game.MAX_ENEMIES - game._enemies.size()
	if free_slots < spawn_requests.size():
		var room_center: Vector2 = game._map.map_to_local(room.get_center())
		var dist_sq: float = game._character.global_position.distance_squared_to(room_center)
		game._reclaim_distant_enemies_for_room(room, dist_sq, spawn_requests.size() - free_slots, game._character.global_position)

	var spawned_count: int = 0
	for req: Dictionary in spawn_requests:
		if game._enemies.size() >= Game.MAX_ENEMIES:
			break
		var pos: Vector2 = req[&"pos"]
		var enemy_id: StringName = req[&"id"]
		var pentagram: Projectile = Projectile.acquire(Game.SUMMON_PENTAGRAM_SCENE)
		pentagram.global_position = pos
		game._on_projectile_spawn_requested(pentagram)
		game._spawn_enemy_at(pos, room, _scene_for_enemy_id(enemy_id), depth, false, false)
		game._enemies[game._enemies.size() - 1].stay_in_home_room = true
		spawned_count += 1
	if spawned_count > 0:
		Audio.play_sfx(Audio.Sfx.NECRO_SUMMON)
	game._room_remaining_enemies[room] = spawned_count
	game._room_spawned_enemies[room] = spawned_count
	_refresh_obelisk_auras(game, room)


func _update_obelisk_rooms(game: Game) -> void:
	for room: Rect2i in _active_obelisk_rooms:
		_refresh_obelisk_auras(game, room)
		if game._current_room == room:
			if _active_event_room != room:
				_active_event_room = room
				Audio.set_music_track(Audio.MusicTrack.EVENT, EVENT_MUSIC_FADE_IN)
				_fog.set_event_atmosphere(true)
		elif _active_event_room == room:
			on_event_disarmed(room)


func _refresh_obelisk_auras(game: Game, room: Rect2i) -> void:
	var alive_obelisks: Array[CursedObelisk] = get_active_obelisks_in_room(room)
	var tethers_by_obelisk: Array[Array] = []
	for _i: int in range(alive_obelisks.size()):
		tethers_by_obelisk.append([])

	for enemy: Enemy in game._enemies:
		if enemy.is_dead or enemy.home_room != room:
			continue
		var shielded: bool = false
		for i: int in range(alive_obelisks.size()):
			var r_sq: float = alive_obelisks[i].aura_radius * alive_obelisks[i].aura_radius
			if enemy.global_position.distance_squared_to(alive_obelisks[i].global_position) <= r_sq:
				shielded = true
				tethers_by_obelisk[i].append(enemy.global_position)
		enemy.is_damage_immune = shielded

	for i: int in range(alive_obelisks.size()):
		var world_pts: Array[Vector2] = []
		for pos_var: Variant in tethers_by_obelisk[i]:
			world_pts.append(pos_var)
		alive_obelisks[i].set_tether_world_positions(world_pts)


func _on_obelisk_died(game: Game, room: Rect2i) -> void:
	trigger_shake(3.0, 0.20)
	_refresh_obelisk_auras(game, room)
	_try_clear_obelisk_room(game, room)


func _try_clear_obelisk_room(game: Game, room: Rect2i) -> void:
	var encounter: ObeliskEncounter = game._map.plan.obelisk_encounters.get(room, null)
	if encounter == null or encounter.is_cleared:
		return
	if not get_active_obelisks_in_room(room).is_empty():
		return
	for enemy: Enemy in game._enemies:
		if not enemy.is_dead and enemy.home_room == room:
			return
	encounter.clear()
	_active_obelisk_rooms.erase(room)
	if game._map.active_event_room == room:
		game._map.active_event_room = Rect2i()
	var chest: CursedChest = _chests_by_room.get(room, null)
	if chest != null:
		chest.unlock_reward()
	on_event_cleared(room, &"Cursed Obelisk Chamber", &"Open the chest to claim your reward!")
	game._patrol_manager.schedule_respawn(room)


func _start_rune_encounter(game: Game, chest: CursedChest) -> void:
	var room: Rect2i = chest.room
	var encounter: RunePlateEncounter = game._map.plan.rune_encounters.get(room, null)
	if encounter == null or encounter.is_cleared or encounter.is_triggered:
		return
	chest.activate()
	encounter.is_triggered = true
	encounter.spawn_timer = encounter.get_trickle_interval()
	game._map.active_event_room = room
	if not _active_rune_rooms.has(room):
		_active_rune_rooms.append(room)

	for plate_var: Variant in _runes_by_room.get(room, []):
		var plate: RunePlate = plate_var
		if plate != null:
			plate.activate()
			if not plate.completed.is_connected(_on_rune_plate_completed):
				plate.completed.connect(_on_rune_plate_completed.bind(game, room))

	on_event_armed(room, &"Rune Plates Chamber", &"Hold 3 runes to purge - switching resets progress!")
	_spawn_rune_enemies(game, encounter, RunePlateEncounter.OPENING_SPAWN_COUNT)


func _update_rune_rooms(game: Game, delta: float) -> void:
	for room: Rect2i in _active_rune_rooms.duplicate():
		var encounter: RunePlateEncounter = game._map.plan.rune_encounters.get(room, null)
		if encounter == null or encounter.is_cleared:
			_active_rune_rooms.erase(room)
			continue
		if game._current_room == room:
			if _active_event_room != room:
				_active_event_room = room
				Audio.set_music_track(Audio.MusicTrack.EVENT, EVENT_MUSIC_FADE_IN)
				_fog.set_event_atmosphere(true)
		elif _active_event_room == room:
			on_event_disarmed(room)

		var plates: Array[RunePlate] = get_active_rune_plates_in_room(room)
		var stepped_plate: RunePlate = null
		if game._current_room == room:
			for plate: RunePlate in plates:
				if plate.is_point_inside(game._character.global_position):
					stepped_plate = plate
					break

		if stepped_plate != null:
			var prev: RunePlate = _charging_plate_by_room.get(room, null)
			if prev != null and prev != stepped_plate and prev.state != RunePlate.PlateState.COMPLETED and prev.progress > 0.0:
				prev.reset_progress()
				trigger_shake(2.0, 0.12)
				Audio.play_sfx(Audio.Sfx.SPIKE_TRAP)
			_charging_plate_by_room[room] = stepped_plate

		for plate: RunePlate in plates:
			if plate.step_charge(delta, plate == stepped_plate):
				break

		if encounter.is_cleared:
			continue
		var tracked: RunePlate = _charging_plate_by_room.get(room, null)
		if tracked != null and tracked.progress <= 0.0:
			_charging_plate_by_room.erase(room)

		if game._current_room == room:
			encounter.spawn_timer -= delta
			if encounter.spawn_timer <= 0.0:
				encounter.spawn_timer = encounter.get_trickle_interval()
				var alive_in_room: int = 0
				for enemy: Enemy in game._enemies:
					if not enemy.is_dead and enemy.home_room == room:
						alive_in_room += 1
				var max_alive: int = encounter.get_max_alive()
				if alive_in_room < max_alive:
					_spawn_rune_enemies(game, encounter, mini(RunePlateEncounter.TRICKLE_SPAWN_COUNT, max_alive - alive_in_room))


func _spawn_rune_enemies(game: Game, encounter: RunePlateEncounter, count: int) -> void:
	if count <= 0:
		return
	var room: Rect2i = encounter.room
	var free_slots: int = Game.MAX_ENEMIES - game._enemies.size()
	if free_slots < count:
		var room_center: Vector2 = game._map.map_to_local(room.get_center())
		var dist_sq: float = game._character.global_position.distance_squared_to(room_center)
		game._reclaim_distant_enemies_for_room(room, dist_sq, count - free_slots, game._character.global_position)

	var roster: Array[StringName] = encounter.build_spawn_roster(count)
	var player_cell: Vector2i = game._map.local_to_map(game._character.global_position)
	var cells: Array[Vector2i] = WaveAmbush.pick_spawn_cells_in_room(game._map.plan, room, roster.size(), player_cell)
	var depth: int = clampi(encounter.depth, 1, 12)
	var spawn_count: int = mini(roster.size(), cells.size())
	for i: int in range(spawn_count):
		if game._enemies.size() >= Game.MAX_ENEMIES:
			break
		var pos: Vector2 = game._map.map_to_local(cells[i])
		var pentagram: Projectile = Projectile.acquire(Game.SUMMON_PENTAGRAM_SCENE)
		pentagram.global_position = pos
		game._on_projectile_spawn_requested(pentagram)
		game._spawn_enemy_at(pos, room, _scene_for_enemy_id(roster[i]), depth, false, false)
		var spawned_enemy: Enemy = game._enemies[game._enemies.size() - 1]
		spawned_enemy.stay_in_home_room = true
		if encounter.total_spawned >= RunePlateEncounter.MAX_XP_GRANTS:
			spawned_enemy.xp_value = 0.0
		encounter.total_spawned += 1
	if spawn_count > 0:
		Audio.play_sfx(Audio.Sfx.NECRO_SUMMON)


func _on_rune_plate_completed(plate: RunePlate, game: Game, room: Rect2i) -> void:
	if _charging_plate_by_room.get(room, null) == plate:
		_charging_plate_by_room.erase(room)

	var shock_sq: float = RunePlate.SHOCKWAVE_RADIUS * RunePlate.SHOCKWAVE_RADIUS
	for enemy: Enemy in game._enemies:
		if enemy.is_dead or enemy.home_room != room:
			continue
		var diff: Vector2 = enemy.global_position - plate.global_position
		if diff.length_squared() <= shock_sq:
			var push_dir: Vector2 = diff.normalized() if diff.length_squared() > 0.01 else Vector2.UP
			enemy.apply_knockback(push_dir * RunePlate.SHOCKWAVE_KNOCKBACK)
	trigger_shake(3.0, 0.22)

	var remaining: int = get_active_rune_plates_in_room(room).size()
	if remaining > 0:
		_hud.show_event_toast(&"Rune %d / 3 Charged!" % (RunePlateEncounter.PLATE_COUNT - remaining), Color(0.45, 1.0, 0.72, 1.0))
		return

	var encounter: RunePlateEncounter = game._map.plan.rune_encounters.get(room, null)
	if encounter == null or encounter.is_cleared:
		return
	encounter.clear()
	_active_rune_rooms.erase(room)
	_charging_plate_by_room.erase(room)
	if game._map.active_event_room == room:
		game._map.active_event_room = Rect2i()

	for enemy: Enemy in game._enemies.duplicate():
		if is_instance_valid(enemy) and not enemy.is_dead and enemy.home_room == room:
			enemy.xp_value = 0.0
			enemy.is_damage_immune = false
			enemy.take_damage(999999.0, false)

	trigger_shake(4.5, 0.30)
	var chest: CursedChest = _chests_by_room.get(room, null)
	if chest != null:
		chest.unlock_reward()
	on_event_cleared(room, &"Rune Plates Chamber", &"Ritual purged - Open the chest for loot!")
	game._patrol_manager.schedule_respawn(room)


func _start_wave_ambush(game: Game, chest: CursedChest) -> void:
	var room: Rect2i = chest.room
	var ambush: WaveAmbush = game._map.plan.wave_ambushes.get(room, null)
	if ambush == null or ambush.is_cleared or _active_ambush != null:
		return
	chest.activate()
	var interior: Rect2i = room.grow(-1)
	for i: int in range(1, game._squad.size()):
		var follower: Hero = game._squad[i]
		if not follower.is_dead and not interior.has_point(game._map.local_to_map(follower.global_position)):
			follower.squad_member.teleport_to_leader(follower, game._map)
	game._map.barriers.lock_room(room, game._map._walkable_cells, game._map.nav_window)
	game._map.active_event_room = room
	on_event_armed(room, &"Cursed Ambush", &"Survive 3 waves to break the seal")
	ambush.start()
	_active_ambush = ambush


func _materialize_ambush_wave(game: Game, ambush: WaveAmbush) -> void:
	var room: Rect2i = ambush.room
	var room_center: Vector2 = game._map.map_to_local(room.get_center())
	var free_slots: int = Game.MAX_ENEMIES - game._enemies.size()
	if free_slots < ambush.pending_spawns.size():
		var needed_evict: int = ambush.pending_spawns.size() - free_slots
		var dist_sq: float = game._character.global_position.distance_squared_to(room_center)
		game._reclaim_distant_enemies_for_room(room, dist_sq, needed_evict, game._character.global_position)

	var enemy_level: int = clampi(ambush.depth, 1, 12)
	var spawned_count: int = 0
	for entry: Dictionary in ambush.pending_spawns:
		if game._enemies.size() >= Game.MAX_ENEMIES:
			break
		var pos: Vector2 = entry[&"pos"]
		var enemy_id: StringName = entry[&"id"]
		game._spawn_enemy_at(pos, room, _scene_for_enemy_id(enemy_id), enemy_level, false, false)
		game._room_spawned_enemies[room] = game._room_spawned_enemies.get(room, 0) + 1
		spawned_count += 1
	ambush.activate_wave(spawned_count)


func _check_ambush_wave_clear(game: Game) -> void:
	if _active_ambush == null or _active_ambush.state != WaveAmbush.State.WAVE_ACTIVE:
		return
	var room: Rect2i = _active_ambush.room
	if _active_ambush.wave_remaining > 0:
		return
	if _active_ambush.current_wave >= WaveAmbush.TOTAL_WAVES and game._room_summoned_enemies.get(room, 0) > 0:
		return
	if _active_ambush.advance_or_clear():
		_active_ambush = null
		game._map.barriers.unlock_room(room, game._map._walkable_cells, game._map.nav_window)
		game._map.active_event_room = Rect2i()
		var chest: CursedChest = _chests_by_room.get(room, null)
		if chest != null:
			chest.unlock_reward()
		on_event_cleared(room, &"Cursed Ambush", &"Exits unlocked - Open the chest for loot!")
		game._patrol_manager.schedule_respawn(room)


func _claim_chest_reward(game: Game, chest: CursedChest) -> void:
	chest.claim_reward()
	_cursed_chests.erase(chest)
	_chests_by_room.erase(chest.room)
	Audio.play_sfx(Audio.Sfx.COIN_PICKUP)
	var facing: Vector2 = game._character.move_direction
	if facing.length_squared() < 0.01:
		facing = (chest.position - game._character.position).normalized()
	if facing.length_squared() < 0.01:
		facing = Vector2.DOWN
	var raw_anchor: Vector2 = chest.position + facing.normalized() * 34.0
	game._spawn_pickups_for_room(chest.room, true, raw_anchor)


static func _scene_for_enemy_id(enemy_id: StringName) -> PackedScene:
	match enemy_id:
		&"lava_slime":
			return Game.LAVA_SLIME_SCENE
		&"skeleton_archer":
			return Game.SKELETON_ARCHER_SCENE
		&"necromancer":
			return Game.NECROMANCER_SCENE
		_:
			return Game.SKELETON_SCENE


func trigger_shake(strength: float, duration: float) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_duration = maxf(_shake_duration, duration)
	_shake_timer = maxf(_shake_timer, duration)


func update(delta: float) -> void:
	if _shake_timer <= 0.0:
		_camera.offset = Vector2.ZERO
		return
	_shake_timer = maxf(0.0, _shake_timer - delta)
	var ratio: float = _shake_timer / _shake_duration if _shake_duration > 0.0 else 0.0
	var mag: float = _shake_strength * ratio
	_camera.offset = Vector2(randf_range(-mag, mag), randf_range(-mag, mag))
	if _shake_timer <= 0.0:
		_shake_strength = 0.0
		_shake_duration = 0.0
		_camera.offset = Vector2.ZERO

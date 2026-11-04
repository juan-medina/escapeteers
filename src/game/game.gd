# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Game
extends Node2D

const MAX_CHARACTERS: int = 80
const MAX_ENEMIES: int = 160
const MAX_SPAWNS_PER_FRAME: int = 8
const ENEMY_ACTIVE_DIST_SQ: float = 480.0 * 480.0
const ENEMY_DESPAWN_DIST_SQ: float = 1350.0 * 1350.0
const ROOM_RESPAWN_DIST_SQ: float = 950.0 * 950.0
const STREAM_CHECK_INTERVAL: float = 0.15

const ARCHER_SCENE: PackedScene = preload("res://character/heroes/archer/archer.tscn")
const ARMORED_AXEMAN_SCENE: PackedScene = preload("res://character/heroes/armored_axeman/armored_axeman.tscn")
const KNIGHT_SCENE: PackedScene = preload("res://character/heroes/knight/knight.tscn")
const KNIGHT_TEMPLAR_SCENE: PackedScene = preload("res://character/heroes/knight_templar/knight_templar.tscn")
const PRIEST_SCENE: PackedScene = preload("res://character/heroes/priest/priest.tscn")
const SOLDIER_SCENE: PackedScene = preload("res://character/heroes/soldier/soldier.tscn")
const SWORDSMAN_SCENE: PackedScene = preload("res://character/heroes/swordsman/swordsman.tscn")
const WIZARD_SCENE: PackedScene = preload("res://character/heroes/wizard/wizard.tscn")
const UNKNOWN_SCENE: PackedScene = preload("res://character/heroes/unknown/unknown.tscn")
const LAVA_SLIME_SCENE: PackedScene = preload("res://character/enemies/lava_slime/lava_slime.tscn")
const GAME_OVER_DIALOG_SCENE: PackedScene = preload("res://game_over_dialog/game_over_dialog.tscn")
const RECRUIT_PANEL_SCENE: PackedScene = preload("res://recruit_panel/recruit_panel.tscn")
const LEVEL_UP_PANEL_SCENE: PackedScene = preload("res://level_up_panel/level_up_panel.tscn")
const HUD_SCENE: PackedScene = preload("res://hud/hud.tscn")

const HERO_SPAWN_WEIGHTS: Dictionary[PackedScene, int] = {
	ARMORED_AXEMAN_SCENE: 5,
	KNIGHT_SCENE: 3,
	KNIGHT_TEMPLAR_SCENE: 2,
	SWORDSMAN_SCENE: 2,
	WIZARD_SCENE: 1,
	ARCHER_SCENE: 1,
	SOLDIER_SCENE: 1,
	PRIEST_SCENE: 1,
}

var _squad: Array[Hero] = []
var _unrecruited_characters: Array[Character] = []
var _class_levels: Dictionary[StringName, int] = {}
var _hud: Hud = null
var _squad_level: int = 1
var _current_xp: float = 0.0
var _xp_required: float = 50.0
var _pending_level_ups: int = 0
var _enemies: Array[Enemy] = []
var _hero_deck: Array[PackedScene] = []
var _room_remaining_enemies: Dictionary[Rect2i, int] = {}
var _room_spawned_enemies: Dictionary[Rect2i, int] = {}
var _stream_timer: float = 0.0
var _entity_pool: EntityPool = EntityPool.new()
var _pending_spawns: Array[Dictionary] = []

@onready var _camera: Camera2D = $Camera2D
@onready var _characters: Node2D = $Characters
@onready var _character: Hero = $Characters/Character as Hero
@onready var _map: Map = $Map
@onready var _projectiles: Node2D = $Projectiles


func _ready() -> void:
	# Workaround for Godot 4 Camera2D not re-centering after the window resizes.
	get_tree().root.size_changed.connect(_on_window_resized)
	process_priority = 1
	y_sort_enabled = true
	set_process(false)

	_map.generation_progress_updated.connect(_on_map_generation_progress)
	await _map.generate_map()

	_character.position = _map.get_hero_spawn_position()
	_camera.position = _character.position
	_character.y_sort_enabled = true
	_character.is_player = true
	_character.move_direction = Vector2.UP
	_character.record_step(0.0)
	_character.projectile_spawn_requested.connect(_on_projectile_spawn_requested)
	_character.enemy_hit.connect(_on_hero_enemy_hit.bind(_character))
	_character.death_completed.connect(_on_player_death_completed)
	_character.died.connect(_on_player_died)
	_squad.append(_character)

	_class_levels[&"soldier"] = 1
	var soldier_data: HeroData = HeroData.get_hero(&"soldier")
	if soldier_data != null:
		soldier_data.apply_to_hero(_character, 1)

	_hud = HUD_SCENE.instantiate() as Hud
	add_child(_hud)
	_hud.update_xp(_current_xp, _xp_required, _squad_level)
	if _hud.damage_meter != null:
		_hud.damage_meter.update_squad(_squad)
	_hud.setup_map(_map.plan, _character)

	var transition_mgr: Node = get_node_or_null(^"/root/Transition")
	if transition_mgr != null:
		transition_mgr.call(&"set_loading_progress", 0.92, &"Assembling the fellowship...")
	await get_tree().process_frame
	_entity_pool.setup(_characters)
	_entity_pool.prewarm(LAVA_SLIME_SCENE, 80)
	_spawn_initial_characters()
	_check_recruitment()
	_register_and_populate_rooms(_map.companion_rooms)
	while not _pending_spawns.is_empty():
		var req: Dictionary = _pending_spawns.pop_front()
		@warning_ignore("unsafe_call_argument")
		_spawn_enemy_at(req[&"pos"], req[&"room"])

	if transition_mgr != null:
		transition_mgr.call(&"set_loading_progress", 1.0, &"Ready to escape!")
	await get_tree().process_frame
	set_process(true)
	if transition_mgr != null:
		await transition_mgr.call(&"hide_loading")
	Audio.play_game_music()


func get_active_enemy_count() -> int:
	return _enemies.size()


func _on_map_generation_progress(progress: float, stage_name: StringName) -> void:
	var transition_mgr: Node = get_node_or_null(^"/root/Transition")
	if transition_mgr != null:
		transition_mgr.call(&"set_loading_progress", progress, stage_name)


func _process(delta: float) -> void:
	if is_instance_valid(_character):
		_camera.position = _character.position
		if not _character.is_dead:
			_character.record_step(delta)
			_stream_timer -= delta
			if _stream_timer <= 0.0:
				_stream_timer = STREAM_CHECK_INTERVAL
				_update_map_streaming()
			_map.update_streaming(_character.global_position, _character.velocity)

	_update_followers(delta)
	_check_recruitment()
	_update_enemies()
	_process_pending_spawns()


func remove_member(hero: Hero) -> void:
	var idx: int = _squad.find(hero)
	if idx == -1 or hero == _character:
		return

	_squad.remove_at(idx)
	hero.queue_free()
	_rebalance_escort_slots()


func _update_map_streaming() -> void:
	var new_rooms: Array[Rect2i] = _map.expand_frontier_near(_character.global_position)
	if not new_rooms.is_empty():
		for room: Rect2i in new_rooms:
			_spawn_companions_for_room(room)
		_register_and_populate_rooms(new_rooms)

	_respawn_nearby_hibernating_rooms()


func _spawn_initial_characters() -> void:
	var starter_positions: Array[Vector2] = _map.get_starter_companion_spawn_positions()
	for pos: Vector2 in starter_positions:
		_spawn_recruit_at(pos)

	for room: Rect2i in _map.companion_rooms:
		_spawn_companions_for_room(room)


func _spawn_companions_for_room(room: Rect2i) -> void:
	if MAX_CHARACTERS > 0 and (_squad.size() + _unrecruited_characters.size()) >= MAX_CHARACTERS:
		return

	var positions: Array[Vector2] = _map.get_companion_spawn_positions_for_room(room)
	for pos: Vector2 in positions:
		if MAX_CHARACTERS > 0 and (_squad.size() + _unrecruited_characters.size()) >= MAX_CHARACTERS:
			break
		_spawn_recruit_at(pos)


func _draw_next_hero_scene() -> PackedScene:
	if _hero_deck.is_empty():
		_hero_deck = _build_hero_deck()
		_hero_deck.shuffle()
	return _hero_deck.pop_back()


func _spawn_recruit_at(pos: Vector2) -> void:
	var ch: Unknown = UNKNOWN_SCENE.instantiate() as Unknown
	_characters.add_child(ch)
	ch.position = pos
	ch.y_sort_enabled = true
	_unrecruited_characters.append(ch)


func _build_hero_deck() -> Array[PackedScene]:
	var deck: Array[PackedScene] = []
	for scene: PackedScene in HERO_SPAWN_WEIGHTS:
		var weight: int = HERO_SPAWN_WEIGHTS[scene]
		for _i: int in range(weight):
			deck.append(scene)
	return deck


func _register_and_populate_rooms(rooms: Array[Rect2i]) -> void:
	var player_pos: Vector2 = _character.global_position
	for room: Rect2i in rooms:
		if not _room_remaining_enemies.has(room):
			var quota: int = _map.get_room_enemy_quota(room)
			_room_remaining_enemies[room] = quota
			_room_spawned_enemies[room] = 0
		var room_center_world: Vector2 = _map.map_to_local(room.get_center())
		if _map.is_room_materialized(room) and player_pos.distance_squared_to(room_center_world) <= ROOM_RESPAWN_DIST_SQ:
			_populate_room_enemies(room)


func _populate_room_enemies(room: Rect2i) -> void:
	if not _map.is_room_materialized(room):
		return
	var remaining: int = _room_remaining_enemies.get(room, 0)
	var alive_in_room: int = _room_spawned_enemies.get(room, 0)
	var needed: int = remaining - alive_in_room
	if needed <= 0 or (_enemies.size() + _pending_spawns.size()) >= MAX_ENEMIES:
		return

	var capacity: int = MAX_ENEMIES - (_enemies.size() + _pending_spawns.size())
	var to_spawn: int = mini(needed, capacity)
	var spawn_positions: Array[Vector2] = _map.get_enemy_spawn_positions_for_room(room, to_spawn)

	for pos: Vector2 in spawn_positions:
		_pending_spawns.append({&"room": room, &"pos": pos})
		_room_spawned_enemies[room] = _room_spawned_enemies.get(room, 0) + 1


func _process_pending_spawns() -> void:
	var spawned: int = 0
	var cam_pos: Vector2 = _camera.global_position
	while not _pending_spawns.is_empty() and spawned < MAX_SPAWNS_PER_FRAME:
		if _enemies.size() >= MAX_ENEMIES:
			break
		var req: Dictionary = _pending_spawns.pop_front()
		var room: Rect2i = req[&"room"]
		var pos: Vector2 = req[&"pos"]
		var cell: Vector2i = _map.local_to_map(pos)
		if pos.distance_squared_to(cam_pos) > ENEMY_DESPAWN_DIST_SQ or not _map.is_cell_walkable(cell):
			if _room_spawned_enemies.has(room):
				_room_spawned_enemies[room] = maxi(0, _room_spawned_enemies[room] - 1)
			continue
		_spawn_enemy_at(pos, room)
		spawned += 1


func _spawn_enemy_at(pos: Vector2, room: Rect2i) -> void:
	var slime: Enemy = _entity_pool.acquire(LAVA_SLIME_SCENE) as Enemy
	slime.home_room = room
	slime.position = pos
	slime.map = _map
	slime.y_sort_enabled = true
	var depth: int = _map.get_room_depth(room)
	var enemy_level: int = clampi(depth, 1, 10)
	slime.set_level(enemy_level)
	if not slime.projectile_spawn_requested.is_connected(_on_projectile_spawn_requested):
		slime.projectile_spawn_requested.connect(_on_projectile_spawn_requested)
	for conn: Dictionary in slime.died.get_connections():
		@warning_ignore("unsafe_call_argument")
		slime.died.disconnect(conn.callable)
	slime.died.connect(_on_enemy_died.bind(slime, room))
	for d_conn: Dictionary in slime.death_completed.get_connections():
		@warning_ignore("unsafe_call_argument")
		slime.death_completed.disconnect(d_conn.callable)
	slime.death_completed.connect(_on_enemy_death_completed.bind(slime))
	slime.sync_screen_state(_camera.global_position)
	_enemies.append(slime)


func _respawn_nearby_hibernating_rooms() -> void:
	var player_pos: Vector2 = _character.global_position
	var room_candidates: Array[Dictionary] = []

	for room: Rect2i in _map.companion_rooms:
		var remaining: int = _room_remaining_enemies.get(room, 0)
		var spawned: int = _room_spawned_enemies.get(room, 0)
		if remaining <= spawned or not _map.is_room_materialized(room):
			continue

		var room_world_center: Vector2 = _map.map_to_local(room.get_center())
		var dist_sq: float = player_pos.distance_squared_to(room_world_center)
		if dist_sq <= ROOM_RESPAWN_DIST_SQ:
			room_candidates.append({&"room": room, &"dist_sq": dist_sq})

	if room_candidates.is_empty():
		return

	room_candidates.sort_custom(_compare_room_candidate_asc)

	for cand: Dictionary in room_candidates:
		var room: Rect2i = cand[&"room"]
		var room_dist_sq: float = cand[&"dist_sq"]
		var remaining: int = _room_remaining_enemies.get(room, 0)
		var spawned: int = _room_spawned_enemies.get(room, 0)
		var needed: int = remaining - spawned
		if needed <= 0:
			continue

		var free_slots: int = MAX_ENEMIES - (_enemies.size() + _pending_spawns.size())
		if free_slots < needed:
			_reclaim_distant_enemies_for_room(room, room_dist_sq, needed - free_slots, player_pos)

		_populate_room_enemies(room)


func _reclaim_distant_enemies_for_room(target_room: Rect2i, target_room_dist_sq: float, count_needed: int, player_pos: Vector2) -> void:
	var reclaimed: int = 0
	var min_evict_dist_sq: float = target_room_dist_sq + 6400.0

	var p_idx: int = _pending_spawns.size() - 1
	while p_idx >= 0 and reclaimed < count_needed:
		var req: Dictionary = _pending_spawns[p_idx]
		var r_room: Rect2i = req[&"room"]
		if r_room != target_room:
			var r_center: Vector2 = _map.map_to_local(r_room.get_center())
			if player_pos.distance_squared_to(r_center) > min_evict_dist_sq:
				_pending_spawns.remove_at(p_idx)
				if _room_spawned_enemies.has(r_room):
					_room_spawned_enemies[r_room] = maxi(0, _room_spawned_enemies[r_room] - 1)
				reclaimed += 1
		p_idx -= 1

	if reclaimed >= count_needed:
		return

	var evictable: Array[Dictionary] = []
	for enemy: Enemy in _enemies:
		if not is_instance_valid(enemy) or enemy.is_dead:
			continue
		if enemy.home_room == target_room or enemy.is_on_screen or enemy.current_state != Enemy.State.PATROL:
			continue
		var home_center: Vector2 = _map.map_to_local(enemy.home_room.get_center())
		var home_dist_sq: float = player_pos.distance_squared_to(home_center)
		if home_dist_sq > min_evict_dist_sq:
			evictable.append({&"enemy": enemy, &"dist_sq": home_dist_sq})

	if evictable.is_empty():
		return

	evictable.sort_custom(_compare_room_candidate_desc)

	for item: Dictionary in evictable:
		if reclaimed >= count_needed:
			break
		var enemy_to_evict: Enemy = item[&"enemy"]
		var h_room: Rect2i = enemy_to_evict.home_room
		if _room_spawned_enemies.has(h_room):
			_room_spawned_enemies[h_room] = maxi(0, _room_spawned_enemies[h_room] - 1)
		_entity_pool.release(enemy_to_evict, LAVA_SLIME_SCENE)
		var e_idx: int = _enemies.find(enemy_to_evict)
		if e_idx != -1:
			_enemies.remove_at(e_idx)
		reclaimed += 1


static func _compare_room_candidate_asc(a: Dictionary, b: Dictionary) -> bool:
	var dist_a: float = a[&"dist_sq"]
	var dist_b: float = b[&"dist_sq"]
	return dist_a < dist_b


static func _compare_room_candidate_desc(a: Dictionary, b: Dictionary) -> bool:
	var dist_a: float = a[&"dist_sq"]
	var dist_b: float = b[&"dist_sq"]
	return dist_a > dist_b


func _on_enemy_died(slime: Enemy, room: Rect2i) -> void:
	if _room_remaining_enemies.has(room):
		_room_remaining_enemies[room] = maxi(0, _room_remaining_enemies[room] - 1)
	if _room_spawned_enemies.has(room):
		_room_spawned_enemies[room] = maxi(0, _room_spawned_enemies[room] - 1)

	_add_squad_xp(slime.xp_value)


func _on_enemy_death_completed(slime: Enemy) -> void:
	_entity_pool.release(slime, LAVA_SLIME_SCENE)


func _on_projectile_spawn_requested(projectile: Projectile) -> void:
	_projectiles.add_child(projectile)


func _update_followers(delta: float) -> void:
	for i: int in range(1, _squad.size()):
		var follower: Hero = _squad[i]
		if follower.squad_member != null:
			follower.squad_member.update(follower, delta, _squad, _map)


func _update_enemies() -> void:
	var camera_pos: Vector2 = _camera.global_position

	var i: int = _enemies.size() - 1
	while i >= 0:
		var enemy: Enemy = _enemies[i]
		if not is_instance_valid(enemy) or enemy.is_dead:
			_enemies.remove_at(i)
			i -= 1
			continue

		var dist_sq: float = enemy.global_position.distance_squared_to(camera_pos)
		if dist_sq > ENEMY_DESPAWN_DIST_SQ:
			var room: Rect2i = enemy.home_room
			if _room_spawned_enemies.has(room):
				_room_spawned_enemies[room] = maxi(0, _room_spawned_enemies[room] - 1)
			_entity_pool.release(enemy, LAVA_SLIME_SCENE)
			_enemies.remove_at(i)
			i -= 1
			continue

		if dist_sq > ENEMY_ACTIVE_DIST_SQ:
			if enemy.current_state == Enemy.State.PATROL and enemy.is_physics_processing():
				enemy.sync_screen_state(camera_pos)
			i -= 1
			continue

		if not enemy.is_physics_processing():
			enemy.sync_screen_state(camera_pos)

		var closest: Hero = _get_closest_squad_member(enemy.global_position)
		if closest != null:
			enemy.set_target_candidate(closest)
		i -= 1


func _get_closest_squad_member(pos: Vector2) -> Hero:
	var closest: Hero = null
	var min_dist_sq: float = INF
	for member: Hero in _squad:
		if not is_instance_valid(member) or member.is_dead:
			continue
		var dist_sq: float = pos.distance_squared_to(member.global_position)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			closest = member
	return closest


func _on_hero_died(hero: Hero) -> void:
	if hero == _character:
		return

	var squad_idx: int = _squad.find(hero)
	if squad_idx != -1:
		_squad.remove_at(squad_idx)
		_rebalance_escort_slots()
		if _hud != null and _hud.damage_meter != null:
			_hud.damage_meter.update_squad(_squad)
		return

	var unrecruited_idx: int = _unrecruited_characters.find(hero)
	if unrecruited_idx != -1:
		_unrecruited_characters.remove_at(unrecruited_idx)


func _on_player_died() -> void:
	Audio.play_hero_death_music()


func _on_player_death_completed() -> void:
	Audio.play_hero_death_music()
	var dialog: GameOverDialog = GAME_OVER_DIALOG_SCENE.instantiate() as GameOverDialog
	add_child(dialog)
	get_tree().paused = true


func _check_recruitment() -> void:
	var i: int = _unrecruited_characters.size() - 1

	while i >= 0:
		var candidate: Character = _unrecruited_characters[i]
		for member: Hero in _squad:
			if candidate.is_touching(member):
				_unrecruited_characters.remove_at(i)
				var recruit_pos: Vector2 = candidate.position
				candidate.queue_free()
				_open_recruit_panel(recruit_pos)
				return

		i -= 1


func _open_recruit_panel(recruit_pos: Vector2) -> void:
	get_tree().paused = true
	var panel: RecruitPanel = RECRUIT_PANEL_SCENE.instantiate() as RecruitPanel
	panel.hero_selected.connect(_on_hero_recruited.bind(recruit_pos))
	add_child(panel)
	panel.setup_choices(_class_levels, _get_squad_unit_counts())


func _on_hero_recruited(hero_data: HeroData, recruit_pos: Vector2) -> void:
	get_tree().paused = false
	var hero_level: int = get_class_level(hero_data.id)
	var new_hero: Hero = hero_data.instantiate_hero(hero_level)
	if new_hero == null:
		return

	_characters.add_child(new_hero)
	new_hero.is_player = false
	new_hero.position = recruit_pos
	new_hero.y_sort_enabled = true
	new_hero.leader = _character
	new_hero.squad_member = SquadMember.new()
	new_hero.projectile_spawn_requested.connect(_on_projectile_spawn_requested)
	new_hero.enemy_hit.connect(_on_hero_enemy_hit.bind(new_hero))
	new_hero.died.connect(_on_hero_died.bind(new_hero))
	_squad.append(new_hero)
	_rebalance_escort_slots()
	if _hud != null and _hud.damage_meter != null:
		_hud.damage_meter.update_squad(_squad)


func _on_hero_enemy_hit(_enemy: Enemy, damage: float, _is_heavy: bool, hero: Hero) -> void:
	if _hud != null and _hud.damage_meter != null and hero != null and hero.hero_data != null:
		_hud.damage_meter.record_damage(hero.hero_data.id, damage)


func get_class_level(class_id: StringName) -> int:
	return _class_levels.get(class_id, 1)


func _get_squad_unit_counts() -> Dictionary[StringName, int]:
	var counts: Dictionary[StringName, int] = {}
	for member: Hero in _squad:
		if is_instance_valid(member) and not member.is_dead and member.hero_data != null:
			var id: StringName = member.hero_data.id
			counts[id] = counts.get(id, 0) + 1
	return counts


static func _get_xp_required_for_level(lvl: int) -> float:
	return 50.0 + float(lvl - 1) * 40.0 + float((lvl - 1) * (lvl - 1)) * 10.0


func _add_squad_xp(amount: float) -> void:
	_current_xp += amount
	while _current_xp >= _xp_required:
		_current_xp -= _xp_required
		_squad_level += 1
		_xp_required = _get_xp_required_for_level(_squad_level)
		_pending_level_ups += 1

	if _hud != null:
		_hud.update_xp(_current_xp, _xp_required, _squad_level)

	if _pending_level_ups > 0 and not get_tree().paused:
		_open_next_level_up()


func _open_next_level_up() -> void:
	if _pending_level_ups <= 0:
		return

	_pending_level_ups -= 1
	get_tree().paused = true
	var panel: LevelUpPanel = LEVEL_UP_PANEL_SCENE.instantiate() as LevelUpPanel
	panel.class_leveled_up.connect(_on_class_leveled_up)
	add_child(panel)
	panel.setup_choices(_squad, _class_levels)


func _on_class_leveled_up(hero_data: HeroData) -> void:
	var new_level: int = get_class_level(hero_data.id) + 1
	_class_levels[hero_data.id] = new_level

	for member: Hero in _squad:
		if is_instance_valid(member) and not member.is_dead:
			if member.hero_data != null and member.hero_data.id == hero_data.id:
				hero_data.apply_to_hero(member, new_level)
				member.health = member.max_health

	get_tree().paused = false
	if _pending_level_ups > 0:
		_open_next_level_up()


static func _is_backline_hero(hero: Hero) -> bool:
	return hero.can_heal or (hero.can_ranged and not hero.can_melee)


static func _get_hero_formation_priority(hero: Hero) -> int:
	if hero.can_heal:
		return 0
	if hero.can_ranged and not hero.can_melee:
		return 1
	if hero.can_melee and hero.can_ranged:
		return 2
	return 3


static func _compare_hero_formation_priority(a: Hero, b: Hero) -> bool:
	return _get_hero_formation_priority(a) < _get_hero_formation_priority(b)


static func _calculate_arc_angles(count: int, is_front: bool, full_circle: bool) -> Array[float]:
	var angles: Array[float] = []
	if count <= 0:
		return angles

	var center_angle: float = 0.0 if is_front else PI
	if count == 1:
		angles.append(center_angle)
		return angles

	if full_circle:
		var step: float = TAU / float(count)
		for i: int in range(count):
			angles.append(center_angle + float(i) * step)
		return angles

	var max_span: float = PI * 0.75
	var arc_span: float = minf(max_span, float(count - 1) * 0.6)
	var start_angle: float = center_angle - (arc_span * 0.5)
	var step_size: float = arc_span / float(count - 1)
	for i: int in range(count):
		angles.append(start_angle + float(i) * step_size)
	return angles


func _rebalance_escort_slots() -> void:
	if _squad.size() <= 1:
		return

	var backline: Array[Hero] = []
	var frontline: Array[Hero] = []

	for i: int in range(1, _squad.size()):
		var hero: Hero = _squad[i]
		if _is_backline_hero(hero):
			backline.append(hero)
		else:
			frontline.append(hero)

	backline.sort_custom(_compare_hero_formation_priority)
	frontline.sort_custom(_compare_hero_formation_priority)

	_squad.resize(1)
	_squad.append_array(backline)
	_squad.append_array(frontline)

	var ring: int = 0
	var backline_idx: int = 0
	var frontline_idx: int = 0
	var total_assigned: int = 0

	while backline_idx < backline.size() or frontline_idx < frontline.size():
		var ring_cap: int = SquadMember.RING_BASE_CAPACITY * (ring + 1)
		var ring_backline: Array[Hero] = []
		var ring_frontline: Array[Hero] = []

		while backline_idx < backline.size() and (ring_backline.size() + ring_frontline.size()) < ring_cap:
			ring_backline.append(backline[backline_idx])
			backline_idx += 1

		while frontline_idx < frontline.size() and (ring_backline.size() + ring_frontline.size()) < ring_cap:
			ring_frontline.append(frontline[frontline_idx])
			frontline_idx += 1

		var b_count: int = ring_backline.size()
		var f_count: int = ring_frontline.size()

		var b_angles: Array[float] = _calculate_arc_angles(b_count, false, f_count == 0 and b_count > 4)
		var f_angles: Array[float] = _calculate_arc_angles(f_count, true, b_count == 0 and f_count > 4)

		for i: int in range(b_count):
			var follower: Hero = ring_backline[i]
			if follower.squad_member != null:
				follower.squad_member.assign_formation_slot(ring, b_angles[i], total_assigned, false)
			total_assigned += 1

		for i: int in range(f_count):
			var follower: Hero = ring_frontline[i]
			if follower.squad_member != null:
				follower.squad_member.assign_formation_slot(ring, f_angles[i], total_assigned, true)
			total_assigned += 1

		ring += 1


func _on_window_resized() -> void:
	# Workaround for Godot 4 Camera2D not re-centering after the window resizes.
	_camera.enabled = false
	_camera.enabled = true
	_camera.force_update_scroll()

# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Game
extends Node2D


class PendingSpawn:
	extends RefCounted
	var room: Rect2i
	var pos: Vector2

	func _init(spawn_room: Rect2i, spawn_pos: Vector2) -> void:
		room = spawn_room
		pos = spawn_pos


class RoomCandidate:
	extends RefCounted
	var room: Rect2i
	var dist_sq: float

	func _init(cand_room: Rect2i, cand_dist_sq: float) -> void:
		room = cand_room
		dist_sq = cand_dist_sq


class EvictCandidate:
	extends RefCounted
	var enemy: Enemy
	var dist_sq: float

	func _init(cand_enemy: Enemy, cand_dist_sq: float) -> void:
		enemy = cand_enemy
		dist_sq = cand_dist_sq


const MAX_CHARACTERS: int = 80
const MAX_ENEMIES: int = 160
const MAX_SPAWNS_PER_FRAME: int = 3
const ENEMY_ACTIVE_DIST_SQ: float = 480.0 * 480.0
const ENEMY_DESPAWN_DIST_SQ: float = 1350.0 * 1350.0
const ROOM_RESPAWN_DIST_SQ: float = 950.0 * 950.0
const STREAM_CHECK_INTERVAL: float = 0.15
const BASE_SQUAD_SPEED: float = 100.0
const SPRINT_SQUAD_SPEED: float = 150.0
const SPRINT_WARMUP_TIME: float = 0.4
const SPRINT_ACCELERATION: float = 50.0
const COMBAT_EXIT_DELAY: float = 1.25
const SPIKE_DAMAGE_MAX_HP_RATIO: float = 0.15
const SPIKE_HIT_COOLDOWN: float = 0.65

const UNKNOWN_SCENE: PackedScene = preload("res://character/heroes/unknown/unknown.tscn")
const COIN_SCENE: PackedScene = preload("res://coin/coin.tscn")
const KEY_PICKUP_SCENE: PackedScene = preload("res://key_pickup/key_pickup.tscn")
const LAVA_SLIME_SCENE: PackedScene = preload("res://character/enemies/lava_slime/lava_slime.tscn")
const SKELETON_SCENE: PackedScene = preload("res://character/enemies/skeleton/skeleton.tscn")
const SKELETON_ARCHER_SCENE: PackedScene = preload("res://character/enemies/skeleton_archer/skeleton_archer.tscn")
const NECROMANCER_SCENE: PackedScene = preload("res://character/enemies/necromancer/necromancer.tscn")
const ARROW_SCENE: PackedScene = preload("res://projectile/arrow/arrow.tscn")
const BONE_ARROW_SCENE: PackedScene = preload("res://projectile/bone_arrow/bone_arrow.tscn")
const LAVA_SPIKE_SCENE: PackedScene = preload("res://projectile/lava_spike/lava_spike.tscn")
const ICE_SCENE: PackedScene = preload("res://projectile/ice/ice.tscn")
const HEAL_EFFECT_SCENE: PackedScene = preload("res://projectile/heal/heal_effect.tscn")
const SMITE_EFFECT_SCENE: PackedScene = preload("res://projectile/smite/smite_effect.tscn")
const SUMMON_PENTAGRAM_SCENE: PackedScene = preload("res://projectile/summon_pentagram/summon_pentagram.tscn")

var _squad: Array[Hero] = []
var _unrecruited_characters: Array[Unknown] = []
var _starter_recruits: Array[Unknown] = []
var _coins: Array[Coin] = []
var _reroll_coins: int = 0
var _potion_manager: PotionManager = PotionManager.new()
var _keys: Array[KeyPickup] = []
var _collected_keys: Dictionary[WorldPlan.KeyColor, bool] = {}
var _class_levels: Dictionary[StringName, int] = {}
var _squad_level: int = 1
var _current_xp: float = 0.0
var _xp_required: float = 50.0
var _pending_level_ups: int = 0
var _pending_recruit_pos: Vector2 = Vector2.ZERO
var _enemies: Array[Enemy] = []
var _room_remaining_enemies: Dictionary[Rect2i, int] = {}
var _room_spawned_enemies: Dictionary[Rect2i, int] = {}
var _room_spawned_necros: Dictionary[Rect2i, int] = {}
var _stream_timer: float = 0.0
var _entity_pool: EntityPool = EntityPool.new()
var _projectile_pool: EntityPool = EntityPool.new()
var _pending_spawns: Array[PendingSpawn] = []
var _character: Hero = null
var _squad_speed: float = BASE_SQUAD_SPEED
var _combat_cooldown_timer: float = 0.0
var _continuous_move_timer: float = 0.0
var _spike_hit_cooldowns: Dictionary[Character, float] = {}
var _current_room: Rect2i = Rect2i()
var _last_player_cell: Vector2i = Vector2i(2147483647, 2147483647)

@onready var _camera: Camera2D = $Camera2D
@onready var _characters: Node2D = $Characters
@onready var _map: Map = $Map
@onready var _projectiles: Node2D = $Projectiles
@onready var _hud: Hud = $Hud
@onready var _recruit_panel: RecruitPanel = $Overlays/RecruitPanel
@onready var _level_up_panel: LevelUpPanel = $Overlays/LevelUpPanel
@onready var _pause_overlay: PauseOverlay = $PauseOverlay


func _ready() -> void:
	# Workaround for Godot 4 Camera2D not re-centering after the window resizes.
	get_tree().root.size_changed.connect(_on_window_resized)
	process_priority = 1
	y_sort_enabled = true
	set_process(false)

	await HeroData.initialize()
	await EnemyData.initialize()
	await CodexItemsPanel.initialize_data()
	await CodexMechanicsPanel.initialize_data()
	_recruit_panel.initialize()
	_level_up_panel.initialize()
	_pause_overlay.initialize()

	_map.generation_progress_updated.connect(Transition.set_loading_progress)
	_map.secret_torches_completed.connect(_on_secret_torches_completed)
	_map.door_unlocked.connect(_on_door_unlocked)
	_map.locked_door_bumped.connect(_on_locked_door_bumped)
	_map.shortcut_opened.connect(_potion_manager.on_shortcut_opened.bind(_map))
	_potion_manager.setup(_characters, _projectiles, _hud, HEAL_EFFECT_SCENE)
	await _map.generate_map()

	var starting_data: HeroData = HeroData.get_hero(Transition.starting_hero_id)
	_class_levels[starting_data.id] = 1
	_character = _spawn_hero(starting_data, _map.get_hero_spawn_position(), true)
	_camera.position = _character.position

	_hud.update_xp(_current_xp, _xp_required, _squad_level)
	_hud.update_squad(_squad)
	_hud.setup_map(_map.plan, _character)
	_check_room_entry()

	Transition.set_loading_progress(0.92)
	await get_tree().process_frame
	_entity_pool.setup(_characters)
	_entity_pool.prewarm(LAVA_SLIME_SCENE, 25)
	_entity_pool.prewarm(SKELETON_SCENE, 30)
	_entity_pool.prewarm(SKELETON_ARCHER_SCENE, 15)
	_entity_pool.prewarm(NECROMANCER_SCENE, 10)
	_projectile_pool.setup(_projectiles)
	Projectile.set_pool(_projectile_pool)
	_projectile_pool.prewarm(ARROW_SCENE, 30)
	_projectile_pool.prewarm(BONE_ARROW_SCENE, 30)
	_projectile_pool.prewarm(LAVA_SPIKE_SCENE, 20)
	for scene: PackedScene in [ICE_SCENE, HEAL_EFFECT_SCENE, SMITE_EFFECT_SCENE, SUMMON_PENTAGRAM_SCENE]:
		_projectile_pool.prewarm(scene, 15)
	_spawn_initial_characters()
	_check_recruitment()
	_check_pickups()
	_register_and_populate_rooms(_map.companion_rooms)
	while not _pending_spawns.is_empty():
		var req: PendingSpawn = _pending_spawns.pop_back()
		_spawn_enemy_at(req.pos, req.room)

	Transition.set_loading_progress(1.0)
	await get_tree().process_frame
	set_process(true)
	await Transition.hide_loading()
	Audio.play_music(true)


func _exit_tree() -> void:
	Projectile.set_pool(null)


func _on_secret_torches_completed() -> void:
	for starter: Unknown in _starter_recruits:
		if _unrecruited_characters.has(starter):
			starter.forced_hero_id = &"torchero"
			starter.ignite_secret_light()
			break
	_starter_recruits.clear()


func _process(delta: float) -> void:
	_camera.position = _character.position
	if not _character.is_dead:
		if _character.is_moving:
			_hud.dismiss_movement_hint()
			_check_room_entry()
		_character.record_step(delta)
		_stream_timer -= delta
		if _stream_timer <= 0.0:
			_stream_timer = STREAM_CHECK_INTERVAL
			_update_map_streaming()
		_map.update_streaming(_character.global_position, _character.velocity)

	_map.update_spikes(delta)
	var potion_xp: float = _potion_manager.update_buffs(delta, _squad, _character)
	if potion_xp > 0.0:
		_add_squad_xp(potion_xp)
	_update_squad_speed(delta)
	_update_followers(delta)
	_update_spike_hazards(delta)
	_check_recruitment()
	_check_pickups()
	_map.update_gates(_squad, _collected_keys, delta)
	_update_enemies()
	_process_pending_spawns()


func _update_map_streaming() -> void:
	var new_rooms: Array[Rect2i] = _map.expand_frontier_near(_character.global_position)
	if not new_rooms.is_empty():
		for room: Rect2i in new_rooms:
			_spawn_companions_for_room(room)
			_spawn_pickups_for_room(room)
		_register_and_populate_rooms(new_rooms)

	_respawn_nearby_hibernating_rooms()


func _check_room_entry() -> void:
	var player_cell: Vector2i = _map.local_to_map(_character.global_position)
	if player_cell == _last_player_cell:
		return
	_last_player_cell = player_cell

	var room: Rect2i = _map.plan.get_room_at(player_cell)
	if room == _current_room:
		return
	_current_room = room
	if room.size == Vector2i.ZERO:
		return

	if room == _map.hero_room:
		_hud.notify_room_entered(room, &"Starting Chamber", true)
		return

	var room_level: int = clampi(_map.get_room_depth(room), 1, 12)
	var remaining: int = _room_remaining_enemies.get(room, _map.get_room_enemy_quota(room))
	var archetype_name: StringName = RoomLayout.get_archetype_title(_map.plan.get_room_archetype(room))
	var title: String = &"%s - Lv. %d" % [archetype_name, room_level]
	_hud.notify_room_entered(room, title, remaining <= 0)


func _spawn_initial_characters() -> void:
	_starter_recruits.clear()
	for pos: Vector2 in _map.get_starter_companion_spawn_positions():
		_starter_recruits.append(_spawn_recruit_at(pos))

	for room: Rect2i in _map.companion_rooms:
		_spawn_companions_for_room(room)
		_spawn_pickups_for_room(room)

	for gate: SectorGatePlanner.SectorGate in _map.plan.sector_gates:
		if not gate.has_key:
			continue
		var key_node: KeyPickup = KEY_PICKUP_SCENE.instantiate() as KeyPickup
		_characters.add_child(key_node)
		key_node.position = _map.map_to_local(gate.key_cell)
		key_node.setup(gate.color)
		_keys.append(key_node)


func _spawn_companions_for_room(room: Rect2i) -> void:
	if (_squad.size() + _unrecruited_characters.size()) >= MAX_CHARACTERS:
		return

	for pos: Vector2 in _map.get_companion_spawn_positions_for_room(room):
		if (_squad.size() + _unrecruited_characters.size()) >= MAX_CHARACTERS:
			break
		_spawn_recruit_at(pos)


func _spawn_recruit_at(pos: Vector2) -> Unknown:
	var ch: Unknown = UNKNOWN_SCENE.instantiate() as Unknown
	_characters.add_child(ch)
	ch.position = pos
	ch.y_sort_enabled = true
	_unrecruited_characters.append(ch)
	return ch


func _spawn_pickups_for_room(room: Rect2i) -> void:
	var pickups: Dictionary = _map.get_room_pickups(room)
	var coin_positions: Array[Vector2] = pickups[&"coins"]
	for pos: Vector2 in coin_positions:
		var coin: Coin = COIN_SCENE.instantiate() as Coin
		_characters.add_child(coin)
		coin.position = pos
		_coins.append(coin)
	var potion_spawns: Array[Dictionary] = pickups[&"potions"]
	_potion_manager.spawn_list(potion_spawns)


func _check_pickups() -> void:
	if _character.is_dead:
		return
	for i: int in range(_coins.size() - 1, -1, -1):
		var coin: Coin = _coins[i]
		if PotionManager.is_squad_touching(_squad, coin.position, Coin.PICKUP_DISTANCE):
			_coins.remove_at(i)
			coin.queue_free()
			_reroll_coins += 1
			Codex.discover_item(&"reroll_coin")
			Audio.play_sfx(Audio.Sfx.COIN_PICKUP)

	_potion_manager.check_pickups(_squad, _character, _xp_required)

	for j: int in range(_keys.size() - 1, -1, -1):
		var key_node: KeyPickup = _keys[j]
		if PotionManager.is_squad_touching(_squad, key_node.position, KeyPickup.PICKUP_DISTANCE):
			var color: WorldPlan.KeyColor = key_node.key_color
			_keys.remove_at(j)
			key_node.queue_free()
			_collected_keys[color] = true
			Audio.play_sfx(Audio.Sfx.KEY_PICKUP)
			_hud.set_key_state(color, true, false)
			_hud.show_event_toast(&"%s Key Found!" % KeyPickup.get_color_name(color), KeyPickup.get_display_color(color))


func _on_door_unlocked(gate: SectorGatePlanner.SectorGate) -> void:
	var all_unlocked: bool = _map.plan.are_all_doors_unlocked(gate.color)
	_hud.notify_door_unlocked(gate, all_unlocked)
	_hud.show_event_toast(&"%s Door Unlocked!" % KeyPickup.get_color_name(gate.color), KeyPickup.get_display_color(gate.color))


func _on_locked_door_bumped(color: WorldPlan.KeyColor) -> void:
	_hud.show_event_toast(&"Locked - Need %s Key" % KeyPickup.get_color_name(color), KeyPickup.get_display_color(color))


func _spawn_hero(hero_data: HeroData, pos: Vector2, is_leader: bool) -> Hero:
	Codex.discover_hero(hero_data.id)
	var hero_level: int = _class_levels.get(hero_data.id, 1)
	var hero: Hero = hero_data.scene.instantiate() as Hero
	hero_data.apply_to_hero(hero, hero_level)
	_potion_manager.apply_buffs_to_hero(hero)
	if is_leader:
		hero.name = &"Character"
	_characters.add_child(hero)
	hero.is_player = is_leader
	hero.position = pos
	hero.y_sort_enabled = true
	hero.speed = _squad_speed
	hero.projectile_spawn_requested.connect(_on_projectile_spawn_requested)
	hero.enemy_hit.connect(_on_hero_enemy_hit.bind(hero))
	if is_leader:
		hero.move_direction = Vector2.UP
		hero.record_step(0.0)
		hero.death_completed.connect(_on_player_death_completed)
		hero.died.connect(_on_player_died)
	else:
		hero.leader = _character
		hero.squad_member = SquadMember.new()
		hero.died.connect(_on_hero_died.bind(hero))
	_squad.append(hero)
	return hero


func _register_and_populate_rooms(rooms: Array[Rect2i]) -> void:
	var player_pos: Vector2 = _character.global_position
	for room: Rect2i in rooms:
		if not _room_remaining_enemies.has(room):
			var quota: int = _map.get_room_enemy_quota(room)
			_room_remaining_enemies[room] = quota
			_room_spawned_enemies[room] = 0
		var room_center_world: Vector2 = _map.map_to_local(room.get_center())
		if _map.is_cell_walkable(room.get_center()) and player_pos.distance_squared_to(room_center_world) <= ROOM_RESPAWN_DIST_SQ:
			_populate_room_enemies(room)


func _populate_room_enemies(room: Rect2i) -> void:
	if not _map.is_cell_walkable(room.get_center()):
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
		_pending_spawns.append(PendingSpawn.new(room, pos))
		_room_spawned_enemies[room] = _room_spawned_enemies.get(room, 0) + 1


func _process_pending_spawns() -> void:
	var spawned: int = 0
	var cam_pos: Vector2 = _camera.global_position
	while not _pending_spawns.is_empty() and spawned < MAX_SPAWNS_PER_FRAME:
		if _enemies.size() >= MAX_ENEMIES:
			break
		var req: PendingSpawn = _pending_spawns.pop_back()
		var cell: Vector2i = _map.local_to_map(req.pos)
		if req.pos.distance_squared_to(cam_pos) > ENEMY_DESPAWN_DIST_SQ or not _map.is_cell_walkable(cell):
			if _room_spawned_enemies.has(req.room):
				_room_spawned_enemies[req.room] = maxi(0, _room_spawned_enemies[req.room] - 1)
			continue
		_spawn_enemy_at(req.pos, req.room)
		spawned += 1


func _spawn_enemy_at(pos: Vector2, room: Rect2i, forced_scene: PackedScene = null, forced_level: int = -1, is_summoned: bool = false) -> void:
	var depth: int = _map.get_room_depth(room)
	var enemy_scene: PackedScene = forced_scene
	if enemy_scene == null:
		enemy_scene = _pick_enemy_scene_for_room(room, depth)
	var enemy: Enemy = _entity_pool.acquire(enemy_scene) as Enemy
	enemy.home_room = room
	enemy.position = pos
	enemy.map = _map
	enemy.y_sort_enabled = true
	var enemy_level: int = forced_level if forced_level > 0 else clampi(depth, 1, 12)
	enemy.set_level(enemy_level)
	if not enemy.projectile_spawn_requested.is_connected(_on_projectile_spawn_requested):
		enemy.projectile_spawn_requested.connect(_on_projectile_spawn_requested)
		enemy.minion_summon_requested.connect(_on_enemy_minion_summon_requested)
		enemy.attacked.connect(_on_enemy_attacked)
		enemy.died.connect(_on_enemy_died.bind(enemy))
		enemy.death_completed.connect(_on_enemy_death_completed.bind(enemy))
	enemy.sync_screen_state(_camera.global_position)
	if is_summoned:
		enemy.play_summon_intro()
	_enemies.append(enemy)


func _respawn_nearby_hibernating_rooms() -> void:
	var player_pos: Vector2 = _character.global_position
	var room_candidates: Array[RoomCandidate] = []

	for room: Rect2i in _map.companion_rooms:
		var remaining: int = _room_remaining_enemies.get(room, 0)
		var spawned: int = _room_spawned_enemies.get(room, 0)
		if remaining <= spawned or not _map.is_cell_walkable(room.get_center()):
			continue

		var room_world_center: Vector2 = _map.map_to_local(room.get_center())
		var dist_sq: float = player_pos.distance_squared_to(room_world_center)
		if dist_sq <= ROOM_RESPAWN_DIST_SQ:
			room_candidates.append(RoomCandidate.new(room, dist_sq))

	if room_candidates.is_empty():
		return

	room_candidates.sort_custom(_compare_room_candidate_asc)

	for cand: RoomCandidate in room_candidates:
		var room: Rect2i = cand.room
		var remaining: int = _room_remaining_enemies.get(room, 0)
		var spawned: int = _room_spawned_enemies.get(room, 0)
		var needed: int = remaining - spawned
		if needed <= 0:
			continue

		var free_slots: int = MAX_ENEMIES - (_enemies.size() + _pending_spawns.size())
		if free_slots < needed:
			_reclaim_distant_enemies_for_room(room, cand.dist_sq, needed - free_slots, player_pos)

		_populate_room_enemies(room)


func _reclaim_distant_enemies_for_room(target_room: Rect2i, target_room_dist_sq: float, count_needed: int, player_pos: Vector2) -> void:
	var reclaimed: int = 0
	var min_evict_dist_sq: float = target_room_dist_sq + 6400.0

	var p_idx: int = _pending_spawns.size() - 1
	while p_idx >= 0 and reclaimed < count_needed:
		var req: PendingSpawn = _pending_spawns[p_idx]
		if req.room != target_room:
			var r_center: Vector2 = _map.map_to_local(req.room.get_center())
			if player_pos.distance_squared_to(r_center) > min_evict_dist_sq:
				_pending_spawns.remove_at(p_idx)
				if _room_spawned_enemies.has(req.room):
					_room_spawned_enemies[req.room] = maxi(0, _room_spawned_enemies[req.room] - 1)
				reclaimed += 1
		p_idx -= 1

	if reclaimed >= count_needed:
		return

	var evictable: Array[EvictCandidate] = []
	for enemy: Enemy in _enemies:
		if enemy.is_dead or enemy.home_room == target_room or enemy.is_on_screen or enemy.current_state != Enemy.State.PATROL:
			continue
		var home_center: Vector2 = _map.map_to_local(enemy.home_room.get_center())
		var home_dist_sq: float = player_pos.distance_squared_to(home_center)
		if home_dist_sq > min_evict_dist_sq:
			evictable.append(EvictCandidate.new(enemy, home_dist_sq))

	if evictable.is_empty():
		return

	evictable.sort_custom(_compare_evict_candidate_desc)

	for item: EvictCandidate in evictable:
		if reclaimed >= count_needed:
			break
		_despawn_enemy(item.enemy)
		reclaimed += 1


func _despawn_enemy(enemy: Enemy) -> void:
	var room: Rect2i = enemy.home_room
	if _room_spawned_enemies.has(room):
		_room_spawned_enemies[room] = maxi(0, _room_spawned_enemies[room] - 1)
	if enemy is Necromancer and _room_spawned_necros.has(room):
		_room_spawned_necros[room] = maxi(0, _room_spawned_necros[room] - 1)
	_spike_hit_cooldowns.erase(enemy)
	_entity_pool.release(enemy)
	_enemies.erase(enemy)


static func _compare_room_candidate_asc(a: RoomCandidate, b: RoomCandidate) -> bool:
	return a.dist_sq < b.dist_sq


static func _compare_evict_candidate_desc(a: EvictCandidate, b: EvictCandidate) -> bool:
	return a.dist_sq > b.dist_sq


func _pick_enemy_scene_for_room(room: Rect2i, depth: int) -> PackedScene:
	var archetype: WorldPlan.RoomArchetype = _map.plan.get_room_archetype(room)
	var result: PackedScene = LAVA_SLIME_SCENE
	match archetype:
		WorldPlan.RoomArchetype.BONE_SWARM:
			result = SKELETON_SCENE
		WorldPlan.RoomArchetype.ARCHER_GARRISON:
			result = SKELETON_ARCHER_SCENE if randf() < 0.65 else SKELETON_SCENE
		WorldPlan.RoomArchetype.NECRO_CRYPT:
			var max_necros: int = 1 if depth <= 4 else 2
			var spawned_necros: int = _room_spawned_necros.get(room, 0)
			if spawned_necros < max_necros:
				_room_spawned_necros[room] = spawned_necros + 1
				result = NECROMANCER_SCENE
			else:
				result = SKELETON_ARCHER_SCENE if randf() < 0.35 else SKELETON_SCENE
	return result


func _on_enemy_minion_summon_requested(pos: Vector2, room: Rect2i, enemy_level: int) -> void:
	if _enemies.size() >= MAX_ENEMIES:
		return
	var cell: Vector2i = _map.local_to_map(pos)
	if not _map.is_cell_walkable(cell):
		return
	var pentagram: Projectile = Projectile.acquire(SUMMON_PENTAGRAM_SCENE)
	pentagram.global_position = pos
	pentagram.launch()

	if _room_remaining_enemies.has(room):
		_room_remaining_enemies[room] += 1
	if _room_spawned_enemies.has(room):
		_room_spawned_enemies[room] += 1

	var minion_scene: PackedScene = SKELETON_ARCHER_SCENE if randf() < 0.30 else SKELETON_SCENE
	_spawn_enemy_at(pos, room, minion_scene, enemy_level, true)


func _on_enemy_died(enemy: Enemy) -> void:
	Audio.play_sfx(Audio.Sfx.ENEMY_DEATH)
	_spike_hit_cooldowns.erase(enemy)
	for member: Hero in _squad:
		if member.active_target == enemy:
			member.active_target = null
	for child: Node in _projectiles.get_children():
		(child as Projectile).clear_character_references(enemy)
	var room: Rect2i = enemy.home_room
	if _room_remaining_enemies.has(room):
		_room_remaining_enemies[room] = maxi(0, _room_remaining_enemies[room] - 1)
		if _room_remaining_enemies[room] <= 0:
			_hud.set_room_cleared(room, true)
	if _room_spawned_enemies.has(room):
		_room_spawned_enemies[room] = maxi(0, _room_spawned_enemies[room] - 1)

	_add_squad_xp(enemy.xp_value)
	_reset_combat_cooldown()


func _on_enemy_death_completed(enemy: Enemy) -> void:
	_spike_hit_cooldowns.erase(enemy)
	_entity_pool.release(enemy)


func _on_projectile_spawn_requested(projectile: Projectile) -> void:
	if projectile.get_parent() == null:
		_projectiles.add_child(projectile)
	projectile.launch()


func _update_followers(delta: float) -> void:
	for i: int in range(1, _squad.size()):
		var follower: Hero = _squad[i]
		follower.squad_member.update(follower, delta, _squad, _map)


func _update_enemies() -> void:
	var camera_pos: Vector2 = _camera.global_position

	var i: int = _enemies.size() - 1
	while i >= 0:
		var enemy: Enemy = _enemies[i]
		if enemy.is_dead:
			_enemies.remove_at(i)
			i -= 1
			continue

		var dist_sq: float = enemy.global_position.distance_squared_to(camera_pos)
		if dist_sq > ENEMY_DESPAWN_DIST_SQ:
			_despawn_enemy(enemy)
			i -= 1
			continue

		if dist_sq > ENEMY_ACTIVE_DIST_SQ:
			if enemy.current_state == Enemy.State.PATROL and enemy.is_physics_processing():
				enemy.sync_screen_state(camera_pos)
			i -= 1
			continue

		if not enemy.is_physics_processing():
			enemy.sync_screen_state(camera_pos)

		var best_target: Hero = _get_best_squad_target(enemy)
		if best_target != null:
			enemy.set_target_candidate(best_target)
		i -= 1


func _get_best_squad_target(enemy: Enemy) -> Hero:
	var best: Hero = null
	var min_eff_dist_sq: float = INF
	var max_dist_sq: float = enemy.detection_range * enemy.detection_range
	var enemy_pos: Vector2 = enemy.global_position
	for member: Hero in _squad:
		if member.is_dead:
			continue
		var raw_dist_sq: float = enemy_pos.distance_squared_to(member.global_position)
		if raw_dist_sq > max_dist_sq:
			continue
		var eff_dist_sq: float = enemy.get_effective_target_dist_sq(member)
		if eff_dist_sq < min_eff_dist_sq:
			min_eff_dist_sq = eff_dist_sq
			best = member
	return best


func _on_hero_died(hero: Hero) -> void:
	Audio.play_sfx(Audio.Sfx.HERO_DOWN)
	_squad.erase(hero)
	_clear_dead_hero_references(hero)
	_rebalance_escort_slots()
	_hud.update_squad(_squad)


func _on_player_died() -> void:
	Audio.play_sfx(Audio.Sfx.HERO_DOWN)
	Audio.stop_music()
	_clear_dead_hero_references(_character)
	_hud.update_squad(_squad)


func _clear_dead_hero_references(dead_hero: Hero) -> void:
	_spike_hit_cooldowns.erase(dead_hero)
	for member: Hero in _squad:
		if member.active_target == dead_hero:
			member.active_target = null
	for enemy: Enemy in _enemies:
		enemy.clear_hero_references(dead_hero)
	for child: Node in _projectiles.get_children():
		(child as Projectile).clear_character_references(dead_hero)


func _on_player_death_completed() -> void:
	Audio.play_sfx(Audio.Sfx.GAME_OVER)
	Audio.stop_music()
	_pause_overlay.open_game_over()


func _check_recruitment() -> void:
	if _character.is_dead:
		return
	var i: int = _unrecruited_characters.size() - 1

	while i >= 0:
		var candidate: Unknown = _unrecruited_characters[i]
		for member: Hero in _squad:
			if member.is_dead:
				continue
			if candidate.is_touching(member):
				_unrecruited_characters.remove_at(i)
				var recruit_pos: Vector2 = candidate.position
				var forced_id: StringName = candidate.forced_hero_id
				var starter_idx: int = _starter_recruits.find(candidate)
				if starter_idx != -1:
					_starter_recruits.remove_at(starter_idx)
					if _starter_recruits.is_empty():
						_map.cancel_secret_torches()
				candidate.queue_free()
				_open_recruit_panel(recruit_pos, forced_id)
				return

		i -= 1


func _open_recruit_panel(recruit_pos: Vector2, forced_hero_id: StringName = &"") -> void:
	Audio.play_sfx(Audio.Sfx.HERO_RECRUITED)
	get_tree().paused = true
	_pending_recruit_pos = recruit_pos
	_recruit_panel.visible = true
	_recruit_panel.setup_choices(_class_levels, _get_squad_unit_counts(), forced_hero_id, _reroll_coins)


func _on_recruit_reroll_requested() -> void:
	if _reroll_coins <= 0:
		return
	_reroll_coins -= 1
	_recruit_panel.reroll_choices(_class_levels, _get_squad_unit_counts(), _reroll_coins)


func _on_hero_recruited(hero_data: HeroData) -> void:
	get_tree().paused = false
	_spawn_hero(hero_data, _pending_recruit_pos, false)
	_rebalance_escort_slots()
	_hud.update_squad(_squad)


func _on_hero_enemy_hit(enemy: Enemy, damage: float, is_heavy: bool, hero: Hero) -> void:
	Codex.discover_enemy(enemy.enemy_id)
	_hud.record_damage(hero.hero_data.id, damage)
	_reset_combat_cooldown()
	Audio.play_sfx(Audio.Sfx.HEAVY_IMPACT if is_heavy else Audio.Sfx.HIT_IMPACT)
	if not enemy.is_dead and enemy.target == null:
		enemy.set_target_candidate(hero)


func _get_squad_unit_counts() -> Dictionary[StringName, int]:
	var counts: Dictionary[StringName, int] = {}
	for member: Hero in _squad:
		if not member.is_dead:
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

	_hud.update_xp(_current_xp, _xp_required, _squad_level)

	if _pending_level_ups > 0 and not get_tree().paused and not _character.is_dead:
		_open_next_level_up()


func _open_next_level_up() -> void:
	if _pending_level_ups <= 0:
		return

	Audio.play_sfx(Audio.Sfx.LEVEL_UP)
	_pending_level_ups -= 1
	get_tree().paused = true
	_level_up_panel.visible = true
	_level_up_panel.setup_choices(_class_levels, _get_squad_unit_counts(), _reroll_coins)


func _on_level_up_reroll_requested() -> void:
	if _reroll_coins <= 0:
		return
	_reroll_coins -= 1
	_level_up_panel.reroll_choices(_class_levels, _get_squad_unit_counts(), _reroll_coins)


func _on_class_leveled_up(hero_data: HeroData) -> void:
	var new_level: int = _class_levels.get(hero_data.id, 1) + 1
	_class_levels[hero_data.id] = new_level

	for member: Hero in _squad:
		if not member.is_dead and member.hero_data.id == hero_data.id:
			hero_data.apply_to_hero(member, new_level)
			member.health = member.max_health
			member.play_level_up_vfx()

	_hud.update_squad(_squad)

	get_tree().paused = false
	if _pending_level_ups > 0:
		_open_next_level_up()


static func _is_backline_hero(hero: Hero) -> bool:
	var role: HeroData.Role = hero.hero_data.role
	return role == HeroData.Role.HEALER or role == HeroData.Role.RANGED


static func _get_hero_formation_priority(hero: Hero) -> int:
	match hero.hero_data.role:
		HeroData.Role.HEALER:
			return 0
		HeroData.Role.RANGED:
			return 1
		HeroData.Role.HYBRID:
			return 2
		_:
			return 3


static func _compare_hero_formation_priority(a: Hero, b: Hero) -> bool:
	return _get_hero_formation_priority(a) < _get_hero_formation_priority(b)


static func _calculate_arc_angles(count: int, is_front: bool) -> Array[float]:
	var angles: Array[float] = []
	if count <= 0:
		return angles

	var center_angle: float = 0.0 if is_front else PI
	if count == 1:
		angles.append(center_angle)
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

		var b_angles: Array[float] = _calculate_arc_angles(b_count, false)
		var f_angles: Array[float] = _calculate_arc_angles(f_count, true)

		for i: int in range(b_count):
			var follower: Hero = ring_backline[i]
			follower.squad_member.assign_formation_slot(ring, b_angles[i], total_assigned, false)
			total_assigned += 1

		for i: int in range(f_count):
			var follower: Hero = ring_frontline[i]
			follower.squad_member.assign_formation_slot(ring, f_angles[i], total_assigned, true)
			total_assigned += 1

		ring += 1


func _reset_combat_cooldown() -> void:
	_combat_cooldown_timer = COMBAT_EXIT_DELAY
	_continuous_move_timer = 0.0
	_squad_speed = BASE_SQUAD_SPEED


func _on_enemy_attacked(_target: Hero, _damage_amount: float) -> void:
	_reset_combat_cooldown()


func _is_any_enemy_engaged() -> bool:
	for enemy: Enemy in _enemies:
		if enemy.is_dead or not enemy.visible:
			continue
		if enemy.is_engaged():
			return true
	return false


func _is_any_hero_engaged() -> bool:
	for member: Hero in _squad:
		if member.is_dead:
			continue
		if member.is_engaged():
			return true
	return false


func _update_squad_speed(delta: float) -> void:
	var in_combat: bool = _is_any_enemy_engaged() or _is_any_hero_engaged()
	if in_combat:
		_reset_combat_cooldown()
	elif _combat_cooldown_timer > 0.0:
		_combat_cooldown_timer = maxf(0.0, _combat_cooldown_timer - delta)
		_continuous_move_timer = 0.0
		_squad_speed = BASE_SQUAD_SPEED
	elif _character.is_moving:
		_continuous_move_timer += delta
		if _continuous_move_timer >= SPRINT_WARMUP_TIME:
			_squad_speed = move_toward(_squad_speed, SPRINT_SQUAD_SPEED, SPRINT_ACCELERATION * delta)
		else:
			_squad_speed = BASE_SQUAD_SPEED
	else:
		_continuous_move_timer = 0.0
		_squad_speed = BASE_SQUAD_SPEED

	var effective_speed: float = _squad_speed * _potion_manager.get_speed_multiplier()
	for member: Hero in _squad:
		if not member.is_dead:
			member.speed = effective_speed


func _update_spike_hazards(delta: float) -> void:
	var expired: Array[Character] = []
	for ch: Character in _spike_hit_cooldowns:
		var rem_cd: float = _spike_hit_cooldowns[ch] - delta
		if rem_cd > 0.0:
			_spike_hit_cooldowns[ch] = rem_cd
		else:
			expired.append(ch)
	for ch: Character in expired:
		_spike_hit_cooldowns.erase(ch)

	for member: Hero in _squad:
		if not member.is_dead:
			_check_character_spike(member)

	for enemy: Enemy in _enemies:
		if not enemy.is_dead and enemy.visible and enemy.is_physics_processing():
			var damage: float = _check_character_spike(enemy)
			if damage > 0.0:
				_hud.record_damage(&"spike", damage)


func _check_character_spike(character: Character) -> float:
	if _spike_hit_cooldowns.has(character):
		return 0.0
	var foot_cell: Vector2i = _map.local_to_map(character.get_hurtbox_position())
	if not _map.is_spike_active_at(foot_cell):
		return 0.0
	Audio.play_sfx(Audio.Sfx.SPIKE_TRAP)
	_spike_hit_cooldowns[character] = SPIKE_HIT_COOLDOWN
	var damage: float = maxf(1.0, roundf(character.max_health * SPIKE_DAMAGE_MAX_HP_RATIO))
	character.take_damage(damage)
	return damage


func _on_window_resized() -> void:
	# Workaround for Godot 4 Camera2D not re-centering after the window resizes.
	_camera.enabled = false
	_camera.enabled = true
	_camera.force_update_scroll()

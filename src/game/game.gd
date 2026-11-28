# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Game
extends Node2D


class PendingSpawn:
	extends RefCounted
	var room: Rect2i
	var pos: Vector2
	var is_patrol: bool = false

	func _init(spawn_room: Rect2i, spawn_pos: Vector2, spawn_is_patrol: bool = false) -> void:
		room = spawn_room
		pos = spawn_pos
		is_patrol = spawn_is_patrol


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
const MAX_SUMMONS_PER_ROOM: int = 6
const MAX_ALIVE_FOR_SUMMON: int = 20
const ENEMY_ACTIVE_DIST_SQ: float = 420.0 * 420.0
const ENEMY_DESPAWN_DIST_SQ: float = 1350.0 * 1350.0
const ENEMY_SCAN_STRIDE: int = 6
const ROOM_RESPAWN_DIST_SQ: float = 950.0 * 950.0
const STREAM_CHECK_INTERVAL: float = 0.15
const BASE_SQUAD_SPEED: float = 100.0
const SPRINT_SQUAD_SPEED: float = 150.0
const SPRINT_WARMUP_TIME: float = 0.4
const SPRINT_ACCELERATION: float = 50.0
const COMBAT_EXIT_DELAY: float = 1.25
const SPIKE_DAMAGE_MAX_HP_RATIO: float = 0.15
const SPIKE_HIT_COOLDOWN: float = 0.65
const BLOOD_SPIKE_DAMAGE_MAX_HP_RATIO: float = 0.30
const BLOOD_SPIKE_HIT_COOLDOWN: float = 0.45

const UNKNOWN_SCENE: PackedScene = preload("res://character/heroes/unknown/unknown.tscn")
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
var _patrol_manager: PatrolManager = PatrolManager.new()
var _event_director: EventDirector = EventDirector.new()
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
var _room_summoned_enemies: Dictionary[Rect2i, int] = {}
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
var _enemy_scan_tick: int = 0
var _run_tracker: RunTracker = RunTracker.new()

@onready var _camera: Camera2D = $Camera2D
@onready var _characters: Node2D = $Characters
@onready var _map: Map = $Map
@onready var _projectiles: Node2D = $Projectiles
@onready var _hud: Hud = $Hud
@onready var _fog: Fog = $Fog
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
	await CodexEventsPanel.initialize_data()
	await CodexMechanicsPanel.initialize_data()
	_recruit_panel.initialize()
	_level_up_panel.initialize()
	_pause_overlay.initialize()

	_map.generation_progress_updated.connect(Transition.set_loading_progress)
	_map.secret_torches_completed.connect(_on_secret_torches_completed)
	_map.door_unlocked.connect(_on_door_unlocked)
	_map.locked_door_bumped.connect(_on_locked_door_bumped)
	_map.shortcut_opened.connect(_on_shortcut_opened)
	_event_director.setup(_hud, _fog, _camera)
	_map.event_room_armed.connect(_event_director.handle_map_event_armed.bind(self))
	_map.event_room_disarmed.connect(_event_director.on_event_disarmed)
	_potion_manager.setup(_characters, _projectiles, _hud, HEAL_EFFECT_SCENE)
	await _map.generate_map()
	_patrol_manager.setup(_map, _room_remaining_enemies, _room_spawned_enemies)

	var starting_data: HeroData = HeroData.get_hero(Transition.starting_hero_id)
	_class_levels[starting_data.id] = 1
	_character = _spawn_hero(starting_data, _map.get_hero_spawn_position(), true)
	_camera.position = _character.position

	_hud.update_xp(_current_xp, _xp_required, _squad_level)
	_hud.update_squad(_squad)
	_hud.setup_map(_map.plan, _character)
	_check_room_entry()
	_run_tracker.start_run(_map, _hud, starting_data.id)

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
	_event_director.update(delta)
	if not _character.is_dead:
		_run_tracker.advance_time(delta, _hud)
		_patrol_manager.advance_time(delta)
		if _character.is_moving:
			_hud.dismiss_movement_hint()
			_check_room_entry()
		_character.record_step(delta)
		_stream_timer -= delta
		if _stream_timer <= 0.0:
			_stream_timer = STREAM_CHECK_INTERVAL
			_update_map_streaming()
		_map.update_streaming(_character.global_position, _character.velocity)

	_map.update_spikes(delta, _map.local_to_map(_character.global_position) if not _character.is_dead else Vector2i(2147483647, 2147483647))
	if not _character.is_dead:
		_event_director.update_events(self, delta)
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

	_patrol_manager.update_repopulation(_camera.global_position)
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
	_patrol_manager.set_occupied_room(room)

	if room == _map.hero_room:
		_hud.notify_room_entered(room, &"Starting Chamber")
		return

	_hud.notify_room_entered(room, _event_director.get_room_entry_title(_map, room))
	var event_type: WorldPlan.RoomEventType = _map.plan.room_event_types.get(room, WorldPlan.RoomEventType.NONE)
	var event_codex_id: StringName = EventDirector.get_codex_id(event_type)
	if not event_codex_id.is_empty():
		Codex.discover(Codex.Category.EVENTS, event_codex_id)


func _spawn_initial_characters() -> void:
	_starter_recruits.clear()
	for pos: Vector2 in _map.get_starter_companion_spawn_positions():
		_starter_recruits.append(_spawn_recruit_at(pos, _map.hero_room))

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

	_event_director.spawn_event_chests(_map, _characters)
	_potion_manager.spawn_cell_pickups(_map.plan.corridor_coin_cells, _map.plan.corridor_potion_spawns, _map, _coins)


func _spawn_companions_for_room(room: Rect2i) -> void:
	if (_squad.size() + _unrecruited_characters.size()) >= MAX_CHARACTERS:
		return

	for pos: Vector2 in _map.get_companion_spawn_positions_for_room(room):
		if (_squad.size() + _unrecruited_characters.size()) >= MAX_CHARACTERS:
			break
		_spawn_recruit_at(pos, room)


func _spawn_recruit_at(pos: Vector2, room: Rect2i) -> Unknown:
	var ch: Unknown = UNKNOWN_SCENE.instantiate() as Unknown
	_characters.add_child(ch)
	ch.position = pos
	ch.home_room = room
	ch.y_sort_enabled = true
	_unrecruited_characters.append(ch)
	return ch


func _spawn_pickups_for_room(room: Rect2i, include_event_reward: bool = false, drop_anchor: Vector2 = Vector2.INF) -> void:
	_potion_manager.spawn_pickups(_map.get_room_pickups(room, include_event_reward, drop_anchor), _coins)


func _check_pickups() -> void:
	if _character.is_dead:
		return
	for i: int in range(_coins.size() - 1, -1, -1):
		var coin: Coin = _coins[i]
		if PotionManager.is_squad_touching(_squad, coin.position, Coin.PICKUP_DISTANCE):
			_coins.remove_at(i)
			coin.queue_free()
			_reroll_coins += 1
			Codex.discover(Codex.Category.ITEMS, &"reroll_coin")
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
			var key_name: String = KeyPickup.get_color_name(color)
			_hud.show_event_banner(&"KEY FOUND", &"%s Key" % key_name, &"", KeyPickup.get_display_color(color))


func _on_door_unlocked(gate: SectorGatePlanner.SectorGate) -> void:
	var all_unlocked: bool = _map.plan.are_all_doors_unlocked(gate.color)
	_hud.notify_door_unlocked(gate, all_unlocked)
	_hud.show_event_toast(&"%s Door Unlocked!" % KeyPickup.get_color_name(gate.color), KeyPickup.get_display_color(gate.color))


func _on_locked_door_bumped(color: WorldPlan.KeyColor) -> void:
	_hud.show_event_toast(&"Locked - Need %s Key" % KeyPickup.get_color_name(color), KeyPickup.get_display_color(color))


func _on_shortcut_opened(shortcut: ShortcutTunnelPlanner.LocalShortcut) -> void:
	_hud.notify_shortcut_opened(shortcut)


func _spawn_hero(hero_data: HeroData, pos: Vector2, is_leader: bool) -> Hero:
	Codex.discover(Codex.Category.HEROES, hero_data.id)
	if not _class_levels.has(hero_data.id):
		_class_levels[hero_data.id] = 1
	var hero_level: int = _class_levels[hero_data.id]
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
		if _map.plan.is_event_room(room):
			_room_remaining_enemies[room] = 0
			_room_spawned_enemies[room] = 0
			continue
		if not _room_remaining_enemies.has(room):
			var quota: int = _map.get_room_enemy_quota(room)
			_room_remaining_enemies[room] = quota
			_room_spawned_enemies[room] = 0
		var room_center_world: Vector2 = _map.map_to_local(room.get_center())
		if _map.is_cell_walkable(room.get_center()) and player_pos.distance_squared_to(room_center_world) <= ROOM_RESPAWN_DIST_SQ:
			_populate_room_enemies(room)


func _populate_room_enemies(room: Rect2i, is_patrol: bool = false) -> void:
	if not _map.is_cell_walkable(room.get_center()):
		return
	var needed: int = _patrol_manager.get_needed_spawns(room, is_patrol)
	if needed <= 0 or (_enemies.size() + _pending_spawns.size()) >= MAX_ENEMIES:
		return

	var capacity: int = MAX_ENEMIES - (_enemies.size() + _pending_spawns.size())
	var to_spawn: int = mini(needed, capacity)
	var spawn_positions: Array[Vector2] = _map.get_enemy_spawn_positions_for_room(room, to_spawn)

	for pos: Vector2 in spawn_positions:
		_pending_spawns.append(PendingSpawn.new(room, pos, is_patrol))
	_patrol_manager.record_spawned(room, spawn_positions.size(), is_patrol)


func _process_pending_spawns() -> void:
	var spawned: int = 0
	var cam_pos: Vector2 = _camera.global_position
	while not _pending_spawns.is_empty() and spawned < MAX_SPAWNS_PER_FRAME:
		if _enemies.size() >= MAX_ENEMIES:
			break
		var req: PendingSpawn = _pending_spawns.pop_back()
		var cell: Vector2i = _map.local_to_map(req.pos)
		if req.pos.distance_squared_to(cam_pos) > ENEMY_DESPAWN_DIST_SQ or not _map.is_cell_walkable(cell):
			_patrol_manager.record_despawned(req.room, req.is_patrol)
			continue
		_spawn_enemy_at(req.pos, req.room, null, -1, false, req.is_patrol)
		spawned += 1


func _spawn_enemy_at(
	pos: Vector2,
	room: Rect2i,
	forced_scene: PackedScene = null,
	forced_level: int = -1,
	is_summoned: bool = false,
	is_patrol: bool = false,
) -> void:
	var depth: int = _map.get_room_depth(room)
	var enemy_scene: PackedScene = forced_scene
	if enemy_scene == null:
		if is_patrol:
			enemy_scene = PatrolManager.pick_enemy_scene(_map.plan.get_room_archetype(room), LAVA_SLIME_SCENE, SKELETON_SCENE, SKELETON_ARCHER_SCENE)
		else:
			enemy_scene = _pick_enemy_scene_for_room(room, depth)
	var enemy: Enemy = _entity_pool.acquire(enemy_scene) as Enemy
	enemy.home_room = room
	enemy.position = pos
	enemy.map = _map
	enemy.y_sort_enabled = true
	var enemy_level: int = forced_level if forced_level > 0 else clampi(depth, 1, 12)
	enemy.set_level(enemy_level, is_patrol)
	if not enemy.projectile_spawn_requested.is_connected(_on_projectile_spawn_requested):
		enemy.projectile_spawn_requested.connect(_on_projectile_spawn_requested)
		enemy.minion_summon_requested.connect(_on_enemy_minion_summon_requested)
		enemy.attacked.connect(_on_enemy_attacked)
		enemy.died.connect(_on_enemy_died.bind(enemy))
		enemy.death_completed.connect(_on_enemy_death_completed.bind(enemy))
	enemy.sync_screen_state(_camera.global_position)
	if room != Rect2i() and room == _map.active_event_room and CombatAction.is_valid_target(_character):
		enemy.set_target_candidate(_character, true)
	if is_summoned:
		enemy.play_summon_intro()
	_enemies.append(enemy)


func _respawn_nearby_hibernating_rooms() -> void:
	var player_pos: Vector2 = _character.global_position
	var room_candidates: Array[PatrolManager.RoomCandidate] = _patrol_manager.collect_rooms(player_pos, ROOM_RESPAWN_DIST_SQ)
	if room_candidates.is_empty():
		return

	for cand: PatrolManager.RoomCandidate in room_candidates:
		var free_slots: int = MAX_ENEMIES - (_enemies.size() + _pending_spawns.size())
		if free_slots < cand.needed:
			_reclaim_distant_enemies_for_room(cand.room, cand.dist_sq, cand.needed - free_slots, player_pos)
		_populate_room_enemies(cand.room, cand.is_patrol)


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
				_patrol_manager.record_despawned(req.room, req.is_patrol)
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


static func _decrement_room_count(counts: Dictionary[Rect2i, int], room: Rect2i) -> void:
	if counts.has(room):
		counts[room] = maxi(0, counts[room] - 1)


func _despawn_enemy(enemy: Enemy) -> void:
	var room: Rect2i = enemy.home_room
	if enemy.is_minion:
		_decrement_room_count(_room_summoned_enemies, room)
	elif enemy.is_patrol_respawn:
		_patrol_manager.record_despawned(room)
	else:
		_decrement_room_count(_room_spawned_enemies, room)
		if enemy is Necromancer:
			_decrement_room_count(_room_spawned_necros, room)
	_spike_hit_cooldowns.erase(enemy)
	_entity_pool.release(enemy)
	_enemies.erase(enemy)


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
			var max_necros: int = 1 if depth <= 6 else 2
			var spawned_necros: int = _room_spawned_necros.get(room, 0)
			if spawned_necros < max_necros:
				_room_spawned_necros[room] = spawned_necros + 1
				result = NECROMANCER_SCENE
			else:
				result = SKELETON_ARCHER_SCENE if randf() < 0.35 else SKELETON_SCENE
	return result


func _on_enemy_minion_summon_requested(pos: Vector2, room: Rect2i, enemy_level: int) -> void:
	var summoned: int = _room_summoned_enemies.get(room, 0)
	var spawned: int = _room_spawned_enemies.get(room, 0)
	if _enemies.size() >= MAX_ENEMIES or summoned >= MAX_SUMMONS_PER_ROOM or (spawned + summoned) >= MAX_ALIVE_FOR_SUMMON:
		return
	var cell: Vector2i = _map.local_to_map(pos)
	if not _map.is_cell_walkable(cell):
		return
	var pentagram: Projectile = Projectile.acquire(SUMMON_PENTAGRAM_SCENE)
	pentagram.global_position = pos
	pentagram.launch()
	_room_summoned_enemies[room] = summoned + 1
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
	if enemy.is_minion:
		_decrement_room_count(_room_summoned_enemies, room)
		_event_director.handle_ambush_enemy_died(self, enemy, room)
	elif enemy.is_patrol_respawn:
		_patrol_manager.on_patrol_enemy_died(room)
	else:
		if not _event_director.handle_ambush_enemy_died(self, enemy, room) and _room_remaining_enemies.has(room):
			_room_remaining_enemies[room] = maxi(0, _room_remaining_enemies[room] - 1)
			if _room_remaining_enemies[room] <= 0:
				if not _event_director.handle_event_room_enemies_cleared(self, room):
					_patrol_manager.schedule_respawn(room)
		_decrement_room_count(_room_spawned_enemies, room)
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
	_enemy_scan_tick = (_enemy_scan_tick + 1) % ENEMY_SCAN_STRIDE

	var i: int = _enemies.size() - 1
	while i >= 0:
		var enemy: Enemy = _enemies[i]
		if enemy.is_dead:
			_enemies.remove_at(i)
			i -= 1
			continue

		var dist_sq: float = enemy.global_position.distance_squared_to(camera_pos)
		if dist_sq > ENEMY_DESPAWN_DIST_SQ and not _event_director.is_active_open_event_room(enemy.home_room):
			_despawn_enemy(enemy)
			i -= 1
			continue

		if dist_sq > ENEMY_ACTIVE_DIST_SQ and enemy.is_sleeping:
			i -= 1
			continue

		enemy.sync_screen_state(camera_pos)
		if enemy.is_sleeping:
			i -= 1
			continue

		if (i % ENEMY_SCAN_STRIDE) == _enemy_scan_tick:
			var best_target: Hero = _get_best_squad_target(enemy)
			if best_target != null:
				enemy.set_target_candidate(best_target)
		i -= 1

	SquadNavigator.update_enemy_separation(Enemy.active_enemies)


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
	_run_tracker.record_companion_death(hero, _map, _characters, _hud)


func _on_player_died() -> void:
	_event_director.on_player_died()
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
	var score: RunScore = _run_tracker.build_game_over_score(_squad, _class_levels, _hud)
	_pause_overlay.open_game_over(_run_tracker.stats, score)


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
				_run_tracker.begin_recruit(candidate)
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
	_run_tracker.complete_rescue(_hud)


func _on_hero_enemy_hit(enemy: Enemy, damage: float, is_heavy: bool, hero: Hero) -> void:
	Codex.discover(Codex.Category.ENEMIES, enemy.enemy_id)
	if damage > 0.0:
		_hud.record_damage(hero.hero_data.id, damage)
		Audio.play_sfx(Audio.Sfx.HEAVY_IMPACT if is_heavy else Audio.Sfx.HIT_IMPACT)
	_reset_combat_cooldown()
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
	return 50.0 + float(lvl - 1) * 38.0 + float((lvl - 1) * (lvl - 1)) * 5.5


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


func _rebalance_escort_slots() -> void:
	SquadMember.rebalance_slots(_squad)


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
			var hero_spike_dmg: float = _check_character_spike(member)
			if hero_spike_dmg > 0.0:
				_run_tracker.record_trap_damage(hero_spike_dmg)

	for enemy: Enemy in _enemies:
		if not enemy.is_dead and enemy.visible and enemy.is_physics_processing():
			var damage: float = _check_character_spike(enemy, true)
			if damage > 0.0:
				_hud.record_damage(&"spike", damage)


func _check_character_spike(character: Character, is_enemy: bool = false) -> float:
	if not is_enemy and Hero.god_mode:
		return 0.0
	if _spike_hit_cooldowns.has(character):
		return 0.0
	var foot_cell: Vector2i = _map.local_to_map(character.get_hurtbox_position())
	if not _map.is_spike_active_at(foot_cell):
		return 0.0
	var is_blood: bool = _map.plan.event_spike_cell_rooms.has(foot_cell)
	if is_enemy and (is_blood or (character as Enemy).is_damage_immune):
		return 0.0
	Audio.play_sfx(Audio.Sfx.SPIKE_TRAP)
	_spike_hit_cooldowns[character] = BLOOD_SPIKE_HIT_COOLDOWN if is_blood else SPIKE_HIT_COOLDOWN
	var ratio: float = BLOOD_SPIKE_DAMAGE_MAX_HP_RATIO if is_blood else SPIKE_DAMAGE_MAX_HP_RATIO
	var damage: float = maxf(1.0, roundf(character.max_health * ratio))
	character.take_damage(damage)
	return damage


func _on_window_resized() -> void:
	# Workaround for Godot 4 Camera2D not re-centering after the window resizes.
	_camera.enabled = false
	_camera.enabled = true
	_camera.force_update_scroll()

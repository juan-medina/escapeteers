# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name PotionManager
extends RefCounted

const POTION_SCENE: PackedScene = preload("res://potion/potion_pickup.tscn")
const COIN_SCENE: PackedScene = preload("res://coin/coin.tscn")
const MAX_HEAL_VFX_PER_TICK: int = 6

var _characters: Node2D = null
var _projectiles: Node2D = null
var _hud: Hud = null
var _heal_effect_scene: PackedScene = null
var _potions: Array[PotionPickup] = []
var _haste_timer: float = 0.0
var _fury_timer: float = 0.0
var _haste_active: bool = false
var _fury_active: bool = false
var _heal_ticks_left: int = 0
var _heal_tick_timer: float = 0.0
var _xp_ticks_left: int = 0
var _xp_tick_timer: float = 0.0
var _xp_pending: float = 0.0


func setup(characters: Node2D, projectiles: Node2D, hud: Hud, heal_effect_scene: PackedScene) -> void:
	_characters = characters
	_projectiles = projectiles
	_hud = hud
	_heal_effect_scene = heal_effect_scene


func spawn_at(pos: Vector2, potion_type: PotionPickup.PotionType) -> PotionPickup:
	var potion: PotionPickup = POTION_SCENE.instantiate() as PotionPickup
	_characters.add_child(potion)
	potion.position = pos
	potion.setup(potion_type)
	_potions.append(potion)
	return potion


func spawn_list(spawns: Array[Dictionary]) -> void:
	for item: Dictionary in spawns:
		var pos: Vector2 = item[&"pos"]
		var potion_type: PotionPickup.PotionType = item[&"type"]
		spawn_at(pos, potion_type)


func spawn_pickups(pickups: Dictionary, coins: Array[Coin]) -> void:
	var coin_positions: Array[Vector2] = pickups[&"coins"]
	for pos: Vector2 in coin_positions:
		_spawn_coin_at(pos, coins)
	var potion_spawns: Array[Dictionary] = pickups[&"potions"]
	spawn_list(potion_spawns)


func spawn_cell_pickups(coin_cells: Array[Vector2i], potion_spawns: Array[Dictionary], map: Map, coins: Array[Coin]) -> void:
	for cell: Vector2i in coin_cells:
		_spawn_coin_at(map.map_to_local(cell), coins)
	for item: Dictionary in potion_spawns:
		var cell: Vector2i = item[&"cell"]
		var potion_type: PotionPickup.PotionType = item[&"type"]
		spawn_at(map.map_to_local(cell), potion_type)


func _spawn_coin_at(pos: Vector2, coins: Array[Coin]) -> void:
	var coin: Coin = COIN_SCENE.instantiate() as Coin
	_characters.add_child(coin)
	coin.position = pos
	coins.append(coin)


func on_shortcut_opened(color: WorldPlan.KeyColor, map: Map, coins: Array[Coin]) -> void:
	_hud.notify_shortcut_opened(color)
	for gate: SectorGatePlanner.SectorGate in map.plan.sector_gates:
		if gate.color == color and gate.has_shortcut:
			spawn_cell_pickups(gate.shortcut_coin_cells, gate.shortcut_potion_spawns, map, coins)
			if gate.key_room == gate.shortcut_target_room or gate.shortcut_wall_cells.size() < 2:
				return
			var pos_a: Vector2 = map.map_to_local(gate.shortcut_wall_cells[0] + Vector2i(0, -2))
			var pos_b: Vector2 = map.map_to_local(gate.shortcut_wall_cells[1] + Vector2i(0, -2))
			spawn_at((pos_a + pos_b) * 0.5, PotionPickup.PotionType.HASTE)
			return


func check_pickups(squad: Array[Hero], leader: Hero, xp_required: float) -> void:
	var i: int = _potions.size() - 1
	while i >= 0:
		var potion: PotionPickup = _potions[i]
		if is_squad_touching(squad, potion.position, PotionPickup.PICKUP_DISTANCE):
			var potion_type: PotionPickup.PotionType = potion.potion_type
			_potions.remove_at(i)
			potion.queue_free()
			_apply_effect(potion_type, squad, leader, xp_required)
		i -= 1


func update_buffs(delta: float, squad: Array[Hero], leader: Hero) -> float:
	if leader.is_dead:
		return 0.0
	if _haste_timer <= 0.0 and _fury_timer <= 0.0 and not _haste_active and not _fury_active and _heal_ticks_left <= 0 and _xp_ticks_left <= 0:
		return 0.0

	_haste_timer = maxf(0.0, _haste_timer - delta)
	_fury_timer = maxf(0.0, _fury_timer - delta)
	var haste_now: bool = _haste_timer > 0.0
	var fury_now: bool = _fury_timer > 0.0
	if haste_now != _haste_active or fury_now != _fury_active:
		_sync_squad_buffs(squad)

	if _heal_ticks_left > 0:
		_heal_tick_timer -= delta
		if _heal_tick_timer <= 0.0:
			_apply_heal_tick(squad)

	var xp_gained: float = 0.0
	if _xp_ticks_left > 0:
		_xp_tick_timer -= delta
		if _xp_tick_timer <= 0.0:
			var chunk: float = _xp_pending if _xp_ticks_left == 1 else roundf(_xp_pending / float(_xp_ticks_left))
			_xp_pending = maxf(0.0, _xp_pending - chunk)
			_xp_ticks_left -= 1
			if _xp_ticks_left > 0:
				_xp_tick_timer = PotionPickup.XP_TICK_INTERVAL
			if _xp_ticks_left == 2 or _xp_ticks_left == 0:
				leader.play_level_up_vfx()
			Audio.play_sfx(Audio.Sfx.POTION_XP)
			xp_gained = chunk

	_hud.update_potion_buffs(_haste_timer, _fury_timer, _heal_ticks_left > 0, _xp_ticks_left > 0)
	return xp_gained


func apply_buffs_to_hero(hero: Hero) -> void:
	hero.attack_speed_multiplier = PotionPickup.HASTE_ATTACK_SPEED_MULTIPLIER if _haste_timer > 0.0 else 1.0
	hero.damage_multiplier = PotionPickup.FURY_DAMAGE_MULTIPLIER if _fury_timer > 0.0 else 1.0


func get_speed_multiplier() -> float:
	return PotionPickup.HASTE_SPEED_MULTIPLIER if _haste_timer > 0.0 else 1.0


static func is_squad_touching(squad: Array[Hero], pos: Vector2, dist: float) -> bool:
	var dist_sq: float = dist * dist
	for member: Hero in squad:
		if not member.is_dead and pos.distance_squared_to(member.position) <= dist_sq:
			return true
	return false


func _apply_effect(potion_type: PotionPickup.PotionType, squad: Array[Hero], leader: Hero, xp_required: float) -> void:
	Codex.discover_item(PotionPickup.get_codex_id(potion_type))
	_hud.show_event_toast(PotionPickup.get_toast_text(potion_type), PotionPickup.get_display_color(potion_type))
	match potion_type:
		PotionPickup.PotionType.HEALTH:
			_heal_ticks_left = PotionPickup.HEALTH_TICK_COUNT
			_heal_tick_timer = 0.0
			_apply_heal_tick(squad, false)
			Audio.play_sfx(Audio.Sfx.POTION_HEALTH)
		PotionPickup.PotionType.HASTE:
			_haste_timer = PotionPickup.HASTE_DURATION
			_sync_squad_buffs(squad)
			Audio.play_sfx(Audio.Sfx.POTION_HASTE)
		PotionPickup.PotionType.FURY:
			_fury_timer = PotionPickup.FURY_DURATION
			_sync_squad_buffs(squad)
			Audio.play_sfx(Audio.Sfx.POTION_FURY)
		PotionPickup.PotionType.XP:
			_xp_pending += roundf(xp_required * PotionPickup.XP_LEVEL_RATIO)
			_xp_ticks_left = PotionPickup.XP_TICK_COUNT
			_xp_tick_timer = PotionPickup.XP_START_DELAY
			leader.play_level_up_vfx()
			Audio.play_sfx(Audio.Sfx.POTION_XP)
	_hud.update_potion_buffs(_haste_timer, _fury_timer, _heal_ticks_left > 0, _xp_ticks_left > 0)


func _apply_heal_tick(squad: Array[Hero], play_sfx: bool = true) -> void:
	_heal_ticks_left -= 1
	if _heal_ticks_left > 0:
		_heal_tick_timer = PotionPickup.HEALTH_TICK_INTERVAL

	var vfx_targets: Array[Hero] = []
	for member: Hero in squad:
		if member.is_dead:
			continue
		var was_injured: bool = member.health < member.max_health
		member.heal(roundf(member.max_health * PotionPickup.HEALTH_TICK_RATIO))
		if was_injured and vfx_targets.size() < MAX_HEAL_VFX_PER_TICK:
			vfx_targets.append(member)

	for member: Hero in squad:
		if vfx_targets.size() >= MAX_HEAL_VFX_PER_TICK:
			break
		if not member.is_dead and not vfx_targets.has(member):
			vfx_targets.append(member)

	for member: Hero in vfx_targets:
		var effect: Projectile = Projectile.acquire(_heal_effect_scene)
		effect.global_position = member.global_position
		if effect.get_parent() == null:
			_projectiles.add_child(effect)
		effect.launch()

	if play_sfx:
		Audio.play_sfx(Audio.Sfx.HEAL)


func _sync_squad_buffs(squad: Array[Hero]) -> void:
	_haste_active = _haste_timer > 0.0
	_fury_active = _fury_timer > 0.0
	var atk_mult: float = PotionPickup.HASTE_ATTACK_SPEED_MULTIPLIER if _haste_active else 1.0
	var dmg_mult: float = PotionPickup.FURY_DAMAGE_MULTIPLIER if _fury_active else 1.0
	for member: Hero in squad:
		if not member.is_dead:
			member.attack_speed_multiplier = atk_mult
			member.damage_multiplier = dmg_mult

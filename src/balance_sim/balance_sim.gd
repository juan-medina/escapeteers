# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

## Headless battle / progression simulator used to tune difficulty. It reads the real data (heroes.json, enemies.json) and the real dungeon
## generator (WorldPlan: room depth, archetype, enemy quota, recruit count) and plays whole runs without any rendering.
##
## Run from the repo root:
##   godot --headless --path src -s res://balance_sim/balance_sim.gd -- --seeds=30
##
## Every option below can be overridden as `--name=value` (see DEFAULTS). Useful ones for tuning:
##   --scaling=game|proposed     "game" = CharacterData.eval_stat as shipped (linear), "proposed" = roadmap Priority 1 formulas
##   --hero_growth=0.10          override growth of hero health/damage/heal (blank = use heroes.json)
##   --enemy_growth=0.12         override growth of enemy health/damage      (blank = use enemies.json)
##   --enemy_count_mult=1.5      scale the room enemy quota
##   --enemy_level_per_depth=1.5 enemy level gained per dungeon depth (game: 1.0, capped by --enemy_level_cap)
##
## Not modelled: movement/pathing, line of sight, frost slow, spikes. Knockback and stun are approximated as lost enemy time. Combat is
## abstracted into a time-stepped exchange, so absolute numbers are only as good as the calibration knobs (uptime, shield, contact, pull).
## Use it to compare *changes* and *curves*, then calibrate the knobs against a few real playtests.
# gdlint: disable=max-file-lines
extends SceneTree

const HEROES_PATH: String = "res://character/heroes/heroes.json"
const ENEMIES_PATH: String = "res://character/enemies/enemies.json"

## Mirrors of gameplay constants that live in scenes/scripts we cannot load headlessly.
const MAX_SQUAD: int = 80
const MAX_ROOM_ENEMIES: int = 160
const HEAL_THRESHOLD: float = 0.8
const NECRO_ARCHER_MINION_CHANCE: float = 0.30
const KNOCKBACK_DECAY: float = 600.0

const WIN_RATE_REQUIRED: float = 0.9
const HP_LOSS_ALLOWED: float = 0.5

const KITER_IDS: Array[StringName] = [&"skeleton_archer", &"necromancer"]
const SWEEP_SIZES: Array[int] = [1, 2, 3, 4, 6, 8, 10, 12, 16, 20]
const SWEEP_COMPOSITION: Array[StringName] = [
	&"armored_axeman",
	&"priest",
	&"archer",
	&"knight",
	&"knight_templar",
	&"swordsman",
	&"wizard",
	&"soldier",
]
const SWEEP_PLAN_SEEDS: int = 8

const DEFAULTS: Dictionary[StringName, String] = {
	&"sections": "all",
	&"seeds": "30",
	&"max_depth": "12",
	&"scaling": "game",
	&"leader": "knight",
	&"recruit_policy": "smart",
	&"levelup_policy": "by_count",
	&"explore": "0.5",
	&"dt": "0.1",
	&"hero_uptime": "0.75",
	&"enemy_uptime": "0.85",
	&"shield": "0.6",
	&"contact_base": "4",
	&"contact_per_front": "3",
	&"pull_base": "4",
	&"pull_per_sqrt_enemy": "2.5",
	&"summon_delay": "1.5",
	&"kiter_melee_eff": "0.5",
	&"room_timeout": "240",
	&"rest_seconds": "15",
	&"hero_growth": "",
	&"enemy_growth": "",
	&"enemy_xp_growth": "",
	&"enemy_count_mult": "1.0",
	&"enemy_hp_mult": "1.0",
	&"enemy_dmg_mult": "1.0",
	&"enemy_level_per_depth": "1.0",
	&"enemy_level_cap": "12",
	&"sweep_trials": "40",
	&"sweep_level_per_depth": "0.5",
}

var _args: Dictionary[StringName, String] = {}
var _heroes: Dictionary = {}
var _enemies: Dictionary = {}
var _hero_ids: Array[StringName] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _proposed_scaling: bool = false
var _dt: float = 0.1
var _hero_uptime: float = 0.75
var _enemy_uptime: float = 0.85
var _shield: float = 0.6
var _contact_base: int = 4
var _contact_per_front: int = 3
var _pull_base: float = 4.0
var _pull_per_sqrt_enemy: float = 2.5
var _summon_delay: float = 1.5
var _kiter_melee_eff: float = 0.5
var _room_timeout: float = 240.0
var _rest_seconds: float = 15.0
var _hero_growth: float = NAN
var _enemy_growth: float = NAN
var _enemy_xp_growth: float = NAN
var _enemy_count_mult: float = 1.0
var _enemy_hp_mult: float = 1.0
var _enemy_dmg_mult: float = 1.0
var _enemy_level_per_depth: float = 1.0
var _enemy_level_cap: int = 12
var _max_depth: int = 12
var _explore: float = 0.5
var _seeds: int = 30

# Per-fight scratch state.
var _run: Run = null
var _cur_enemies: Array[Unit] = []
var _now: float = 0.0
var _damage_taken: float = 0.0
var _swing_attack: Attack = null

# Per-depth aggregates of the progression runs (index = depth).
var _ag_entered: Array[int] = []
var _ag_fights: Array[int] = []
var _ag_wins: Array[int] = []
var _ag_hp_lost: Array[float] = []
var _ag_time: Array[float] = []
var _ag_deaths: Array[int] = []
var _ag_enemies: Array[int] = []
var _ag_enemy_hp: Array[float] = []
var _ag_squad_dps: Array[float] = []
var _ag_size: Array[float] = []
var _ag_class_level: Array[float] = []
var _ag_squad_level: Array[float] = []
var _ag_died_at: Array[int] = []
var _runs_completed: int = 0

# Room samples for the fixed-squad sweep: depth -> Array[Vector2i(archetype, quota)].
var _sweep_rooms: Dictionary[int, Array] = {}
var _sweep_win_rate: Dictionary[Vector2i, float] = {}
var _sweep_hp_loss: Dictionary[Vector2i, float] = {}


class Attack:
	extends RefCounted
	var damage: float = 0.0
	var hits: int = 1
	var cooldown: float = 1.0
	var chance: float = 0.35
	var knockback: float = 0.0
	var stun: float = 0.0
	var timer: float = 0.0


class Unit:
	extends RefCounted
	var id: StringName = &""
	var is_hero: bool = false
	var level: int = 1
	var max_hp: float = 1.0
	var hp: float = 1.0
	var alive: bool = true
	var backline: bool = false
	var kiter: bool = false
	var dives: bool = false
	var xp: float = 0.0
	var arrival: float = 0.0
	var speed: float = 40.0
	var detect: float = 150.0
	var attack_range: float = 20.0
	var fast_done: int = 0
	var stagger: float = 0.0
	var stun: float = 0.0
	var summon_count: int = 0
	var summon_cooldown: float = 0.0
	var summon_timer: float = 0.0
	var melee: Attack = null
	var heavy: Attack = null
	var ranged: Attack = null
	var heal: Attack = null


class Run:
	extends RefCounted
	var squad: Array[Unit] = []
	var leader: Unit = null
	var class_levels: Dictionary[StringName, int] = {}
	var squad_level: int = 1
	var xp: float = 0.0
	var xp_required: float = 50.0
	var progression: bool = true
	var recruit_rolls: int = 0
	var healer_offered: bool = false


class FightResult:
	extends RefCounted
	var won: bool = false
	var stalled: bool = false
	var time: float = 0.0
	var hp_lost: float = 0.0
	var deaths: int = 0
	var enemies: int = 0
	var enemy_hp: float = 0.0
	var squad_dps: float = 0.0


func _init() -> void:
	if not _load_config():
		quit(1)
		return
	_heroes = _load_json(HEROES_PATH)
	_enemies = _load_json(ENEMIES_PATH)
	for key: Variant in _heroes.keys():
		var entry: Dictionary = _heroes[key]
		if entry.get("secret", false) != true:
			_hero_ids.append(StringName(str(key)))

	_print_header()
	var sections: String = _args[&"sections"]
	if sections == "all" or sections == "run":
		_run_progression()
	if sections == "all" or sections == "sweep":
		_run_sweep()
	if sections == "all":
		_print_required_size()
	quit()


func _load_config() -> bool:
	for key: StringName in DEFAULTS:
		_args[key] = DEFAULTS[key]
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var parts: PackedStringArray = arg.substr(2).split("=", true, 1)
		var key: StringName = StringName(parts[0])
		if not DEFAULTS.has(key):
			printerr("Unknown option: %s" % arg)
			return false
		_args[key] = parts[1]

	_proposed_scaling = _args[&"scaling"] == "proposed"
	_dt = _f(&"dt")
	_hero_uptime = _f(&"hero_uptime")
	_enemy_uptime = _f(&"enemy_uptime")
	_shield = _f(&"shield")
	_contact_base = _i(&"contact_base")
	_contact_per_front = _i(&"contact_per_front")
	_pull_base = _f(&"pull_base")
	_pull_per_sqrt_enemy = _f(&"pull_per_sqrt_enemy")
	_summon_delay = _f(&"summon_delay")
	_kiter_melee_eff = _f(&"kiter_melee_eff")
	_room_timeout = _f(&"room_timeout")
	_rest_seconds = _f(&"rest_seconds")
	_hero_growth = _growth_arg(&"hero_growth")
	_enemy_growth = _growth_arg(&"enemy_growth")
	_enemy_xp_growth = _growth_arg(&"enemy_xp_growth")
	_enemy_count_mult = _f(&"enemy_count_mult")
	_enemy_hp_mult = _f(&"enemy_hp_mult")
	_enemy_dmg_mult = _f(&"enemy_dmg_mult")
	_enemy_level_per_depth = _f(&"enemy_level_per_depth")
	_enemy_level_cap = _i(&"enemy_level_cap")
	_max_depth = _i(&"max_depth")
	_explore = _f(&"explore")
	_seeds = _i(&"seeds")
	return true


func _f(key: StringName) -> float:
	return _args[key].to_float()


func _i(key: StringName) -> int:
	return _args[key].to_int()


func _growth_arg(key: StringName) -> float:
	var raw: String = _args[key]
	if raw.is_empty():
		return NAN
	return raw.to_float()


func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var result: Dictionary = parsed
	return result


# ---------------------------------------------------------------------------------------------------------------------
# Stat evaluation and unit construction
# ---------------------------------------------------------------------------------------------------------------------


## Mirrors CharacterData.eval_stat. `growth_override` (NAN = none) lets us tune growth without touching the json files.
static func _float_val(dict: Dictionary, key: Variant, default_val: float = 0.0) -> float:
	var val: Variant = dict.get(key)
	if val is float:
		return val
	if val is int:
		var i: int = val
		return float(i)
	return default_val


static func _int_val(dict: Dictionary, key: Variant, default_val: int = 0) -> int:
	var val: Variant = dict.get(key)
	if val is int:
		return val
	if val is float:
		var f: float = val
		return int(f)
	return default_val


func _eval(stat: Variant, level: int, default_base: float, growth_override: float) -> float:
	if stat is Dictionary:
		var d: Dictionary = stat
		var base: float = _float_val(d, "base", default_base)
		var growth: float = _float_val(d, "growth", 0.0)
		if not is_nan(growth_override):
			growth = growth_override
		if _args[&"scaling"] == "linear":
			return _eval_linear(base, growth, level)
		return _eval_proposed(base, growth, level)
	if stat is float:
		return stat
	if stat is int:
		var i: int = stat
		return float(i)
	return default_base


## Legacy linear formula, also used by EnemyData.get_xp.
static func _eval_linear(base: float, growth: float, level: int) -> float:
	return base * (1.0 + float(maxi(1, level) - 1) * growth)


## Roadmap Priority 1: attack-speed divisor for cooldowns, soft compound growth for everything else.
static func _eval_proposed(base: float, growth: float, level: int) -> float:
	var steps: float = float(maxi(1, level) - 1)
	if growth < 0.0:
		return base / (1.0 + steps * absf(growth))
	if growth > 0.0:
		return base * pow(1.0 + growth, steps)
	return base


func _fill_attack(attack: Attack, skill: Dictionary, level: int, damage_key: String, growth: float, damage_mult: float, uptime: float) -> void:
	attack.damage = _eval(skill.get(damage_key), level, 10.0, growth) * damage_mult
	attack.hits = _int_val(skill, "hits", 1)
	attack.cooldown = _eval(skill.get("cooldown"), level, 1.0, NAN) / uptime
	attack.chance = _float_val(skill, "chance", 0.35)
	attack.knockback = _eval(skill.get("knockback"), level, 0.0, NAN)
	attack.stun = _eval(skill.get("stun_duration"), level, 0.0, NAN)


func _new_attack(skill: Dictionary, level: int, damage_key: String, growth: float, damage_mult: float, uptime: float) -> Attack:
	var attack: Attack = Attack.new()
	_fill_attack(attack, skill, level, damage_key, growth, damage_mult, uptime)
	attack.timer = _rng.randf() * attack.cooldown
	return attack


func _apply_skills(unit: Unit, skills: Array, level: int, growth: float, damage_mult: float, uptime: float) -> void:
	var melee_idx: int = 0
	for item: Variant in skills:
		var skill: Dictionary = item
		var type: String = skill["type"]
		if type == "melee":
			if melee_idx == 0:
				if unit.melee == null:
					unit.melee = _new_attack(skill, level, "damage", growth, damage_mult, uptime)
				else:
					_fill_attack(unit.melee, skill, level, "damage", growth, damage_mult, uptime)
			else:
				if unit.heavy == null:
					unit.heavy = _new_attack(skill, level, "damage", growth, damage_mult, uptime)
				else:
					_fill_attack(unit.heavy, skill, level, "damage", growth, damage_mult, uptime)
			melee_idx += 1
		elif type == "ranged":
			unit.attack_range = float(_eval(skill.get("range"), level, 140.0, NAN))
			if unit.ranged == null:
				unit.ranged = _new_attack(skill, level, "damage", growth, damage_mult, uptime)
			else:
				_fill_attack(unit.ranged, skill, level, "damage", growth, damage_mult, uptime)
		elif type == "heal":
			if unit.heal == null:
				unit.heal = _new_attack(skill, level, "heal_amount", growth, 1.0, 1.0)
			else:
				_fill_attack(unit.heal, skill, level, "heal_amount", growth, 1.0, 1.0)
		elif type == "summon":
			unit.summon_count = _int_val(skill, "summon_count", 2)
			unit.summon_cooldown = _eval(skill.get("cooldown"), level, 4.5, NAN) / uptime
			if unit.summon_timer <= 0.0:
				unit.summon_timer = _rng.randf() * unit.summon_cooldown


func _apply_hero_stats(unit: Unit, level: int) -> void:
	var data: Dictionary = _heroes[unit.id]
	unit.level = level
	unit.max_hp = _eval(data.get("health"), level, 100.0, _hero_growth)
	unit.hp = unit.max_hp
	var skills: Array = data["skills"]
	_apply_skills(unit, skills, level, _hero_growth, 1.0, _hero_uptime)


func _build_hero(id: StringName, level: int) -> Unit:
	var unit: Unit = Unit.new()
	unit.id = id
	unit.is_hero = true
	_apply_hero_stats(unit, level)
	unit.backline = unit.heal != null or (unit.ranged != null and unit.melee == null)
	return unit


func _build_enemy(id: StringName, level: int) -> Unit:
	var data: Dictionary = _enemies[id]
	var unit: Unit = Unit.new()
	unit.id = id
	unit.level = level
	unit.max_hp = _eval(data.get("health"), level, 100.0, _enemy_growth) * _enemy_hp_mult
	unit.hp = unit.max_hp
	var xp_dict: Dictionary = data.get("xp", {})
	var xp_base: float = _float_val(xp_dict, "base", 10.0)
	var xp_growth: float = _float_val(xp_dict, "growth", 0.0)
	if not is_nan(_enemy_xp_growth):
		xp_growth = _enemy_xp_growth
	unit.xp = _eval_linear(xp_base, xp_growth, level)
	unit.speed = _eval(data.get("speed"), level, 40.0, NAN)
	unit.detect = _eval(data.get("detection_range"), level, 150.0, NAN)
	unit.kiter = KITER_IDS.has(id)
	unit.dives = id == &"skeleton"
	var skills: Array = data["skills"]
	_apply_skills(unit, skills, level, _enemy_growth, _enemy_dmg_mult, _enemy_uptime)
	if unit.melee != null:
		unit.attack_range = 22.0
	return unit


func _unit_dps(unit: Unit) -> float:
	var melee_dps: float = 0.0
	var ranged_dps: float = 0.0
	if unit.melee != null:
		melee_dps = unit.melee.damage * float(unit.melee.hits) / unit.melee.cooldown
	if unit.ranged != null:
		ranged_dps = unit.ranged.damage * float(unit.ranged.hits) / unit.ranged.cooldown
	var dps: float = maxf(melee_dps, ranged_dps)
	if unit.heal != null:
		dps += 0.5 * unit.heal.damage / unit.heal.cooldown
	return dps


func _squad_dps(squad: Array[Unit]) -> float:
	var total: float = 0.0
	for unit: Unit in squad:
		if unit.alive:
			total += _unit_dps(unit)
	return total


# ---------------------------------------------------------------------------------------------------------------------
# Rooms
# ---------------------------------------------------------------------------------------------------------------------


## Mirrors Game._pick_enemy_scene_for_room.
func _pick_enemy_id(archetype: int, depth: int, necros_spawned: int) -> StringName:
	if archetype == WorldPlan.RoomArchetype.BONE_SWARM:
		return &"skeleton"
	if archetype == WorldPlan.RoomArchetype.ARCHER_GARRISON:
		return &"skeleton_archer" if _rng.randf() < 0.65 else &"skeleton"
	if archetype == WorldPlan.RoomArchetype.NECRO_CRYPT:
		var max_necros: int = 1 if depth <= 4 else 2
		if necros_spawned < max_necros:
			return &"necromancer"
		return &"skeleton_archer" if _rng.randf() < 0.35 else &"skeleton"
	return &"lava_slime"


func _enemy_level_for_depth(depth: int) -> int:
	return clampi(roundi(1.0 + float(depth - 1) * _enemy_level_per_depth), 1, _enemy_level_cap)


func _spawn_room(archetype: int, depth: int, quota: int) -> Array[Unit]:
	var level: int = _enemy_level_for_depth(depth)
	var count: int = maxi(1, roundi(float(quota) * _enemy_count_mult))
	# Enemies notice the squad one group at a time, so the pull window grows slower than linearly with the quota.
	var spread: float = _pull_base + _pull_per_sqrt_enemy * sqrt(float(count))
	var necros: int = 0
	var result: Array[Unit] = []
	for _i_enemy: int in range(count):
		var id: StringName = _pick_enemy_id(archetype, depth, necros)
		if id == &"necromancer":
			necros += 1
		var enemy: Unit = _build_enemy(id, level)
		var distance: float = enemy.detect * _rng.randf_range(0.4, 1.0)
		var approach: float = maxf(0.0, distance - enemy.attack_range) / maxf(1.0, enemy.speed)
		enemy.arrival = approach + _rng.randf() * spread
		result.append(enemy)
	return result


# ---------------------------------------------------------------------------------------------------------------------
# Combat
# ---------------------------------------------------------------------------------------------------------------------


func _fight(run: Run, enemies: Array[Unit]) -> FightResult:
	_run = run
	_cur_enemies = enemies
	_now = 0.0
	_damage_taken = 0.0
	var result: FightResult = FightResult.new()
	var squad: Array[Unit] = run.squad
	var start_max_hp: float = 0.0
	var start_alive: int = 0
	for unit: Unit in squad:
		if unit.alive:
			start_max_hp += unit.max_hp
			start_alive += 1
	result.squad_dps = _squad_dps(squad)
	result.enemies = enemies.size()
	for enemy: Unit in enemies:
		result.enemy_hp += enemy.hp

	while _now < _room_timeout and run.leader.alive:
		var allies: Array[Unit] = []
		var front: Array[Unit] = []
		var back: Array[Unit] = []
		for unit: Unit in squad:
			if unit.alive:
				allies.append(unit)
				if unit.backline:
					back.append(unit)
				else:
					front.append(unit)

		var engaged: Array[Unit] = []
		var ground: Array[Unit] = []
		var kiters: Array[Unit] = []
		var any_alive: bool = false
		for enemy: Unit in _cur_enemies:
			if not enemy.alive:
				continue
			any_alive = true
			if enemy.arrival <= _now:
				engaged.append(enemy)
				if enemy.kiter:
					kiters.append(enemy)
				else:
					ground.append(enemy)
		if not any_alive:
			result.won = true
			break

		for hero: Unit in allies:
			_tick(hero)
			_hero_act(hero, ground, kiters, engaged, allies)

		var slots_left: int = _contact_base + _contact_per_front * front.size()
		for enemy: Unit in engaged:
			if not enemy.alive:
				continue
			_tick(enemy)
			slots_left = _enemy_act(enemy, slots_left, front, back, allies)
		_now += _dt

	var alive_after: int = 0
	for unit: Unit in squad:
		if unit.alive:
			alive_after += 1
	result.time = _now
	result.stalled = not result.won and run.leader.alive
	result.hp_lost = _damage_taken / maxf(start_max_hp, 1.0)
	result.deaths = start_alive - alive_after
	result.won = result.won and run.leader.alive
	return result


func _tick(unit: Unit) -> void:
	if unit.melee != null:
		unit.melee.timer -= _dt
	if unit.heavy != null:
		unit.heavy.timer -= _dt
	if unit.ranged != null:
		unit.ranged.timer -= _dt
	if unit.heal != null:
		unit.heal.timer -= _dt
	if unit.summon_count > 0:
		unit.summon_timer -= _dt
	unit.stagger -= _dt
	unit.stun -= _dt


func _pick_alive(list: Array[Unit]) -> Unit:
	if list.is_empty():
		return null
	for _attempt: int in range(4):
		var candidate: Unit = list[_rng.randi() % list.size()]
		if candidate.alive:
			return candidate
	for unit: Unit in list:
		if unit.alive:
			return unit
	return null


func _lowest_hp_ally(list: Array[Unit]) -> Unit:
	var best: Unit = null
	var best_ratio: float = 2.0
	for unit: Unit in list:
		if not unit.alive:
			continue
		var ratio: float = unit.hp / unit.max_hp
		if ratio < best_ratio:
			best_ratio = ratio
			best = unit
	return best


## Resolves one melee swing (light or heavy) and remembers which attack fired so the caller can apply its knockback/stun.
func _melee_swing(attacker: Unit) -> float:
	var melee: Attack = attacker.melee
	_swing_attack = melee
	var damage: float = melee.damage * float(melee.hits)
	var heavy: Attack = attacker.heavy
	if heavy != null and heavy.timer <= 0.0 and attacker.fast_done >= 2 and _rng.randf() < heavy.chance:
		damage = heavy.damage * float(heavy.hits)
		heavy.timer = heavy.cooldown
		attacker.fast_done = 0
		_swing_attack = heavy
	else:
		attacker.fast_done += 1
	melee.timer = melee.cooldown
	return damage


func _hero_act(hero: Unit, ground: Array[Unit], kiters: Array[Unit], engaged: Array[Unit], allies: Array[Unit]) -> void:
	if hero.heal != null and hero.heal.timer <= 0.0:
		var patient: Unit = _lowest_hp_ally(allies)
		if patient != null and patient.hp / patient.max_hp < HEAL_THRESHOLD:
			patient.hp = minf(patient.max_hp, patient.hp + hero.heal.damage)
			hero.heal.timer = hero.heal.cooldown

	var use_melee: bool = hero.melee != null and (hero.ranged == null or not ground.is_empty())
	if use_melee:
		if hero.melee.timer > 0.0:
			return
		var target: Unit = _pick_alive(ground)
		var efficiency: float = 1.0
		if target == null:
			target = _pick_alive(kiters)
			efficiency = _kiter_melee_eff
		if target != null:
			var swing_damage: float = _melee_swing(hero) * efficiency
			_damage_enemy(target, swing_damage, _swing_attack)
	elif hero.ranged != null and hero.ranged.timer <= 0.0:
		var shot_target: Unit = _pick_alive(engaged)
		if shot_target != null:
			hero.ranged.timer = hero.ranged.cooldown
			_damage_enemy(shot_target, hero.ranged.damage * float(hero.ranged.hits), hero.ranged)


func _enemy_act(enemy: Unit, slots_left: int, front: Array[Unit], back: Array[Unit], allies: Array[Unit]) -> int:
	if enemy.stun > 0.0:
		return slots_left

	if enemy.summon_count > 0:
		if enemy.summon_timer <= 0.0:
			_summon_minions(enemy)
			enemy.summon_timer = enemy.summon_cooldown
		return slots_left

	if enemy.melee != null:
		if enemy.stagger > 0.0:
			return slots_left
		if slots_left > 0:
			if enemy.melee.timer <= 0.0:
				var target: Unit = _pick_enemy_target(enemy, front, back, allies)
				if target != null:
					_damage_hero(target, _melee_swing(enemy))
			return slots_left - 1
		if enemy.ranged != null and enemy.ranged.timer <= 0.0:
			var ranged_target: Unit = _pick_alive(allies)
			if ranged_target != null:
				enemy.ranged.timer = enemy.ranged.cooldown
				_damage_hero(ranged_target, enemy.ranged.damage)
		return slots_left

	if enemy.ranged != null and enemy.ranged.timer <= 0.0:
		var archer_target: Unit = _pick_alive(allies)
		if archer_target != null:
			enemy.ranged.timer = enemy.ranged.cooldown
			_damage_hero(archer_target, enemy.ranged.damage)
	return slots_left


func _pick_enemy_target(enemy: Unit, front: Array[Unit], back: Array[Unit], allies: Array[Unit]) -> Unit:
	if not front.is_empty() and _rng.randf() < _shield:
		var guard: Unit = _pick_alive(front)
		if guard != null:
			return guard
	if enemy.dives and not back.is_empty():
		var diver_target: Unit = _pick_alive(back)
		if diver_target != null:
			return diver_target
	return _pick_alive(allies)


func _summon_minions(necromancer: Unit) -> void:
	for _i_minion: int in range(necromancer.summon_count):
		if _cur_enemies.size() >= MAX_ROOM_ENEMIES:
			return
		var id: StringName = &"skeleton_archer" if _rng.randf() < NECRO_ARCHER_MINION_CHANCE else &"skeleton"
		var minion: Unit = _build_enemy(id, necromancer.level)
		# Minions are fragile fodder
		minion.max_hp = maxf(15.0, roundf(minion.max_hp * 0.4))
		minion.hp = minion.max_hp
		if minion.melee != null:
			minion.melee.damage = maxf(2.0, roundf(minion.melee.damage * 0.5))
			minion.heavy = null
		if minion.ranged != null:
			minion.ranged.damage = maxf(2.0, roundf(minion.ranged.damage * 0.5))
		minion.arrival = _now + _summon_delay
		_cur_enemies.append(minion)


func _damage_hero(hero: Unit, amount: float) -> void:
	var dealt: float = minf(amount, hero.hp)
	hero.hp -= dealt
	_damage_taken += dealt
	if hero.hp <= 0.0:
		hero.alive = false


## Knockback (Enemy.KNOCKBACK_DECAY = 600 px/s^2) is modelled as time lost: the enemy flies back, then walks the distance again.
## Stun blocks all actions.
func _damage_enemy(enemy: Unit, amount: float, source: Attack) -> void:
	enemy.hp -= amount
	if enemy.hp <= 0.0:
		if enemy.alive:
			enemy.alive = false
			_add_xp(enemy.xp)
		return
	if source.knockback > 0.0:
		var fly_time: float = source.knockback / KNOCKBACK_DECAY
		var fly_distance: float = source.knockback * source.knockback / (2.0 * KNOCKBACK_DECAY)
		enemy.stagger = maxf(enemy.stagger, fly_time + fly_distance / maxf(1.0, enemy.speed))
	if source.stun > 0.0:
		enemy.stun = maxf(enemy.stun, source.stun)


# ---------------------------------------------------------------------------------------------------------------------
# Squad progression (mirrors Game / RecruitPanel / LevelUpPanel)
# ---------------------------------------------------------------------------------------------------------------------


## Mirrors Game._get_xp_required_for_level.
static func _xp_required_for_level(level: int) -> float:
	return 50.0 + float(level - 1) * 40.0 + float((level - 1) * (level - 1)) * 10.0


func _add_xp(amount: float) -> void:
	if not _run.progression:
		return
	_run.xp += amount
	while _run.xp >= _run.xp_required:
		_run.xp -= _run.xp_required
		_run.squad_level += 1
		_run.xp_required = _xp_required_for_level(_run.squad_level)
		_level_up_class()


func _class_counts(run: Run) -> Dictionary[StringName, int]:
	var counts: Dictionary[StringName, int] = {}
	for unit: Unit in run.squad:
		if unit.alive:
			counts[unit.id] = counts.get(unit.id, 0) + 1
	return counts


func _level_up_class() -> void:
	var counts: Dictionary[StringName, int] = _class_counts(_run)
	var owned: Array[StringName] = []
	for id: StringName in counts:
		owned.append(id)
	owned.shuffle()
	var shown: Array[StringName] = []
	for idx: int in range(mini(3, owned.size())):
		shown.append(owned[idx])

	var policy: String = _args[&"levelup_policy"]
	var pick: StringName = shown[0]
	if policy == "by_count":
		for id: StringName in shown:
			if counts[id] > counts[pick]:
				pick = id
	elif policy == "lowest_level":
		for id: StringName in shown:
			if _run.class_levels.get(id, 1) < _run.class_levels.get(pick, 1):
				pick = id

	var new_level: int = _run.class_levels.get(pick, 1) + 1
	_run.class_levels[pick] = new_level
	for unit: Unit in _run.squad:
		if unit.alive and unit.id == pick:
			_apply_hero_stats(unit, new_level)


## Mirrors RecruitPanel.setup_choices (3 uniform cards, early healer protection) plus a simple player policy.
func _recruit(run: Run) -> void:
	if run.squad.size() >= MAX_SQUAD:
		return
	run.recruit_rolls += 1
	var pool: Array[StringName] = _hero_ids.duplicate()
	pool.shuffle()
	var choices: Array[StringName] = []
	for idx: int in range(mini(3, pool.size())):
		choices.append(pool[idx])

	var owns_priest: bool = _class_counts(run).get(&"priest", 0) > 0
	if choices.has(&"priest"):
		run.healer_offered = true
	elif run.recruit_rolls <= 2 and not run.healer_offered and not owns_priest:
		if run.recruit_rolls == 2 or _rng.randf() < 0.5:
			choices[_rng.randi_range(0, choices.size() - 1)] = &"priest"
			run.healer_offered = true

	var pick: StringName = choices[0]
	var policy: String = _args[&"recruit_policy"]
	if policy == "random":
		pick = choices[_rng.randi_range(0, choices.size() - 1)]
	elif policy == "smart":
		pick = _smart_recruit(run, choices, owns_priest)

	var level: int = run.class_levels.get(pick, 1)
	run.class_levels[pick] = level
	run.squad.append(_build_hero(pick, level))


func _smart_recruit(run: Run, choices: Array[StringName], owns_priest: bool) -> StringName:
	if choices.has(&"priest") and not owns_priest:
		return &"priest"
	var front_count: int = 0
	var total: int = 0
	for unit: Unit in run.squad:
		if unit.alive:
			total += 1
			if not unit.backline:
				front_count += 1
	var needs_front: bool = float(front_count) < 0.5 * float(total)
	var best: StringName = choices[0]
	var best_score: float = -1.0
	for id: StringName in choices:
		var probe: Unit = _build_hero(id, _int_val(run.class_levels, id, 1))
		var score: float = sqrt(probe.max_hp * _unit_dps(probe))
		if needs_front and not probe.backline:
			score *= 1.3
		if score > best_score:
			best_score = score
			best = id
	return best


func _new_run() -> Run:
	var run: Run = Run.new()
	var leader_id: StringName = StringName(_args[&"leader"])
	run.class_levels[leader_id] = 1
	run.leader = _build_hero(leader_id, 1)
	run.squad.append(run.leader)
	_run = run
	# The hero room holds two starter recruits.
	_recruit(run)
	_recruit(run)
	return run


## Dead companions are lost for the run; survivors get topped up by priests between rooms.
func _clean_up_and_rest(run: Run) -> void:
	var survivors: Array[Unit] = []
	for unit: Unit in run.squad:
		if unit.alive:
			survivors.append(unit)
	run.squad = survivors

	var pool: float = 0.0
	for unit: Unit in run.squad:
		if unit.heal != null:
			pool += unit.heal.damage * _rest_seconds / unit.heal.cooldown
	while pool > 0.5:
		var patient: Unit = _lowest_hp_ally(run.squad)
		if patient == null or patient.hp >= patient.max_hp - 0.01:
			break
		var amount: float = minf(pool, patient.max_hp - patient.hp)
		patient.hp += amount
		pool -= amount


# ---------------------------------------------------------------------------------------------------------------------
# Section 1: full progression runs
# ---------------------------------------------------------------------------------------------------------------------


func _init_aggregates() -> void:
	var size: int = _max_depth + 2
	_ag_entered.resize(size)
	_ag_fights.resize(size)
	_ag_wins.resize(size)
	_ag_hp_lost.resize(size)
	_ag_time.resize(size)
	_ag_deaths.resize(size)
	_ag_enemies.resize(size)
	_ag_enemy_hp.resize(size)
	_ag_squad_dps.resize(size)
	_ag_size.resize(size)
	_ag_class_level.resize(size)
	_ag_squad_level.resize(size)
	_ag_died_at.resize(size)
	for idx: int in range(size):
		_ag_entered[idx] = 0
		_ag_fights[idx] = 0
		_ag_wins[idx] = 0
		_ag_hp_lost[idx] = 0.0
		_ag_time[idx] = 0.0
		_ag_deaths[idx] = 0
		_ag_enemies[idx] = 0
		_ag_enemy_hp[idx] = 0.0
		_ag_squad_dps[idx] = 0.0
		_ag_size[idx] = 0.0
		_ag_class_level[idx] = 0.0
		_ag_squad_level[idx] = 0.0
		_ag_died_at[idx] = 0


func _run_progression() -> void:
	_init_aggregates()
	for run_idx: int in range(_seeds):
		_simulate_run(run_idx + 1)
	_print_progression()


func _simulate_run(plan_seed: int) -> void:
	seed(plan_seed)
	_rng.seed = plan_seed
	var plan: WorldPlan = WorldPlan.new()
	plan.generate(plan_seed, _max_depth)
	var rooms_by_depth: Dictionary[int, Array] = {}
	for room: Rect2i in plan.rooms:
		var room_depth: int = plan.get_room_depth(room)
		if not rooms_by_depth.has(room_depth):
			rooms_by_depth[room_depth] = []
		var bucket: Array = rooms_by_depth[room_depth]
		bucket.append(room)

	var run: Run = _new_run()
	for depth: int in range(1, _max_depth + 1):
		if not rooms_by_depth.has(depth):
			break
		var rooms: Array = rooms_by_depth[depth]
		rooms.shuffle()
		var visit_count: int = clampi(ceili(float(rooms.size()) * _explore), 1, rooms.size())
		_record_entry(run, depth)
		for visit: int in range(visit_count):
			var room: Rect2i = rooms[visit]
			var enemies: Array[Unit] = _spawn_room(plan.get_room_archetype(room), depth, plan.get_room_enemy_quota(room))
			var result: FightResult = _fight(run, enemies)
			_record_fight(depth, result)
			if not result.won:
				_ag_died_at[depth] += 1
				return
			_clean_up_and_rest(run)
			for _recruit_idx: int in range(plan.get_companion_spawns_for_room(room).size()):
				_recruit(run)
	_runs_completed += 1


func _record_entry(run: Run, depth: int) -> void:
	var alive: int = 0
	var level_sum: float = 0.0
	for unit: Unit in run.squad:
		if unit.alive:
			alive += 1
			level_sum += float(unit.level)
	_ag_entered[depth] += 1
	_ag_size[depth] += float(alive)
	_ag_class_level[depth] += level_sum / float(maxi(1, alive))
	_ag_squad_level[depth] += float(run.squad_level)


func _record_fight(depth: int, result: FightResult) -> void:
	_ag_fights[depth] += 1
	if result.won:
		_ag_wins[depth] += 1
	_ag_hp_lost[depth] += result.hp_lost
	_ag_time[depth] += result.time
	_ag_deaths[depth] += result.deaths
	_ag_enemies[depth] += result.enemies
	_ag_enemy_hp[depth] += result.enemy_hp
	_ag_squad_dps[depth] += result.squad_dps


static func _verdict(hp_lost: float, win_rate: float) -> String:
	if win_rate < 0.6:
		return "DEADLY"
	if hp_lost < 0.15:
		return "trivial"
	if hp_lost < 0.40:
		return "fair"
	if hp_lost < 0.70:
		return "hard"
	return "brutal"


func _print_progression() -> void:
	print("")
	print(
		(
			"## 1. Progression runs (%d dungeons, explore=%.2f, recruit=%s, levelup=%s)"
			% [_seeds, _explore, _args[&"recruit_policy"], _args[&"levelup_policy"]]
		)
	)
	print("")
	print(
		"Averages per depth. `Reach` = runs that got to this depth. `HP lost` = damage taken in a room / squad max HP. `Kill est` = enemy HP / squad DPS."
	)
	print("")
	print(
		"| Depth | Reach | Win | HP lost | Deaths | Time s | Enemies | Enemy HP | Squad DPS | Kill est s | Squad | Class lvl | Squad lvl | Verdict |"
	)
	print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for depth: int in range(1, _max_depth + 1):
		var entered: int = _ag_entered[depth]
		var fights: int = _ag_fights[depth]
		if entered == 0 or fights == 0:
			continue
		var win_rate: float = float(_ag_wins[depth]) / float(fights)
		var hp_lost: float = _ag_hp_lost[depth] / float(fights)
		var squad_dps: float = _ag_squad_dps[depth] / float(fights)
		var enemy_hp: float = _ag_enemy_hp[depth] / float(fights)
		var kill_est: float = enemy_hp / maxf(squad_dps, 0.001)
		print(
			(
				"| %d | %3d%% | %3d%% | %3d%% | %.2f | %.0f | %.0f | %.0f | %.0f | %.0f | %.1f | %.1f | %.1f | %s |"
				% [
					depth,
					roundi(100.0 * float(entered) / float(_seeds)),
					roundi(100.0 * win_rate),
					roundi(100.0 * hp_lost),
					float(_ag_deaths[depth]) / float(fights),
					_ag_time[depth] / float(fights),
					float(_ag_enemies[depth]) / float(fights),
					enemy_hp,
					squad_dps,
					kill_est,
					_ag_size[depth] / float(entered),
					_ag_class_level[depth] / float(entered),
					_ag_squad_level[depth] / float(entered),
					_verdict(hp_lost, win_rate),
				]
			)
		)

	print("")
	print("Where runs end (leader dead):")
	var parts: PackedStringArray = PackedStringArray()
	for depth: int in range(1, _max_depth + 1):
		if _ag_died_at[depth] > 0:
			parts.append("depth %d: %d%%" % [depth, roundi(100.0 * float(_ag_died_at[depth]) / float(_seeds))])
	parts.append("cleared everything: %d%%" % roundi(100.0 * float(_runs_completed) / float(_seeds)))
	print(", ".join(parts))


# ---------------------------------------------------------------------------------------------------------------------
# Section 2: fixed-squad sweep (how big must the squad be for each depth?)
# ---------------------------------------------------------------------------------------------------------------------


func _collect_sweep_rooms() -> void:
	for plan_idx: int in range(SWEEP_PLAN_SEEDS):
		var plan: WorldPlan = WorldPlan.new()
		plan.generate(5000 + plan_idx, _max_depth)
		for room: Rect2i in plan.rooms:
			var depth: int = plan.get_room_depth(room)
			if not _sweep_rooms.has(depth):
				_sweep_rooms[depth] = []
			var bucket: Array = _sweep_rooms[depth]
			bucket.append(Vector2i(plan.get_room_archetype(room), plan.get_room_enemy_quota(room)))


func _make_sweep_run(size: int, level: int) -> Run:
	var run: Run = Run.new()
	run.progression = false
	var leader_id: StringName = StringName(_args[&"leader"])
	run.leader = _build_hero(leader_id, level)
	run.squad.append(run.leader)
	for idx: int in range(size - 1):
		run.squad.append(_build_hero(SWEEP_COMPOSITION[idx % SWEEP_COMPOSITION.size()], level))
	return run


func _run_sweep() -> void:
	_rng.seed = 424242
	seed(424242)
	_collect_sweep_rooms()
	var trials: int = _i(&"sweep_trials")
	var level_per_depth: float = _f(&"sweep_level_per_depth")
	for size: int in SWEEP_SIZES:
		for depth: int in range(1, _max_depth + 1):
			if not _sweep_rooms.has(depth):
				continue
			var samples: Array = _sweep_rooms[depth]
			var level: int = 1 + int(float(depth) * level_per_depth)
			var wins: int = 0
			var hp_lost: float = 0.0
			for _trial: int in range(trials):
				var room: Vector2i = samples[_rng.randi() % samples.size()]
				var result: FightResult = _fight(_make_sweep_run(size, level), _spawn_room(room.x, depth, room.y))
				if result.won:
					wins += 1
				hp_lost += result.hp_lost
			_sweep_win_rate[Vector2i(size, depth)] = float(wins) / float(trials)
			_sweep_hp_loss[Vector2i(size, depth)] = hp_lost / float(trials)
	_print_sweep_matrix("win rate", _sweep_win_rate)
	_print_sweep_matrix("avg HP lost", _sweep_hp_loss)


func _print_sweep_matrix(title: String, values: Dictionary[Vector2i, float]) -> void:
	print("")
	print(
		(
			"## 2. Fixed squad sweep, %s (rows = squad size, columns = room depth; every class at level 1 + depth * %.2f; squad = leader + mixed cycle)"
			% [title, _f(&"sweep_level_per_depth")]
		)
	)
	print("")
	var header: String = "| Squad |"
	var divider: String = "|---|"
	for depth: int in range(1, _max_depth + 1):
		header += " D%d |" % depth
		divider += "---|"
	print(header)
	print(divider)
	for size: int in SWEEP_SIZES:
		var row: String = "| %d |" % size
		for depth: int in range(1, _max_depth + 1):
			var key: Vector2i = Vector2i(size, depth)
			if values.has(key):
				row += " %d%% |" % roundi(100.0 * values[key])
			else:
				row += " - |"
		print(row)


func _print_required_size() -> void:
	print("")
	print(
		(
			"## 3. Squad size needed vs squad size you actually have (needed = smallest sweep size with win >= %d%% and HP lost <= %d%%)"
			% [roundi(100.0 * WIN_RATE_REQUIRED), roundi(100.0 * HP_LOSS_ALLOWED)]
		)
	)
	print("")
	print(
		"`Slack` = have - needed. Large positive = too easy (you can walk in with fewer units). Around 0 = you must gather the whole squad to push on."
	)
	print("")
	print("| Depth | Needed | Have (avg) | Slack |")
	print("|---|---|---|---|")
	for depth: int in range(1, _max_depth + 1):
		var needed: int = -1
		for size: int in SWEEP_SIZES:
			var key: Vector2i = Vector2i(size, depth)
			if not _sweep_win_rate.has(key):
				continue
			if _sweep_win_rate[key] >= WIN_RATE_REQUIRED and _sweep_hp_loss[key] <= HP_LOSS_ALLOWED:
				needed = size
				break
		var needed_text: String = str(needed) if needed > 0 else ">%d" % SWEEP_SIZES[SWEEP_SIZES.size() - 1]
		if _ag_entered.size() <= depth or _ag_entered[depth] == 0:
			print("| %d | %s | - | - |" % [depth, needed_text])
			continue
		var have: float = _ag_size[depth] / float(_ag_entered[depth])
		var slack_text: String = "%+.1f" % (have - float(needed)) if needed > 0 else "n/a"
		print("| %d | %s | %.1f | %s |" % [depth, needed_text, have, slack_text])


func _print_header() -> void:
	print("# Escapeteers balance simulation")
	print("")
	var keys: Array[String] = []
	for key: StringName in _args:
		keys.append("%s=%s" % [key, _args[key]])
	keys.sort()
	print("Config: " + " ".join(keys))

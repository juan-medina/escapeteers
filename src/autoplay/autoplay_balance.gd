# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name AutoplayBalance
extends RefCounted

const ARCHETYPE_NAMES: Dictionary[int, StringName] = {
	WorldPlan.RoomArchetype.SLIME_PIT: &"SLIME_PIT",
	WorldPlan.RoomArchetype.BONE_SWARM: &"BONE_SWARM",
	WorldPlan.RoomArchetype.ARCHER_GARRISON: &"ARCHER_GARRISON",
	WorldPlan.RoomArchetype.NECRO_CRYPT: &"NECRO_CRYPT",
}
const EVENT_TYPE_NAMES: Dictionary[int, StringName] = {
	WorldPlan.RoomEventType.CLOSING_SPIKES: &"BLOOD_SPIKES",
	WorldPlan.RoomEventType.WAVE_AMBUSH: &"WAVE_AMBUSH",
}

var _runs: Array[Dictionary] = []

var _cur_game: Game = null
var _cur_map: Map = null
var _cur_seed: int = 0
var _cur_leader: StringName = &""
var _cur_build: String = ""
var _cur_sim_time: float = 0.0
var _cur_enemies_killed: int = 0
var _cur_death_cause: StringName = &"none"
var _cur_active_room: Rect2i = Rect2i()
var _cur_room_records: Dictionary[Rect2i, Dictionary] = {}
var _cur_class_stats: Dictionary[StringName, Dictionary] = {}
var _hooked_heroes: Dictionary[int, bool] = {}
var _hooked_enemies: Dictionary[int, bool] = {}
var _last_attacker_by_hero: Dictionary[int, StringName] = {}


func reset_session() -> void:
	_runs.clear()


func begin_run(game: Game, map: Map, seed_val: int, leader_id: StringName, build_policy: String) -> void:
	_cur_game = game
	_cur_map = map
	_cur_seed = seed_val
	_cur_leader = leader_id
	_cur_build = build_policy
	_cur_sim_time = 0.0
	_cur_enemies_killed = 0
	_cur_death_cause = &"none"
	_cur_active_room = Rect2i()
	_cur_room_records.clear()
	_cur_class_stats.clear()
	_hooked_heroes.clear()
	_hooked_enemies.clear()
	_last_attacker_by_hero.clear()

	if not game._characters.child_entered_tree.is_connected(_on_character_child_entered):
		game._characters.child_entered_tree.connect(_on_character_child_entered)

	for child: Node in game._characters.get_children():
		_hook_character_node(child)


func update(game: Game, map: Map, delta: float) -> void:
	if game.get_tree().paused:
		return

	_cur_sim_time += delta
	_track_unit_uptime(game, delta)
	_track_rooms(game, map)


func finish_run(bot: AutoplayBot, game: Game, map: Map, reason: String = "") -> Dictionary:
	var leader_dead: bool = not is_instance_valid(game._character) or game._character.is_dead
	var max_depth: int = bot.max_depth_reached
	var rooms_entered: int = _cur_room_records.size()
	var rooms_cleared: int = 0
	for rec: Dictionary in _cur_room_records.values():
		if rec[&"cleared"]:
			rooms_cleared += 1

	var doors_unlocked: int = 0
	for gate: SectorGatePlanner.SectorGate in map.plan.sector_gates:
		if gate.door_unlocked:
			doors_unlocked += 1
	var doors_mask: String = bot.get_doors_mask(map)
	var keys_mask: String = bot.get_keys_mask(game)

	var final_class_stats: Dictionary = {}
	for cid: StringName in _cur_class_stats:
		var st: Dictionary = _cur_class_stats[cid]
		var fallback_lv: int = st[&"max_level"]
		var max_lv: int = game._class_levels.get(cid, fallback_lv)
		var combat_sec: float = st[&"combat_unit_sec"]
		var alive_sec: float = st[&"alive_unit_sec"]
		var dmg: float = st[&"damage"]
		var heal: float = st[&"healing"]
		final_class_stats[cid] = {
			&"picks": st[&"picks"],
			&"max_level": max_lv,
			&"damage": dmg,
			&"healing": heal,
			&"damage_taken": st[&"damage_taken"],
			&"deaths": st[&"deaths"],
			&"combat_unit_sec": combat_sec,
			&"alive_unit_sec": alive_sec,
			&"combat_dps": dmg / maxf(1.0, combat_sec),
			&"overall_dps": dmg / maxf(1.0, alive_sec),
			&"hps": heal / maxf(1.0, alive_sec),
		}

	var room_list: Array[Dictionary] = []
	for room: Rect2i in _cur_room_records:
		var rec: Dictionary = _cur_room_records[room].duplicate()
		if not rec[&"cleared"]:
			var enter_time: float = rec[&"enter_time"]
			var raw_entry_hp: float = rec[&"entry_max_hp"]
			var dmg_taken: float = rec[&"damage_taken"]
			rec[&"clear_time"] = _cur_sim_time - enter_time
			var entry_hp: float = maxf(1.0, raw_entry_hp)
			rec[&"hp_lost_pct"] = dmg_taken / entry_hp * 100.0
		room_list.append(rec)

	var summary: Dictionary = {
		&"seed": _cur_seed,
		&"leader": String(_cur_leader),
		&"build": _cur_build,
		&"won": bot.has_won and not leader_dead,
		&"reason": reason,
		&"leader_dead": leader_dead,
		&"death_cause": String(_cur_death_cause),
		&"doors_unlocked": doors_unlocked,
		&"doors_mask": doors_mask,
		&"keys_mask": keys_mask,
		&"max_depth": max_depth,
		&"rooms_entered": rooms_entered,
		&"rooms_cleared": rooms_cleared,
		&"duration_sec": _cur_sim_time,
		&"final_squad_size": game._squad.size(),
		&"squad_level": game._squad_level,
		&"enemies_killed": _cur_enemies_killed,
		&"classes": final_class_stats,
		&"rooms": room_list,
	}
	if not map.plan.rooms.is_empty():
		summary[&"dungeon_rooms"] = map.plan.rooms.size()
	_runs.append(summary)
	return summary


func build_report_dict() -> Dictionary:
	return {
		&"run_count": _runs.size(),
		&"runs": _runs,
		&"builds": _aggregate_by_build(),
		&"reasons": _aggregate_reasons(_runs),
		&"death_causes": _aggregate_death_causes(_runs),
		&"door_funnel": _aggregate_door_funnel(_runs),
		&"classes": _aggregate_classes(_runs),
		&"classes_balanced": _aggregate_classes(_filter_runs_by_build("balanced", false)),
		&"classes_mono": _aggregate_classes(_filter_runs_by_build("mono:", true)),
		&"depths": _aggregate_depths(_runs),
		&"archetypes": _aggregate_archetypes(_runs),
	}


func print_balance_report(title: String = "AUTOPLAY BALANCE REPORT") -> void:
	var report: Dictionary = build_report_dict()
	var builds: Array[Dictionary] = report[&"builds"]
	var reasons: Dictionary[String, int] = report[&"reasons"]
	var death_causes: Array[Dictionary] = report[&"death_causes"]
	var door_funnel: Dictionary[String, int] = report[&"door_funnel"]
	var classes: Array[Dictionary] = report[&"classes"]
	var classes_bal: Array[Dictionary] = report[&"classes_balanced"]
	var classes_mono: Array[Dictionary] = report[&"classes_mono"]
	var depths: Array[Dictionary] = report[&"depths"]
	var archetypes: Array[Dictionary] = report[&"archetypes"]

	print(&"\n================ %s ================" % title)
	print(&"Runs Completed: %d" % _runs.size())
	_print_summary_blocks(reasons, death_causes, door_funnel)
	_print_build_table(builds)
	if not classes_bal.is_empty() and not classes_mono.is_empty():
		_print_class_table(classes_bal, "CLASS BALANCE BREAKDOWN (BALANCED RUNS)")
		_print_class_table(classes_mono, "CLASS BALANCE BREAKDOWN (MONO RUNS)")
	else:
		_print_class_table(classes, "CLASS BALANCE BREAKDOWN")
	_print_archetype_table(archetypes)
	_print_depth_table(depths)
	print(&"===========================================================\n")


func _on_character_child_entered(node: Node) -> void:
	_hook_character_node(node)


func _hook_character_node(node: Node) -> void:
	if node is Hero:
		var hero: Hero = node as Hero
		var hid: int = hero.get_instance_id()
		if _hooked_heroes.has(hid):
			return
		_hooked_heroes[hid] = true
		if hero.hero_data != null:
			_ensure_class_entry(hero.hero_data.id)
			var cid: StringName = hero.hero_data.id
			var prev_picks: int = _cur_class_stats[cid][&"picks"]
			_cur_class_stats[cid][&"picks"] = prev_picks + 1
		hero.enemy_hit.connect(_on_hero_enemy_hit.bind(hero))
		hero.ally_healed.connect(_on_hero_ally_healed.bind(hero))
		hero.damaged.connect(_on_hero_damaged.bind(hero))
		hero.died.connect(_on_hero_died.bind(hero))
	elif node is Enemy:
		var enemy: Enemy = node as Enemy
		var eid: int = enemy.get_instance_id()
		if _hooked_enemies.has(eid):
			return
		_hooked_enemies[eid] = true
		enemy.attacked.connect(_on_enemy_attacked.bind(enemy))
		enemy.died.connect(_on_enemy_died)


func _ensure_class_entry(class_id: StringName) -> void:
	if _cur_class_stats.has(class_id):
		return
	_cur_class_stats[class_id] = {
		&"picks": 0,
		&"max_level": 1,
		&"damage": 0.0,
		&"healing": 0.0,
		&"damage_taken": 0.0,
		&"deaths": 0,
		&"combat_unit_sec": 0.0,
		&"alive_unit_sec": 0.0,
	}


func _on_hero_enemy_hit(_enemy: Enemy, damage: float, _is_heavy: bool, hero: Hero) -> void:
	if hero.hero_data == null:
		return
	var cid: StringName = hero.hero_data.id
	_ensure_class_entry(cid)
	var prev_dmg: float = _cur_class_stats[cid][&"damage"]
	_cur_class_stats[cid][&"damage"] = prev_dmg + damage


func _on_hero_ally_healed(_ally: Character, amount: float, hero: Hero) -> void:
	if hero.hero_data == null:
		return
	var cid: StringName = hero.hero_data.id
	_ensure_class_entry(cid)
	var prev_heal: float = _cur_class_stats[cid][&"healing"]
	_cur_class_stats[cid][&"healing"] = prev_heal + amount


func _on_hero_damaged(amount: float, _current_health: float, hero: Hero) -> void:
	if hero.hero_data != null:
		var cid: StringName = hero.hero_data.id
		_ensure_class_entry(cid)
		var prev_taken: float = _cur_class_stats[cid][&"damage_taken"]
		_cur_class_stats[cid][&"damage_taken"] = prev_taken + amount
	if _cur_active_room != Rect2i() and _cur_room_records.has(_cur_active_room):
		var rec: Dictionary = _cur_room_records[_cur_active_room]
		var prev_room_dmg: float = rec[&"damage_taken"]
		rec[&"damage_taken"] = prev_room_dmg + amount
	if _cur_map != null and is_instance_valid(hero):
		var foot_cell: Vector2i = _cur_map.local_to_map(hero.get_hurtbox_position())
		if _cur_map.is_spike_active_at(foot_cell):
			var is_blood: bool = _cur_map.plan.event_spike_cell_rooms.has(foot_cell)
			_last_attacker_by_hero[hero.get_instance_id()] = &"blood_spike" if is_blood else &"spike"


func _on_hero_died(hero: Hero) -> void:
	if hero.hero_data != null:
		var cid: StringName = hero.hero_data.id
		_ensure_class_entry(cid)
		var prev_deaths: int = _cur_class_stats[cid][&"deaths"]
		_cur_class_stats[cid][&"deaths"] = prev_deaths + 1
	if _cur_active_room != Rect2i() and _cur_room_records.has(_cur_active_room):
		var rec: Dictionary = _cur_room_records[_cur_active_room]
		if hero.is_player:
			var prev_wipes: int = rec[&"wipes"]
			rec[&"wipes"] = prev_wipes + 1
		else:
			var prev_rd: int = rec[&"deaths"]
			rec[&"deaths"] = prev_rd + 1
	if hero.is_player:
		_cur_death_cause = _last_attacker_by_hero.get(hero.get_instance_id(), &"combat")


func _on_enemy_attacked(target: Hero, _damage_amount: float, enemy: Enemy) -> void:
	if is_instance_valid(target) and is_instance_valid(enemy):
		_last_attacker_by_hero[target.get_instance_id()] = enemy.enemy_id


func _on_enemy_died() -> void:
	_cur_enemies_killed += 1


func _track_unit_uptime(game: Game, delta: float) -> void:
	var in_combat: bool = game._is_any_enemy_engaged() or game._is_any_hero_engaged()
	for member: Hero in game._squad:
		if not is_instance_valid(member) or member.is_dead or member.hero_data == null:
			continue
		var cid: StringName = member.hero_data.id
		_ensure_class_entry(cid)
		var st: Dictionary = _cur_class_stats[cid]
		var prev_alive: float = st[&"alive_unit_sec"]
		st[&"alive_unit_sec"] = prev_alive + delta
		if in_combat:
			var prev_combat: float = st[&"combat_unit_sec"]
			st[&"combat_unit_sec"] = prev_combat + delta
		var lvl: int = game._class_levels.get(cid, member.level)
		var max_lvl: int = st[&"max_level"]
		if lvl > max_lvl:
			st[&"max_level"] = lvl


func _track_rooms(game: Game, map: Map) -> void:
	if not is_instance_valid(game._character):
		return
	var cell: Vector2i = map.local_to_map(game._character.global_position)
	var room: Rect2i = map.plan.get_room_at(cell)
	if room != Rect2i() and room != map.hero_room:
		_cur_active_room = room
		if not _cur_room_records.has(room):
			var total_max_hp: float = _sum_squad_max_hp(game)
			var event_type: WorldPlan.RoomEventType = map.plan.room_event_types.get(room, WorldPlan.RoomEventType.NONE)
			var arch_name: StringName = (
				EVENT_TYPE_NAMES[event_type]
				if EVENT_TYPE_NAMES.has(event_type)
				else ARCHETYPE_NAMES.get(map.plan.get_room_archetype(room), &"SLIME_PIT")
			)
			_cur_room_records[room] = {
				&"depth": map.get_room_depth(room),
				&"archetype": String(arch_name),
				&"quota": map.get_room_enemy_quota(room),
				&"enter_time": _cur_sim_time,
				&"clear_time": 0.0,
				&"entry_max_hp": total_max_hp,
				&"damage_taken": 0.0,
				&"hp_lost_pct": 0.0,
				&"deaths": 0,
				&"wipes": 0,
				&"cleared": false,
			}

	for tracked_room: Rect2i in _cur_room_records:
		var rec: Dictionary = _cur_room_records[tracked_room]
		if rec[&"cleared"]:
			continue
		var room_cleared: bool = false
		if map.plan.closing_spike_hazards.has(tracked_room):
			var hazard: ClosingSpikeHazard = map.plan.closing_spike_hazards[tracked_room]
			room_cleared = hazard != null and hazard.is_cleared
		elif map.plan.wave_ambushes.has(tracked_room):
			var ambush: WaveAmbush = map.plan.wave_ambushes[tracked_room]
			room_cleared = ambush != null and ambush.is_cleared
		elif game._room_remaining_enemies.has(tracked_room) and game._room_remaining_enemies[tracked_room] <= 0:
			room_cleared = true
		if room_cleared:
			rec[&"cleared"] = true
			var enter_time: float = rec[&"enter_time"]
			var raw_entry_hp: float = rec[&"entry_max_hp"]
			var dmg_taken: float = rec[&"damage_taken"]
			rec[&"clear_time"] = _cur_sim_time - enter_time
			var entry_hp: float = maxf(1.0, raw_entry_hp)
			rec[&"hp_lost_pct"] = dmg_taken / entry_hp * 100.0


static func _sum_squad_max_hp(game: Game) -> float:
	var total: float = 0.0
	for member: Hero in game._squad:
		if is_instance_valid(member) and not member.is_dead:
			total += member.max_health
	return total


func _filter_runs_by_build(pattern: String, is_prefix: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for run: Dictionary in _runs:
		var build_str: String = run[&"build"]
		if (is_prefix and build_str.begins_with(pattern)) or (not is_prefix and build_str == pattern):
			out.append(run)
	return out


static func _aggregate_reasons(runs: Array[Dictionary]) -> Dictionary[String, int]:
	var counts: Dictionary[String, int] = {}
	for run: Dictionary in runs:
		var r_reason: String = run.get(&"reason", "")
		var key: String = r_reason if r_reason != "" else ("won" if run[&"won"] else "leader_dead")
		var prev: int = counts.get(key, 0)
		counts[key] = prev + 1
	return counts


static func _aggregate_death_causes(runs: Array[Dictionary]) -> Array[Dictionary]:
	var counts: Dictionary[String, int] = {}
	for run: Dictionary in runs:
		if not run[&"leader_dead"]:
			continue
		var cause: String = run[&"death_cause"]
		var prev: int = counts.get(cause, 0)
		counts[cause] = prev + 1
	var out: Array[Dictionary] = []
	for cause: String in counts:
		out.append({&"cause": cause, &"count": counts[cause]})
	out.sort_custom(_compare_count_desc)
	return out


static func _compare_count_desc(a: Dictionary, b: Dictionary) -> bool:
	var ca: int = a[&"count"]
	var cb: int = b[&"count"]
	return ca > cb


static func _aggregate_door_funnel(runs: Array[Dictionary]) -> Dictionary[String, int]:
	var funnel: Dictionary[String, int] = {"B": 0, "G": 0, "Y": 0, "R": 0, "D12": 0}
	var door_keys: Array[String] = ["B", "G", "Y", "R"]
	for run: Dictionary in runs:
		var mask: String = run.get(&"doors_mask", "-")
		for key: String in door_keys:
			if mask.contains(key):
				funnel[key] += 1
		if run[&"won"]:
			funnel["D12"] += 1
	return funnel


func _aggregate_by_build() -> Array[Dictionary]:
	var groups: Dictionary[String, Array] = {}
	for run: Dictionary in _runs:
		var key: String = "%s | %s" % [run[&"leader"], run[&"build"]]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(run)

	var results: Array[Dictionary] = []
	for key: String in groups:
		var runs_arr: Array = groups[key]
		var n: int = runs_arr.size()
		var wins: int = 0
		var sum_depth: float = 0.0
		var sum_doors: float = 0.0
		var sum_cleared: float = 0.0
		var sum_time: float = 0.0
		var sum_squad: float = 0.0
		var sum_dmg: float = 0.0
		var sum_combat_sec: float = 0.0
		var sum_deaths: int = 0
		var frame_limits: int = 0
		for r_var: Variant in runs_arr:
			var r: Dictionary = r_var
			if r[&"won"]:
				wins += 1
			var r_depth: float = r[&"max_depth"]
			var r_doors: int = r.get(&"doors_unlocked", 0)
			var r_cleared: float = r[&"rooms_cleared"]
			var r_time: float = r[&"duration_sec"]
			var r_squad: float = r[&"final_squad_size"]
			var r_reason: String = r.get(&"reason", "")
			if r_reason == "frame_limit":
				frame_limits += 1
			sum_depth += r_depth
			sum_doors += float(r_doors)
			sum_cleared += r_cleared
			sum_time += r_time
			sum_squad += r_squad
			var cls: Dictionary = r[&"classes"]
			for st_var: Variant in cls.values():
				var st: Dictionary = st_var
				var s_dmg: float = st[&"damage"]
				var s_csec: float = st[&"combat_unit_sec"]
				var s_deaths: int = st[&"deaths"]
				sum_dmg += s_dmg
				sum_combat_sec += s_csec
				sum_deaths += s_deaths

		(
			results
			. append(
				{
					&"key": key,
					&"runs": n,
					&"win_pct": float(wins) / float(maxi(1, n)) * 100.0,
					&"avg_depth": sum_depth / float(maxi(1, n)),
					&"avg_doors": sum_doors / float(maxi(1, n)),
					&"avg_cleared": sum_cleared / float(maxi(1, n)),
					&"avg_time": sum_time / float(maxi(1, n)),
					&"avg_squad": sum_squad / float(maxi(1, n)),
					&"avg_unit_dps": sum_dmg / maxf(1.0, sum_combat_sec),
					&"avg_deaths": float(sum_deaths) / float(maxi(1, n)),
					&"frame_limits": frame_limits,
				}
			)
		)

	results.sort_custom(_compare_build_desc)
	return results


static func _compare_build_desc(a: Dictionary, b: Dictionary) -> bool:
	var wa: float = a[&"win_pct"]
	var wb: float = b[&"win_pct"]
	if absf(wa - wb) > 0.01:
		return wa > wb
	var da: float = a[&"avg_depth"]
	var db: float = b[&"avg_depth"]
	return da > db


static func _aggregate_classes(runs: Array[Dictionary]) -> Array[Dictionary]:
	var totals: Dictionary[StringName, Dictionary] = {}
	for run: Dictionary in runs:
		var cls: Dictionary = run[&"classes"]
		for cid: StringName in cls:
			var st: Dictionary = cls[cid]
			if not totals.has(cid):
				totals[cid] = {
					&"id": cid,
					&"picks": 0,
					&"sum_max_lv": 0,
					&"runs_present": 0,
					&"damage": 0.0,
					&"healing": 0.0,
					&"damage_taken": 0.0,
					&"deaths": 0,
					&"combat_sec": 0.0,
					&"alive_sec": 0.0,
				}
			var acc: Dictionary = totals[cid]
			var a_picks: int = acc[&"picks"]
			var s_picks: int = st[&"picks"]
			var a_lv: int = acc[&"sum_max_lv"]
			var s_lv: int = st[&"max_level"]
			var a_rp: int = acc[&"runs_present"]
			var a_dmg: float = acc[&"damage"]
			var s_dmg: float = st[&"damage"]
			var a_heal: float = acc[&"healing"]
			var s_heal: float = st[&"healing"]
			var a_dt: float = acc[&"damage_taken"]
			var s_dt: float = st[&"damage_taken"]
			var a_d: int = acc[&"deaths"]
			var s_d: int = st[&"deaths"]
			var a_csec: float = acc[&"combat_sec"]
			var s_csec: float = st[&"combat_unit_sec"]
			var a_asec: float = acc[&"alive_sec"]
			var s_asec: float = st[&"alive_unit_sec"]
			acc[&"picks"] = a_picks + s_picks
			acc[&"sum_max_lv"] = a_lv + s_lv
			acc[&"runs_present"] = a_rp + 1
			acc[&"damage"] = a_dmg + s_dmg
			acc[&"healing"] = a_heal + s_heal
			acc[&"damage_taken"] = a_dt + s_dt
			acc[&"deaths"] = a_d + s_d
			acc[&"combat_sec"] = a_csec + s_csec
			acc[&"alive_sec"] = a_asec + s_asec

	var out: Array[Dictionary] = []
	for cid: StringName in totals:
		var acc: Dictionary = totals[cid]
		var raw_rp: int = acc[&"runs_present"]
		var rp: int = maxi(1, raw_rp)
		var picks: int = acc[&"picks"]
		var sum_max_lv: int = acc[&"sum_max_lv"]
		var dmg: float = acc[&"damage"]
		var combat_sec: float = acc[&"combat_sec"]
		var healing: float = acc[&"healing"]
		var alive_sec: float = acc[&"alive_sec"]
		var dmg_taken: float = acc[&"damage_taken"]
		var deaths: int = acc[&"deaths"]
		(
			out
			. append(
				{
					&"id": String(cid),
					&"picks": picks,
					&"avg_max_lv": float(sum_max_lv) / float(rp),
					&"combat_dps": dmg / maxf(1.0, combat_sec),
					&"hps": healing / maxf(1.0, alive_sec),
					&"dmg_taken_per_pick": dmg_taken / float(maxi(1, picks)),
					&"deaths": deaths,
					&"death_rate": float(deaths) / float(maxi(1, picks)) * 100.0,
				}
			)
		)

	out.sort_custom(_compare_class_dps_desc)
	return out


static func _compare_class_dps_desc(a: Dictionary, b: Dictionary) -> bool:
	var da: float = a[&"combat_dps"]
	var db: float = b[&"combat_dps"]
	return da > db


static func _aggregate_archetypes(runs: Array[Dictionary]) -> Array[Dictionary]:
	var buckets: Dictionary[String, Array] = {}
	for run: Dictionary in runs:
		var room_list: Array = run[&"rooms"]
		for rec_var: Variant in room_list:
			var rec: Dictionary = rec_var
			var arch: String = rec[&"archetype"]
			if not buckets.has(arch):
				buckets[arch] = []
			buckets[arch].append(rec)

	return _finalize_room_buckets(buckets, false)


static func _aggregate_depths(runs: Array[Dictionary]) -> Array[Dictionary]:
	var buckets: Dictionary[String, Array] = {}
	for run: Dictionary in runs:
		var room_list: Array = run[&"rooms"]
		for rec_var: Variant in room_list:
			var rec: Dictionary = rec_var
			var depth: int = rec[&"depth"]
			var key: String = "%02d" % depth
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append(rec)

	return _finalize_room_buckets(buckets, true)


static func _finalize_room_buckets(buckets: Dictionary[String, Array], sort_by_key: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var keys: Array[String] = []
	for k: String in buckets:
		keys.append(k)
	if sort_by_key:
		keys.sort()

	for k: String in keys:
		var list: Array = buckets[k]
		var entered: int = list.size()
		var cleared: int = 0
		var sum_time: float = 0.0
		var sum_hp_lost: float = 0.0
		var deaths: int = 0
		var wipes: int = 0
		for rec_var: Variant in list:
			var rec: Dictionary = rec_var
			if rec[&"cleared"]:
				cleared += 1
				var ctime: float = rec[&"clear_time"]
				sum_time += ctime
			var hp_lost: float = rec[&"hp_lost_pct"]
			var r_deaths: int = rec[&"deaths"]
			var r_wipes: int = rec[&"wipes"]
			sum_hp_lost += hp_lost
			deaths += r_deaths
			wipes += r_wipes

		(
			out
			. append(
				{
					&"key": k,
					&"entered": entered,
					&"cleared": cleared,
					&"avg_clear_sec": sum_time / float(maxi(1, cleared)),
					&"avg_hp_lost_pct": sum_hp_lost / float(maxi(1, entered)),
					&"deaths": deaths,
					&"wipes": wipes,
				}
			)
		)
	return out


static func _print_summary_blocks(reasons: Dictionary[String, int], death_causes: Array[Dictionary], door_funnel: Dictionary[String, int]) -> void:
	var reason_parts: Array[String] = []
	for key: String in reasons:
		reason_parts.append("%s=%d" % [key, reasons[key]])
	print(&"End Reasons: %s" % ", ".join(reason_parts))

	var cause_parts: Array[String] = []
	for item: Dictionary in death_causes:
		var cause: String = item[&"cause"]
		var cnt: int = item[&"count"]
		cause_parts.append("%s=%d" % [cause, cnt])
	if not cause_parts.is_empty():
		print(&"Death Causes: %s" % ", ".join(cause_parts))

	print(
		(
			&"Sector Door Funnel: B=%d  G=%d  Y=%d  R=%d  D12Win=%d"
			% [door_funnel["B"], door_funnel["G"], door_funnel["Y"], door_funnel["R"], door_funnel["D12"]]
		)
	)


static func _print_build_table(builds: Array[Dictionary]) -> void:
	print(&"\nBUILD LEADERBOARD:")
	print(&"  %-30s  Runs   Win%%  AvgDepth  Doors  Cleared  AvgTime  Squad  UnitDPS  Deaths  FLim" % "Leader | Build")
	for b: Dictionary in builds:
		print(
			(
				&"  %-30s  %4d  %5.1f     %5.1f   %4.1f    %5.1f   %6.1fs   %4.1f   %6.1f   %5.1f  %4d"
				% [
					b[&"key"],
					b[&"runs"],
					b[&"win_pct"],
					b[&"avg_depth"],
					b[&"avg_doors"],
					b[&"avg_cleared"],
					b[&"avg_time"],
					b[&"avg_squad"],
					b[&"avg_unit_dps"],
					b[&"avg_deaths"],
					b[&"frame_limits"],
				]
			)
		)


static func _print_class_table(classes: Array[Dictionary], title: String = "CLASS BALANCE BREAKDOWN") -> void:
	if classes.is_empty():
		return
	var avg_dps: float = 0.0
	for c: Dictionary in classes:
		var c_dps: float = c[&"combat_dps"]
		avg_dps += c_dps
	avg_dps /= float(maxi(1, classes.size()))

	print(&"\n%s (Combat Unit DPS avg=%.1f):" % [title, avg_dps])
	print(&"  %-16s  Picks  AvgLv  UnitDPS   Heal/s  DmgTaken/u  Death%%   Flag" % "Class")
	for c: Dictionary in classes:
		var dps: float = c[&"combat_dps"]
		var hps: float = c[&"hps"]
		var death_rate: float = c[&"death_rate"]
		var flag: String = ""
		if dps >= avg_dps * 1.35:
			flag = "HIGH_DPS"
		elif hps < 0.5 and dps <= avg_dps * 0.65:
			flag = "LOW_DPS"
		if death_rate >= 35.0:
			flag = (flag + "+FRAGILE") if flag != "" else "FRAGILE"
		print(
			(
				&"  %-16s  %5d   %4.1f   %6.1f   %6.2f      %6.1f   %5.1f%%  %s"
				% [c[&"id"], c[&"picks"], c[&"avg_max_lv"], dps, hps, c[&"dmg_taken_per_pick"], death_rate, flag]
			)
		)


static func _print_archetype_table(archetypes: Array[Dictionary]) -> void:
	if archetypes.is_empty():
		return
	print(&"\nROOM ARCHETYPE DIFFICULTY:")
	print(&"  %-16s  Entered  Cleared  AvgClear  AvgHPLost  Deaths  Wipes" % "Archetype")
	for a: Dictionary in archetypes:
		print(
			(
				&"  %-16s  %7d  %7d    %5.1fs     %5.1f%%  %6d  %5d"
				% [a[&"key"], a[&"entered"], a[&"cleared"], a[&"avg_clear_sec"], a[&"avg_hp_lost_pct"], a[&"deaths"], a[&"wipes"]]
			)
		)


static func _print_depth_table(depths: Array[Dictionary]) -> void:
	if depths.is_empty():
		return
	print(&"\nDEPTH PROGRESSION CURVE:")
	print(&"  Depth  Entered  Cleared  AvgClear  AvgHPLost  Deaths  Wipes")
	for d: Dictionary in depths:
		print(
			(
				&"  D%-4s  %7d  %7d    %5.1fs     %5.1f%%  %6d  %5d"
				% [d[&"key"], d[&"entered"], d[&"cleared"], d[&"avg_clear_sec"], d[&"avg_hp_lost_pct"], d[&"deaths"], d[&"wipes"]]
			)
		)

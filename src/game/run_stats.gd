# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name RunStats
extends RefCounted


class ClassBreakdownEntry:
	extends RefCounted
	var class_id: StringName = &""
	var hero_name: String = ""
	var abbr: String = ""
	var color: Color = Color.WHITE
	var level: int = 1
	var total_damage: float = 0.0
	var dps: float = 0.0
	var pct: float = 0.0


var total_escapees: int = 0
var escapees_rescued: int = 0
var fallen_companions: int = 0
var elapsed_time: float = 0.0
var rooms_discovered: int = 0
var total_rooms: int = 0
var explored_percent: int = 0
var trap_damage_taken: float = 0.0
var leader_class_id: StringName = &""
var leader_level: int = 1
var class_levels: Dictionary[StringName, int] = {}
var living_counts: Dictionary[StringName, int] = {}
var fallen_counts: Dictionary[StringName, int] = {}
var class_breakdown: Array[ClassBreakdownEntry] = []
var mvp_class_id: StringName = &""
var mvp_damage: float = 0.0


func reset(p_total_escapees: int, p_total_rooms: int, p_leader_id: StringName) -> void:
	total_escapees = p_total_escapees
	escapees_rescued = 0
	fallen_companions = 0
	elapsed_time = 0.0
	rooms_discovered = 0
	total_rooms = p_total_rooms
	explored_percent = 0
	trap_damage_taken = 0.0
	leader_class_id = p_leader_id
	leader_level = 1
	class_levels.clear()
	living_counts.clear()
	fallen_counts.clear()
	class_breakdown.clear()
	mvp_class_id = &""
	mvp_damage = 0.0


func record_rescue() -> void:
	escapees_rescued += 1


func record_companion_death(hero_id: StringName) -> void:
	fallen_companions += 1
	fallen_counts[hero_id] = fallen_counts.get(hero_id, 0) + 1


func record_trap_damage(amount: float) -> void:
	if amount > 0.0:
		trap_damage_taken += amount


func record_room_discovered(count: int) -> void:
	rooms_discovered = count


func record_exploration(percent: int) -> void:
	explored_percent = clampi(percent, 0, 100)


func finalize_snapshot(
	squad: Array[Hero],
	p_class_levels: Dictionary[StringName, int],
	run_class_damages: Dictionary[StringName, float],
	run_combat_time: float,
) -> void:
	class_levels = p_class_levels.duplicate()
	leader_level = class_levels.get(leader_class_id, 1)
	living_counts.clear()
	for member: Hero in squad:
		if not member.is_dead and not member.is_player and member.hero_data != null:
			var cid: StringName = member.hero_data.id
			living_counts[cid] = living_counts.get(cid, 0) + 1

	var tracked_classes: Array[StringName] = []
	for cid: StringName in class_levels:
		if HeroData.get_hero(cid) != null:
			tracked_classes.append(cid)
	for cid: StringName in run_class_damages:
		if HeroData.get_hero(cid) != null and not tracked_classes.has(cid):
			tracked_classes.append(cid)

	var total_hero_damage: float = 0.0
	for cid: StringName in tracked_classes:
		total_hero_damage += run_class_damages.get(cid, 0.0)

	var effective_combat_time: float = maxf(1.0, run_combat_time)
	class_breakdown.clear()
	mvp_class_id = &""
	mvp_damage = 0.0

	for cid: StringName in tracked_classes:
		var hero_data: HeroData = HeroData.get_hero(cid)
		var dmg: float = run_class_damages.get(cid, 0.0)
		var entry: ClassBreakdownEntry = ClassBreakdownEntry.new()
		entry.class_id = cid
		entry.hero_name = hero_data.name
		entry.abbr = hero_data.abbr
		entry.color = hero_data.color
		entry.level = class_levels.get(cid, 1)
		entry.total_damage = dmg
		entry.dps = dmg / effective_combat_time
		entry.pct = (dmg / total_hero_damage * 100.0) if total_hero_damage > 0.0 else 0.0
		class_breakdown.append(entry)

	class_breakdown.sort_custom(_compare_breakdown_desc)
	if not class_breakdown.is_empty() and class_breakdown[0].total_damage > 0.0:
		mvp_class_id = class_breakdown[0].class_id
		mvp_damage = class_breakdown[0].total_damage


static func format_duration(seconds: float) -> String:
	var total_secs: int = maxi(0, int(floorf(seconds)))
	var mins: int = floori(float(total_secs) / 60.0)
	var secs: int = total_secs % 60
	return "%02d:%02d" % [mins, secs]


static func _compare_breakdown_desc(a: ClassBreakdownEntry, b: ClassBreakdownEntry) -> bool:
	if absf(a.total_damage - b.total_damage) > 0.01:
		return a.total_damage > b.total_damage
	return a.level > b.level

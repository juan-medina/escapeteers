# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

## Tracks active run telemetry, escapee progress, companion tombstones, and Game Over score calculation.
class_name RunTracker
extends RefCounted

const TOMBSTONE_SCENE: PackedScene = preload("res://tombstone/tombstone.tscn")
const TOMBSTONE_STACK_OFFSET: float = 4.5

var stats: RunStats = RunStats.new()

var _room_remaining_escapees: Dictionary[Rect2i, int] = {}
var _pending_recruit_room: Rect2i = Rect2i()
var _tombstone_cell_counts: Dictionary[Vector2i, int] = {}
var _last_reported_run_second: int = -1


func start_run(map: Map, hud: Hud, leader_id: StringName) -> void:
	_room_remaining_escapees = _build_room_escapee_counts(map)
	_pending_recruit_room = Rect2i()
	_tombstone_cell_counts.clear()
	_last_reported_run_second = -1

	var total_escapees: int = 0
	for escapee_count: int in _room_remaining_escapees.values():
		total_escapees += escapee_count

	stats.reset(total_escapees, map.plan.rooms.size() + 1, leader_id)
	hud.setup_run_tracker(total_escapees, _room_remaining_escapees)
	hud.update_run_time(0.0)


func advance_time(delta: float, hud: Hud) -> void:
	stats.elapsed_time += delta
	var run_second: int = int(floorf(stats.elapsed_time))
	if run_second != _last_reported_run_second:
		_last_reported_run_second = run_second
		hud.update_run_time(stats.elapsed_time)


func begin_recruit(candidate: Unknown) -> void:
	_pending_recruit_room = candidate.home_room


func complete_rescue(hud: Hud) -> void:
	stats.record_rescue()
	var prev_remaining: int = _room_remaining_escapees.get(_pending_recruit_room, 0)
	var remaining: int = maxi(0, prev_remaining - 1)
	_room_remaining_escapees[_pending_recruit_room] = remaining
	hud.update_escapee_progress(stats.escapees_rescued, stats.total_escapees, stats.fallen_companions, true, false)
	hud.set_room_unrescued_escapees(_pending_recruit_room, remaining)


func record_companion_death(hero: Hero, map: Map, characters_container: Node2D, hud: Hud) -> void:
	var death_cell: Vector2i = map.local_to_map(hero.global_position)
	var tile_pos: Vector2 = map.map_to_local(death_cell)
	var stack_idx: int = _tombstone_cell_counts.get(death_cell, 0)
	_tombstone_cell_counts[death_cell] = stack_idx + 1
	var spawn_pos: Vector2 = tile_pos
	if stack_idx > 0:
		var angle: float = float(stack_idx - 1) * 2.1
		spawn_pos += Vector2.from_angle(angle) * TOMBSTONE_STACK_OFFSET

	var tombstone: Tombstone = TOMBSTONE_SCENE.instantiate() as Tombstone
	characters_container.add_child(tombstone)
	tombstone.position = spawn_pos
	tombstone.setup(hero.hero_data)

	stats.record_companion_death(hero.hero_data.id)
	hud.add_fallen_marker(tile_pos, hero.hero_data.color)
	hud.update_escapee_progress(stats.escapees_rescued, stats.total_escapees, stats.fallen_companions, false, true)


func record_trap_damage(amount: float) -> void:
	stats.record_trap_damage(amount)


func build_game_over_score(squad: Array[Hero], class_levels: Dictionary[StringName, int], hud: Hud) -> RunScore:
	hud.finalize_run_stats(stats, squad, class_levels)
	var score: RunScore = RunScore.calculate(stats)
	score.commit_best_score()
	return score


static func _build_room_escapee_counts(map: Map) -> Dictionary[Rect2i, int]:
	var counts: Dictionary[Rect2i, int] = {}
	counts[map.hero_room] = map.get_starter_companion_spawn_positions().size()
	for room: Rect2i in map.plan.rooms:
		if map.plan.is_event_room(room):
			continue
		var count: int = maxi(1, map.plan.get_companion_spawns_for_room(room).size())
		if count > 0:
			counts[room] = count
	return counts

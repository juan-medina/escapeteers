# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name CorridorLootPlanner
extends RefCounted

const CORRIDOR_MIN_LOOT_LEN: int = 14
const CORRIDOR_END_MARGIN: int = 4
const CORRIDOR_LOOT_INTERVAL: int = 20
const CORRIDOR_MAX_LOOT_PER_SEG: int = 3
const CORRIDOR_LOOT_CHANCE: float = 0.28
const CORRIDOR_LONG_BONUS_CHANCE: float = 0.12
const SHORTCUT_MIN_LOOT_LEN: int = 14
const SHORTCUT_LOOT_INTERVAL: int = 22
const SHORTCUT_MAX_LOOT: int = 6
const COIN_RATIO: float = 0.60
const MIN_PICKUP_SPACING_SQ: int = 25
const SPIKE_AVOID_SQ: int = 4
const ALONG_OFFSETS: Array[int] = [0, 1, -1, 2, -2, 3, -3]


static func plan_loot(plan: WorldPlan) -> void:
	_plan_corridor_loot(plan)
	_plan_shortcut_loot(plan)


static func _plan_corridor_loot(plan: WorldPlan) -> void:
	var placed_cells: Dictionary[Vector2i, bool] = {}
	for seg: Dictionary in plan._corridor_segments:
		var is_horiz: bool = seg[&"is_horizontal"]
		var fixed_c: int = seg[&"fixed"]
		var half_w: int = seg[&"half_width"]

		var run: Vector2i = RoomLayout.get_usable_corridor_run(plan, seg)
		var best_start: int = run.x
		var best_len: int = run.y
		if best_len < CORRIDOR_MIN_LOOT_LEN:
			continue

		var usable_start: int = best_start + CORRIDOR_END_MARGIN
		var usable_end: int = best_start + best_len - 1 - CORRIDOR_END_MARGIN
		if usable_start > usable_end:
			continue

		var slot_count: int = clampi(floori(float(best_len) / float(CORRIDOR_LOOT_INTERVAL)) + 1, 1, CORRIDOR_MAX_LOOT_PER_SEG)
		var slot_chance: float = CORRIDOR_LOOT_CHANCE + (CORRIDOR_LONG_BONUS_CHANCE if best_len >= 28 else 0.0)
		var lane_offsets: Array[int] = _get_lane_offsets(is_horiz, half_w)

		for i: int in range(slot_count):
			if plan._rng.randf() > slot_chance:
				continue
			var t: float = float(i + 1) / float(slot_count + 1)
			var base_along: int = roundi(lerpf(float(usable_start), float(usable_end), t))
			var cell: Vector2i = _find_valid_corridor_loot_cell(
				plan,
				is_horiz,
				fixed_c,
				base_along,
				usable_start,
				usable_end,
				lane_offsets,
				placed_cells,
			)
			if cell.x == 2147483647:
				continue
			placed_cells[cell] = true
			if plan._rng.randf() < COIN_RATIO:
				plan.corridor_coin_cells.append(cell)
			else:
				plan.corridor_potion_spawns.append({&"cell": cell, &"type": _roll_potion_type(plan._rng)})


static func _plan_shortcut_loot(plan: WorldPlan) -> void:
	for gate: SectorGatePlanner.SectorGate in plan.sector_gates:
		if not gate.has_shortcut or gate.key_room == gate.shortcut_target_room or gate.shortcut_segments.is_empty():
			continue

		var runs: Array[Dictionary] = ShortcutTunnelPlanner.get_usable_shortcut_runs(plan, gate)
		var total_len: int = ShortcutTunnelPlanner.get_total_runs_length(runs)
		if total_len < SHORTCUT_MIN_LOOT_LEN:
			continue

		var loot_count: int = clampi(maxi(1, roundi(float(total_len) / float(SHORTCUT_LOOT_INTERVAL))), 1, SHORTCUT_MAX_LOOT)
		var placed_cells: Dictionary[Vector2i, bool] = {}

		for i: int in range(loot_count):
			var offset: int = clampi(roundi(float(i + 1) * float(total_len) / float(loot_count + 1)), 0, total_len - 1)
			var sample: Dictionary = ShortcutTunnelPlanner.sample_run_position(runs, offset)
			var seg: Dictionary = sample[&"seg"]
			var is_horiz: bool = seg[&"is_horizontal"]
			var fixed_c: int = seg[&"fixed"]
			var half_w: int = seg[&"half_width"]
			var run_start: int = sample[&"run_start"]
			var run_end: int = sample[&"run_end"]
			var base_along: int = sample[&"coord"]
			var lane_offsets: Array[int] = _get_lane_offsets(is_horiz, half_w)

			var cell: Vector2i = _find_valid_shortcut_loot_cell(
				plan,
				gate,
				is_horiz,
				fixed_c,
				base_along,
				run_start,
				run_end,
				lane_offsets,
				placed_cells,
			)
			if cell.x == 2147483647:
				continue
			placed_cells[cell] = true
			if plan._rng.randf() < COIN_RATIO:
				gate.shortcut_coin_cells.append(cell)
			else:
				gate.shortcut_potion_spawns.append({&"cell": cell, &"type": _roll_potion_type(plan._rng)})


static func _get_lane_offsets(is_horiz: bool, half_w: int) -> Array[int]:
	if is_horiz and half_w == 1:
		return [0, 1]
	if is_horiz:
		return [0, 1, -1]
	return [0, -1, 1]


static func _find_valid_corridor_loot_cell(
	plan: WorldPlan,
	is_horiz: bool,
	fixed_c: int,
	base_along: int,
	min_along: int,
	max_along: int,
	lane_offsets: Array[int],
	placed_cells: Dictionary[Vector2i, bool],
) -> Vector2i:
	for along_off: int in ALONG_OFFSETS:
		var along_c: int = clampi(base_along + along_off, min_along, max_along)
		for lane_off: int in lane_offsets:
			var cell: Vector2i = Vector2i(along_c, fixed_c + lane_off) if is_horiz else Vector2i(fixed_c + lane_off, along_c)
			if _is_valid_corridor_loot_cell(plan, cell, placed_cells):
				return cell
	return Vector2i(2147483647, 2147483647)


static func _is_valid_corridor_loot_cell(
	plan: WorldPlan,
	cell: Vector2i,
	placed_cells: Dictionary[Vector2i, bool],
) -> bool:
	if not plan.is_floor(cell) or not plan.is_floor(cell + Vector2i(0, -1)):
		return false
	if plan.get_room_at(cell) != Rect2i() or plan.hero_room.grow(4).has_point(cell):
		return false
	if plan.no_prop_cells.has(cell) or WorldPlan._intersects_any_point(cell, plan.protected_neck_rects):
		return false
	if plan.has_candle_post_near(cell, 4):
		return false
	if WorldPlan._has_cell_near(cell, plan._spike_cells, SPIKE_AVOID_SQ):
		return false
	if WorldPlan._has_cell_near(cell, placed_cells, MIN_PICKUP_SPACING_SQ):
		return false
	return true


static func _find_valid_shortcut_loot_cell(
	plan: WorldPlan,
	gate: SectorGatePlanner.SectorGate,
	is_horiz: bool,
	fixed_c: int,
	base_along: int,
	min_along: int,
	max_along: int,
	lane_offsets: Array[int],
	placed_cells: Dictionary[Vector2i, bool],
) -> Vector2i:
	for along_off: int in ALONG_OFFSETS:
		var along_c: int = clampi(base_along + along_off, min_along, max_along)
		for lane_off: int in lane_offsets:
			var cell: Vector2i = Vector2i(along_c, fixed_c + lane_off) if is_horiz else Vector2i(fixed_c + lane_off, along_c)
			if _is_valid_shortcut_loot_cell(plan, gate, cell, placed_cells):
				return cell
	return Vector2i(2147483647, 2147483647)


static func _is_valid_shortcut_loot_cell(
	plan: WorldPlan,
	gate: SectorGatePlanner.SectorGate,
	cell: Vector2i,
	placed_cells: Dictionary[Vector2i, bool],
) -> bool:
	if not ShortcutTunnelPlanner.is_shortcut_floor_cell(cell, gate) or not ShortcutTunnelPlanner.is_shortcut_floor_cell(cell + Vector2i(0, -1), gate):
		return false
	if plan.get_room_at(cell) != Rect2i() or plan.hero_room.grow(4).has_point(cell):
		return false
	if plan.is_floor(cell) or plan.no_prop_cells.has(cell) or WorldPlan._intersects_any_point(cell, plan.protected_neck_rects):
		return false
	if WorldPlan._has_cell_near(cell, plan._spike_cells, SPIKE_AVOID_SQ):
		return false
	if WorldPlan._has_cell_near(cell, placed_cells, MIN_PICKUP_SPACING_SQ):
		return false
	return true


static func _roll_potion_type(rng: RandomNumberGenerator) -> PotionPickup.PotionType:
	var roll: float = rng.randf()
	if roll < 0.35:
		return PotionPickup.PotionType.HEALTH
	if roll < 0.55:
		return PotionPickup.PotionType.HASTE
	if roll < 0.75:
		return PotionPickup.PotionType.FURY
	return PotionPickup.PotionType.XP

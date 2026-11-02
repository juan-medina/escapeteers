# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name LightManager
extends Node2D


class LightCandidate:
	var light: TorchLight
	var dist_sq: float

	func _init(p_light: TorchLight, p_dist_sq: float) -> void:
		light = p_light
		dist_sq = p_dist_sq


const MAX_ENABLED_LIGHTS: int = 36
const MAX_LIGHT_DISTANCE_SQ: float = 750.0 * 750.0
const FLICKER_SPEED: float = 8.0
const JITTER_SPEED: float = 14.0

var _all_lights: Array[TorchLight] = []
var _chunk_lights: Dictionary[Vector2i, Array] = {}
var _cell_lights: Dictionary[Vector2i, TorchLight] = {}
var _enabled_lights: Array[TorchLight] = []

var _focus_pos: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _jitter: float = 0.0
var _target_jitter: float = 0.0
var _jitter_timer: float = 0.0
var _run_seed: int = 0


func setup(run_seed: int) -> void:
	clear()
	_run_seed = run_seed


func set_focus(pos: Vector2) -> void:
	_focus_pos = pos


func add_light(chunk_coord: Vector2i, cell_pos: Vector2i, world_pos: Vector2) -> TorchLight:
	if _cell_lights.has(cell_pos):
		return _cell_lights[cell_pos]

	var torch: TorchLight = TorchLight.new()
	torch.position = world_pos
	torch.cell_pos = cell_pos
	var phase_hash: int = hash([_run_seed, cell_pos.x, cell_pos.y])
	torch.phase_offset = float(absi(phase_hash) % 6283) / 1000.0
	add_child(torch)

	if not _chunk_lights.has(chunk_coord):
		_chunk_lights[chunk_coord] = []
	_chunk_lights[chunk_coord].append(torch)
	_cell_lights[cell_pos] = torch
	_all_lights.append(torch)
	return torch


func has_light(cell_pos: Vector2i) -> bool:
	return _cell_lights.has(cell_pos)


func remove_chunk_lights(chunk_coord: Vector2i) -> void:
	if not _chunk_lights.has(chunk_coord):
		return

	var lights: Array = _chunk_lights[chunk_coord]
	for torch_var: Variant in lights:
		@warning_ignore("unsafe_cast")
		var torch: TorchLight = torch_var as TorchLight
		if torch == null or not is_instance_valid(torch):
			continue
		var enabled_idx: int = _enabled_lights.find(torch)
		if enabled_idx != -1:
			_enabled_lights.remove_at(enabled_idx)
		var all_idx: int = _all_lights.find(torch)
		if all_idx != -1:
			_all_lights.remove_at(all_idx)
		_cell_lights.erase(torch.cell_pos)
		torch.queue_free()

	_chunk_lights.erase(chunk_coord)


func clear() -> void:
	for torch: TorchLight in _all_lights:
		if is_instance_valid(torch):
			torch.queue_free()
	_all_lights.clear()
	_chunk_lights.clear()
	_cell_lights.clear()
	_enabled_lights.clear()


func get_active_light_count() -> int:
	return _enabled_lights.size()


func get_total_light_count() -> int:
	return _all_lights.size()


func _process(delta: float) -> void:
	_time += delta
	_jitter_timer -= delta
	if _jitter_timer <= 0.0:
		_jitter_timer = randf_range(0.05, 0.12)
		_target_jitter = randf_range(-0.08, 0.08)
	_jitter = lerpf(_jitter, _target_jitter, delta * JITTER_SPEED)

	_update_culling_and_flicker()


func _update_culling_and_flicker() -> void:
	var candidates: Array[LightCandidate] = []
	for torch: TorchLight in _all_lights:
		if not is_instance_valid(torch):
			continue
		var dist_sq: float = torch.global_position.distance_squared_to(_focus_pos)
		if dist_sq <= MAX_LIGHT_DISTANCE_SQ:
			candidates.append(LightCandidate.new(torch, dist_sq))

	if candidates.size() > MAX_ENABLED_LIGHTS:
		candidates.sort_custom(_compare_candidate_distance)

	var new_enabled: Array[TorchLight] = []
	var limit: int = mini(candidates.size(), MAX_ENABLED_LIGHTS)
	for i: int in range(limit):
		var torch: TorchLight = candidates[i].light
		new_enabled.append(torch)
		torch.enabled = true
		var wave: float = sin(_time * FLICKER_SPEED + torch.phase_offset) * 0.04
		torch.apply_flicker(wave, _jitter)

	for old_torch: TorchLight in _enabled_lights:
		if is_instance_valid(old_torch) and not new_enabled.has(old_torch):
			old_torch.enabled = false

	_enabled_lights = new_enabled


static func _compare_candidate_distance(a: LightCandidate, b: LightCandidate) -> bool:
	return a.dist_sq < b.dist_sq

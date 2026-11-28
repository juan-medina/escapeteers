# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

## Hold-the-zone arcane plate that charges while occupied, decays outside, resets if abandoned for another plate, and emits a shockwave on completion.
class_name RunePlate
extends Node2D

signal completed(plate: RunePlate)

enum PlateState {
	DORMANT,
	READY,
	CHARGING,
	DECAYING,
	COMPLETED,
}

const PLATE_RADIUS: float = 44.0
const CHARGE_DURATION: float = 5.5
const DECAY_RATE: float = 1.0 / 16.5
const SHOCKWAVE_RADIUS: float = 110.0
const SHOCKWAVE_KNOCKBACK: float = 280.0

const DORMANT_MODULATE: Color = Color(0.42, 0.40, 0.52, 0.72)
const READY_MODULATE: Color = Color(0.45, 0.88, 1.0, 0.95)
const CHARGING_MODULATE: Color = Color(1.0, 0.92, 0.45, 1.0)
const COMPLETED_MODULATE: Color = Color(0.50, 1.0, 0.70, 1.0)
const READY_LIGHT_COLOR: Color = Color(0.35, 0.82, 1.0, 1.0)
const COMPLETED_LIGHT_COLOR: Color = Color(0.42, 1.0, 0.65, 1.0)

var room: Rect2i = Rect2i()
var state: PlateState = PlateState.DORMANT
var progress: float = 0.0
var radius: float = PLATE_RADIUS
var charge_duration: float = CHARGE_DURATION

@onready var _ring: RuneRing = $RuneRing
@onready var _circle_root: Node2D = $RitualCircle
@onready var _particles: CPUParticles2D = $RuneParticles
@onready var _burst_particles: CPUParticles2D = $BurstParticles
@onready var _light: PointLight2D = $RuneLight


func _ready() -> void:
	_ring.radius = radius
	_ring.sync_state(state, 0.0)
	_circle_root.modulate = DORMANT_MODULATE
	_particles.emitting = false
	_light.enabled = false


func activate() -> void:
	if state != PlateState.DORMANT:
		return
	state = PlateState.READY
	progress = 0.0
	_circle_root.modulate = READY_MODULATE
	_light.color = READY_LIGHT_COLOR
	_light.energy = 0.35
	_light.enabled = true
	_particles.emitting = false
	_ring.sync_state(state, progress)


func is_point_inside(world_pos: Vector2) -> bool:
	return global_position.distance_squared_to(world_pos) <= radius * radius


func step_charge(delta: float, is_charging: bool) -> bool:
	if state == PlateState.DORMANT or state == PlateState.COMPLETED:
		return false
	if is_charging:
		state = PlateState.CHARGING
		progress = minf(1.0, progress + delta / maxf(0.1, charge_duration))
		_circle_root.modulate = READY_MODULATE.lerp(CHARGING_MODULATE, progress)
		_particles.emitting = true
		_light.energy = lerpf(0.45, 1.15, progress)
		if progress >= 1.0:
			_complete()
			return true
	else:
		progress = maxf(0.0, progress - DECAY_RATE * delta)
		state = PlateState.DECAYING if progress > 0.0 else PlateState.READY
		_circle_root.modulate = READY_MODULATE.lerp(CHARGING_MODULATE, progress)
		_particles.emitting = false
		_light.energy = 0.35
	_ring.sync_state(state, progress)
	return false


func reset_progress() -> void:
	if state == PlateState.DORMANT or state == PlateState.COMPLETED:
		return
	progress = 0.0
	state = PlateState.READY
	_particles.emitting = false
	_light.energy = 0.35
	_circle_root.modulate = READY_MODULATE
	_ring.sync_state(state, 0.0)


func _complete() -> void:
	state = PlateState.COMPLETED
	progress = 1.0
	_particles.emitting = false
	_burst_particles.restart()
	_light.color = COMPLETED_LIGHT_COLOR
	_light.energy = 0.85
	_light.enabled = true
	_circle_root.modulate = COMPLETED_MODULATE
	_ring.trigger_completed()
	Audio.play_sfx(Audio.Sfx.SECRET_TORCH)
	completed.emit(self)

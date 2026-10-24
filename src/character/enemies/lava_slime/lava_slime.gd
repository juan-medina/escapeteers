# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name LavaSlime
extends Enemy

enum AttackType {
	NONE,
	MELEE,
	RANGED_SPIKE,
}

const LAVA_SPIKE_SCENE: PackedScene = preload("res://character/enemies/lava_slime/lava_spike.tscn")
const HORIZONTAL_ALIGNMENT_TOLERANCE: float = 16.0
const _ANIM_ATTACK_MELEE: StringName = &"attack_melee"
const _ANIM_ATTACK_SPIKE: StringName = &"attack_spike"

@export var melee_range: float = 45.0
@export var melee_damage: float = 8.0

var _selected_attack: AttackType = AttackType.NONE


func _ready() -> void:
	speed = 35.0
	detection_range = 135.0
	attack_range = 135.0
	attack_cooldown = 1.5
	damage = 5.0
	super._ready()


func _can_attack_target() -> bool:
	if target == null or not is_instance_valid(target):
		_selected_attack = AttackType.NONE
		return false

	var dist: float = global_position.distance_to(target.global_position)

	# 1. Close/mid range -> always Melee attack
	if dist <= melee_range:
		_selected_attack = AttackType.MELEE
		return true

	# 2. Beyond melee range up to max range -> Ranged Spike attack if in line
	if dist <= attack_range:
		var y_diff: float = absf(target.global_position.y - global_position.y)
		if y_diff <= HORIZONTAL_ALIGNMENT_TOLERANCE and SquadNavigator.has_line_of_sight(self, target.global_position):
			_selected_attack = AttackType.RANGED_SPIKE
			return true

	_selected_attack = AttackType.NONE
	return false


func _get_attack_animation_name() -> StringName:
	if _selected_attack == AttackType.MELEE:
		return _ANIM_ATTACK_MELEE
	return _ANIM_ATTACK_SPIKE


func _perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		_selected_attack = AttackType.NONE
		return

	var dir_x: float = -1.0 if target.global_position.x < global_position.x else 1.0
	flip_h = dir_x < 0.0

	if _selected_attack == AttackType.MELEE:
		var dist: float = global_position.distance_to(target.global_position)
		if dist <= melee_range * 1.5:
			apply_melee_damage(target, melee_damage)
	elif _selected_attack == AttackType.RANGED_SPIKE:
		var spike: LavaSpike = LAVA_SPIKE_SCENE.instantiate() as LavaSpike
		spike.global_position = global_position + Vector2(dir_x * 8.0, 0.0)
		spike.direction = Vector2(dir_x, 0.0)
		spike.damage = damage
		spawn_projectile(spike)

	_selected_attack = AttackType.NONE

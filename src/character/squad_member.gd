# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name SquadMember
extends RefCounted

const RING_BASE_RADIUS: float = 28.0
const RING_LAYER_SPACING: float = 22.0
const RING_BASE_CAPACITY: int = 6
const SEPARATION_RADIUS: float = 18.0
const SEPARATION_SPEED: float = 65.0
const PLAYER_CLEARANCE_RADIUS: float = 25.0
const PLAYER_PUSH_SPEED: float = 145.0
const FOLLOW_ARRIVAL_RADIUS: float = 16.0
const FOLLOW_STOP_DISTANCE: float = 1.5
const FOLLOW_ACCELERATION: float = 520.0
const REACTION_DELAY_BASE: float = 0.12
const REACTION_DELAY_STEP: float = 0.06
const REACTION_JITTER: float = 0.05
const TRAIL_STEP_DELAY: float = 0.045
const TRAIL_LANE_SPACING: float = 5.0
const FAR_CATCHUP_DISTANCE: float = 48.0
const MIN_MOVEMENT_THRESHOLD_SQUARED: float = 0.04

var slot_index: int = 0
var slot_offset: Vector2 = Vector2.ZERO
var reaction_delay: float = REACTION_DELAY_BASE
var navigator: SquadNavigator = SquadNavigator.new()


func assign_escort_slot(new_slot_index: int, total_slots: int) -> void:
	slot_index = new_slot_index
	var remaining_index: int = slot_index
	var remaining_total: int = total_slots
	var ring: int = 0
	var ring_capacity: int = RING_BASE_CAPACITY

	while remaining_index >= ring_capacity:
		remaining_index -= ring_capacity
		remaining_total -= ring_capacity
		ring += 1
		ring_capacity = RING_BASE_CAPACITY * (ring + 1)

	var count_in_ring: int = mini(remaining_total, ring_capacity)
	var angle: float = (float(ring) * 0.55) + (TAU * float(remaining_index) / float(maxi(count_in_ring, 1)))
	var radius: float = RING_BASE_RADIUS + (float(ring) * RING_LAYER_SPACING)
	slot_offset = Vector2(cos(angle), sin(angle)) * radius

	var jitter: float = fmod(float(slot_index) * 0.6180339, 1.0) * REACTION_JITTER
	reaction_delay = REACTION_DELAY_BASE + (float(ring) * REACTION_DELAY_STEP) + jitter


func update(character: Character, delta: float, squad: Array[Character], map: Map) -> void:
	var leader: Character = character.leader
	if leader == null:
		return

	var target_pos: Vector2 = _compute_target_position(leader)
	if map != null:
		target_pos = map.clamp_to_walkable(target_pos)

	var waypoint: Vector2 = navigator.get_next_waypoint(character, target_pos, map, delta)
	var to_waypoint: Vector2 = waypoint - character.position
	var dist_to_waypoint: float = to_waypoint.length()
	var dist_to_target: float = character.position.distance_to(target_pos)

	var desired_velocity: Vector2 = Vector2.ZERO
	if dist_to_target > FOLLOW_STOP_DISTANCE and dist_to_waypoint > 0.5:
		var target_speed: float = character.speed
		if dist_to_target < FOLLOW_ARRIVAL_RADIUS:
			target_speed = character.speed * (dist_to_target / FOLLOW_ARRIVAL_RADIUS)
		elif dist_to_target > FAR_CATCHUP_DISTANCE:
			var catchup_factor: float = clampf((dist_to_target - FAR_CATCHUP_DISTANCE) / FAR_CATCHUP_DISTANCE, 0.0, 1.5)
			target_speed = character.speed * (1.5 + catchup_factor)
		else:
			target_speed = minf(character.speed * 1.5, character.speed + (dist_to_target - FOLLOW_ARRIVAL_RADIUS) * 1.5)
		desired_velocity = (to_waypoint / dist_to_waypoint) * target_speed

	var sep_scale: float = 0.4 if dist_to_target > FAR_CATCHUP_DISTANCE else 1.0
	desired_velocity += _compute_separation(character, squad) * sep_scale
	character.velocity = character.velocity.move_toward(desired_velocity, FOLLOW_ACCELERATION * delta)

	if dist_to_target <= FOLLOW_STOP_DISTANCE and desired_velocity.length_squared() < MIN_MOVEMENT_THRESHOLD_SQUARED:
		character.velocity = Vector2.ZERO

	character.move_and_slide()
	character.is_moving = character.velocity.length_squared() > 4.0
	character.update_visuals(character.velocity * delta)


func _compute_target_position(leader: Character) -> Vector2:
	var formation_pos: Vector2 = leader.position + slot_offset
	if leader.crescent_blend <= 0.001:
		return formation_pos

	var tail_delay: float = minf(0.06 + float(slot_index) * TRAIL_STEP_DELAY, 1.8)
	var trail_pos: Vector2 = leader.get_delayed_position(tail_delay)

	var perp: Vector2 = Vector2(-leader.move_direction.y, leader.move_direction.x)
	var lane: float = float((slot_index % 3) - 1)
	var trail_target: Vector2 = trail_pos + perp * (lane * TRAIL_LANE_SPACING)

	return formation_pos.lerp(trail_target, leader.crescent_blend)


func _compute_separation(character: Character, squad: Array[Character]) -> Vector2:
	var push: Vector2 = Vector2.ZERO
	var min_dist_sq: float = SEPARATION_RADIUS * SEPARATION_RADIUS
	var player_dist_sq: float = PLAYER_CLEARANCE_RADIUS * PLAYER_CLEARANCE_RADIUS

	for other: Character in squad:
		if other == character:
			continue
		var diff: Vector2 = character.position - other.position
		var dist_sq: float = diff.length_squared()

		if other.is_player:
			if dist_sq > 0.0001 and dist_sq < player_dist_sq:
				var dist: float = sqrt(dist_sq)
				var strength: float = (PLAYER_CLEARANCE_RADIUS - dist) / PLAYER_CLEARANCE_RADIUS
				var push_dir: Vector2 = diff / dist
				if other.is_moving and push_dir.dot(other.move_direction) > 0.7:
					var perp: Vector2 = Vector2(-other.move_direction.y, other.move_direction.x)
					if push_dir.dot(perp) < 0.0:
						perp = -perp
					push_dir = (push_dir + perp * 1.2).normalized()
				push += push_dir * (PLAYER_PUSH_SPEED * strength)
		elif dist_sq > 0.0001 and dist_sq < min_dist_sq:
			var dist: float = sqrt(dist_sq)
			var strength: float = (SEPARATION_RADIUS - dist) / SEPARATION_RADIUS
			push += (diff / dist) * (SEPARATION_SPEED * strength)

	return push

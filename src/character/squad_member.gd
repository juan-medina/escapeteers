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
var slot_radius: float = RING_BASE_RADIUS
var slot_angle_offset: float = 0.0
var reaction_delay: float = REACTION_DELAY_BASE
var navigator: SquadNavigator = SquadNavigator.new()


func assign_formation_slot(ring: int, angle_offset: float, new_slot_index: int, _is_frontline: bool) -> void:
	slot_index = new_slot_index
	slot_angle_offset = angle_offset
	slot_radius = RING_BASE_RADIUS + (float(ring) * RING_LAYER_SPACING)
	slot_offset = Vector2(cos(slot_angle_offset), sin(slot_angle_offset)) * slot_radius

	var jitter: float = fmod(float(slot_index) * 0.6180339, 1.0) * REACTION_JITTER
	reaction_delay = REACTION_DELAY_BASE + (float(ring) * REACTION_DELAY_STEP) + jitter


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
	var angle_step: float = TAU / float(maxi(count_in_ring, 1))
	var ring_stagger: float = float(ring) * 0.55

	var angle_offset: float = ring_stagger
	if remaining_index > 0:
		var pair: int = int(float(remaining_index + 1) / 2.0)
		var sign_val: float = 1.0 if (remaining_index % 2 == 1) else -1.0
		angle_offset = ring_stagger + (sign_val * float(pair) * angle_step)

	assign_formation_slot(ring, angle_offset, slot_index, false)


func get_formation_position(leader: Hero) -> Vector2:
	return _compute_target_position(leader)


func update(hero: Hero, delta: float, squad: Array[Hero], map: Map) -> void:
	var leader: Hero = hero.leader
	if leader == null or leader.is_dead or hero.is_dead:
		hero.velocity = Vector2.ZERO
		hero.update_visuals(Vector2.ZERO)
		return

	var formation_pos: Vector2 = _compute_target_position(leader)
	if map != null:
		formation_pos = map.clamp_to_walkable(formation_pos)

	var move_dest: Vector2 = formation_pos
	var current_leash: float = hero.get_current_leash()
	var dist_from_slot: float = hero.position.distance_to(formation_pos)

	var target_valid: bool = (
		hero.can_melee
		and current_leash > 0.0
		and hero.active_target is Enemy
		and is_instance_valid(hero.active_target)
		and hero.active_target.health > 0.0
		and formation_pos.distance_to(hero.active_target.global_position) <= current_leash
	)

	if target_valid:
		if dist_from_slot > current_leash:
			hero.movement_state = Character.MovementState.FALL_BACK
			move_dest = formation_pos
		else:
			var target_pos: Vector2 = hero.active_target.global_position
			if hero.can_reach_target(hero.active_target):
				hero.movement_state = Character.MovementState.IDLE
				move_dest = hero.position
				if not hero.is_attacking:
					var diff_x: float = target_pos.x - hero.global_position.x
					if absf(diff_x) > 1.0:
						hero.flip_h = diff_x < 0.0
			else:
				hero.movement_state = Character.MovementState.NAVIGATING
				move_dest = target_pos
	else:
		if hero.active_target != null and (not is_instance_valid(hero.active_target) or hero.active_target.health <= 0.0):
			hero.active_target = null
		if dist_from_slot > FOLLOW_STOP_DISTANCE:
			hero.movement_state = Character.MovementState.NAVIGATING
			move_dest = formation_pos
		else:
			hero.movement_state = Character.MovementState.IDLE
			move_dest = hero.position

	var waypoint: Vector2 = navigator.get_next_waypoint(hero, move_dest, map, delta)
	var to_waypoint: Vector2 = waypoint - hero.position
	var dist_to_waypoint: float = to_waypoint.length()
	var dist_to_dest: float = hero.position.distance_to(move_dest)

	var desired_velocity: Vector2 = Vector2.ZERO
	if dist_to_dest > FOLLOW_STOP_DISTANCE and dist_to_waypoint > 0.5:
		var target_speed: float = hero.speed
		if dist_to_dest < FOLLOW_ARRIVAL_RADIUS:
			target_speed = hero.speed * (dist_to_dest / FOLLOW_ARRIVAL_RADIUS)
		elif dist_to_dest > FAR_CATCHUP_DISTANCE:
			var catchup_factor: float = clampf((dist_to_dest - FAR_CATCHUP_DISTANCE) / FAR_CATCHUP_DISTANCE, 0.0, 1.5)
			target_speed = hero.speed * (1.5 + catchup_factor)
		else:
			target_speed = minf(hero.speed * 1.5, hero.speed + (dist_to_dest - FOLLOW_ARRIVAL_RADIUS) * 1.5)
		desired_velocity = (to_waypoint / dist_to_waypoint) * target_speed

	var sep_scale: float = 0.4 if dist_to_dest > FAR_CATCHUP_DISTANCE else 1.0
	desired_velocity += _compute_separation(hero, squad) * sep_scale
	hero.velocity = hero.velocity.move_toward(desired_velocity, FOLLOW_ACCELERATION * delta)

	if dist_to_dest <= FOLLOW_STOP_DISTANCE and desired_velocity.length_squared() < MIN_MOVEMENT_THRESHOLD_SQUARED:
		hero.velocity = Vector2.ZERO

	hero.move_and_slide()
	hero.is_moving = hero.velocity.length_squared() > 4.0
	hero.update_visuals(hero.velocity * delta)


func _compute_target_position(leader: Hero) -> Vector2:
	var forward_dir: Vector2 = leader.move_direction if leader.move_direction != Vector2.ZERO else Vector2.RIGHT
	var forward_angle: float = forward_dir.angle()
	var current_angle: float = forward_angle + slot_angle_offset
	var formation_pos: Vector2 = leader.position + Vector2(cos(current_angle), sin(current_angle)) * slot_radius

	if leader.crescent_blend <= 0.001:
		return formation_pos

	var tail_delay: float = minf(0.06 + float(slot_index) * TRAIL_STEP_DELAY, 1.8)
	var trail_pos: Vector2 = leader.get_delayed_position(tail_delay)

	var perp: Vector2 = Vector2(-leader.move_direction.y, leader.move_direction.x)
	var lane: float = float((slot_index % 3) - 1)
	var trail_target: Vector2 = trail_pos + perp * (lane * TRAIL_LANE_SPACING)

	var blend_factor: float = leader.crescent_blend
	var normalized_angle: float = absf(wrapf(slot_angle_offset, -PI, PI))
	if normalized_angle < (PI * 0.5):
		blend_factor *= 0.35

	return formation_pos.lerp(trail_target, blend_factor)


func _compute_separation(hero: Hero, squad: Array[Hero]) -> Vector2:
	var push: Vector2 = Vector2.ZERO
	var min_dist_sq: float = SEPARATION_RADIUS * SEPARATION_RADIUS
	var player_dist_sq: float = PLAYER_CLEARANCE_RADIUS * PLAYER_CLEARANCE_RADIUS

	for other: Hero in squad:
		if other == hero:
			continue
		var diff: Vector2 = hero.position - other.position
		var dist_sq: float = diff.length_squared()

		if other.is_player:
			if hero.active_target != null and is_instance_valid(hero.active_target) and hero.active_target.health > 0.0:
				continue
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

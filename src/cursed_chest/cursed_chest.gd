# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

## Small cursed bait chest placed in special event rooms; triggers the room and unlocks loot on clear.
class_name CursedChest
extends Node2D

enum ChestState {
	WAITING,
	ACTIVE,
	READY_TO_LOOT,
	LOOTED,
}

const TRIGGER_DISTANCE: float = 18.0
const LOOT_READY_DELAY: float = 0.45
const FADE_DELAY: float = 2.0
const FADE_DURATION: float = 0.6
const BASE_SPRITE_Y: float = -4.0
const BOB_AMPLITUDE: float = 1.2
const BOB_SPEED: float = 3.2
const CURSED_RING_COLOR: Color = Color(0.75, 0.25, 1.0, 0.85)
const ACTIVE_RING_COLOR: Color = Color(0.85, 0.22, 0.28, 0.45)
const REWARD_RING_COLOR: Color = Color(1.0, 0.85, 0.25, 0.90)
const LOOTED_RING_COLOR: Color = Color(0.35, 0.25, 0.45, 0.30)
const CURSED_PARTICLE_COLOR: Color = Color(0.75, 0.30, 1.0, 0.85)
const REWARD_PARTICLE_COLOR: Color = Color(1.0, 0.86, 0.30, 0.90)

var room: Rect2i = Rect2i()
var state: ChestState = ChestState.WAITING

var _bob_elapsed: float = 0.0
var _loot_delay_timer: float = 0.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _indicator: GroundIndicator = $GroundIndicator
@onready var _particles: CPUParticles2D = $CursedParticles


func _ready() -> void:
	_sprite.play(&"closed")
	_indicator.custom_ring_color = CURSED_RING_COLOR
	_particles.color = CURSED_PARTICLE_COLOR
	_particles.emitting = true


func _process(delta: float) -> void:
	if _loot_delay_timer > 0.0:
		_loot_delay_timer = maxf(0.0, _loot_delay_timer - delta)
	if state != ChestState.WAITING and state != ChestState.READY_TO_LOOT:
		return
	_bob_elapsed += delta
	_sprite.position.y = BASE_SPRITE_Y + sin(_bob_elapsed * BOB_SPEED) * BOB_AMPLITUDE


## Activates the cursed trap while keeping the chest sealed during combat.
func activate() -> void:
	if state != ChestState.WAITING:
		return
	state = ChestState.ACTIVE
	_sprite.position.y = BASE_SPRITE_Y
	_particles.emitting = false
	_indicator.custom_ring_color = ACTIVE_RING_COLOR
	_play_pop_tween()


## Opens the chest to reveal its gold reward after the event room is cleared.
func unlock_reward() -> void:
	if state == ChestState.READY_TO_LOOT or state == ChestState.LOOTED:
		return
	state = ChestState.READY_TO_LOOT
	_loot_delay_timer = LOOT_READY_DELAY
	_sprite.position.y = BASE_SPRITE_Y
	_sprite.play(&"open_gold")
	_particles.color = REWARD_PARTICLE_COLOR
	_particles.emitting = true
	_indicator.custom_ring_color = REWARD_RING_COLOR
	_play_pop_tween()


## Returns true when the opened chest is ready to dispense loot on touch.
func can_claim_reward() -> bool:
	return state == ChestState.READY_TO_LOOT and _loot_delay_timer <= 0.0


## Empties the chest once its reward loot has been popped out.
func claim_reward() -> void:
	if state != ChestState.READY_TO_LOOT:
		return
	state = ChestState.LOOTED
	_sprite.position.y = BASE_SPRITE_Y
	_sprite.play(&"open_empty")
	_particles.emitting = false
	_indicator.custom_ring_color = LOOTED_RING_COLOR
	_play_pop_tween()
	var fade: Tween = create_tween()
	fade.tween_interval(FADE_DELAY)
	fade.tween_property(self, ^"modulate:a", 0.0, FADE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fade.tween_callback(queue_free)


func _play_pop_tween() -> void:
	scale = Vector2(1.25, 0.80)
	var tween: Tween = create_tween()
	tween.tween_property(self, ^"scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name PotionPickup
extends Node2D

enum PotionType {
	HEALTH,
	HASTE,
	FURY,
	XP,
}

const PICKUP_DISTANCE: float = 18.0
const BASE_SPRITE_Y: float = -3.0
const BOB_AMPLITUDE: float = 1.5
const BOB_SPEED: float = 4.0

const HEALTH_TICK_COUNT: int = 4
const HEALTH_TICK_RATIO: float = 0.10
const HEALTH_TICK_INTERVAL: float = 0.50
const HASTE_DURATION: float = 12.0
const HASTE_SPEED_MULTIPLIER: float = 1.40
const HASTE_ATTACK_SPEED_MULTIPLIER: float = 1.30
const FURY_DURATION: float = 12.0
const FURY_DAMAGE_MULTIPLIER: float = 1.35
const XP_LEVEL_RATIO: float = 0.35
const XP_START_DELAY: float = 0.25
const XP_TICK_COUNT: int = 5
const XP_TICK_INTERVAL: float = 0.22

var potion_type: PotionType = PotionType.HEALTH

var _bob_elapsed: float = 0.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _indicator: GroundIndicator = $GroundIndicator


func _ready() -> void:
	_apply_visuals()


func _process(delta: float) -> void:
	_bob_elapsed += delta
	_sprite.position.y = BASE_SPRITE_Y + sin(_bob_elapsed * BOB_SPEED) * BOB_AMPLITUDE


func setup(type: PotionType) -> void:
	potion_type = type
	if is_node_ready():
		_apply_visuals()


static func get_toast_text(type: PotionType) -> String:
	match type:
		PotionType.HASTE:
			return "Speed Potion - Squad Haste!"
		PotionType.FURY:
			return "Fury Potion - Bonus Damage!"
		PotionType.XP:
			return "XP Elixir - Bonus Experience!"
		_:
			return "Health Potion - Squad Healed!"


static func get_display_color(type: PotionType) -> Color:
	match type:
		PotionType.HASTE:
			return Color(0.35, 0.85, 1.0, 1.0)
		PotionType.FURY:
			return Color(1.0, 0.84, 0.28, 1.0)
		PotionType.XP:
			return Color(0.82, 0.48, 1.0, 1.0)
		_:
			return Color(1.0, 0.38, 0.42, 1.0)


static func get_ring_color(type: PotionType) -> Color:
	var c: Color = get_display_color(type)
	return Color(c.r, c.g, c.b, 0.75)


static func get_codex_id(type: PotionType) -> StringName:
	match type:
		PotionType.HASTE:
			return &"potion_haste"
		PotionType.FURY:
			return &"potion_fury"
		PotionType.XP:
			return &"potion_xp"
		_:
			return &"potion_health"


func _apply_visuals() -> void:
	var anim_name: StringName = &"health"
	match potion_type:
		PotionType.HASTE:
			anim_name = &"haste"
		PotionType.FURY:
			anim_name = &"fury"
		PotionType.XP:
			anim_name = &"xp"
	_sprite.play(anim_name)
	_indicator.custom_ring_color = get_ring_color(potion_type)

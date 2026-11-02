# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Unknown
extends Character

@onready var _ground_indicator: GroundIndicator = get_node_or_null(^"GroundIndicator") as GroundIndicator


func _ready() -> void:
	super._ready()
	set_process(false)
	set_physics_process(false)
	disable_collisions()
	if _health_bar != null:
		_health_bar.visible = false
	if _ground_indicator != null:
		_ground_indicator.is_recruited = false
		_ground_indicator.is_player = false

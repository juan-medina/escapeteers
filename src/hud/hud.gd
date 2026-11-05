# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Hud
extends CanvasLayer

const FILL_SPEED: float = 60.0

var _current_level: int = 1
var _target_xp: float = 0.0
var _display_xp: float = 0.0
var _display_max_xp: float = 50.0

@onready var damage_meter: DamageMeter = $DamageMeter
@onready var squad_grid: SquadGrid = $SquadGrid
@onready var map_overlay: MapOverlay = $MapOverlay
@onready var _level_badge: Label = $Margin/HBox/LevelBadge
@onready var _xp_bar: ProgressBar = $Margin/HBox/XPBar
@onready var _xp_text: Label = $Margin/HBox/XPText
@onready var _map_hint: Label = $MapHint


func _ready() -> void:
	set_process(false)
	InputManager.device_changed.connect(_on_device_changed)
	_update_map_prompt(InputManager.current_device)


func _process(delta: float) -> void:
	if _xp_bar.max_value != _display_max_xp:
		_xp_bar.max_value = _display_max_xp

	var diff: float = _target_xp - _display_xp
	if absf(diff) < 0.2:
		_display_xp = _target_xp
		set_process(false)
	else:
		var step: float = maxf(FILL_SPEED * delta, absf(diff) * 8.0 * delta)
		if diff > 0.0:
			_display_xp = minf(_target_xp, _display_xp + step)
		else:
			_display_xp = maxf(_target_xp, _display_xp - step)

	_xp_bar.value = _display_xp
	_xp_text.text = "%d / %d" % [int(_display_xp), int(_display_max_xp)]


func update_xp(current_xp: float, xp_required: float, squad_level: int) -> void:
	_level_badge.text = "Lv. %d" % squad_level

	if squad_level > _current_level:
		_current_level = squad_level
		_display_xp = 0.0
		_display_max_xp = xp_required
		_target_xp = current_xp
		_xp_bar.max_value = _display_max_xp
		_xp_bar.value = 0.0
	else:
		_target_xp = current_xp
		_display_max_xp = xp_required

	set_process(true)


func setup_map(plan: WorldPlan, target: Hero) -> void:
	if map_overlay != null:
		map_overlay.setup(plan, target)


func _on_device_changed(device: InputManager.DeviceType) -> void:
	_update_map_prompt(device)


func _update_map_prompt(device: InputManager.DeviceType) -> void:
	if _map_hint == null:
		return
	match device:
		InputManager.DeviceType.XBOX:
			_map_hint.text = "Press VIEW / BACK for map"
		InputManager.DeviceType.PLAYSTATION:
			_map_hint.text = "Press SHARE / SELECT for map"
		InputManager.DeviceType.GENERIC_GAMEPAD:
			_map_hint.text = "Press SELECT / BACK for map"
		_:
			_map_hint.text = "Press TAB / M for map"

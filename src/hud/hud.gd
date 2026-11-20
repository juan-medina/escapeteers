# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Hud
extends CanvasLayer

const FILL_SPEED: float = 60.0
const HINT_AUTO_DISMISS_DELAY: float = 8.0
const HINT_FADE_DURATION: float = 0.8
const ROOM_TOAST_FADE_IN: float = 0.18
const ROOM_TOAST_HOLD: float = 2.0
const ROOM_TOAST_FADE_OUT: float = 0.45
const KEY_COLLECTED_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const KEY_USED_COLOR: Color = Color(0.45, 0.48, 0.52, 0.20)

var _current_level: int = 1
var _target_xp: float = 0.0
var _display_xp: float = 0.0
var _display_max_xp: float = 50.0
var _movement_hint_dismissed: bool = false
var _room_toast_tween: Tween = null

@onready var _damage_meter: DamageMeter = $DamageMeter
@onready var _squad_grid: SquadGrid = $SquadGrid
@onready var _map_overlay: MapOverlay = $MapOverlay
@onready var _level_badge: Label = $Margin/HBox/LevelBadge
@onready var _xp_bar: ProgressBar = $Margin/HBox/XPBar
@onready var _xp_text: Label = $Margin/HBox/XPText
@onready var _map_hint: Label = $MapHint
@onready var _movement_hint: Label = $MovementHint
@onready var _room_toast: PanelContainer = $RoomToast
@onready var _room_toast_label: Label = $RoomToast/Label
@onready var _key_icons: Array[TextureRect] = [
	$Margin/HBox/KeyBar/BlueKey,
	$Margin/HBox/KeyBar/GreenKey,
	$Margin/HBox/KeyBar/YellowKey,
	$Margin/HBox/KeyBar/RedKey,
]
@onready var _door_edge_indicators: Array[Node2D] = [
	$EdgeIndicators/BlueDoorIndicator,
	$EdgeIndicators/GreenDoorIndicator,
	$EdgeIndicators/YellowDoorIndicator,
	$EdgeIndicators/RedDoorIndicator,
]
@onready var _door_edge_arrows: Array[Node2D] = [
	$EdgeIndicators/BlueDoorIndicator/Arrow,
	$EdgeIndicators/GreenDoorIndicator/Arrow,
	$EdgeIndicators/YellowDoorIndicator/Arrow,
	$EdgeIndicators/RedDoorIndicator/Arrow,
]
@onready var _key_edge_indicators: Array[Node2D] = [
	$EdgeIndicators/BlueKeyIndicator,
	$EdgeIndicators/GreenKeyIndicator,
	$EdgeIndicators/YellowKeyIndicator,
	$EdgeIndicators/RedKeyIndicator,
]
@onready var _key_edge_arrows: Array[Node2D] = [
	$EdgeIndicators/BlueKeyIndicator/Arrow,
	$EdgeIndicators/GreenKeyIndicator/Arrow,
	$EdgeIndicators/YellowKeyIndicator/Arrow,
	$EdgeIndicators/RedKeyIndicator/Arrow,
]


func _ready() -> void:
	set_process(false)
	_map_overlay.set_hud_edge_indicators(_door_edge_indicators, _door_edge_arrows, _key_edge_indicators, _key_edge_arrows)
	InputManager.input_mode_changed.connect(_on_input_mode_changed)
	_update_map_prompt(InputManager.current_mode)
	var hint_timer: SceneTreeTimer = get_tree().create_timer(HINT_AUTO_DISMISS_DELAY)
	hint_timer.timeout.connect(dismiss_movement_hint)


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
	_xp_text.text = &"%d / %d" % [int(_display_xp), int(_display_max_xp)]


func update_xp(current_xp: float, xp_required: float, squad_level: int) -> void:
	_level_badge.text = &"Lv. %d" % squad_level
	_map_overlay.set_squad_level(squad_level)

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


func update_squad(squad: Array[Hero]) -> void:
	_damage_meter.update_squad(squad)
	_squad_grid.update_squad(squad)


func record_damage(class_id: StringName, amount: float) -> void:
	_damage_meter.record_damage(class_id, amount)


func setup_map(plan: WorldPlan, target: Hero) -> void:
	_reset_keys()
	_map_overlay.setup(plan, target)


func set_key_state(color: WorldPlan.KeyColor, collected: bool, used: bool) -> void:
	var idx: int = int(color)
	if idx >= 0 and idx < _key_icons.size():
		_key_icons[idx].visible = collected or used
		_key_icons[idx].modulate = KEY_USED_COLOR if used else KEY_COLLECTED_COLOR
	_map_overlay.set_key_state(color, collected, used)


func notify_shortcut_opened(color: WorldPlan.KeyColor) -> void:
	_map_overlay.notify_shortcut_opened(color)
	show_event_toast(&"Shortcut Opened!", Color(0.95, 0.90, 0.45, 1.0))


func show_event_toast(title: String, color: Color) -> void:
	_show_toast(title, color)


func notify_room_entered(room: Rect2i, title: String, is_cleared: bool) -> void:
	_map_overlay.mark_room_discovered(room)
	_map_overlay.set_room_cleared(room, is_cleared)

	var color: Color = _map_overlay.get_room_color(room)
	color.a = 1.0
	_show_toast(title, color)


func _reset_keys() -> void:
	for icon: TextureRect in _key_icons:
		icon.visible = false
		icon.modulate = KEY_COLLECTED_COLOR


func _show_toast(title: String, color: Color) -> void:
	_room_toast_label.text = title
	_room_toast_label.add_theme_color_override(&"font_color", color)

	if _room_toast_tween != null and _room_toast_tween.is_valid():
		_room_toast_tween.kill()
	_room_toast.modulate.a = 0.0
	_room_toast.visible = true
	_room_toast_tween = create_tween()
	_room_toast_tween.tween_property(_room_toast, ^"modulate:a", 1.0, ROOM_TOAST_FADE_IN)
	_room_toast_tween.tween_interval(ROOM_TOAST_HOLD)
	_room_toast_tween.tween_property(_room_toast, ^"modulate:a", 0.0, ROOM_TOAST_FADE_OUT)
	_room_toast_tween.tween_callback(_room_toast.hide)


func set_room_cleared(room: Rect2i, is_cleared: bool) -> void:
	_map_overlay.set_room_cleared(room, is_cleared)


func dismiss_movement_hint() -> void:
	if _movement_hint_dismissed:
		return
	_movement_hint_dismissed = true
	var tween: Tween = create_tween()
	tween.tween_property(_movement_hint, ^"modulate:a", 0.0, HINT_FADE_DURATION)
	tween.tween_callback(_movement_hint.hide)


func _on_input_mode_changed(mode: InputManager.InputMode) -> void:
	_update_map_prompt(mode)


func _update_map_prompt(mode: InputManager.InputMode) -> void:
	match mode:
		InputManager.InputMode.XBOX:
			_map_hint.text = &"Press VIEW / BACK for map"
		InputManager.InputMode.PLAYSTATION:
			_map_hint.text = &"Press SHARE / SELECT for map"
		InputManager.InputMode.GENERIC_GAMEPAD:
			_map_hint.text = &"Press SELECT / BACK for map"
		_:
			_map_hint.text = &"Press TAB / M for map"

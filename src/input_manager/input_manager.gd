# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

extends Node

signal input_mode_changed(mode: InputMode)

enum InputMode {
	KEYBOARD_AND_MOUSE,
	XBOX,
	PLAYSTATION,
	GENERIC_GAMEPAD,
}

const CURSOR_HIDE_DELAY: float = 2.5
const CURSOR_TIMER_RESTART_THRESHOLD: float = CURSOR_HIDE_DELAY - 0.1
const STICK_DEADZONE: float = 0.2
const MOUSE_WAKE_DIST_SQ: float = 4.0
const POINTER_DEADZONE: float = 12.0
const POINTER_MAX_DISTANCE: float = 64.0
const PLAYSTATION_KEYWORDS: Array[String] = ["ps5", "ps4", "playstation", "dualshock", "dualsense"]
const XBOX_KEYWORDS: Array[String] = ["xbox", "xinput"]

var current_mode: InputMode = InputMode.KEYBOARD_AND_MOUSE

var _notifications_enabled: bool = false
var _cursor_hide_timer: Timer = null
var _is_pointer_steering: bool = false
var _is_touch_steering: bool = false
var _pointer_screen_pos: Vector2 = Vector2.ZERO
var _connected_joypads: Array[int] = []
var _joypad_modes: Dictionary[int, InputMode] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cursor_hide_timer = Timer.new()
	_cursor_hide_timer.wait_time = CURSOR_HIDE_DELAY
	_cursor_hide_timer.one_shot = true
	_cursor_hide_timer.timeout.connect(_on_cursor_hide_timer_timeout)
	add_child(_cursor_hide_timer)

	Input.joy_connection_changed.connect(_on_joy_connection_changed)

	_hide_cursor()
	_refresh_connected_joypads()
	if not _connected_joypads.is_empty():
		_set_input_mode(_get_joypad_mode(_connected_joypads[0]))
	else:
		_set_input_mode(InputMode.KEYBOARD_AND_MOUSE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_stop_pointer_steering()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if motion.relative.length_squared() >= MOUSE_WAKE_DIST_SQ:
			_show_cursor()
			_set_input_mode(InputMode.KEYBOARD_AND_MOUSE)
	elif event is InputEventJoypadMotion:
		var joy_motion: InputEventJoypadMotion = event as InputEventJoypadMotion
		if absf(joy_motion.axis_value) >= STICK_DEADZONE:
			_hide_cursor()
			_set_input_mode(_get_joypad_mode(joy_motion.device))
	elif event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.is_pressed() and not key.is_echo():
			if not _is_pointer_steering:
				_hide_cursor()
			_set_input_mode(InputMode.KEYBOARD_AND_MOUSE)
	elif event is InputEventMouseButton:
		var mouse_btn: InputEventMouseButton = event as InputEventMouseButton
		if mouse_btn.button_index == MOUSE_BUTTON_LEFT and not mouse_btn.is_pressed():
			_is_pointer_steering = false
		elif mouse_btn.is_pressed():
			_show_cursor()
			_set_input_mode(InputMode.KEYBOARD_AND_MOUSE)
	elif event is InputEventJoypadButton:
		var joy_btn: InputEventJoypadButton = event as InputEventJoypadButton
		if joy_btn.is_pressed():
			_hide_cursor()
			_set_input_mode(_get_joypad_mode(joy_btn.device))
	elif event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if not touch.is_pressed():
			_stop_pointer_steering()
		else:
			_hide_cursor()
			_set_input_mode(InputMode.KEYBOARD_AND_MOUSE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_btn: InputEventMouseButton = event as InputEventMouseButton
		if mouse_btn.button_index == MOUSE_BUTTON_LEFT and mouse_btn.is_pressed():
			_is_pointer_steering = true
			_is_touch_steering = false
			_pointer_screen_pos = mouse_btn.position
	elif event is InputEventMouseMotion:
		if _is_pointer_steering and not _is_touch_steering:
			var motion: InputEventMouseMotion = event as InputEventMouseMotion
			_pointer_screen_pos = motion.position
	elif event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.is_pressed():
			_is_pointer_steering = true
			_is_touch_steering = true
			_pointer_screen_pos = touch.position
		else:
			_stop_pointer_steering()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		_is_pointer_steering = true
		_is_touch_steering = true
		_pointer_screen_pos = drag.position


func enable_notifications() -> void:
	if _notifications_enabled:
		return
	_notifications_enabled = true
	if not _connected_joypads.is_empty():
		Alerts.controller_detected()


func get_movement_vector(origin_screen_pos: Vector2 = Vector2.ZERO) -> Vector2:
	var joypad: Vector2 = _get_stick_movement()
	if joypad != Vector2.ZERO:
		return joypad

	var actions: Vector2 = Input.get_vector(&"left", &"right", &"up", &"down")
	if actions != Vector2.ZERO:
		return actions

	return _get_pointer_movement(origin_screen_pos)


func _get_stick_movement() -> Vector2:
	for pad: int in _connected_joypads:
		var raw_stick: Vector2 = Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
		var mag: float = raw_stick.length()
		if mag >= STICK_DEADZONE:
			var scaled_mag: float = clampf((mag - STICK_DEADZONE) / (1.0 - STICK_DEADZONE), 0.0, 1.0)
			return raw_stick.normalized() * scaled_mag
	return Vector2.ZERO


func _get_pointer_movement(origin_screen_pos: Vector2) -> Vector2:
	if not _is_pointer_steering:
		return Vector2.ZERO

	if not _is_touch_steering and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_is_pointer_steering = false
		return Vector2.ZERO

	var viewport: Viewport = get_viewport()
	var target_pos: Vector2 = _pointer_screen_pos
	if not _is_touch_steering:
		target_pos = viewport.get_mouse_position()
		_pointer_screen_pos = target_pos

	var origin: Vector2 = origin_screen_pos if origin_screen_pos != Vector2.ZERO else viewport.get_visible_rect().size * 0.5
	var diff: Vector2 = target_pos - origin
	var dist: float = diff.length()
	if dist < POINTER_DEADZONE:
		return Vector2.ZERO

	var scaled: float = clampf((dist - POINTER_DEADZONE) / (POINTER_MAX_DISTANCE - POINTER_DEADZONE), 0.0, 1.0)
	return diff.normalized() * scaled


func _stop_pointer_steering() -> void:
	_is_pointer_steering = false
	_is_touch_steering = false


func _show_cursor() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _cursor_hide_timer.is_stopped() or _cursor_hide_timer.time_left < CURSOR_TIMER_RESTART_THRESHOLD:
		_cursor_hide_timer.start()


func _hide_cursor() -> void:
	if not _cursor_hide_timer.is_stopped():
		_cursor_hide_timer.stop()
	if Input.mouse_mode != Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _set_input_mode(mode: InputMode) -> void:
	if current_mode == mode:
		return
	current_mode = mode
	input_mode_changed.emit(current_mode)


func _refresh_connected_joypads() -> void:
	_connected_joypads = Input.get_connected_joypads()
	_joypad_modes.clear()
	for joypad_id: int in _connected_joypads:
		_joypad_modes[joypad_id] = _detect_joypad_mode(joypad_id)


func _get_joypad_mode(joypad_id: int) -> InputMode:
	if _joypad_modes.has(joypad_id):
		return _joypad_modes[joypad_id]
	return InputMode.GENERIC_GAMEPAD


func _detect_joypad_mode(joypad_id: int) -> InputMode:
	var joy_name: String = Input.get_joy_name(joypad_id).to_lower()
	for keyword: String in PLAYSTATION_KEYWORDS:
		if joy_name.contains(keyword):
			return InputMode.PLAYSTATION
	for keyword: String in XBOX_KEYWORDS:
		if joy_name.contains(keyword):
			return InputMode.XBOX
	return InputMode.GENERIC_GAMEPAD


func _on_cursor_hide_timer_timeout() -> void:
	if _is_pointer_steering and not _is_touch_steering:
		_cursor_hide_timer.start()
		return
	_hide_cursor()


func _on_joy_connection_changed(joypad_id: int, connected: bool) -> void:
	_refresh_connected_joypads()
	if connected:
		_set_input_mode(_get_joypad_mode(joypad_id))
	elif _connected_joypads.is_empty():
		_set_input_mode(InputMode.KEYBOARD_AND_MOUSE)

	if not _notifications_enabled:
		return
	if connected:
		Alerts.controller_connected()
	else:
		Alerts.controller_disconnected()

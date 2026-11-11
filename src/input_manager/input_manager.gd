# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

extends Node

signal device_changed(device: DeviceType)

enum DeviceType {
	KEYBOARD_AND_MOUSE,
	XBOX,
	PLAYSTATION,
	GENERIC_GAMEPAD,
}

const MOUSE_HIDE_TIME: float = 2.5
const DEFAULT_DEADZONE: float = 0.2
const MOUSE_MOVE_THRESHOLD_SQ: float = 4.0
const POINTER_DEADZONE: float = 12.0
const POINTER_MAX_RANGE: float = 64.0

var current_device: DeviceType = DeviceType.KEYBOARD_AND_MOUSE
var _notifications_enabled: bool = false
var _mouse_hide_timer: Timer = null
var _pointer_active: bool = false
var _touch_active: bool = false
var _pointer_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mouse_hide_timer = Timer.new()
	_mouse_hide_timer.wait_time = MOUSE_HIDE_TIME
	_mouse_hide_timer.one_shot = true
	_mouse_hide_timer.timeout.connect(_on_mouse_hide_timer_timeout)
	add_child(_mouse_hide_timer)

	Input.joy_connection_changed.connect(_on_joy_connection_changed)

	var joypads: Array[int] = Input.get_connected_joypads()
	if not joypads.is_empty():
		_set_device(_detect_joypad_device(joypads[0]))
	else:
		_set_device(DeviceType.KEYBOARD_AND_MOUSE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_pointer_active = false
		_touch_active = false


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if motion.relative.length_squared() >= MOUSE_MOVE_THRESHOLD_SQ:
			_set_device(DeviceType.KEYBOARD_AND_MOUSE)
	elif event is InputEventMouseButton:
		var mouse_btn: InputEventMouseButton = event as InputEventMouseButton
		if mouse_btn.button_index == MOUSE_BUTTON_LEFT and not mouse_btn.is_pressed():
			_pointer_active = false
		elif mouse_btn.is_pressed():
			_set_device(DeviceType.KEYBOARD_AND_MOUSE)
	elif event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if not touch.is_pressed():
			_pointer_active = false
			_touch_active = false
		else:
			_set_device(DeviceType.KEYBOARD_AND_MOUSE)
	elif event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.is_pressed():
			_set_device(DeviceType.KEYBOARD_AND_MOUSE)
	elif event is InputEventJoypadButton:
		var joy_btn: InputEventJoypadButton = event as InputEventJoypadButton
		if joy_btn.is_pressed():
			_set_device(_detect_joypad_device(joy_btn.device))
	elif event is InputEventJoypadMotion:
		var joy_motion: InputEventJoypadMotion = event as InputEventJoypadMotion
		if absf(joy_motion.axis_value) >= DEFAULT_DEADZONE:
			_set_device(_detect_joypad_device(joy_motion.device))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_btn: InputEventMouseButton = event as InputEventMouseButton
		if mouse_btn.button_index == MOUSE_BUTTON_LEFT:
			if mouse_btn.is_pressed():
				_pointer_active = true
				_touch_active = false
				_pointer_pos = mouse_btn.position
	elif event is InputEventMouseMotion:
		if _pointer_active and not _touch_active:
			var motion: InputEventMouseMotion = event as InputEventMouseMotion
			_pointer_pos = motion.position
	elif event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.is_pressed():
			_pointer_active = true
			_touch_active = true
			_pointer_pos = touch.position
		else:
			_pointer_active = false
			_touch_active = false
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		_pointer_active = true
		_touch_active = true
		_pointer_pos = drag.position


func _on_mouse_hide_timer_timeout() -> void:
	var joypads: Array[int] = Input.get_connected_joypads()
	if not joypads.is_empty():
		_set_device(_detect_joypad_device(joypads[0]))


func enable_notifications() -> void:
	if _notifications_enabled:
		return
	_notifications_enabled = true
	if not Input.get_connected_joypads().is_empty():
		Alerts.controller_detected()


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		_set_device(_detect_joypad_device(device))
	else:
		var joypads: Array[int] = Input.get_connected_joypads()
		if joypads.is_empty():
			_set_device(DeviceType.KEYBOARD_AND_MOUSE)

	if not _notifications_enabled:
		return
	if connected:
		Alerts.controller_connected()
	else:
		Alerts.controller_disconnected()


func is_controller_active() -> bool:
	return current_device != DeviceType.KEYBOARD_AND_MOUSE


func get_movement_vector(origin_screen_pos: Vector2 = Vector2.ZERO, deadzone: float = DEFAULT_DEADZONE) -> Vector2:
	for pad: int in Input.get_connected_joypads():
		var raw_stick: Vector2 = Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
		var mag: float = raw_stick.length()
		if mag >= deadzone:
			var scaled_mag: float = clampf((mag - deadzone) / (1.0 - deadzone), 0.0, 1.0)
			return raw_stick.normalized() * scaled_mag

	var x: float = Input.get_action_strength(&"right") - Input.get_action_strength(&"left")
	var y: float = Input.get_action_strength(&"down") - Input.get_action_strength(&"up")
	var keys: Vector2 = Vector2(x, y)
	if keys.length_squared() > 0.01:
		if keys.length_squared() > 1.0:
			return keys.normalized()
		return keys

	if _pointer_active:
		if not _touch_active and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_pointer_active = false
			return Vector2.ZERO
		var target_pos: Vector2 = _pointer_pos
		if not _touch_active:
			var vp: Viewport = get_viewport()
			if vp != null:
				target_pos = vp.get_mouse_position()
				_pointer_pos = target_pos
		var origin: Vector2 = origin_screen_pos
		if origin == Vector2.ZERO:
			var vp_origin: Viewport = get_viewport()
			if vp_origin != null:
				origin = vp_origin.get_visible_rect().size * 0.5
		var diff: Vector2 = target_pos - origin
		var dist: float = diff.length()
		if dist >= POINTER_DEADZONE:
			var scaled: float = clampf((dist - POINTER_DEADZONE) / (POINTER_MAX_RANGE - POINTER_DEADZONE), 0.0, 1.0)
			return diff.normalized() * scaled

	return Vector2.ZERO


func _set_device(new_device: DeviceType) -> void:
	if current_device == new_device:
		if current_device == DeviceType.KEYBOARD_AND_MOUSE and not Input.get_connected_joypads().is_empty():
			_mouse_hide_timer.start()
		return

	current_device = new_device
	if current_device == DeviceType.KEYBOARD_AND_MOUSE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if not Input.get_connected_joypads().is_empty():
			_mouse_hide_timer.start()
		else:
			_mouse_hide_timer.stop()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		_mouse_hide_timer.stop()

	device_changed.emit(current_device)


func _detect_joypad_device(device_id: int) -> DeviceType:
	var joy_name: String = Input.get_joy_name(device_id).to_lower()
	for ps_id: String in ["ps5", "ps4", "playstation", "dualshock", "dualsense"]:
		if joy_name.contains(ps_id):
			return DeviceType.PLAYSTATION
	if joy_name.contains("xbox") or joy_name.contains("xinput"):
		return DeviceType.XBOX
	return DeviceType.GENERIC_GAMEPAD

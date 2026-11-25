# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name UiPanel
extends Control

const _UI_NAV_ACTIONS: Array[StringName] = [&"ui_left", &"ui_right", &"ui_up", &"ui_down", &"ui_accept"]
const _UI_TO_MOVE_ACTION: Dictionary[StringName, StringName] = {
	&"ui_left": &"left",
	&"ui_right": &"right",
	&"ui_up": &"up",
	&"ui_down": &"down",
}

@export var first_focus: Control = null

var _blocked_nav_actions: Dictionary[StringName, bool] = {}


func _ready() -> void:
	set_process_input(false)
	Audio.connect_menu_sounds(self)
	if is_visible_in_tree():
		grab_first_focus()
		_capture_held_nav_inputs()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if is_visible_in_tree():
			_capture_held_nav_inputs()
		else:
			_blocked_nav_actions.clear()
			set_process_input(false)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		_blocked_nav_actions.clear()
		set_process_input(false)
		return

	var released: Array[StringName] = []
	for action: StringName in _blocked_nav_actions:
		if not _is_nav_action_held(action):
			released.append(action)
	for action: StringName in released:
		_blocked_nav_actions.erase(action)

	if _blocked_nav_actions.is_empty():
		set_process_input(false)
		return

	for action: StringName in _blocked_nav_actions:
		if event.is_action_pressed(action, true):
			get_viewport().set_input_as_handled()
			return


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"back"):
		get_viewport().set_input_as_handled()
		_ensure_focus()


func grab_first_focus() -> void:
	if first_focus != null:
		Audio.grab_focus_silent(first_focus)


func _ensure_focus() -> void:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner != null and is_ancestor_of(focus_owner):
		return
	grab_first_focus()


func _capture_held_nav_inputs() -> void:
	_blocked_nav_actions.clear()
	for action: StringName in _UI_NAV_ACTIONS:
		if _is_nav_action_held(action):
			_blocked_nav_actions[action] = true
	set_process_input(not _blocked_nav_actions.is_empty())


static func _is_nav_action_held(action: StringName) -> bool:
	if Input.is_action_pressed(action):
		return true
	if _UI_TO_MOVE_ACTION.has(action) and Input.is_action_pressed(_UI_TO_MOVE_ACTION[action]):
		return true
	match action:
		&"ui_left":
			return _is_stick_dir_held(JOY_AXIS_LEFT_X, -1.0)
		&"ui_right":
			return _is_stick_dir_held(JOY_AXIS_LEFT_X, 1.0)
		&"ui_up":
			return _is_stick_dir_held(JOY_AXIS_LEFT_Y, -1.0)
		&"ui_down":
			return _is_stick_dir_held(JOY_AXIS_LEFT_Y, 1.0)
	return false


static func _is_stick_dir_held(axis: JoyAxis, dir_sign: float) -> bool:
	for pad: int in Input.get_connected_joypads():
		if Input.get_joy_axis(pad, axis) * dir_sign >= InputManager.STICK_DEADZONE:
			return true
	return false

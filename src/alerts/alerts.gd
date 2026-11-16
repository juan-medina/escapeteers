# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

extends CanvasLayer

const SILENT_DB: float = -80.0
const TOAST_SCENE: PackedScene = preload("res://toast/toast.tscn")
const ERROR_DIALOG_SCENE: PackedScene = preload("res://error_dialog/error_dialog.tscn")

var _toast: Toast = null
var _error_dialog: ErrorDialog = null
var _terminating: bool = false


func _ready() -> void:
	layer = 10000
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Intercept the window-close request so termination fades gracefully.
	get_tree().set_auto_accept_quit(false)

	_toast = TOAST_SCENE.instantiate() as Toast
	add_child(_toast)

	_error_dialog = ERROR_DIALOG_SCENE.instantiate() as ErrorDialog
	_error_dialog.visible = false
	add_child(_error_dialog)

	await BuildInfo.initialize()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _terminating:
			if _error_dialog.visible:
				get_tree().quit()
			return
		await quit_game()


func controller_detected() -> void:
	_toast.show_message(&"Controller Detected")


func controller_connected() -> void:
	_toast.show_message(&"Controller Connected")


func controller_disconnected() -> void:
	_toast.show_message(&"Controller Disconnected")


func is_terminating() -> bool:
	return _terminating


func quit_game() -> void:
	await _terminate(false, &"")


func fatal_error(user_message: StringName) -> void:
	# The caller logs the technical detail; this shows the short line and quits.
	await _terminate(true, user_message)


func _terminate(is_error: bool, message: StringName) -> void:
	if _terminating:
		return
	_terminating = true

	var tree: SceneTree = get_tree()
	tree.paused = true

	var master_index: int = AudioServer.get_bus_index(&"Master")
	var start_db: float = AudioServer.get_bus_volume_db(master_index)

	var tween: Tween = create_tween()
	tween.tween_method(Audio.set_master_volume_db, start_db, SILENT_DB, Transition.FADE_PHASE)
	await Transition.fade_to_black(Transition.FADE_PHASE)

	Audio.stop_all_players(tree.root)

	if is_error:
		_show_error_dialog(message)
		return

	tree.quit()


func _show_error_dialog(message: StringName) -> void:
	_error_dialog.setup(message)
	_error_dialog.visible = true
	_error_dialog.grab_first_focus()

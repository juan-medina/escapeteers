# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

extends CanvasLayer

enum MenuTarget { MAIN_MENU }

const FADE_DURATION: float = 1.5
const FADE_PHASE: float = FADE_DURATION / 3
const SILENT_DB: float = -80.0

const GAME_SCENE: PackedScene = preload("res://game/game.tscn")
const LOADING_SCREEN_SCENE: PackedScene = preload("res://loading_screen/loading_screen.tscn")
const MENU_SCENE: PackedScene = preload("res://menu/menu.tscn")

var in_transition: bool = false
var filler: ColorRect = null
var pending_menu_target: MenuTarget = MenuTarget.MAIN_MENU

var _loading_screen: LoadingScreen = null


func _ready() -> void:
	layer = 9999
	# keep processing while the tree is paused during a transition
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	filler = ColorRect.new()
	filler.color = Color(0, 0, 0, 0)
	filler.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(filler)

	_loading_screen = LOADING_SCREEN_SCENE.instantiate() as LoadingScreen
	_loading_screen.visible = false
	add_child(_loading_screen)


func set_loading_progress(progress: float, message: StringName = &"") -> void:
	if _loading_screen != null:
		_loading_screen.set_progress(progress, message)


func hide_loading() -> void:
	if not visible or _loading_screen == null or not _loading_screen.visible:
		visible = false
		in_transition = false
		return

	if Alerts.is_terminating():
		return

	await _loading_screen.fade_out(0.35)
	visible = false
	in_transition = false


func reload_game() -> void:
	await _go_to_game_scene()


func go_to_menu(target: MenuTarget = MenuTarget.MAIN_MENU) -> void:
	if in_transition:
		return

	pending_menu_target = target
	get_viewport().gui_release_focus()

	var tree: SceneTree = get_tree()
	tree.paused = true
	visible = true
	in_transition = true

	await filler.create_tween().tween_property(filler, ^"color:a", 1.0, 0.25).finished

	tree.change_scene_to_packed.call_deferred(MENU_SCENE)
	tree.paused = false
	await tree.process_frame

	await tree.create_timer(0.1, true, false, false).timeout
	if Alerts.is_terminating():
		return

	await filler.create_tween().tween_property(filler, ^"color:a", 0.0, 0.25).finished
	visible = false
	in_transition = false


func go_to_menu_instant() -> void:
	get_tree().change_scene_to_packed.call_deferred(MENU_SCENE)


func _go_to_game_scene() -> void:
	if in_transition:
		return

	# Drop focus so a second accept during the fade hits no button.
	get_viewport().gui_release_focus()

	var tree: SceneTree = get_tree()

	# Pause the tree to prevent gameplay updates and input during transition.
	tree.paused = true
	visible = true
	in_transition = true

	await _loading_screen.fade_in(&"Delving into the dungeon...", 0.25)

	# change is deferred, so yield a frame for the new scene to exist
	tree.change_scene_to_packed.call_deferred(GAME_SCENE)
	tree.paused = false
	await tree.process_frame

	# A fatal error in the new scene's _ready leaves us; let Alerts finish.
	if Alerts.is_terminating():
		return

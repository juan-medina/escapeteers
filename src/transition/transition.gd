# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

extends CanvasLayer

const FADE_PHASE: float = 0.5
const SCENE_FADE_DURATION: float = 0.25
const LOADING_FADE_OUT_DURATION: float = 0.35
const MENU_SETTLE_DELAY: float = 0.1

const GAME_SCENE: PackedScene = preload("res://game/game.tscn")
const LOADING_SCREEN_SCENE: PackedScene = preload("res://loading_screen/loading_screen.tscn")
const MENU_SCENE: PackedScene = preload("res://menu/menu.tscn")

var starting_hero_id: StringName = &"soldier"
var select_hero_on_menu: bool = false

var _filler: ColorRect = null
var _loading_screen: LoadingScreen = null
var _in_transition: bool = false


func _ready() -> void:
	layer = 9999
	# keep processing while the tree is paused during a transition
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_filler = ColorRect.new()
	_filler.color = Color(0, 0, 0, 0)
	_filler.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_filler)

	_loading_screen = LOADING_SCREEN_SCENE.instantiate() as LoadingScreen
	add_child(_loading_screen)


func fade_to_black(duration: float = FADE_PHASE) -> void:
	visible = true
	await _filler.create_tween().tween_property(_filler, ^"color:a", 1.0, duration).finished


func set_loading_progress(progress: float) -> void:
	_loading_screen.set_progress(progress)


func hide_loading() -> void:
	if not visible or not _loading_screen.visible:
		visible = false
		_in_transition = false
		return

	if Alerts.is_terminating():
		return

	await _loading_screen.fade_out(LOADING_FADE_OUT_DURATION)
	visible = false
	_in_transition = false


func reload_game(hero_id: StringName = &"") -> void:
	if not _begin_transition():
		return

	if not hero_id.is_empty():
		starting_hero_id = hero_id

	await _loading_screen.fade_in(SCENE_FADE_DURATION)
	await _change_scene(GAME_SCENE)


func go_to_menu(select_hero: bool = false) -> void:
	if not _begin_transition():
		return

	select_hero_on_menu = select_hero

	await fade_to_black(SCENE_FADE_DURATION)
	await _change_scene(MENU_SCENE)

	await get_tree().create_timer(MENU_SETTLE_DELAY, true, false, false).timeout
	if Alerts.is_terminating():
		return

	await _filler.create_tween().tween_property(_filler, ^"color:a", 0.0, SCENE_FADE_DURATION).finished
	visible = false
	_in_transition = false


func _begin_transition() -> bool:
	if _in_transition:
		return false

	# Drop focus so a second accept during the fade hits no button.
	get_viewport().gui_release_focus()
	# Pause the tree to prevent gameplay updates and input during transition.
	get_tree().paused = true
	visible = true
	_in_transition = true
	return true


func _change_scene(scene: PackedScene) -> void:
	var tree: SceneTree = get_tree()
	# Change is deferred, so yield a frame for the new scene to exist.
	tree.change_scene_to_packed.call_deferred(scene)
	tree.paused = false
	await tree.process_frame

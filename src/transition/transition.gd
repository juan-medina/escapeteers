# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

extends CanvasLayer

const FADE_DURATION: float = 1.5
const FADE_PHASE: float = FADE_DURATION / 3
const SILENT_DB: float = -80.0

const GAME_SCENE: PackedScene = preload("res://game/game.tscn")
var in_transition: bool = false
var filler: ColorRect = null


func _ready() -> void:
	layer = 9999
	# keep processing while the tree is paused during a transition
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	filler = ColorRect.new()
	filler.color = Color(0, 0, 0, 0)
	filler.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(filler)


func reload_game() -> void:
	await _go_to_scene(GAME_SCENE)


func _go_to_scene(scene: PackedScene) -> void:
	if in_transition:
		return

	# Drop focus so a second accept during the fade hits no button.
	get_viewport().gui_release_focus()

	var tree: SceneTree = get_tree()

	# Pause the tree to prevent gameplay updates and input during transition.
	tree.paused = true
	visible = true
	in_transition = true

	await filler.create_tween().tween_property(filler, ^"color:a", 1.0, FADE_PHASE).finished

	# change is deferred, so yield a frame for the new scene to exist
	tree.change_scene_to_packed.call_deferred(scene)
	tree.paused = false
	await tree.process_frame

	# let it settle behind black so it does not jump on fade in
	await tree.create_timer(FADE_PHASE, true, false, false).timeout

	# A fatal error in the new scene's _ready leaves us black; let Alerts finish.
	if Alerts.is_terminating():
		return

	await filler.create_tween().tween_property(filler, ^"color:a", 0.0, FADE_PHASE).finished

	visible = false
	in_transition = false

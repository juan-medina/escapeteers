# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

extends Node

const MENU_MUSIC: AudioStreamOggVorbis = preload("res://data/assets/music/11 - The Mighty Kingdom.ogg")
const GAME_MUSIC: AudioStreamOggVorbis = preload("res://data/assets/music/09 - Battle 2.ogg")
const HERO_DEATH_MUSIC: AudioStreamOggVorbis = preload("res://data/assets/music/18 - Never Give Up.ogg")

var _suppress_hover: bool = false

var _hover: AudioStreamPlayer
var _click: AudioStreamPlayer
var _return: AudioStreamPlayer
var _start: AudioStreamPlayer
var _pause: AudioStreamPlayer
var _music_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hover = _create_player(preload("res://data/assets/sounds/Hover.wav"), "Hover")
	_click = _create_player(preload("res://data/assets/sounds/Click.wav"), "Click")
	_return = _create_player(preload("res://data/assets/sounds/Return.wav"), "Return")
	_start = _create_player(preload("res://data/assets/sounds/Start.wav"), "Start")
	_pause = _create_player(preload("res://data/assets/sounds/Pause.wav"), "Pause")
	_music_player = _create_music_player("MusicPlayer")


func _create_player(stream: AudioStream, node_name: String) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = node_name
	player.stream = stream
	player.bus = &"Sfx"
	add_child(player)
	return player


func _create_music_player(node_name: String) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = node_name
	player.bus = &"Music"
	add_child(player)
	return player


func play_menu_music() -> void:
	_play_music(MENU_MUSIC)


func play_game_music() -> void:
	_play_music(GAME_MUSIC)


func play_hero_death_music() -> void:
	_play_music(HERO_DEATH_MUSIC)


func stop_music() -> void:
	_music_player.stop()


func _play_music(stream: AudioStreamOggVorbis) -> void:
	if stream == null:
		return
	stream.loop = true
	if _music_player.stream == stream and _music_player.playing:
		return
	_music_player.stream = stream
	_music_player.play()


func play_hover() -> void:
	if _suppress_hover:
		return
	_hover.play()


func play_click() -> void:
	_click.play()


func slider_change(_value: float) -> void:
	_click.play()


func play_return() -> void:
	_return.play()


func play_start() -> void:
	_start.play()


func play_pause() -> void:
	_pause.play()


func grab_focus_silent(control: Control) -> void:
	# Focus without the hover sound. focus_entered still fires synchronously,
	# so focus-driven visuals react normally — only the sound is skipped.
	_suppress_hover = true
	control.grab_focus()
	_suppress_hover = false


func connect_menu_sounds(root: Node) -> void:
	for child: Node in root.get_children():
		var control: Control = child as Control
		if control:
			connect_sound(control)
			connect_menu_sounds(control)


func connect_sound(control: Control) -> void:
	var button: BaseButton = control as BaseButton
	if button:
		_connect_button(button)
		return

	var slider: Slider = control as Slider
	if slider:
		_connect_slider(slider)
		return

	var line_edit: LineEdit = control as LineEdit
	if line_edit:
		_connect_line_edit(line_edit)
		return


func _connect_line_edit(line_edit: LineEdit) -> void:
	line_edit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_connect_focus(line_edit)


func _connect_button(button: BaseButton) -> void:
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_connect_focus(button)

	if button.is_in_group(&"ui_return"):
		button.pressed.connect(play_return)
	elif button.is_in_group(&"ui_start"):
		button.pressed.connect(play_start)
	else:
		button.pressed.connect(play_click)


func _connect_slider(slider: Slider) -> void:
	slider.mouse_entered.connect(slider.grab_focus)
	slider.focus_entered.connect(play_hover)
	slider.value_changed.connect(slider_change)


func _connect_focus(control: Control) -> void:
	if control.focus_mode != Control.FOCUS_NONE:
		control.mouse_entered.connect(control.grab_focus)
	control.focus_entered.connect(play_hover)


func set_master_volume_db(db: float) -> void:
	var master_index: int = AudioServer.get_bus_index(&"Master")
	AudioServer.set_bus_volume_db(master_index, db)


func stop_all_players(node: Node) -> void:
	# Stops every player before a quit, so Godot logs no audio error at exit.
	var stereo: AudioStreamPlayer = node as AudioStreamPlayer
	if stereo:
		stereo.stop()
	var positional: AudioStreamPlayer2D = node as AudioStreamPlayer2D
	if positional:
		positional.stop()
	for child: Node in node.get_children():
		stop_all_players(child)

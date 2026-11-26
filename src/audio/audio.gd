# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

extends Node

enum MusicTrack {
	MENU,
	GAME,
	EVENT,
}

enum Sfx {
	GAME_OVER,
	HERO_DOWN,
	EVENT_START,
	EVENT_CLEAR,
	LEVEL_UP,
	HERO_RECRUITED,
	SECRET_TORCH,
	COIN_PICKUP,
	POTION_HEALTH,
	POTION_HASTE,
	POTION_FURY,
	POTION_XP,
	KEY_PICKUP,
	DOOR_UNLOCK,
	SHORTCUT_OPEN,
	SPIKE_TRAP,
	TELEGRAPH,
	NECRO_SUMMON,
	HERO_HURT,
	HEAL,
	ENEMY_DEATH,
	HEAVY_IMPACT,
	HIT_IMPACT,
	MAGIC_CAST,
	BOW_SHOOT,
	MELEE_SWOOSH,
	FOOTSTEP,
}

const AUDIO_LIBRARY_SCENE: PackedScene = preload("res://audio/audio_library.tscn")
const MUSIC_FADE_OUT_DB: float = -36.0
const MUSIC_FADE_IN_DB: float = -24.0

var _suppress_hover: bool = false
var _sfx: Array[AudioStreamPlayer] = []

var _menu_music: AudioStreamPlayer
var _game_music: AudioStreamPlayer
var _event_music: AudioStreamPlayer
var _current_music: AudioStreamPlayer = null
var _music_tween: Tween = null
var _hover: AudioStreamPlayer
var _click: AudioStreamPlayer
var _return: AudioStreamPlayer
var _start: AudioStreamPlayer
var _pause: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var lib: Node = AUDIO_LIBRARY_SCENE.instantiate()
	add_child(lib)
	_menu_music = lib.get_node(^"Music/MenuMusic") as AudioStreamPlayer
	_game_music = lib.get_node(^"Music/GameMusic") as AudioStreamPlayer
	_event_music = lib.get_node(^"Music/EventMusic") as AudioStreamPlayer
	(_menu_music.stream as AudioStreamOggVorbis).loop = true
	(_game_music.stream as AudioStreamOggVorbis).loop = true
	(_event_music.stream as AudioStreamOggVorbis).loop = true
	_hover = lib.get_node(^"UI/Hover") as AudioStreamPlayer
	_click = lib.get_node(^"UI/Click") as AudioStreamPlayer
	_return = lib.get_node(^"UI/Return") as AudioStreamPlayer
	_start = lib.get_node(^"UI/Start") as AudioStreamPlayer
	_pause = lib.get_node(^"UI/Pause") as AudioStreamPlayer
	for key: String in Sfx.keys():
		var player: AudioStreamPlayer = lib.find_child(key.to_pascal_case(), true, false) as AudioStreamPlayer
		_sfx.append(player)


func play_sfx(sfx: Sfx) -> void:
	var player: AudioStreamPlayer = _sfx[sfx]
	if player.playing:
		return
	for child: Node in player.get_parent().get_children():
		var other: AudioStreamPlayer = child as AudioStreamPlayer
		if other.playing:
			if other.get_index() < player.get_index():
				return
			other.stop()
			break
	player.play()


func set_music_track(track: MusicTrack, fade_duration: float = 0.0) -> void:
	var target: AudioStreamPlayer = _get_music_player(track)
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = null

	if target == _current_music and target.playing:
		for player: AudioStreamPlayer in [_menu_music, _game_music, _event_music]:
			if player != target:
				player.stop()
				player.volume_db = 0.0
		if fade_duration > 0.0 and not is_zero_approx(target.volume_db):
			_music_tween = create_tween()
			_music_tween.tween_property(target, ^"volume_db", 0.0, fade_duration)
		else:
			target.volume_db = 0.0
		return

	if fade_duration <= 0.0 or _current_music == null or not _current_music.playing:
		for player: AudioStreamPlayer in [_menu_music, _game_music, _event_music]:
			player.stop()
			player.volume_db = 0.0
		target.play()
		_current_music = target
		return

	var prev: AudioStreamPlayer = _current_music
	for player: AudioStreamPlayer in [_menu_music, _game_music, _event_music]:
		if player != prev and player != target:
			player.stop()
			player.volume_db = 0.0

	_current_music = target
	target.volume_db = MUSIC_FADE_IN_DB
	if not target.playing:
		target.play()
	_music_tween = create_tween()
	_music_tween.set_parallel(true)
	_music_tween.tween_property(target, ^"volume_db", 0.0, fade_duration)
	_music_tween.tween_property(prev, ^"volume_db", MUSIC_FADE_OUT_DB, fade_duration)
	_music_tween.chain().tween_callback(_finish_music_fade_out.bind(prev))


func play_music(is_game: bool = true) -> void:
	set_music_track(MusicTrack.GAME if is_game else MusicTrack.MENU, 0.0)


func stop_music() -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = null
	for player: AudioStreamPlayer in [_menu_music, _game_music, _event_music]:
		player.stop()
		player.volume_db = 0.0
	_current_music = null


func _finish_music_fade_out(player: AudioStreamPlayer) -> void:
	if player != _current_music:
		player.stop()
		player.volume_db = 0.0


func _get_music_player(track: MusicTrack) -> AudioStreamPlayer:
	match track:
		MusicTrack.MENU:
			return _menu_music
		MusicTrack.EVENT:
			return _event_music
		_:
			return _game_music


func play_click() -> void:
	_click.play()


func play_pause() -> void:
	_pause.play()


func grab_focus_silent(control: Control) -> void:
	_suppress_hover = true
	control.grab_focus()
	_suppress_hover = false


func connect_menu_sounds(root: Node) -> void:
	for child: Node in root.get_children():
		var control: Control = child as Control
		if control:
			_connect_sound(control)
			connect_menu_sounds(control)


func set_master_volume_db(db: float) -> void:
	var master_index: int = AudioServer.get_bus_index(&"Master")
	AudioServer.set_bus_volume_db(master_index, db)


func stop_all_players(node: Node) -> void:
	var stereo: AudioStreamPlayer = node as AudioStreamPlayer
	if stereo:
		stereo.stop()
	var positional: AudioStreamPlayer2D = node as AudioStreamPlayer2D
	if positional:
		positional.stop()
	for child: Node in node.get_children():
		stop_all_players(child)


func _play_hover() -> void:
	if _suppress_hover:
		return
	_hover.play()


func _play_return() -> void:
	_return.play()


func _play_start() -> void:
	_start.play()


func _slider_change(_value: float) -> void:
	_click.play()


func _connect_sound(control: Control) -> void:
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
		button.pressed.connect(_play_return)
	elif button.is_in_group(&"ui_start"):
		button.pressed.connect(_play_start)
	else:
		button.pressed.connect(play_click)


func _connect_slider(slider: Slider) -> void:
	_connect_focus(slider)
	slider.value_changed.connect(_slider_change)


func _connect_focus(control: Control) -> void:
	if control.focus_mode != Control.FOCUS_NONE:
		control.mouse_entered.connect(control.grab_focus)
	control.focus_entered.connect(_play_hover)

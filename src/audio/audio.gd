# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

extends Node

const MENU_MUSIC: AudioStreamOggVorbis = preload("res://data/assets/music/Three Red Hearts - Three Red Hearts.ogg")
const GAME_MUSIC: AudioStreamOggVorbis = preload("res://data/assets/music/Three Red Hearts - Box Jump.ogg")

const STEP_1: AudioStream = preload("res://data/assets/sounds/07_Step_rock_01.wav")
const STEP_2: AudioStream = preload("res://data/assets/sounds/08_Step_rock_02.wav")
const STEP_3: AudioStream = preload("res://data/assets/sounds/09_Step_rock_03.wav")
const STEPS: Array[AudioStream] = [STEP_1, STEP_2, STEP_3]

const SWOOSH_1: AudioStream = preload("res://data/assets/sounds/31_swoosh_sword_1.wav")
const SWOOSH_2: AudioStream = preload("res://data/assets/sounds/32_Swoosh_sword_2.wav")
const SWOOSH_3: AudioStream = preload("res://data/assets/sounds/33_Swoosh_Sword_3.wav")
const SWOOSHES: Array[AudioStream] = [SWOOSH_1, SWOOSH_2, SWOOSH_3]

const IMPACT_1: AudioStream = preload("res://data/assets/sounds/09_Impact_01.wav")
const IMPACT_2: AudioStream = preload("res://data/assets/sounds/10_Impact_02.wav")
const IMPACT_3: AudioStream = preload("res://data/assets/sounds/11_Impact_03.wav")
const IMPACT_4: AudioStream = preload("res://data/assets/sounds/12_Impact_04.wav")
const IMPACT_5: AudioStream = preload("res://data/assets/sounds/13_Impact_05.wav")
const IMPACTS: Array[AudioStream] = [IMPACT_1, IMPACT_2, IMPACT_3, IMPACT_4, IMPACT_5]

const ENEMY_DEATH_1: AudioStream = preload("res://data/assets/sounds/Enemy_Death_01.wav")
const ENEMY_DEATH_2: AudioStream = preload("res://data/assets/sounds/Enemy_Death_02.wav")
const ENEMY_DEATH_3: AudioStream = preload("res://data/assets/sounds/Enemy_Death_03.wav")
const ENEMY_DEATHS: Array[AudioStream] = [ENEMY_DEATH_1, ENEMY_DEATH_2, ENEMY_DEATH_3]

const TRAP_SPIKE_1: AudioStream = preload("res://data/assets/sounds/Trap_Spike_01.wav")
const TRAP_SPIKE_2: AudioStream = preload("res://data/assets/sounds/Trap_Spike_02.wav")
const TRAP_SPIKES: Array[AudioStream] = [TRAP_SPIKE_1, TRAP_SPIKE_2]

const BOW_SHOOT: AudioStream = preload("res://data/assets/sounds/Bow_Shoot.wav")
const MAGIC_CAST: AudioStream = preload("res://data/assets/sounds/Magic_Cast.wav")
const ENEMY_MELEE: AudioStream = preload("res://data/assets/sounds/Enemy_Melee.wav")
const ENEMY_RANGED: AudioStream = preload("res://data/assets/sounds/Enemy_Ranged.wav")
const TELEGRAPH_WARNING: AudioStream = preload("res://data/assets/sounds/Telegraph_Warning.wav")
const NECROMANCER_SUMMON: AudioStream = preload("res://data/assets/sounds/Necromancer_Summon.wav")

const SQUAD_STEP_THROTTLE_MSEC: int = 180
const MELEE_SWOOSH_THROTTLE_MSEC: int = 90
const RANGED_ATTACK_THROTTLE_MSEC: int = 80
const IMPACT_THROTTLE_MSEC: int = 70
const ENEMY_ATTACK_THROTTLE_MSEC: int = 80
const ENEMY_DEATH_THROTTLE_MSEC: int = 70
const TELEGRAPH_THROTTLE_MSEC: int = 120
const NECROMANCER_SUMMON_THROTTLE_MSEC: int = 200
const SPIKE_TRAP_THROTTLE_MSEC: int = 80

var _suppress_hover: bool = false

var _hover: AudioStreamPlayer
var _click: AudioStreamPlayer
var _return: AudioStreamPlayer
var _start: AudioStreamPlayer
var _pause: AudioStreamPlayer
var _level_up: AudioStreamPlayer
var _hero_down: AudioStreamPlayer
var _hero_recruited: AudioStreamPlayer
var _music_player: AudioStreamPlayer
var _step_players: Array[AudioStreamPlayer] = []
var _step_player_index: int = 0
var _last_step_time_msec: int = 0
var _swoosh_players: Array[AudioStreamPlayer] = []
var _swoosh_player_index: int = 0
var _last_swoosh_time_msec: int = 0
var _bow_players: Array[AudioStreamPlayer] = []
var _bow_player_index: int = 0
var _last_bow_time_msec: int = 0
var _magic_players: Array[AudioStreamPlayer] = []
var _magic_player_index: int = 0
var _last_magic_time_msec: int = 0
var _impact_players: Array[AudioStreamPlayer] = []
var _impact_player_index: int = 0
var _last_impact_time_msec: int = 0
var _enemy_melee_players: Array[AudioStreamPlayer] = []
var _enemy_melee_player_index: int = 0
var _last_enemy_melee_time_msec: int = 0
var _enemy_ranged_players: Array[AudioStreamPlayer] = []
var _enemy_ranged_player_index: int = 0
var _last_enemy_ranged_time_msec: int = 0
var _enemy_death_players: Array[AudioStreamPlayer] = []
var _enemy_death_player_index: int = 0
var _last_enemy_death_time_msec: int = 0
var _telegraph_players: Array[AudioStreamPlayer] = []
var _telegraph_player_index: int = 0
var _last_telegraph_time_msec: int = 0
var _summon_players: Array[AudioStreamPlayer] = []
var _summon_player_index: int = 0
var _last_summon_time_msec: int = 0
var _spike_trap_players: Array[AudioStreamPlayer] = []
var _spike_trap_player_index: int = 0
var _last_spike_trap_time_msec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hover = _create_player(preload("res://data/assets/sounds/Hover.wav"), &"Hover")
	_click = _create_player(preload("res://data/assets/sounds/Click.wav"), &"Click")
	_return = _create_player(preload("res://data/assets/sounds/Return.wav"), &"Return")
	_start = _create_player(preload("res://data/assets/sounds/Start.wav"), &"Start")
	_pause = _create_player(preload("res://data/assets/sounds/Pause.wav"), &"Pause")
	_level_up = _create_player(preload("res://data/assets/sounds/Level_Up.wav"), &"LevelUp")
	_hero_down = _create_player(preload("res://data/assets/sounds/Hero_Down.wav"), &"HeroDown")
	_hero_recruited = _create_player(preload("res://data/assets/sounds/Hero_Recruited.wav"), &"HeroRecruited")
	_music_player = _create_music_player(&"MusicPlayer")
	for i: int in range(3):
		var player: AudioStreamPlayer = _create_random_player(STEPS, 1.1, StringName("Footstep_%d" % i))
		_step_players.append(player)
	for i: int in range(2):
		var player: AudioStreamPlayer = _create_random_player(SWOOSHES, 1.15, StringName("MeleeSwoosh_%d" % i))
		_swoosh_players.append(player)
	for i: int in range(2):
		var player: AudioStreamPlayer = _create_single_random_player(BOW_SHOOT, 1.15, StringName("BowShoot_%d" % i))
		_bow_players.append(player)
	for i: int in range(2):
		var player: AudioStreamPlayer = _create_single_random_player(MAGIC_CAST, 1.15, StringName("MagicCast_%d" % i))
		_magic_players.append(player)
	for i: int in range(3):
		var player: AudioStreamPlayer = _create_random_player(IMPACTS, 1.15, StringName("HitImpact_%d" % i))
		_impact_players.append(player)
	for i: int in range(2):
		var player: AudioStreamPlayer = _create_single_random_player(ENEMY_MELEE, 1.15, StringName("EnemyMelee_%d" % i))
		_enemy_melee_players.append(player)
	for i: int in range(2):
		var player: AudioStreamPlayer = _create_single_random_player(ENEMY_RANGED, 1.15, StringName("EnemyRanged_%d" % i))
		_enemy_ranged_players.append(player)
	for i: int in range(3):
		var player: AudioStreamPlayer = _create_random_player(ENEMY_DEATHS, 1.15, StringName("EnemyDeath_%d" % i))
		_enemy_death_players.append(player)
	for i: int in range(2):
		var player: AudioStreamPlayer = _create_single_random_player(TELEGRAPH_WARNING, 1.1, StringName("TelegraphWarning_%d" % i))
		_telegraph_players.append(player)
	for i: int in range(2):
		var player: AudioStreamPlayer = _create_single_random_player(NECROMANCER_SUMMON, 1.1, StringName("NecroSummon_%d" % i))
		_summon_players.append(player)
	for i: int in range(2):
		var player: AudioStreamPlayer = _create_random_player(TRAP_SPIKES, 1.15, StringName("SpikeTrap_%d" % i))
		_spike_trap_players.append(player)


func _exit_tree() -> void:
	_step_players.clear()
	_swoosh_players.clear()
	_bow_players.clear()
	_magic_players.clear()
	_impact_players.clear()
	_enemy_melee_players.clear()
	_enemy_ranged_players.clear()
	_enemy_death_players.clear()
	_telegraph_players.clear()
	_summon_players.clear()
	_spike_trap_players.clear()


func play_footstep() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_step_time_msec < SQUAD_STEP_THROTTLE_MSEC:
		return
	_last_step_time_msec = now

	if _step_players.is_empty():
		return

	var player: AudioStreamPlayer = _step_players[_step_player_index]
	_step_player_index = (_step_player_index + 1) % _step_players.size()
	player.play()


func play_melee_swoosh() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_swoosh_time_msec < MELEE_SWOOSH_THROTTLE_MSEC:
		return
	_last_swoosh_time_msec = now

	if _swoosh_players.is_empty():
		return

	var player: AudioStreamPlayer = _swoosh_players[_swoosh_player_index]
	_swoosh_player_index = (_swoosh_player_index + 1) % _swoosh_players.size()
	player.play()


func play_ranged_attack(is_magic: bool = false) -> void:
	var now: int = Time.get_ticks_msec()
	if is_magic:
		if now - _last_magic_time_msec < RANGED_ATTACK_THROTTLE_MSEC or _magic_players.is_empty():
			return
		_last_magic_time_msec = now
		var player: AudioStreamPlayer = _magic_players[_magic_player_index]
		_magic_player_index = (_magic_player_index + 1) % _magic_players.size()
		player.play()
	else:
		if now - _last_bow_time_msec < RANGED_ATTACK_THROTTLE_MSEC or _bow_players.is_empty():
			return
		_last_bow_time_msec = now
		var player: AudioStreamPlayer = _bow_players[_bow_player_index]
		_bow_player_index = (_bow_player_index + 1) % _bow_players.size()
		player.play()


func play_hit_impact(is_heavy: bool = false) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_impact_time_msec < IMPACT_THROTTLE_MSEC:
		return
	_last_impact_time_msec = now

	if _impact_players.is_empty():
		return

	var player: AudioStreamPlayer = _impact_players[_impact_player_index]
	_impact_player_index = (_impact_player_index + 1) % _impact_players.size()
	player.volume_db = 2.0 if is_heavy else 0.0
	player.play()


func play_enemy_attack(is_ranged: bool = false) -> void:
	var now: int = Time.get_ticks_msec()
	if is_ranged:
		if now - _last_enemy_ranged_time_msec < ENEMY_ATTACK_THROTTLE_MSEC or _enemy_ranged_players.is_empty():
			return
		_last_enemy_ranged_time_msec = now
		var player: AudioStreamPlayer = _enemy_ranged_players[_enemy_ranged_player_index]
		_enemy_ranged_player_index = (_enemy_ranged_player_index + 1) % _enemy_ranged_players.size()
		player.play()
	else:
		if now - _last_enemy_melee_time_msec < ENEMY_ATTACK_THROTTLE_MSEC or _enemy_melee_players.is_empty():
			return
		_last_enemy_melee_time_msec = now
		var player: AudioStreamPlayer = _enemy_melee_players[_enemy_melee_player_index]
		_enemy_melee_player_index = (_enemy_melee_player_index + 1) % _enemy_melee_players.size()
		player.play()


func play_enemy_death() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_enemy_death_time_msec < ENEMY_DEATH_THROTTLE_MSEC:
		return
	_last_enemy_death_time_msec = now

	if _enemy_death_players.is_empty():
		return

	var player: AudioStreamPlayer = _enemy_death_players[_enemy_death_player_index]
	_enemy_death_player_index = (_enemy_death_player_index + 1) % _enemy_death_players.size()
	player.play()


func play_telegraph_warning() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_telegraph_time_msec < TELEGRAPH_THROTTLE_MSEC or _telegraph_players.is_empty():
		return
	_last_telegraph_time_msec = now

	var player: AudioStreamPlayer = _telegraph_players[_telegraph_player_index]
	_telegraph_player_index = (_telegraph_player_index + 1) % _telegraph_players.size()
	player.play()


func play_necromancer_summon() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_summon_time_msec < NECROMANCER_SUMMON_THROTTLE_MSEC or _summon_players.is_empty():
		return
	_last_summon_time_msec = now

	var player: AudioStreamPlayer = _summon_players[_summon_player_index]
	_summon_player_index = (_summon_player_index + 1) % _summon_players.size()
	player.play()


func play_spike_trap() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_spike_trap_time_msec < SPIKE_TRAP_THROTTLE_MSEC:
		return
	_last_spike_trap_time_msec = now

	if _spike_trap_players.is_empty():
		return

	var player: AudioStreamPlayer = _spike_trap_players[_spike_trap_player_index]
	_spike_trap_player_index = (_spike_trap_player_index + 1) % _spike_trap_players.size()
	player.play()


func play_level_up() -> void:
	if _level_up != null:
		_level_up.play()


func play_hero_down() -> void:
	if _hero_down != null:
		_hero_down.play()


func play_hero_recruited() -> void:
	if _hero_recruited != null:
		_hero_recruited.play()


func play_music(is_game: bool = true) -> void:
	_play_music(GAME_MUSIC if is_game else MENU_MUSIC)


func stop_music() -> void:
	_music_player.stop()


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
	_stop_footsteps()
	for player: AudioStreamPlayer in _swoosh_players:
		player.stop()
	for player: AudioStreamPlayer in _bow_players:
		player.stop()
	for player: AudioStreamPlayer in _magic_players:
		player.stop()
	for player: AudioStreamPlayer in _impact_players:
		player.stop()
	for player: AudioStreamPlayer in _enemy_melee_players:
		player.stop()
	for player: AudioStreamPlayer in _enemy_ranged_players:
		player.stop()
	for player: AudioStreamPlayer in _enemy_death_players:
		player.stop()
	for player: AudioStreamPlayer in _telegraph_players:
		player.stop()
	for player: AudioStreamPlayer in _summon_players:
		player.stop()
	for player: AudioStreamPlayer in _spike_trap_players:
		player.stop()
	var stereo: AudioStreamPlayer = node as AudioStreamPlayer
	if stereo:
		stereo.stop()
	var positional: AudioStreamPlayer2D = node as AudioStreamPlayer2D
	if positional:
		positional.stop()
	for child: Node in node.get_children():
		stop_all_players(child)


func _create_player(stream: AudioStream, node_name: StringName) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = node_name
	player.stream = stream
	player.bus = &"Sfx"
	add_child(player)
	return player


func _create_music_player(node_name: StringName) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = node_name
	player.bus = &"Music"
	add_child(player)
	return player


func _create_random_player(streams: Array[AudioStream], pitch: float, node_name: StringName) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = node_name
	var randomizer: AudioStreamRandomizer = AudioStreamRandomizer.new()
	for stream: AudioStream in streams:
		randomizer.add_stream(-1, stream)
	randomizer.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	randomizer.random_pitch = pitch
	player.stream = randomizer
	player.bus = &"Sfx"
	add_child(player)
	return player


func _create_single_random_player(stream: AudioStream, pitch: float, node_name: StringName) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = node_name
	var randomizer: AudioStreamRandomizer = AudioStreamRandomizer.new()
	randomizer.add_stream(-1, stream)
	randomizer.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	randomizer.random_pitch = pitch
	player.stream = randomizer
	player.bus = &"Sfx"
	add_child(player)
	return player


func _play_music(stream: AudioStreamOggVorbis) -> void:
	if stream == null:
		return
	stream.loop = true
	if _music_player.stream == stream and _music_player.playing:
		return
	_music_player.stream = stream
	_music_player.play()


func _play_hover() -> void:
	if _suppress_hover:
		return
	_hover.play()


func _stop_footsteps() -> void:
	for player: AudioStreamPlayer in _step_players:
		player.stop()


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
	slider.mouse_entered.connect(slider.grab_focus)
	slider.focus_entered.connect(_play_hover)
	slider.value_changed.connect(_slider_change)


func _connect_focus(control: Control) -> void:
	if control.focus_mode != Control.FOCUS_NONE:
		control.mouse_entered.connect(control.grab_focus)
	control.focus_entered.connect(_play_hover)

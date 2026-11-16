# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

extends Node

const MENU_MUSIC: AudioStreamOggVorbis = preload("res://data/assets/music/Three Red Hearts - Three Red Hearts.ogg")
const GAME_MUSIC: AudioStreamOggVorbis = preload("res://data/assets/music/Three Red Hearts - Box Jump.ogg")

const HOVER_SOUND: AudioStream = preload("res://data/assets/sounds/Hover.wav")
const CLICK_SOUND: AudioStream = preload("res://data/assets/sounds/Click.wav")
const RETURN_SOUND: AudioStream = preload("res://data/assets/sounds/Return.wav")
const START_SOUND: AudioStream = preload("res://data/assets/sounds/Start.wav")
const PAUSE_SOUND: AudioStream = preload("res://data/assets/sounds/Pause.wav")
const LEVEL_UP_SOUND: AudioStream = preload("res://data/assets/sounds/Level_Up.wav")
const HERO_DOWN_SOUND: AudioStream = preload("res://data/assets/sounds/Hero_Down.wav")
const HERO_RECRUITED_SOUND: AudioStream = preload("res://data/assets/sounds/Hero_Recruited.wav")
const GAME_OVER_SOUND: AudioStream = preload("res://data/assets/sounds/Game_Over.wav")

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
const HERO_HURT: AudioStream = preload("res://data/assets/sounds/Hero_Hurt.wav")
const HEAL_RECEIVED: AudioStream = preload("res://data/assets/sounds/Heal_Received.wav")
const SECRET_TORCH: AudioStream = preload("res://data/assets/sounds/Secret_Torch.wav")
const WALL_IMPACT: AudioStream = preload("res://data/assets/sounds/Wall_Impact.wav")

const HEAVY_IMPACT_VOLUME_DB: float = 2.0

const SQUAD_STEP_THROTTLE_MSEC: int = 180
const MELEE_SWOOSH_THROTTLE_MSEC: int = 90
const RANGED_ATTACK_THROTTLE_MSEC: int = 80
const IMPACT_THROTTLE_MSEC: int = 70
const ENEMY_ATTACK_THROTTLE_MSEC: int = 80
const ENEMY_DEATH_THROTTLE_MSEC: int = 70
const TELEGRAPH_THROTTLE_MSEC: int = 120
const NECROMANCER_SUMMON_THROTTLE_MSEC: int = 200
const SPIKE_TRAP_THROTTLE_MSEC: int = 80
const HERO_HURT_THROTTLE_MSEC: int = 100
const HEAL_RECEIVED_THROTTLE_MSEC: int = 80
const WALL_IMPACT_THROTTLE_MSEC: int = 60

var _suppress_hover: bool = false
var _last_play_times_msec: Dictionary[AudioStreamPlayer, int] = {}

var _hover: AudioStreamPlayer
var _click: AudioStreamPlayer
var _return: AudioStreamPlayer
var _start: AudioStreamPlayer
var _pause: AudioStreamPlayer
var _level_up: AudioStreamPlayer
var _hero_down: AudioStreamPlayer
var _hero_recruited: AudioStreamPlayer
var _game_over: AudioStreamPlayer
var _secret_torch: AudioStreamPlayer
var _music_player: AudioStreamPlayer
var _step: AudioStreamPlayer
var _swoosh: AudioStreamPlayer
var _bow: AudioStreamPlayer
var _magic: AudioStreamPlayer
var _impact: AudioStreamPlayer
var _enemy_melee: AudioStreamPlayer
var _enemy_ranged: AudioStreamPlayer
var _enemy_death: AudioStreamPlayer
var _telegraph: AudioStreamPlayer
var _summon: AudioStreamPlayer
var _spike_trap: AudioStreamPlayer
var _hero_hurt: AudioStreamPlayer
var _heal: AudioStreamPlayer
var _wall: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hover = _create_player(&"Hover", HOVER_SOUND)
	_click = _create_player(&"Click", CLICK_SOUND)
	_return = _create_player(&"Return", RETURN_SOUND)
	_start = _create_player(&"Start", START_SOUND)
	_pause = _create_player(&"Pause", PAUSE_SOUND)
	_level_up = _create_player(&"LevelUp", LEVEL_UP_SOUND)
	_hero_down = _create_player(&"HeroDown", HERO_DOWN_SOUND)
	_hero_recruited = _create_player(&"HeroRecruited", HERO_RECRUITED_SOUND)
	_game_over = _create_player(&"GameOver", GAME_OVER_SOUND)
	_secret_torch = _create_player(&"SecretTorch", SECRET_TORCH)
	_music_player = _create_player(&"MusicPlayer", null, &"Music")

	_step = _create_random_player(STEPS, 1.1, 3, &"Footstep")
	_swoosh = _create_random_player(SWOOSHES, 1.15, 2, &"MeleeSwoosh")
	_bow = _create_random_player([BOW_SHOOT], 1.15, 2, &"BowShoot")
	_magic = _create_random_player([MAGIC_CAST], 1.15, 2, &"MagicCast")
	_impact = _create_random_player(IMPACTS, 1.15, 3, &"HitImpact")
	_enemy_melee = _create_random_player([ENEMY_MELEE], 1.15, 2, &"EnemyMelee")
	_enemy_ranged = _create_random_player([ENEMY_RANGED], 1.15, 2, &"EnemyRanged")
	_enemy_death = _create_random_player(ENEMY_DEATHS, 1.15, 3, &"EnemyDeath")
	_telegraph = _create_random_player([TELEGRAPH_WARNING], 1.1, 2, &"TelegraphWarning")
	_summon = _create_random_player([NECROMANCER_SUMMON], 1.1, 2, &"NecroSummon")
	_spike_trap = _create_random_player(TRAP_SPIKES, 1.15, 2, &"SpikeTrap")
	_hero_hurt = _create_random_player([HERO_HURT], 1.15, 2, &"HeroHurt")
	_heal = _create_random_player([HEAL_RECEIVED], 1.1, 2, &"HealReceived")
	_wall = _create_random_player([WALL_IMPACT], 1.2, 2, &"WallImpact")


func play_footstep() -> void:
	_play_throttled(_step, SQUAD_STEP_THROTTLE_MSEC)


func play_melee_swoosh() -> void:
	_play_throttled(_swoosh, MELEE_SWOOSH_THROTTLE_MSEC)


func play_ranged_attack(is_magic: bool = false) -> void:
	_play_throttled(_magic if is_magic else _bow, RANGED_ATTACK_THROTTLE_MSEC)


func play_hit_impact(is_heavy: bool = false) -> void:
	if not _can_play_throttled(_impact, IMPACT_THROTTLE_MSEC):
		return
	_impact.volume_db = HEAVY_IMPACT_VOLUME_DB if is_heavy else 0.0
	_impact.play()


func play_enemy_attack(is_ranged: bool = false) -> void:
	_play_throttled(_enemy_ranged if is_ranged else _enemy_melee, ENEMY_ATTACK_THROTTLE_MSEC)


func play_enemy_death() -> void:
	_play_throttled(_enemy_death, ENEMY_DEATH_THROTTLE_MSEC)


func play_enemy_special(is_summon: bool = false) -> void:
	if is_summon:
		_play_throttled(_summon, NECROMANCER_SUMMON_THROTTLE_MSEC)
	else:
		_play_throttled(_telegraph, TELEGRAPH_THROTTLE_MSEC)


func play_environment(cue: StringName) -> void:
	match cue:
		&"spike":
			_play_throttled(_spike_trap, SPIKE_TRAP_THROTTLE_MSEC)
		&"torch":
			_secret_torch.play()
		&"wall":
			_play_throttled(_wall, WALL_IMPACT_THROTTLE_MSEC)


func play_hero_health(is_heal: bool = false) -> void:
	if is_heal:
		_play_throttled(_heal, HEAL_RECEIVED_THROTTLE_MSEC)
	else:
		_play_throttled(_hero_hurt, HERO_HURT_THROTTLE_MSEC)


func play_level_up() -> void:
	_level_up.play()


func play_defeat(is_game_over: bool = false) -> void:
	if is_game_over:
		_game_over.play()
	else:
		_hero_down.play()


func play_hero_recruited() -> void:
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
	var stereo: AudioStreamPlayer = node as AudioStreamPlayer
	if stereo:
		stereo.stop()
	var positional: AudioStreamPlayer2D = node as AudioStreamPlayer2D
	if positional:
		positional.stop()
	for child: Node in node.get_children():
		stop_all_players(child)


func _create_player(node_name: StringName, stream: AudioStream = null, bus: StringName = &"Sfx") -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = node_name
	player.stream = stream
	player.bus = bus
	add_child(player)
	return player


func _create_random_player(streams: Array[AudioStream], pitch: float, polyphony: int, node_name: StringName) -> AudioStreamPlayer:
	var randomizer: AudioStreamRandomizer = AudioStreamRandomizer.new()
	for stream: AudioStream in streams:
		randomizer.add_stream(-1, stream)
	randomizer.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	randomizer.random_pitch = pitch
	var player: AudioStreamPlayer = _create_player(node_name, randomizer)
	player.max_polyphony = polyphony
	return player


func _can_play_throttled(player: AudioStreamPlayer, throttle_msec: int) -> bool:
	var now: int = Time.get_ticks_msec()
	if _last_play_times_msec.has(player) and now - _last_play_times_msec[player] < throttle_msec:
		return false
	_last_play_times_msec[player] = now
	return true


func _play_throttled(player: AudioStreamPlayer, throttle_msec: int) -> void:
	if _can_play_throttled(player, throttle_msec):
		player.play()


func _play_music(stream: AudioStreamOggVorbis) -> void:
	stream.loop = true
	if _music_player.stream == stream and _music_player.playing:
		return
	_music_player.stream = stream
	_music_player.play()


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

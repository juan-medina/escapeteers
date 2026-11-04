# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

extends Node

signal fullscreen_changed

const CONFIG_PATH: StringName = &"user://game_options.cfg"
const SECTION_DISPLAY: StringName = &"display"
const CRT_SECTION: StringName = &"crt"
const SECTION_AUDIO: StringName = &"audio"
const SECTION_EULA: StringName = &"eula"

const DEFAULT_FULLSCREEN: bool = true
const DEFAULT_MASTER_VOLUME: float = 0.8
const DEFAULT_MUSIC_VOLUME: float = 0.7
const DEFAULT_SFX_VOLUME: float = 1.0
const DEFAULT_EULA_VERSION: StringName = &""
const DEFAULT_CRT_BORDER: bool = true
const DEFAULT_SCANLINES: bool = false
const DEFAULT_CURVATURE: bool = false

const ARG_DEV_USER: StringName = &"--dev_user="

var dev_user: StringName = &""

var fullscreen: bool = DEFAULT_FULLSCREEN:
	get():
		return fullscreen
	set(value):
		if fullscreen == value:
			return
		fullscreen_changed.emit(value)
		fullscreen = value
		_apply_fullscreen()
		_save_options()

var crt_border: bool = true:
	get():
		return crt_border
	set(value):
		if crt_border == value:
			return
		crt_border = value
		_apply_crt_settings()
		_save_options()

var scanlines: bool = true:
	get():
		return scanlines
	set(value):
		if scanlines == value:
			return
		scanlines = value
		_apply_crt_settings()
		_save_options()

var curvature: bool = true:
	get():
		return curvature
	set(value):
		if curvature == value:
			return
		curvature = value
		_apply_crt_settings()
		_save_options()

var music_volume: float = DEFAULT_MUSIC_VOLUME:
	get():
		return music_volume
	set(value):
		if music_volume == value:
			return
		music_volume = value
		_apply_bus_volume(&"Music", music_volume)
		_save_options()

var master_volume: float = DEFAULT_MASTER_VOLUME:
	get():
		return master_volume
	set(value):
		if master_volume == value:
			return
		master_volume = value
		_apply_bus_volume(&"Master", master_volume)
		_save_options()

var sfx_volume: float = DEFAULT_SFX_VOLUME:
	get():
		return sfx_volume
	set(value):
		if sfx_volume == value:
			return
		sfx_volume = value
		_apply_bus_volume(&"Sfx", sfx_volume)
		_save_options()

var eula_accepted_version: StringName = DEFAULT_EULA_VERSION:
	get():
		return eula_accepted_version
	set(value):
		if eula_accepted_version == value:
			return
		eula_accepted_version = value
		_save_options()

var _base_master_db: float = 0.0
var _base_music_db: float = 0.0
var _base_sfx_db: float = 0.0


func _ready() -> void:
	print(&"Options: Initializing...")
	process_mode = Node.PROCESS_MODE_ALWAYS

	_parse_arguments()
	await BuildInfo.initialize()
	_update_title()

	# Cache default bus decibel levels from the audio bus layout.
	_base_master_db = AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Master"))
	_base_music_db = AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music"))
	_base_sfx_db = AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Sfx"))

	_load_options()
	_apply_all_settings()


func _parse_arguments() -> void:
	var all_args: PackedStringArray = OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())

	for arg: String in all_args:
		if arg.begins_with(ARG_DEV_USER):
			dev_user = arg.trim_prefix(ARG_DEV_USER)

	if not dev_user.is_empty():
		print_verbose(&"Options: Dev User configured: %s" % dev_user)


func _update_title() -> void:
	if OS.is_debug_build():
		var base_title: StringName = str(ProjectSettings.get_setting("application/config/name", &""))
		var pid: int = OS.get_process_id()
		if dev_user.is_empty():
			get_window().title = "%s - %d" % [base_title, pid]
		else:
			get_window().title = "%s - %d - %s" % [base_title, pid, dev_user]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen"):
		fullscreen = not fullscreen
		_apply_fullscreen()
		_save_options()


func _load_options() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load(CONFIG_PATH)

	if err == OK:
		fullscreen = config.get_value(SECTION_DISPLAY, &"fullscreen", DEFAULT_FULLSCREEN)
		master_volume = config.get_value(SECTION_AUDIO, &"master_volume", DEFAULT_MASTER_VOLUME)
		music_volume = config.get_value(SECTION_AUDIO, &"music_volume", DEFAULT_MUSIC_VOLUME)
		sfx_volume = config.get_value(SECTION_AUDIO, &"sfx_volume", DEFAULT_SFX_VOLUME)
		eula_accepted_version = config.get_value(SECTION_EULA, &"accepted_version", DEFAULT_EULA_VERSION)
		scanlines = config.get_value(CRT_SECTION, &"scanlines", DEFAULT_SCANLINES)
		curvature = config.get_value(CRT_SECTION, &"curvature", DEFAULT_CURVATURE)
		crt_border = config.get_value(CRT_SECTION, &"crt_border", DEFAULT_CRT_BORDER)
	else:
		# First time launch or missing config - set defaults
		fullscreen = DEFAULT_FULLSCREEN
		master_volume = DEFAULT_MASTER_VOLUME
		music_volume = DEFAULT_MUSIC_VOLUME
		sfx_volume = DEFAULT_SFX_VOLUME
		eula_accepted_version = DEFAULT_EULA_VERSION
		scanlines = DEFAULT_SCANLINES
		curvature = DEFAULT_CURVATURE
		crt_border = DEFAULT_CRT_BORDER


func _save_options() -> void:
	var config: ConfigFile = ConfigFile.new()

	config.set_value(SECTION_DISPLAY, &"fullscreen", fullscreen)

	config.set_value(SECTION_AUDIO, &"master_volume", master_volume)
	config.set_value(SECTION_AUDIO, &"music_volume", music_volume)
	config.set_value(SECTION_AUDIO, &"sfx_volume", sfx_volume)
	config.set_value(SECTION_EULA, &"accepted_version", eula_accepted_version)
	config.set_value(CRT_SECTION, &"scanlines", scanlines)
	config.set_value(CRT_SECTION, &"curvature", curvature)
	config.set_value(CRT_SECTION, &"crt_border", crt_border)

	var err: Error = config.save(CONFIG_PATH)
	if err != OK:
		printerr(&"Options: Failed to save config to %s. Error: %d !" % [CONFIG_PATH, err])


func is_eula_accepted(minor_version: StringName) -> bool:
	return eula_accepted_version == minor_version


func _apply_all_settings() -> void:
	_apply_fullscreen()
	_apply_bus_volume(&"Master", master_volume)
	_apply_bus_volume(&"Music", music_volume)
	_apply_bus_volume(&"Sfx", sfx_volume)
	_apply_crt_settings()


func _apply_fullscreen() -> void:
	var mode: DisplayServer.WindowMode = (
		DisplayServer.WindowMode.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WindowMode.WINDOW_MODE_WINDOWED
	)
	DisplayServer.window_set_mode(mode)


func _apply_crt_settings() -> void:
	Crt.set_border_enabled(crt_border)
	Crt.set_scanlines_enabled(scanlines)
	Crt.set_curvature_enabled(curvature)


func _apply_bus_volume(bus_name: StringName, volume_linear: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index >= 0:
		var base_db: float
		match bus_name:
			&"Music":
				base_db = _base_music_db
			&"Sfx":
				base_db = _base_sfx_db
			_:
				base_db = _base_master_db

		# Convert linear 0.0-1.0 to Db offset, and apply to the base Db
		var volume_db: float = base_db + linear_to_db(volume_linear * volume_linear) if volume_linear > 0.0 else -80.0
		AudioServer.set_bus_volume_db(bus_index, volume_db)
	else:
		printerr(&"Options: Audio Bus '%s' not found!" % bus_name)

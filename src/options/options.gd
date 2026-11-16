# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

extends Node

signal fullscreen_changed(enabled: bool)

const CONFIG_PATH: StringName = &"user://game_options.cfg"
const SECTION_DISPLAY: StringName = &"display"
const SECTION_CRT: StringName = &"crt"
const SECTION_AUDIO: StringName = &"audio"
const SECTION_EULA: StringName = &"eula"
const SECTION_CHANGELOG: StringName = &"changelog"

const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_SFX: StringName = &"Sfx"
const SILENT_DB: float = -80.0

const DEFAULT_FULLSCREEN: bool = true
const DEFAULT_MASTER_VOLUME: float = 0.8
const DEFAULT_MUSIC_VOLUME: float = 0.7
const DEFAULT_SFX_VOLUME: float = 1.0
const DEFAULT_CRT_BORDER: bool = true
const DEFAULT_SCANLINES: bool = false
const DEFAULT_CURVATURE: bool = false

var fullscreen: bool = DEFAULT_FULLSCREEN:
	set(value):
		if fullscreen == value:
			return
		fullscreen = value
		if not _is_loading:
			fullscreen_changed.emit(fullscreen)
			_apply_fullscreen()
			_save_options()

var crt_border: bool = DEFAULT_CRT_BORDER:
	set(value):
		if crt_border == value:
			return
		crt_border = value
		if not _is_loading:
			Crt.set_border_enabled(crt_border)
			_save_options()

var scanlines: bool = DEFAULT_SCANLINES:
	set(value):
		if scanlines == value:
			return
		scanlines = value
		if not _is_loading:
			Crt.set_scanlines_enabled(scanlines)
			_save_options()

var curvature: bool = DEFAULT_CURVATURE:
	set(value):
		if curvature == value:
			return
		curvature = value
		if not _is_loading:
			Crt.set_curvature_enabled(curvature)
			_save_options()

var master_volume: float = DEFAULT_MASTER_VOLUME:
	set(value):
		if master_volume == value:
			return
		master_volume = value
		if not _is_loading:
			_apply_bus_volume(BUS_MASTER, master_volume)
			_save_options()

var music_volume: float = DEFAULT_MUSIC_VOLUME:
	set(value):
		if music_volume == value:
			return
		music_volume = value
		if not _is_loading:
			_apply_bus_volume(BUS_MUSIC, music_volume)
			_save_options()

var sfx_volume: float = DEFAULT_SFX_VOLUME:
	set(value):
		if sfx_volume == value:
			return
		sfx_volume = value
		if not _is_loading:
			_apply_bus_volume(BUS_SFX, sfx_volume)
			_save_options()

var eula_accepted_hash: StringName = &"":
	set(value):
		if eula_accepted_hash == value:
			return
		eula_accepted_hash = value
		if not _is_loading:
			_save_options()

var changelog_seen_hash: StringName = &"":
	set(value):
		if changelog_seen_hash == value:
			return
		changelog_seen_hash = value
		if not _is_loading:
			_save_options()

var _is_loading: bool = false
var _bus_indices: Dictionary[StringName, int] = {}
var _bus_base_dbs: Dictionary[StringName, float] = {}


func _ready() -> void:
	print(&"Options: Initializing...")
	process_mode = Node.PROCESS_MODE_ALWAYS

	await BuildInfo.initialize()
	await HeroData.initialize()
	await EnemyData.initialize()

	# Cache bus indices and default decibel levels from the audio bus layout.
	for bus_name: StringName in [BUS_MASTER, BUS_MUSIC, BUS_SFX]:
		var bus_index: int = AudioServer.get_bus_index(bus_name)
		_bus_indices[bus_name] = bus_index
		_bus_base_dbs[bus_name] = AudioServer.get_bus_volume_db(bus_index)

	_load_options()
	_apply_all_settings()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen"):
		fullscreen = not fullscreen


func is_eula_accepted(hash_value: StringName) -> bool:
	return _matches_hash(eula_accepted_hash, hash_value)


func is_changelog_seen(hash_value: StringName) -> bool:
	return _matches_hash(changelog_seen_hash, hash_value)


func _matches_hash(saved_hash: StringName, target_hash: StringName) -> bool:
	return not target_hash.is_empty() and saved_hash == target_hash


func _load_options() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load(CONFIG_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		printerr(&"Options: Failed to load config from %s. Error: %d !" % [CONFIG_PATH, err])

	_is_loading = true
	fullscreen = config.get_value(SECTION_DISPLAY, &"fullscreen", DEFAULT_FULLSCREEN)
	master_volume = config.get_value(SECTION_AUDIO, &"master_volume", DEFAULT_MASTER_VOLUME)
	music_volume = config.get_value(SECTION_AUDIO, &"music_volume", DEFAULT_MUSIC_VOLUME)
	sfx_volume = config.get_value(SECTION_AUDIO, &"sfx_volume", DEFAULT_SFX_VOLUME)
	eula_accepted_hash = config.get_value(SECTION_EULA, &"accepted_hash", &"")
	changelog_seen_hash = config.get_value(SECTION_CHANGELOG, &"seen_hash", &"")
	scanlines = config.get_value(SECTION_CRT, &"scanlines", DEFAULT_SCANLINES)
	curvature = config.get_value(SECTION_CRT, &"curvature", DEFAULT_CURVATURE)
	crt_border = config.get_value(SECTION_CRT, &"crt_border", DEFAULT_CRT_BORDER)
	_is_loading = false


func _save_options() -> void:
	var config: ConfigFile = ConfigFile.new()

	config.set_value(SECTION_DISPLAY, &"fullscreen", fullscreen)
	config.set_value(SECTION_AUDIO, &"master_volume", master_volume)
	config.set_value(SECTION_AUDIO, &"music_volume", music_volume)
	config.set_value(SECTION_AUDIO, &"sfx_volume", sfx_volume)
	config.set_value(SECTION_EULA, &"accepted_hash", eula_accepted_hash)
	config.set_value(SECTION_CHANGELOG, &"seen_hash", changelog_seen_hash)
	config.set_value(SECTION_CRT, &"scanlines", scanlines)
	config.set_value(SECTION_CRT, &"curvature", curvature)
	config.set_value(SECTION_CRT, &"crt_border", crt_border)

	var err: Error = config.save(CONFIG_PATH)
	if err != OK:
		printerr(&"Options: Failed to save config to %s. Error: %d !" % [CONFIG_PATH, err])


func _apply_all_settings() -> void:
	_apply_fullscreen()
	_apply_bus_volume(BUS_MASTER, master_volume)
	_apply_bus_volume(BUS_MUSIC, music_volume)
	_apply_bus_volume(BUS_SFX, sfx_volume)
	Crt.set_border_enabled(crt_border)
	Crt.set_scanlines_enabled(scanlines)
	Crt.set_curvature_enabled(curvature)


func _apply_fullscreen() -> void:
	var mode: DisplayServer.WindowMode = (
		DisplayServer.WindowMode.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WindowMode.WINDOW_MODE_WINDOWED
	)
	DisplayServer.window_set_mode(mode)


func _apply_bus_volume(bus_name: StringName, volume_linear: float) -> void:
	var bus_index: int = _bus_indices[bus_name]
	var base_db: float = _bus_base_dbs[bus_name]
	# Convert linear 0.0-1.0 to Db offset, and apply to the base Db.
	var volume_db: float = base_db + linear_to_db(volume_linear * volume_linear) if volume_linear > 0.0 else SILENT_DB
	AudioServer.set_bus_volume_db(bus_index, volume_db)

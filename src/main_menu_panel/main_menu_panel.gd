# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name MainMenuPanel
extends UiPanel

signal play_requested
signal codex_requested
signal settings_requested
signal about_requested
signal changelog_requested
signal exit_requested

const ANIM_RUN: StringName = &"run"
const ANIM_IDLE: StringName = &"idle"
const ANIM_BURN: StringName = &"burn"
const PATROL_MIN_X: float = 72.0
const PATROL_MAX_X: float = 212.0
const PATROL_SPEED: float = 28.0
const IDLE_PAUSE_DURATION: float = 1.1
const FLICKER_SPEED: float = 8.0
const SCONCE_BASE_ENERGY: float = 4.2
const SCONCE_BASE_SCALE: float = 0.45
const TORCHERO_BASE_ENERGY: float = 3.2
const TORCHERO_BASE_SCALE: float = 0.75
const TORCH_OFFSET_X: float = 6.0

var _time: float = 0.0
var _patrol_dir: float = 1.0
var _idle_timer: float = 0.0

@onready var _wall_torch: AnimatedSprite2D = $VBox/LogoStage/WallTorch
@onready var _sconce_embers: CPUParticles2D = $VBox/LogoStage/SconceEmbers
@onready var _sconce_light: PointLight2D = $VBox/LogoStage/SconceLight
@onready var _torchero: AnimatedSprite2D = $VBox/LogoStage/Torchero
@onready var _torchero_embers: CPUParticles2D = $VBox/LogoStage/Torchero/TorcheroEmbers
@onready var _torchero_light: PointLight2D = $VBox/LogoStage/Torchero/TorcheroLight
@onready var _codex_badge: Control = $VBox/MenuBox/ButtonsVBox/Codex/UnreadBadge
@onready var _exit_separator: HSeparator = $VBox/MenuBox/ButtonsVBox/HSeparator
@onready var _exit_button: Button = $VBox/MenuBox/ButtonsVBox/Exit


func _ready() -> void:
	super._ready()
	if OS.has_feature(&"web"):
		_exit_separator.visible = false
		_exit_button.visible = false
	Codex.unread_changed.connect(_sync_codex_badge)
	_sync_codex_badge()
	_set_stage_active(is_visible_in_tree())


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready():
		var active: bool = is_visible_in_tree()
		_set_stage_active(active)
		if active:
			Audio.play_music(false)
			_sync_codex_badge()


func _process(delta: float) -> void:
	_time += delta
	_update_lights()
	_update_torchero_patrol(delta)


func _update_lights() -> void:
	var sconce_wave: float = sin(_time * FLICKER_SPEED) * 0.18
	_sconce_light.energy = SCONCE_BASE_ENERGY + sconce_wave
	_sconce_light.texture_scale = SCONCE_BASE_SCALE + sconce_wave * 0.05

	var torchero_wave: float = sin(_time * (FLICKER_SPEED + 1.3) + 1.7) * 0.15
	_torchero_light.energy = TORCHERO_BASE_ENERGY + torchero_wave
	_torchero_light.texture_scale = TORCHERO_BASE_SCALE + torchero_wave * 0.05


func _update_torchero_patrol(delta: float) -> void:
	if _idle_timer > 0.0:
		_idle_timer -= delta
		if _idle_timer <= 0.0:
			_patrol_dir = -_patrol_dir
			_torchero.flip_h = _patrol_dir < 0.0
			_torchero_light.position.x = TORCH_OFFSET_X * _patrol_dir
			_torchero_embers.position.x = TORCH_OFFSET_X * _patrol_dir
			_torchero.play(ANIM_RUN)
		return

	var target_x: float = PATROL_MAX_X if _patrol_dir > 0.0 else PATROL_MIN_X
	_torchero.position.x = move_toward(_torchero.position.x, target_x, PATROL_SPEED * delta)
	if is_equal_approx(_torchero.position.x, target_x):
		_idle_timer = IDLE_PAUSE_DURATION
		_torchero.play(ANIM_IDLE)


func _set_stage_active(active: bool) -> void:
	set_process(active)
	_sconce_light.enabled = active
	_torchero_light.enabled = active
	_sconce_embers.emitting = active
	_torchero_embers.emitting = active
	if active:
		_wall_torch.play(ANIM_BURN)
		_torchero.play(ANIM_IDLE if _idle_timer > 0.0 else ANIM_RUN)
	else:
		_wall_torch.pause()
		_torchero.pause()


func _sync_codex_badge() -> void:
	_codex_badge.visible = Codex.has_any_unread()


func _on_play_pressed() -> void:
	play_requested.emit()


func _on_codex_pressed() -> void:
	codex_requested.emit()


func _on_settings_pressed() -> void:
	settings_requested.emit()


func _on_about_pressed() -> void:
	about_requested.emit()


func _on_changelog_pressed() -> void:
	changelog_requested.emit()


func _on_exit_pressed() -> void:
	exit_requested.emit()

# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name LoadingScreen
extends Control

const PROGRESS_SPEED: float = 3.0
const DOT_INTERVAL: float = 0.28
const MESSAGE_INTERVAL: float = 2.0
const FUNNY_MESSAGES: Array[String] = [
	"Teaching Lava Slimes to aim",
	"Polishing skeleton bones",
	"Bribing the Necromancer",
	"Sharpening floor spikes",
	"Convincing the Priest to heal",
	"Hiding lost heroes in dark corners",
	"Warming up the Wizard's ice spells",
	"Sweeping up yesterday's bones",
	"Checking torches for secret switches",
	"Untangling the Archer's bowstring",
	"Asking the Knight for directions",
	"Inflating Lava Slimes",
	"Waking up grumpy skeletons",
	"Oiling rusty dungeon traps",
	"Counting how many arrows we brought",
	"Telling Torchero where to hide",
	"Stacking skulls in neat little piles",
	"Dent-testing the Templar's shield",
	"Feeding fireballs to the blobs",
	"Dusting off ancient pentagrams",
]

var _target_progress: float = 0.0
var _displayed_progress: float = 0.0
var _last_percent: int = -1
var _dot_time: float = 0.0
var _dot_index: int = 0
var _message_time: float = 0.0
var _message_deck: Array[String] = []
var _base_message: String = ""

@onready var _dust_particles: CPUParticles2D = $DustParticles
@onready var _ember_particles: CPUParticles2D = $EmberParticles
@onready var _squad_node: Node2D = $Squad
@onready var _status_label: Label = $UI/Status
@onready var _progress_bar: ProgressBar = $UI/ProgressBar
@onready var _percentage_label: Label = $UI/Percentage


func set_progress(progress: float) -> void:
	_target_progress = progress


func fade_in(duration: float) -> void:
	_pick_next_message()
	_message_time = 0.0
	_reset_progress()
	modulate.a = 0.0
	_set_active(true)

	var tween: Tween = create_tween()
	tween.tween_property(self, ^"modulate:a", 1.0, duration)
	await tween.finished


func fade_out(duration: float) -> void:
	_target_progress = 1.0
	while _displayed_progress < 0.99:
		await get_tree().process_frame

	_displayed_progress = 1.0
	_progress_bar.value = 1.0
	_last_percent = 100
	_percentage_label.text = "100%"

	var tween: Tween = create_tween()
	tween.tween_property(self, ^"modulate:a", 0.0, duration)
	await tween.finished
	_set_active(false)


func _ready() -> void:
	_set_active(false)


func _process(delta: float) -> void:
	_update_progress(delta)
	_update_text_dots(delta)
	_update_message_rotation(delta)


func _set_active(active: bool) -> void:
	visible = active
	process_mode = Node.PROCESS_MODE_ALWAYS if active else Node.PROCESS_MODE_DISABLED
	set_process(active)
	_dust_particles.emitting = active
	_ember_particles.emitting = active

	for child: Node in _squad_node.get_children():
		var sprite: AnimatedSprite2D = child as AnimatedSprite2D
		if active:
			sprite.play(&"run")
		else:
			sprite.pause()


func _set_base_message(message: String) -> void:
	_base_message = message.trim_suffix("...")
	_dot_index = 0
	_dot_time = 0.0
	_status_label.text = _base_message + "..."


func _reset_progress() -> void:
	_target_progress = 0.0
	_displayed_progress = 0.0
	_progress_bar.value = 0.0
	_last_percent = 0
	_percentage_label.text = "0%"


func _update_progress(delta: float) -> void:
	if _displayed_progress >= _target_progress:
		return

	_displayed_progress = move_toward(_displayed_progress, _target_progress, delta * PROGRESS_SPEED)
	_progress_bar.value = _displayed_progress

	var percent: int = int(roundf(_displayed_progress * 100.0))
	if percent != _last_percent:
		_last_percent = percent
		_percentage_label.text = str(percent) + "%"


func _update_text_dots(delta: float) -> void:
	_dot_time += delta
	if _dot_time < DOT_INTERVAL:
		return

	_dot_time = 0.0
	_dot_index = (_dot_index + 1) % 4
	_status_label.text = _base_message + ".".repeat(_dot_index)


func _update_message_rotation(delta: float) -> void:
	_message_time += delta
	if _message_time < MESSAGE_INTERVAL:
		return

	_message_time = 0.0
	_pick_next_message()


func _pick_next_message() -> void:
	if _message_deck.is_empty():
		_message_deck = FUNNY_MESSAGES.duplicate()
		_message_deck.shuffle()

	var next_message: String = _message_deck.pop_back()
	_set_base_message(next_message)

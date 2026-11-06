# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name LoadingScreen
extends Control

const SWORDSMAN_SCENE: PackedScene = preload("res://character/heroes/swordsman/swordsman.tscn")
const PRIEST_SCENE: PackedScene = preload("res://character/heroes/priest/priest.tscn")
const AXEMAN_SCENE: PackedScene = preload("res://character/heroes/armored_axeman/armored_axeman.tscn")
const ARCHER_SCENE: PackedScene = preload("res://character/heroes/archer/archer.tscn")
const SLIME_SCENE: PackedScene = preload("res://character/enemies/lava_slime/lava_slime.tscn")

const EMBER_COUNT: int = 24
const DUST_COUNT: int = 12

const COLOR_BG: Color = Color(0.05, 0.04, 0.08, 1.0)
const COLOR_GROUND_LINE: Color = Color(0.24, 0.20, 0.32, 1.0)
const COLOR_GROUND_BASE: Color = Color(0.11, 0.09, 0.15, 1.0)
const GROUND_Y: float = 207.0
const COLOR_EMBER_GOLD: Color = Color(1.0, 0.72, 0.24, 1.0)
const COLOR_EMBER_ORANGE: Color = Color(1.0, 0.44, 0.14, 1.0)
const COLOR_EMBER_YELLOW: Color = Color(1.0, 0.92, 0.54, 1.0)

const BAR_X: float = 180.0
const BAR_Y: float = 276.0
const BAR_WIDTH: float = 280.0
const BAR_HEIGHT: float = 12.0
const SEGMENT_WIDTH: float = 6.0
const SEGMENT_GAP: float = 2.0

var _target_progress: float = 0.0
var _displayed_progress: float = 0.0
var _time: float = 0.0
var _dot_time: float = 0.0
var _dot_index: int = 0
var _base_message: String = "Entering the dungeon"

var _ember_positions: PackedVector2Array = PackedVector2Array()
var _ember_speeds: PackedFloat32Array = PackedFloat32Array()
var _ember_sways: PackedFloat32Array = PackedFloat32Array()
var _ember_sizes: PackedFloat32Array = PackedFloat32Array()

var _dust_positions: PackedVector2Array = PackedVector2Array()
var _dust_alphas: PackedFloat32Array = PackedFloat32Array()
var _dust_speeds: PackedFloat32Array = PackedFloat32Array()
var _dust_timer: float = 0.0

@onready var _squad_node: Node2D = $Squad
@onready var _status_label: Label = $UI/Status
@onready var _percentage_label: Label = $UI/Percentage


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_characters()
	_init_particles()
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	_update_progress(delta)
	_update_text_dots(delta)
	_update_embers(delta)
	_update_dust(delta)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG)
	_draw_torch_glow()
	_draw_ground()
	_draw_dust()
	_draw_embers()
	_draw_progress_bar()


func show_instant(initial_message: StringName = &"") -> void:
	if not initial_message.is_empty():
		_set_base_message(String(initial_message))
	_target_progress = 0.0
	_displayed_progress = 0.0
	_percentage_label.text = "0%"
	modulate.a = 1.0
	visible = true


func set_progress(progress: float, message: StringName = &"") -> void:
	_target_progress = clampf(progress, 0.0, 1.0)
	if not message.is_empty():
		_set_base_message(String(message))


func fade_in(initial_message: StringName = &"", duration: float = 0.25) -> void:
	if not initial_message.is_empty():
		_set_base_message(String(initial_message))
	_target_progress = 0.0
	_displayed_progress = 0.0
	_percentage_label.text = "0%"
	modulate.a = 0.0
	visible = true

	var tween: Tween = create_tween()
	tween.tween_property(self, ^"modulate:a", 1.0, duration)
	await tween.finished


func fade_out(duration: float = 0.35) -> void:
	_target_progress = 1.0
	while _displayed_progress < 0.99:
		await get_tree().process_frame

	_displayed_progress = 1.0
	_percentage_label.text = "100%"
	queue_redraw()

	var tween: Tween = create_tween()
	tween.tween_property(self, ^"modulate:a", 0.0, duration)
	await tween.finished
	visible = false


func _set_base_message(message: String) -> void:
	_base_message = message.trim_suffix("...").trim_suffix("..").trim_suffix(".")
	_dot_index = 0
	_dot_time = 0.0
	_status_label.text = _base_message + "..."


func _setup_characters() -> void:
	var scenes: Array[PackedScene] = [SLIME_SCENE, AXEMAN_SCENE, ARCHER_SCENE, PRIEST_SCENE, SWORDSMAN_SCENE]
	var offsets: Array[float] = [-105.0, -55.0, -10.0, 35.0, 80.0]
	var speeds: Array[float] = [2.2, 1.8, 1.9, 1.85, 2.0]
	var frame_offsets: Array[int] = [0, 2, 4, 1, 3]

	for i: int in range(scenes.size()):
		var frames: SpriteFrames = _extract_sprite_frames(scenes[i])
		if frames == null:
			continue

		var sprite: AnimatedSprite2D = AnimatedSprite2D.new()
		sprite.sprite_frames = frames
		sprite.position = Vector2(offsets[i], 0.0)
		sprite.speed_scale = speeds[i]
		sprite.flip_h = false
		_squad_node.add_child(sprite)
		sprite.play(&"run")
		sprite.frame = frame_offsets[i]


func _extract_sprite_frames(scene: PackedScene) -> SpriteFrames:
	var instance: Node = scene.instantiate()
	var sprite: AnimatedSprite2D = instance.get_node_or_null(^"AnimatedSprite2D") as AnimatedSprite2D
	var frames: SpriteFrames = null
	if sprite != null:
		frames = sprite.sprite_frames
	instance.queue_free()
	return frames


func _init_particles() -> void:
	_ember_positions.resize(EMBER_COUNT)
	_ember_speeds.resize(EMBER_COUNT)
	_ember_sways.resize(EMBER_COUNT)
	_ember_sizes.resize(EMBER_COUNT)
	for i: int in range(EMBER_COUNT):
		_reset_ember(i, true)

	_dust_positions.resize(DUST_COUNT)
	_dust_alphas.resize(DUST_COUNT)
	_dust_speeds.resize(DUST_COUNT)
	for j: int in range(DUST_COUNT):
		_dust_alphas[j] = 0.0


func _reset_ember(index: int, random_y: bool = false) -> void:
	var start_y: float = randf_range(160.0, 300.0) if random_y else randf_range(280.0, 310.0)
	_ember_positions[index] = Vector2(randf_range(140.0, 500.0), start_y)
	_ember_speeds[index] = randf_range(20.0, 45.0)
	_ember_sways[index] = randf_range(0.0, TAU)
	_ember_sizes[index] = 1.0 if randf() > 0.35 else 2.0


func _update_embers(delta: float) -> void:
	for i: int in range(EMBER_COUNT):
		var pos: Vector2 = _ember_positions[i]
		pos.y -= _ember_speeds[i] * delta
		pos.x += sin(_time * 2.5 + _ember_sways[i]) * 12.0 * delta
		if pos.y < 35.0 or pos.x < 120.0 or pos.x > 520.0:
			_reset_ember(i)
		else:
			_ember_positions[i] = pos


func _update_dust(delta: float) -> void:
	_dust_timer += delta
	if _dust_timer >= 0.14:
		_dust_timer = 0.0
		_spawn_dust_puff()

	for i: int in range(DUST_COUNT):
		if _dust_alphas[i] > 0.0:
			var pos: Vector2 = _dust_positions[i]
			pos.x -= _dust_speeds[i] * delta
			pos.y -= delta * 3.0
			_dust_positions[i] = pos
			_dust_alphas[i] = maxf(0.0, _dust_alphas[i] - delta * 2.5)


func _spawn_dust_puff() -> void:
	var runner_offsets: Array[float] = [-105.0, -55.0, -10.0, 35.0, 80.0]
	var chosen_x: float = _squad_node.position.x + runner_offsets[randi() % runner_offsets.size()] + randf_range(-6.0, 6.0)
	var spawn_pos: Vector2 = Vector2(chosen_x, GROUND_Y - 1.0)

	for i: int in range(DUST_COUNT):
		if _dust_alphas[i] <= 0.0:
			_dust_positions[i] = spawn_pos
			_dust_alphas[i] = randf_range(0.4, 0.75)
			_dust_speeds[i] = randf_range(25.0, 45.0)
			break


func _update_progress(delta: float) -> void:
	if _displayed_progress < _target_progress:
		_displayed_progress = move_toward(_displayed_progress, _target_progress, delta * 3.0)
		_percentage_label.text = str(int(roundf(_displayed_progress * 100.0))) + "%"


func _update_text_dots(delta: float) -> void:
	_dot_time += delta
	if _dot_time >= 0.28:
		_dot_time = 0.0
		_dot_index = (_dot_index + 1) % 4
		var dots: String = ".".repeat(_dot_index)
		_status_label.text = _base_message + dots


func _draw_torch_glow() -> void:
	var center: Vector2 = Vector2(320.0, 185.0)
	var flicker: float = 0.07 + sin(_time * 7.5) * 0.012 + randf_range(-0.005, 0.005)
	draw_circle(center, 140.0, Color(0.96, 0.58, 0.14, flicker * 0.4))
	draw_circle(center, 80.0, Color(1.0, 0.74, 0.28, flicker * 0.7))


func _draw_ground() -> void:
	draw_rect(Rect2(40.0, GROUND_Y, 560.0, 3.0), COLOR_GROUND_LINE)
	draw_rect(Rect2(40.0, GROUND_Y + 3.0, 560.0, 16.0), COLOR_GROUND_BASE)

	for x: float in range(56.0, 590.0, 32.0):
		draw_line(Vector2(x, GROUND_Y + 3.0), Vector2(x, GROUND_Y + 14.0), Color(0.14, 0.11, 0.19, 0.9), 1.0)


func _draw_dust() -> void:
	for i: int in range(DUST_COUNT):
		if _dust_alphas[i] > 0.0:
			var col: Color = Color(0.38, 0.32, 0.42, _dust_alphas[i])
			draw_rect(Rect2(_dust_positions[i], Vector2(2.0, 2.0)), col)


func _draw_embers() -> void:
	for i: int in range(EMBER_COUNT):
		var pos: Vector2 = _ember_positions[i]
		var ember_size: float = _ember_sizes[i]
		var alpha: float = clampf((pos.y - 35.0) / 180.0, 0.0, 0.9)
		var ember_col: Color = COLOR_EMBER_GOLD
		if i % 3 == 1:
			ember_col = COLOR_EMBER_ORANGE
		elif i % 3 == 2:
			ember_col = COLOR_EMBER_YELLOW
		ember_col.a = alpha
		draw_rect(Rect2(pos, Vector2(ember_size, ember_size)), ember_col)


func _draw_progress_bar() -> void:
	var outer_rect: Rect2 = Rect2(BAR_X, BAR_Y, BAR_WIDTH, BAR_HEIGHT)

	draw_rect(outer_rect.grow(2.0), Color(0.18, 0.14, 0.24, 1.0))
	draw_line(
		Vector2(outer_rect.position.x - 2.0, outer_rect.position.y - 2.0),
		Vector2(outer_rect.end.x + 2.0, outer_rect.position.y - 2.0),
		Color(0.32, 0.26, 0.40, 1.0),
		1.0
	)
	draw_line(
		Vector2(outer_rect.position.x - 2.0, outer_rect.position.y - 2.0),
		Vector2(outer_rect.position.x - 2.0, outer_rect.end.y + 2.0),
		Color(0.32, 0.26, 0.40, 1.0),
		1.0
	)

	draw_rect(outer_rect, Color(0.06, 0.05, 0.09, 1.0))

	var usable_width: float = BAR_WIDTH - 4.0
	var total_segments: int = int(floorf(usable_width / (SEGMENT_WIDTH + SEGMENT_GAP)))
	var active_segments: int = int(roundf(_displayed_progress * float(total_segments)))

	for s: int in range(active_segments):
		var seg_x: float = BAR_X + 2.0 + float(s) * (SEGMENT_WIDTH + SEGMENT_GAP)
		var seg_rect: Rect2 = Rect2(seg_x, BAR_Y + 2.0, SEGMENT_WIDTH, BAR_HEIGHT - 4.0)

		var top_rect: Rect2 = Rect2(seg_x, BAR_Y + 2.0, SEGMENT_WIDTH, (BAR_HEIGHT - 4.0) * 0.5)
		var bot_rect: Rect2 = Rect2(seg_x, BAR_Y + 2.0 + (BAR_HEIGHT - 4.0) * 0.5, SEGMENT_WIDTH, (BAR_HEIGHT - 4.0) * 0.5)

		if s == active_segments - 1 and _displayed_progress < 0.99:
			draw_rect(seg_rect, COLOR_EMBER_YELLOW)
		else:
			draw_rect(top_rect, COLOR_EMBER_GOLD)
			draw_rect(bot_rect, COLOR_EMBER_ORANGE)

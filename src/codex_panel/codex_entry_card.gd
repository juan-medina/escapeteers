# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name CodexEntryCard
extends Button

signal inspected(entry_id: StringName)

const LOCKED_SILHOUETTE_COLOR: Color = Color(0.06, 0.06, 0.09, 1.0)
const LOCKED_TEXT_COLOR: Color = Color(0.50, 0.54, 0.62, 1.0)

@export var entry_id: StringName = &""

var _sprite_frames: SpriteFrames = null
var _display_name: String = ""
var _display_color: Color = Color.WHITE
var _discovered: bool = false

@onready var _preview_sprite: AnimatedSprite2D = $Margin/HBox/PreviewContainer/PreviewSprite
@onready var _name_label: Label = $Margin/HBox/NameLabel
@onready var _unread_badge: Control = $UnreadBadge


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready():
		_sync_sprite_playback()


func setup_hero() -> void:
	var data: HeroData = HeroData.get_hero(entry_id)
	_sprite_frames = data.sprite_frames
	_display_name = data.name
	_display_color = data.color
	_preview_sprite.sprite_frames = _sprite_frames


func setup_enemy() -> void:
	var data: EnemyData = EnemyData.get_enemy(entry_id)
	_sprite_frames = data.sprite_frames
	_display_name = data.name
	_display_color = data.color
	_preview_sprite.sprite_frames = _sprite_frames


func refresh_state(discovered: bool, unread: bool) -> void:
	_discovered = discovered
	if _discovered:
		_preview_sprite.modulate = Color.WHITE
		_name_label.text = _display_name
		_name_label.add_theme_color_override(&"font_color", _display_color)
		_unread_badge.visible = unread
	else:
		_preview_sprite.modulate = LOCKED_SILHOUETTE_COLOR
		_name_label.text = &"???"
		_name_label.add_theme_color_override(&"font_color", LOCKED_TEXT_COLOR)
		_unread_badge.visible = false
	_sync_sprite_playback()


func emit_inspected() -> void:
	inspected.emit(entry_id)


func _sync_sprite_playback() -> void:
	if _sprite_frames == null:
		return
	if is_visible_in_tree() and _discovered:
		_preview_sprite.play(Character.ANIM_IDLE)
	else:
		_preview_sprite.animation = Character.ANIM_IDLE
		_preview_sprite.frame = 0
		_preview_sprite.pause()


func _on_focus_entered() -> void:
	emit_inspected()


func _on_mouse_entered() -> void:
	emit_inspected()


func _on_pressed() -> void:
	emit_inspected()

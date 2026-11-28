# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name CodexEntryCard
extends Button

signal inspected(entry_id: StringName)

const LOCKED_SILHOUETTE_COLOR: Color = Color(0.06, 0.06, 0.09, 1.0)
const LOCKED_TEXT_COLOR: Color = Color(0.50, 0.54, 0.62, 1.0)

@export var entry_id: StringName = &""

var _sprite_frames: SpriteFrames = null
var _anim_name: StringName = Character.ANIM_IDLE
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


func setup_item(item_name: String, color: Color, frames: SpriteFrames, anim_name: StringName) -> void:
	_sprite_frames = frames
	_anim_name = anim_name
	_display_name = item_name
	_display_color = color
	_preview_sprite.sprite_frames = _sprite_frames
	_preview_sprite.scale = Vector2(2.0, 2.0)


func setup_event(event_name: String, color: Color, frames: SpriteFrames, anim_name: StringName, icon_scale: float = 1.0) -> void:
	_sprite_frames = frames
	_anim_name = anim_name
	_display_name = event_name
	_display_color = color
	_preview_sprite.sprite_frames = _sprite_frames
	_preview_sprite.scale = Vector2(icon_scale, icon_scale)


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
		_preview_sprite.play(_anim_name)
	else:
		_preview_sprite.animation = _anim_name
		_preview_sprite.frame = 0
		_preview_sprite.pause()


func _on_focus_entered() -> void:
	emit_inspected()


func _on_mouse_entered() -> void:
	emit_inspected()


func _on_pressed() -> void:
	emit_inspected()

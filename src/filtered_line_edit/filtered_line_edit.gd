# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name FilteredLineEdit
extends LineEdit

signal filtered_text_changed(new_text: String, has_error: bool)

@export var invalid_chars: String = "[^a-zA-Z0-9 ]":
	set(value):
		invalid_chars = value
		_compile_regex()

@export var min_length: int = 0

var _regex: RegEx = RegEx.new()

var _default_theme_font_color: Color


func _init() -> void:
	text_changed.connect(_on_text_changed)
	focus_exited.connect(_on_focus_exited)


func _ready() -> void:
	await BadWordFilter.initialize()
	_compile_regex()
	editable = false
	_default_theme_font_color = get_theme_color("font_color")
	add_theme_color_override("font_uneditable_color", _default_theme_font_color)


func _gui_input(event: InputEvent) -> void:
	if _should_edit(event):
		return

	if event.is_action_pressed(&"ui_accept") and has_focus():
		if editable:
			return

		accept_event()
		Audio.play_click()
		var result: KeyboardResult = await VirtualInput.prompt_keyboard(text, max_length)
		if result.confirmed:
			set_text_value(result.text)

		var next: Control = find_next_valid_focus()
		if next:
			next.grab_focus()


func _should_edit(event: InputEvent) -> bool:
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		editable = true
		return true
	return false


func _on_focus_exited() -> void:
	editable = false


func _compile_regex() -> void:
	if invalid_chars.is_empty():
		_regex.clear()
	else:
		_regex.compile(invalid_chars)


func _remove_invalid_characters(new_text: String) -> String:
	if not _regex.is_valid():
		return new_text
	return _regex.sub(new_text, "", true)


func _on_text_changed(unfiltered_text: String) -> void:
	# Godot will move the caret forward before firing the event
	var new_caret_position: int = caret_column

	# this function will remove any invalid characters
	# and calculate if we have rejected any character
	var rejected_characters: int = set_text_value(unfiltered_text)

	# move the caret back by the number of rejected characters
	if rejected_characters > 0:
		new_caret_position -= rejected_characters

	caret_column = new_caret_position


func copy_to_clipboard() -> void:
	DisplayServer.clipboard_set(text)


func paste_from_clipboard() -> void:
	set_text_value(DisplayServer.clipboard_get())


func set_text_value(new_text: String) -> int:
	text = _remove_invalid_characters(new_text)
	caret_column = text.length()

	var has_error: bool = not _validate_text(text)
	if has_error:
		add_theme_color_override("font_color", Color.RED)
		add_theme_color_override("caret_color", Color.RED)
		add_theme_color_override("font_uneditable_color", Color.RED)
	else:
		remove_theme_color_override("font_color")
		remove_theme_color_override("caret_color")
		add_theme_color_override("font_uneditable_color", _default_theme_font_color)

	filtered_text_changed.emit(text, has_error)

	return new_text.length() - text.length()


func _validate_text(new_text: String) -> bool:
	if min_length > 0 and new_text.length() < min_length:
		return false

	if BadWordFilter.is_bad(new_text):
		return false

	return true

# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name BigTextPanel
extends MenuPanel

const SCROLL_SPEED: float = 500.0
const WEBSITE_URL: StringName = &"https://github.com/juan-medina/escapeteers"

@export var title: String = ""
@export_file("*.txt") var text_file: String = ""

var file_hash: StringName = &""

@onready var _title_label: Label = $VBox/Title
@onready var _text_label: RichTextLabel = $VBox/Text


func _ready() -> void:
	_title_label.text = title
	file_hash = StringName(FileAccess.get_sha256(text_file))
	set_process(is_visible_in_tree())
	super._ready()
	await _load_file()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		set_process(is_visible_in_tree())


func _process(delta: float) -> void:
	var scroll_input: float = Input.get_axis(&"ui_up", &"ui_down")
	if absf(scroll_input) > 0.1:
		_text_label.get_v_scroll_bar().value += scroll_input * SCROLL_SPEED * delta


func _load_file() -> void:
	var file: FileAccess = FileAccess.open(text_file, FileAccess.READ)
	if file == null:
		printerr(&"BigTextPanel: Failed to open %s !" % text_file)
		await Alerts.fatal_error(&"Could not load game data")
		return

	# {build} is a placeholder in the text files, filled with the build stamp.
	var content: String = file.get_as_text().replace(&"{build}", BuildInfo.display_string())

	# In the web build, include a link to download the desktop release.
	var download_text: String = ""
	if OS.has_feature(&"web"):
		download_text = (
			&"\n[center]Download the desktop version from: [pulse freq=2.0 color=#6cc6ff][url=%s/]itch.io[/url][/pulse][/center]\n" % WEBSITE_URL
		)

	_text_label.text = content.replace(&"{download}", download_text)
	file.close()


func _on_meta_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))

# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name BigTextPanel
extends RichTextLabel

const SCROLL_SPEED: float = 500.0

const DOWNLOAD_LINK: StringName = &"https://github.com/juan-medina/escapeteers"


func _ready() -> void:
	set_process(is_visible_in_tree())


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		set_process(is_visible_in_tree())


func _process(delta: float) -> void:
	var scroll_input: float = Input.get_axis(&"ui_up", &"ui_down")
	if absf(scroll_input) > 0.1:
		get_v_scroll_bar().value += scroll_input * SCROLL_SPEED * delta


func load_file(path: StringName) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		printerr(&"BigTextPanel: Failed to open %s !" % path)
		await Alerts.fatal_error(&"Could not load game data")
		return

	# {build} is a placeholder in the text files, filled with the build stamp.
	text = file.get_as_text().replace(&"{build}", BuildInfo.display_string())

	# In the web build, include a link to download the desktop release.
	var download_text: String = ""
	if OS.has_feature(&"web"):
		download_text = (
			&"\n[center]Download the desktop version from: [pulse freq=2.0 color=#6cc6ff][url=%s/]itch.io[/url][/pulse][/center]\n" % DOWNLOAD_LINK
		)

	text = text.replace(&"{download}", download_text)
	file.close()


func _on_meta_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))

# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name PanelHost
extends CanvasLayer

const CROSSFADE: float = 0.12

var _current: MenuPanel = null
var _busy: bool = false


func _show_first(panel: MenuPanel) -> void:
	_hide_all_panels(self)
	_current = panel
	panel.modulate.a = 1.0
	panel.process_mode = Node.PROCESS_MODE_INHERIT
	panel.visible = true
	panel.grab_first_focus()


func _hide_all_panels(from: Node) -> void:
	for child: Node in from.get_children():
		var panel: MenuPanel = child as MenuPanel
		if panel != null:
			panel.visible = false
		_hide_all_panels(child)


func show_panel(next: MenuPanel) -> void:
	if _busy or next == _current:
		return
	_busy = true

	# Drop focus so a second accept during the crossfade hits no button;
	# _on_swap_finished re-grabs focus on the incoming panel.
	get_viewport().gui_release_focus()

	var previous: MenuPanel = _current
	_current = next

	next.modulate.a = 0.0
	next.process_mode = Node.PROCESS_MODE_DISABLED
	next.visible = true

	var tween: Tween = create_tween().set_parallel(true)
	if previous != null:
		previous.process_mode = Node.PROCESS_MODE_DISABLED
		tween.tween_property(previous, ^"modulate:a", 0.0, CROSSFADE)
	tween.tween_property(next, ^"modulate:a", 1.0, CROSSFADE)
	tween.finished.connect(_on_swap_finished.bind(previous, next))


func _on_swap_finished(previous: MenuPanel, next: MenuPanel) -> void:
	if previous != null:
		previous.visible = false
	next.process_mode = Node.PROCESS_MODE_INHERIT
	next.grab_first_focus()
	_busy = false


func set_host_alpha(alpha: float) -> void:
	for child: Node in get_children():
		var control: Control = child as Control
		if control != null:
			control.modulate.a = alpha


func fade_host(target_alpha: float) -> Tween:
	var tween: Tween = create_tween().set_parallel(true)
	for child: Node in get_children():
		var control: Control = child as Control
		if control != null:
			tween.tween_property(control, ^"modulate:a", target_alpha, CROSSFADE)
	return tween

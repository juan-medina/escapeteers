# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name PanelHost
extends CanvasLayer

const CROSSFADE: float = 0.12
const DOT_INTERVAL: float = 0.3

const DOT_STATES: Array[StringName] = [&".", &"..", &"..."]

var _current: MenuPanel = null
var _busy: bool = false
var _is_panel_busy: bool = false
var _dot_index: int = 0

var _blocker: ColorRect = null
var _busy_label: Label = null
var _busy_timer: Timer = null


func _ready() -> void:
	_setup_blocker()


func _setup_blocker() -> void:
	_blocker = ColorRect.new()
	_blocker.name = &"BusyBlocker"
	_blocker.color = Color(0, 0, 0, 0.4)
	_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocker.visible = false
	add_child(_blocker)
	move_child(_blocker, -1)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blocker.add_child(center)

	_busy_label = Label.new()
	_busy_label.text = DOT_STATES[0]
	_busy_label.add_theme_font_size_override(&"font_size", 48)
	_busy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_busy_label)

	_busy_timer = Timer.new()
	_busy_timer.wait_time = DOT_INTERVAL
	_busy_timer.timeout.connect(_on_busy_timer_timeout)
	add_child(_busy_timer)


func _on_busy_timer_timeout() -> void:
	_dot_index = (_dot_index + 1) % DOT_STATES.size()
	_busy_label.text = DOT_STATES[_dot_index]


func _on_panel_busy_changed(is_busy: bool) -> void:
	set_busy(is_busy)


func set_busy(is_busy: bool) -> void:
	_is_panel_busy = is_busy
	_blocker.visible = is_busy
	if is_busy:
		move_child(_blocker, -1)
		_dot_index = 0
		_busy_label.text = DOT_STATES[0]
		_busy_timer.start()
	else:
		_busy_timer.stop()


func _input(_event: InputEvent) -> void:
	if _is_panel_busy:
		get_viewport().set_input_as_handled()


func _show_first(panel: MenuPanel) -> void:
	_hide_all_panels(self)
	_current = panel
	panel.modulate.a = 1.0
	panel.process_mode = Node.PROCESS_MODE_INHERIT
	panel.visible = true
	Audio.grab_focus_silent(panel.first_focus_control())


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
	Audio.grab_focus_silent(next.first_focus_control())
	_busy = false


func set_host_alpha(alpha: float) -> void:
	for child: Node in get_children():
		var control: Control = child as Control
		if control != null and control != _blocker:
			control.modulate.a = alpha


func fade_host(target_alpha: float) -> Tween:
	var tween: Tween = create_tween().set_parallel(true)
	for child: Node in get_children():
		var control: Control = child as Control
		if control != null and control != _blocker:
			tween.tween_property(control, ^"modulate:a", target_alpha, CROSSFADE)
	return tween

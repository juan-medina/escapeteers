# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name MapOverlay
extends Control


class RoomLabelEntry:
	extends RefCounted
	var room: Rect2i
	var label: Label
	var world_center: Vector2
	var depth: int
	var is_event: bool
	var active_event: bool
	var last_color: Color = Color(0.0, 0.0, 0.0, 0.0)

	func _init(
		entry_room: Rect2i,
		entry_label: Label,
		entry_center: Vector2,
		entry_depth: int,
		entry_is_event: bool,
		entry_active_event: bool,
	) -> void:
		room = entry_room
		label = entry_label
		world_center = entry_center
		depth = entry_depth
		is_event = entry_is_event
		active_event = entry_active_event


const TILE_SIZE: float = 16.0
const CHUNK_SIZE_TILES: int = 2
const CHUNK_SIZE_PX: float = float(CHUNK_SIZE_TILES) * TILE_SIZE
const ZOOM_LEVELS: Array[float] = [0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0]
const DEFAULT_ZOOM: float = 2.0
const MIN_ZOOM: float = 0.5
const MAX_ZOOM: float = 4.0
const ZOOM_LERP_SPEED: float = 18.0
const TRIGGER_ZOOM_RATE: float = 2.4
const TRIGGER_DEADZONE: float = 0.25
const PAN_SCREEN_SPEED: float = 260.0
const RECENTER_LERP_SPEED: float = 14.0
const PAN_BOUNDS_MARGIN_PX: float = 96.0
const LABEL_ALL_MIN_ZOOM: float = 1.2
const PAN_ACTIONS: Array[StringName] = [&"left", &"right", &"up", &"down"]
const ROOM_LABEL_SCENE: PackedScene = preload("res://hud/map_overlay/room_level_label.tscn")
const DOOR_COLORS: Array[Color] = [
	Color(0.25, 0.68, 1.0, 1.0),
	Color(0.30, 0.92, 0.48, 1.0),
	Color(1.0, 0.86, 0.25, 1.0),
	Color(1.0, 0.35, 0.35, 1.0),
]
const DOOR_BAR_HALF_THICKNESS: float = 8.0
const SHORTCUT_BAR_HALF_THICKNESS: float = 6.0
const SHORTCUT_CHEVRON_GAP: float = 4.0
const SHORTCUT_CHEVRON_LENGTH: float = 22.0
const SHORTCUT_CHEVRON_HALF_WIDTH: float = 18.0
const LABEL_HALF_SIZE: Vector2 = Vector2(16.0, 8.0)
const LABEL_COLOR_SAFE: Color = Color(0.55, 0.95, 0.62, 1.0)
const LABEL_COLOR_CAUTION: Color = Color(1.0, 0.82, 0.32, 1.0)
const LABEL_COLOR_DANGER: Color = Color(1.0, 0.38, 0.35, 1.0)
const LABEL_COLOR_START: Color = Color(0.70, 0.88, 1.0, 1.0)
const LABEL_COLOR_EVENT: Color = Color(1.0, 0.38, 0.65, 1.0)
const PLAYER_PULSE_COLOR_A: Color = Color(0.22, 0.72, 0.88, 1.0)
const PLAYER_PULSE_COLOR_B: Color = Color(0.75, 0.98, 1.0, 1.0)
const HUD_EDGE_MARGIN_LEFT: float = 22.0
const HUD_EDGE_MARGIN_RIGHT: float = 22.0
const HUD_EDGE_MARGIN_TOP: float = 38.0
const HUD_EDGE_MARGIN_BOTTOM: float = 26.0
const HUD_ON_SCREEN_PAD: float = 8.0

## Screen pixels per world tile. Defaults to crisp 2px per tile.
@export_range(1, 8) var pixels_per_tile: int = 2
@export_range(1, 16) var reveal_chunk_radius: int = 8
@export_range(1, 8) var explore_chunk_radius: int = 2

var map_scale: float = 0.0

var _plan: WorldPlan = null
var _target: Hero = null
var _squad_level: int = 1
var _revealed_chunks: Dictionary[Vector2i, bool] = {}
var _explored_chunks: Dictionary[Vector2i, bool] = {}
var _discovered_rooms: Dictionary[Rect2i, bool] = {}
var _discovered_labels: Array[RoomLabelEntry] = []
var _label_pool: Array[Label] = []
var _next_label_pool_idx: int = 0
var _last_revealed_chunk: Vector2i = Vector2i(2147483647, 2147483647)
var _zoom_px_per_tile: float = DEFAULT_ZOOM
var _target_zoom: float = DEFAULT_ZOOM
var _zoom_anchor_screen: Vector2 = Vector2.ZERO
var _has_zoom_anchor: bool = false
var _last_zoom_pct: int = -1
var _camera_world_pos: Vector2 = Vector2.ZERO
var _is_recentering: bool = false
var _is_dragging: bool = false
var _paused_by_map: bool = false
var _blocked_pan_actions: Dictionary[StringName, bool] = {}
var _wait_left_stick_release: bool = false
var _wait_right_stick_release: bool = false
var _has_revealed_bounds: bool = false
var _revealed_min_chunk: Vector2i = Vector2i.ZERO
var _revealed_max_chunk: Vector2i = Vector2i.ZERO
var _dirty: bool = false
var _collected_keys: Dictionary[WorldPlan.KeyColor, bool] = {}
var _door_entries: Array[Dictionary] = []
var _key_entries: Array[Dictionary] = []
var _shortcut_entries: Array[Dictionary] = []
var _pulse_time: float = 0.0
var _hud_door_indicators: Array[Node2D] = []
var _hud_door_arrows: Array[Node2D] = []
var _hud_key_indicators: Array[Node2D] = []
var _hud_key_arrows: Array[Node2D] = []
var _chunk_meshes: MapChunkMeshes = MapChunkMeshes.new()
var _visibility: MapVisibility = MapVisibility.new()
var _visited_fov_chunks: Dictionary[Vector2i, bool] = {}
var _fov_chunks: Dictionary[Vector2i, bool] = {}

@onready var _zoom_label: Label = $FrameMargin/VBox/HeaderBar/ZoomLabel
@onready var _controls_hint: Label = $FrameMargin/VBox/FooterBar/ControlsHint
@onready var _map_viewport: Control = $FrameMargin/VBox/MapFrame/MapViewport
@onready var _chunks_container: Node2D = $FrameMargin/VBox/MapFrame/MapViewport/Chunks
@onready var _unexplored_floor_mesh: MeshInstance2D = $FrameMargin/VBox/MapFrame/MapViewport/Chunks/UnexploredFloorMesh
@onready var _explored_floor_mesh: MeshInstance2D = $FrameMargin/VBox/MapFrame/MapViewport/Chunks/ExploredFloorMesh
@onready var _walls_mesh: MeshInstance2D = $FrameMargin/VBox/MapFrame/MapViewport/Chunks/WallsMesh
@onready var _shortcut_lines_mesh: MeshInstance2D = $FrameMargin/VBox/MapFrame/MapViewport/Chunks/ShortcutLinesMesh
@onready var _room_labels_container: Node2D = $FrameMargin/VBox/MapFrame/MapViewport/RoomLabels
@onready var _player_marker: Node2D = $FrameMargin/VBox/MapFrame/MapViewport/PlayerMarker
@onready var _player_pulse_ring: Line2D = $FrameMargin/VBox/MapFrame/MapViewport/PlayerMarker/PulseRing
@onready var _door_meshes: Array[MeshInstance2D] = [
	$FrameMargin/VBox/MapFrame/MapViewport/Chunks/BlueDoorMesh,
	$FrameMargin/VBox/MapFrame/MapViewport/Chunks/GreenDoorMesh,
	$FrameMargin/VBox/MapFrame/MapViewport/Chunks/YellowDoorMesh,
	$FrameMargin/VBox/MapFrame/MapViewport/Chunks/RedDoorMesh,
]
@onready var _key_markers: Array[Polygon2D] = [
	$FrameMargin/VBox/MapFrame/MapViewport/Chunks/BlueKeyMarker,
	$FrameMargin/VBox/MapFrame/MapViewport/Chunks/GreenKeyMarker,
	$FrameMargin/VBox/MapFrame/MapViewport/Chunks/YellowKeyMarker,
	$FrameMargin/VBox/MapFrame/MapViewport/Chunks/RedKeyMarker,
]


func _ready() -> void:
	visible = false
	set_process(false)
	_chunk_meshes.bind_layers(_unexplored_floor_mesh, _explored_floor_mesh, _walls_mesh)
	InputManager.input_mode_changed.connect(_on_input_mode_changed)
	_update_controls_hint(InputManager.current_mode)


func _exit_tree() -> void:
	if _paused_by_map:
		_paused_by_map = false
		get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_map"):
		if not visible and get_tree().paused:
			return
		Audio.play_click()
		toggle()
		get_viewport().set_input_as_handled()
		return

	if not visible:
		return

	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"back"):
		Audio.play_click()
		set_map_visible(false)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(&"ui_accept"):
		_request_recenter()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.is_pressed():
			if key.keycode == KEY_PLUS or key.keycode == KEY_EQUAL or key.keycode == KEY_KP_ADD or key.unicode == 43:
				_step_zoom(1, false)
				get_viewport().set_input_as_handled()
			elif key.keycode == KEY_MINUS or key.keycode == KEY_KP_SUBTRACT or key.unicode == 45:
				_step_zoom(-1, false)
				get_viewport().set_input_as_handled()
			elif not key.is_echo() and key.keycode == KEY_C:
				_request_recenter()
				get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton:
		var joy_btn: InputEventJoypadButton = event as InputEventJoypadButton
		if joy_btn.is_pressed():
			if joy_btn.button_index == JOY_BUTTON_RIGHT_SHOULDER:
				_step_zoom(1, false)
				get_viewport().set_input_as_handled()
			elif joy_btn.button_index == JOY_BUTTON_LEFT_SHOULDER:
				_step_zoom(-1, false)
				get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if get_tree().paused and not visible:
		return
	_pulse_time += delta
	if not is_instance_valid(_target):
		return
	if visible:
		if _dirty:
			_rebuild_meshes()
		_update_navigation(delta)
		_update_view()
		_update_matching_door_pulses()
		_update_player_pulse()
	else:
		_update_discovery()
		_update_hud_edge_indicators()


func set_hud_edge_indicators(
	door_indicators: Array[Node2D],
	door_arrows: Array[Node2D],
	key_indicators: Array[Node2D],
	key_arrows: Array[Node2D],
) -> void:
	_hud_door_indicators = door_indicators
	_hud_door_arrows = door_arrows
	_hud_key_indicators = key_indicators
	_hud_key_arrows = key_arrows


func setup(plan: WorldPlan, target: Hero) -> void:
	_target = target
	if is_instance_valid(_target) and _target.move_direction.length_squared() > 0.001:
		_player_marker.rotation = _target.move_direction.angle()
	else:
		_player_marker.rotation = -PI * 0.5
	_zoom_px_per_tile = clampf(float(pixels_per_tile), MIN_ZOOM, MAX_ZOOM)
	_target_zoom = _zoom_px_per_tile
	_has_zoom_anchor = false
	_is_recentering = false
	_is_dragging = false
	_blocked_pan_actions.clear()
	_wait_left_stick_release = false
	_wait_right_stick_release = false
	_last_zoom_pct = -1
	_build_chunks(plan)
	set_process(true)
	if is_instance_valid(_target):
		_camera_world_pos = _target.global_position
		_update_discovery()
		_update_zoom_label()
		if visible:
			_update_view()


func toggle() -> void:
	set_map_visible(not visible)


func set_map_visible(is_vis: bool) -> void:
	if is_vis:
		if not visible and get_tree().paused and not _paused_by_map:
			return
		_paused_by_map = true
		get_tree().paused = true
		visible = true
		_is_dragging = false
		_has_zoom_anchor = false
		_zoom_px_per_tile = _target_zoom
		_capture_held_pan_inputs()
		if is_instance_valid(_target):
			_camera_world_pos = _target.global_position
			_is_recentering = false
			if _dirty:
				_rebuild_meshes()
			_refresh_discovered_labels()
			_update_zoom_label()
			_update_view()
	else:
		visible = false
		_is_dragging = false
		_has_zoom_anchor = false
		_blocked_pan_actions.clear()
		_wait_left_stick_release = false
		_wait_right_stick_release = false
		if _paused_by_map:
			_paused_by_map = false
			get_tree().paused = false
	_update_hud_edge_indicators()


func mark_room_discovered(room: Rect2i) -> void:
	if _plan == null or room.size == Vector2i.ZERO or _discovered_rooms.has(room):
		return
	_discovered_rooms[room] = true

	var label: Label
	if _next_label_pool_idx < _label_pool.size():
		label = _label_pool[_next_label_pool_idx]
	else:
		label = ROOM_LABEL_SCENE.instantiate() as Label
		_label_pool.append(label)
		_room_labels_container.add_child(label)
	_next_label_pool_idx += 1

	var is_start: bool = room == _plan.hero_room
	var depth: int = 0 if is_start else clampi(_plan.get_room_depth(room), 1, 12)
	var is_event: bool = _plan.is_event_room(room)
	var active_event: bool = _is_active_event_room(room)
	var world_center: Vector2 = (Vector2(room.position) + Vector2(room.size) * 0.5) * TILE_SIZE
	label.visible = false
	label.text = "Start" if depth <= 0 else (("! Lv.%d" % depth) if active_event else ("Lv.%d" % depth))
	_discovered_labels.append(RoomLabelEntry.new(room, label, world_center, depth, is_event, active_event))
	if visible:
		_refresh_discovered_labels()


func set_squad_level(squad_level: int) -> void:
	if _squad_level == squad_level:
		return
	_squad_level = squad_level
	if visible:
		_refresh_discovered_labels()


func set_key_state(color: WorldPlan.KeyColor, collected: bool, _used: bool) -> void:
	if collected:
		_collected_keys[color] = true
	else:
		_collected_keys.erase(color)
	_update_gate_markers_visibility()


func notify_door_unlocked(gate: SectorGatePlanner.SectorGate) -> void:
	if _plan != null:
		_visibility.open_door(gate)
		_visited_fov_chunks.clear()
		_last_revealed_chunk = Vector2i(2147483647, 2147483647)
	_update_gate_markers_visibility()


func notify_shortcut_opened(shortcut: ShortcutTunnelPlanner.LocalShortcut) -> void:
	if _plan != null:
		_visibility.open_shortcut(shortcut)
		_visited_fov_chunks.clear()
		_last_revealed_chunk = Vector2i(2147483647, 2147483647)
	_update_gate_markers_visibility()


func get_room_color(room: Rect2i) -> Color:
	var depth: int = _plan.get_room_depth(room)
	return _color_for_room(depth, _is_active_event_room(room))


func _color_for_room(depth: int, active_event: bool) -> Color:
	if depth <= 0:
		return LABEL_COLOR_START
	if active_event:
		return LABEL_COLOR_EVENT
	var diff: int = clampi(depth, 1, 12) - _squad_level
	if diff <= 0:
		return LABEL_COLOR_SAFE
	if diff == 1:
		return LABEL_COLOR_CAUTION
	return LABEL_COLOR_DANGER


func _is_active_event_room(room: Rect2i) -> bool:
	if _plan == null or not _plan.is_event_room(room):
		return false
	var hazard: ClosingSpikeHazard = _plan.closing_spike_hazards.get(room, null)
	return hazard == null or not hazard.is_cleared


func _refresh_discovered_labels() -> void:
	for entry: RoomLabelEntry in _discovered_labels:
		if entry.is_event:
			var is_active: bool = _is_active_event_room(entry.room)
			if is_active != entry.active_event:
				entry.active_event = is_active
				entry.label.text = (&"! Lv.%d" % entry.depth) if is_active else (&"Lv.%d" % entry.depth)
		var color: Color = _color_for_room(entry.depth, entry.active_event)
		if color != entry.last_color:
			entry.last_color = color
			entry.label.add_theme_color_override(&"font_color", color)


func _on_map_viewport_gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var mouse_btn: InputEventMouseButton = event as InputEventMouseButton
		if mouse_btn.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_btn.is_pressed():
			_step_zoom(1, true, mouse_btn.position)
			_map_viewport.accept_event()
		elif mouse_btn.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_btn.is_pressed():
			_step_zoom(-1, true, mouse_btn.position)
			_map_viewport.accept_event()
		elif (
			mouse_btn.button_index == MOUSE_BUTTON_LEFT
			or mouse_btn.button_index == MOUSE_BUTTON_MIDDLE
			or mouse_btn.button_index == MOUSE_BUTTON_RIGHT
		):
			_is_dragging = mouse_btn.is_pressed()
			if _is_dragging:
				_is_recentering = false
			_map_viewport.accept_event()
	elif event is InputEventMouseMotion:
		if _is_dragging:
			var motion: InputEventMouseMotion = event as InputEventMouseMotion
			var scale_now: float = _zoom_px_per_tile / TILE_SIZE
			_camera_world_pos -= motion.relative / scale_now
			_clamp_camera_to_bounds()
			_is_recentering = false
			_has_zoom_anchor = false
			_map_viewport.accept_event()


func _on_input_mode_changed(mode: InputManager.InputMode) -> void:
	_update_controls_hint(mode)


func _update_controls_hint(mode: InputManager.InputMode) -> void:
	match mode:
		InputManager.InputMode.XBOX:
			_controls_hint.text = &"Stick / D-Pad: Pan  |  LB / RB / Triggers: Zoom  |  A: Center  |  VIEW / B: Close"
		InputManager.InputMode.PLAYSTATION:
			_controls_hint.text = &"Stick / D-Pad: Pan  |  L1 / R1 / L2 / R2: Zoom  |  Cross: Center  |  SHARE / Circle: Close"
		InputManager.InputMode.GENERIC_GAMEPAD:
			_controls_hint.text = &"Stick / D-Pad: Pan  |  L / R: Zoom  |  A: Center  |  SELECT / B: Close"
		_:
			_controls_hint.text = &"WASD / Drag: Pan  |  Wheel / +/-: Zoom  |  Space: Center  |  TAB / M: Close"


func _request_recenter() -> void:
	_has_zoom_anchor = false
	_is_dragging = false
	_is_recentering = true


func _step_zoom(direction: int, use_cursor_anchor: bool, anchor_screen: Vector2 = Vector2.ZERO) -> void:
	var next_zoom: float = _target_zoom
	if direction > 0:
		next_zoom = MAX_ZOOM
		for lvl: float in ZOOM_LEVELS:
			if lvl > _target_zoom + 0.01:
				next_zoom = lvl
				break
	elif direction < 0:
		next_zoom = MIN_ZOOM
		for idx: int in range(ZOOM_LEVELS.size() - 1, -1, -1):
			var lvl: float = ZOOM_LEVELS[idx]
			if lvl < _target_zoom - 0.01:
				next_zoom = lvl
				break

	_target_zoom = clampf(next_zoom, MIN_ZOOM, MAX_ZOOM)
	if use_cursor_anchor:
		_zoom_anchor_screen = anchor_screen
		_has_zoom_anchor = true
	else:
		_has_zoom_anchor = false


func _update_navigation(delta: float) -> void:
	var pan_vec: Vector2 = _get_pan_vector()
	if pan_vec != Vector2.ZERO:
		_is_recentering = false
		_has_zoom_anchor = false
		var scale_now: float = _zoom_px_per_tile / TILE_SIZE
		_camera_world_pos += pan_vec * (PAN_SCREEN_SPEED / scale_now) * delta

	var trigger_axis: float = _get_trigger_zoom_axis()
	if absf(trigger_axis) > 0.0:
		_has_zoom_anchor = false
		_target_zoom = clampf(_target_zoom * pow(TRIGGER_ZOOM_RATE, trigger_axis * delta), MIN_ZOOM, MAX_ZOOM)

	if absf(_zoom_px_per_tile - _target_zoom) > 0.001:
		var new_zoom: float = lerpf(_zoom_px_per_tile, _target_zoom, clampf(ZOOM_LERP_SPEED * delta, 0.0, 1.0))
		if absf(new_zoom - _target_zoom) <= 0.002:
			new_zoom = _target_zoom
		if _has_zoom_anchor:
			var old_scale: float = _zoom_px_per_tile / TILE_SIZE
			var new_scale: float = new_zoom / TILE_SIZE
			var offset_from_center: Vector2 = _zoom_anchor_screen - (_map_viewport.size * 0.5)
			var anchor_world: Vector2 = _camera_world_pos + offset_from_center / old_scale
			_zoom_px_per_tile = new_zoom
			_camera_world_pos = anchor_world - offset_from_center / new_scale
		else:
			_zoom_px_per_tile = new_zoom
		_update_zoom_label()
	else:
		_zoom_px_per_tile = _target_zoom
		_has_zoom_anchor = false

	if _is_recentering and is_instance_valid(_target):
		_camera_world_pos = _camera_world_pos.lerp(_target.global_position, clampf(RECENTER_LERP_SPEED * delta, 0.0, 1.0))
		if _camera_world_pos.distance_squared_to(_target.global_position) <= 1.0:
			_camera_world_pos = _target.global_position
			_is_recentering = false

	_clamp_camera_to_bounds()


func _capture_held_pan_inputs() -> void:
	_blocked_pan_actions.clear()
	for action: StringName in PAN_ACTIONS:
		if Input.is_action_pressed(action):
			_blocked_pan_actions[action] = true
	_wait_left_stick_release = _is_any_stick_held(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
	_wait_right_stick_release = _is_any_stick_held(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)


func _is_any_stick_held(axis_x: JoyAxis, axis_y: JoyAxis) -> bool:
	for pad: int in Input.get_connected_joypads():
		var raw: Vector2 = Vector2(Input.get_joy_axis(pad, axis_x), Input.get_joy_axis(pad, axis_y))
		if raw.length() >= InputManager.STICK_DEADZONE:
			return true
	return false


func _get_pan_vector() -> Vector2:
	if _wait_left_stick_release and not _is_any_stick_held(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y):
		_wait_left_stick_release = false
	if _wait_right_stick_release and not _is_any_stick_held(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y):
		_wait_right_stick_release = false
	for action: StringName in PAN_ACTIONS:
		if _blocked_pan_actions.has(action) and not Input.is_action_pressed(action):
			_blocked_pan_actions.erase(action)

	var best_stick: Vector2 = Vector2.ZERO
	var best_mag_sq: float = 0.0
	for pad: int in Input.get_connected_joypads():
		var left_raw: Vector2 = (
			Vector2.ZERO if _wait_left_stick_release else Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
		)
		var right_raw: Vector2 = (
			Vector2.ZERO
			if _wait_right_stick_release
			else Vector2(Input.get_joy_axis(pad, JOY_AXIS_RIGHT_X), Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y))
		)
		for raw_stick: Vector2 in [left_raw, right_raw]:
			var mag: float = raw_stick.length()
			if mag >= InputManager.STICK_DEADZONE:
				var scaled_mag: float = clampf((mag - InputManager.STICK_DEADZONE) / (1.0 - InputManager.STICK_DEADZONE), 0.0, 1.0)
				var stick_vec: Vector2 = raw_stick.normalized() * scaled_mag
				var sq: float = stick_vec.length_squared()
				if sq > best_mag_sq:
					best_mag_sq = sq
					best_stick = stick_vec
	if best_stick != Vector2.ZERO:
		return best_stick

	var lx: float = 0.0 if _blocked_pan_actions.has(&"left") else Input.get_action_strength(&"left")
	var rx: float = 0.0 if _blocked_pan_actions.has(&"right") else Input.get_action_strength(&"right")
	var uy: float = 0.0 if _blocked_pan_actions.has(&"up") else Input.get_action_strength(&"up")
	var dy: float = 0.0 if _blocked_pan_actions.has(&"down") else Input.get_action_strength(&"down")
	var action_vec: Vector2 = Vector2(rx - lx, dy - uy)
	if action_vec.length_squared() > 1.0:
		action_vec = action_vec.normalized()
	return action_vec


func _get_trigger_zoom_axis() -> float:
	var best_axis: float = 0.0
	for pad: int in Input.get_connected_joypads():
		var rt: float = Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT)
		var lt: float = Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_LEFT)
		var axis: float = (rt if rt > TRIGGER_DEADZONE else 0.0) - (lt if lt > TRIGGER_DEADZONE else 0.0)
		if absf(axis) > absf(best_axis):
			best_axis = axis
	return best_axis


func _clamp_camera_to_bounds() -> void:
	if not _has_revealed_bounds:
		return
	var scale_now: float = _zoom_px_per_tile / TILE_SIZE
	var margin_world: float = PAN_BOUNDS_MARGIN_PX / scale_now
	var min_world: Vector2 = Vector2(_revealed_min_chunk) * CHUNK_SIZE_PX
	var max_world: Vector2 = Vector2(_revealed_max_chunk + Vector2i.ONE) * CHUNK_SIZE_PX
	if is_instance_valid(_target):
		min_world = Vector2(minf(min_world.x, _target.global_position.x), minf(min_world.y, _target.global_position.y))
		max_world = Vector2(maxf(max_world.x, _target.global_position.x), maxf(max_world.y, _target.global_position.y))
	_camera_world_pos = Vector2(
		clampf(_camera_world_pos.x, min_world.x - margin_world, max_world.x + margin_world),
		clampf(_camera_world_pos.y, min_world.y - margin_world, max_world.y + margin_world),
	)


func _update_zoom_label() -> void:
	var pct: int = int(roundf((_zoom_px_per_tile / DEFAULT_ZOOM) * 100.0))
	if pct == _last_zoom_pct:
		return
	_last_zoom_pct = pct
	_zoom_label.text = &"%d%%" % pct


func _update_view() -> void:
	map_scale = _zoom_px_per_tile / TILE_SIZE
	_chunks_container.scale = Vector2(map_scale, map_scale)
	var viewport_center: Vector2 = (_map_viewport.size * 0.5).round()
	var cam_scaled: Vector2 = (_camera_world_pos * map_scale).round()
	_chunks_container.position = viewport_center - cam_scaled

	var vp_size: Vector2 = _map_viewport.size
	var show_all_labels: bool = _zoom_px_per_tile >= LABEL_ALL_MIN_ZOOM
	for entry: RoomLabelEntry in _discovered_labels:
		var show_label: bool = show_all_labels or entry.depth <= 0 or entry.active_event
		if not show_label:
			entry.label.visible = false
			continue
		var pos: Vector2 = viewport_center + (entry.world_center * map_scale).round() - cam_scaled - LABEL_HALF_SIZE
		var on_viewport: bool = pos.x >= -32.0 and pos.x <= vp_size.x and pos.y >= -16.0 and pos.y <= vp_size.y
		entry.label.visible = on_viewport
		if on_viewport:
			entry.label.position = pos

	_player_marker.position = viewport_center + (_target.global_position * map_scale).round() - cam_scaled
	if _target.move_direction.length_squared() > 0.001:
		_player_marker.rotation = _target.move_direction.angle()


func _update_discovery() -> void:
	var cur_chunk: Vector2i = Vector2i(floori(_target.global_position.x / CHUNK_SIZE_PX), floori(_target.global_position.y / CHUNK_SIZE_PX))
	if cur_chunk == _last_revealed_chunk:
		return
	_last_revealed_chunk = cur_chunk
	if _visited_fov_chunks.has(cur_chunk):
		return
	_visited_fov_chunks[cur_chunk] = true
	var origin_tile: Vector2i = Vector2i(floori(_target.global_position.x / TILE_SIZE), floori(_target.global_position.y / TILE_SIZE))
	_reveal_chunks_at(origin_tile)


func _reveal_chunks_at(origin_tile: Vector2i) -> void:
	(
		_visibility
		. compute_fov(
			origin_tile,
			reveal_chunk_radius * CHUNK_SIZE_TILES,
			explore_chunk_radius * CHUNK_SIZE_TILES,
			_fov_chunks,
		)
	)
	var markers_changed: bool = false
	for coord: Vector2i in _fov_chunks:
		var is_explore: bool = _fov_chunks[coord]
		if not _revealed_chunks.has(coord):
			_record_revealed_chunk(coord)
			markers_changed = true
			_chunk_meshes.reveal_chunk(coord, is_explore)

		if is_explore and not _explored_chunks.has(coord):
			_explored_chunks[coord] = true
			_chunk_meshes.explore_chunk(coord)

	if markers_changed:
		_update_gate_markers_visibility()
	if _chunk_meshes.has_dirty_regions():
		_dirty = true
		if visible:
			_rebuild_meshes()


func _record_revealed_chunk(coord: Vector2i) -> void:
	_revealed_chunks[coord] = true
	if not _has_revealed_bounds:
		_has_revealed_bounds = true
		_revealed_min_chunk = coord
		_revealed_max_chunk = coord
	else:
		_revealed_min_chunk = Vector2i(mini(_revealed_min_chunk.x, coord.x), mini(_revealed_min_chunk.y, coord.y))
		_revealed_max_chunk = Vector2i(maxi(_revealed_max_chunk.x, coord.x), maxi(_revealed_max_chunk.y, coord.y))


func _rebuild_meshes() -> void:
	if not _dirty:
		return
	_dirty = false
	_chunk_meshes.rebuild_dirty()


func _build_chunks(plan: WorldPlan) -> void:
	_dirty = false
	_plan = plan
	_revealed_chunks.clear()
	_explored_chunks.clear()
	_has_revealed_bounds = false
	_revealed_min_chunk = Vector2i.ZERO
	_revealed_max_chunk = Vector2i.ZERO
	_discovered_rooms.clear()
	_discovered_labels.clear()
	_next_label_pool_idx = 0
	for label: Label in _label_pool:
		label.visible = false
	_collected_keys.clear()
	_door_entries.clear()
	_key_entries.clear()
	_shortcut_entries.clear()
	_pulse_time = 0.0
	_visited_fov_chunks.clear()
	_fov_chunks.clear()
	for i: int in range(_door_meshes.size()):
		_door_meshes[i].mesh = null
		_door_meshes[i].visible = false
		_door_meshes[i].self_modulate = DOOR_COLORS[i]
	_shortcut_lines_mesh.mesh = null
	_shortcut_lines_mesh.visible = false
	for marker: Polygon2D in _key_markers:
		marker.visible = false
	for ind: Node2D in _hud_door_indicators:
		ind.visible = false
		ind.scale = Vector2.ONE
	for ind: Node2D in _hud_key_indicators:
		ind.visible = false
	_last_revealed_chunk = Vector2i(2147483647, 2147483647)

	_chunk_meshes.reset(plan)
	if plan.carve_rects.is_empty():
		_visibility.setup(null)
		for label: Label in _label_pool:
			label.visible = false
		return

	_visibility.setup(plan)
	map_scale = _zoom_px_per_tile / TILE_SIZE
	_chunks_container.scale = Vector2(map_scale, map_scale)
	_build_gate_markers(plan)


func _build_gate_markers(plan: WorldPlan) -> void:
	for gate: SectorGatePlanner.SectorGate in plan.sector_gates:
		var color_idx: int = int(gate.color)
		if color_idx >= 0 and color_idx < _door_meshes.size():
			var door_mid: Vector2 = (Vector2(gate.door_cells[0]) + Vector2(gate.door_cells[1])) * 0.5 + Vector2(0.5, 0.5)
			var door_world: Vector2 = door_mid * TILE_SIZE
			var is_horiz: bool = gate.door_face == RoomLayout.Face.NORTH or gate.door_face == RoomLayout.Face.SOUTH
			var pts: Array[Vector2] = _get_door_line_endpoints(gate.door_cells, is_horiz)
			(
				_door_entries
				. append(
					{
						&"gate": gate,
						&"color_idx": color_idx,
						&"p0": pts[0],
						&"p1": pts[1],
						&"world_pos": door_world,
						&"visible": false,
					}
				)
			)
		if gate.has_key and color_idx >= 0 and color_idx < _key_markers.size():
			var key_mid: Vector2 = Vector2(gate.key_cell) + Vector2(0.5, 0.5)
			var key_world: Vector2 = key_mid * TILE_SIZE
			var key_marker: Polygon2D = _key_markers[color_idx]
			key_marker.position = key_world
			_key_entries.append({&"gate": gate, &"marker": key_marker, &"world_pos": key_world})

	for shortcut: ShortcutTunnelPlanner.LocalShortcut in plan.local_shortcuts:
		var pts: Array[Vector2] = _get_door_line_endpoints(shortcut.door_cells, shortcut.is_horizontal_door)
		var open_dir: Vector2
		if shortcut.is_horizontal_door:
			open_dir = Vector2(0.0, 1.0) if shortcut.room_far.end.y <= shortcut.door_cells[0].y else Vector2(0.0, -1.0)
		else:
			open_dir = Vector2(1.0, 0.0) if shortcut.room_far.end.x <= shortcut.door_cells[0].x else Vector2(-1.0, 0.0)
		_shortcut_entries.append({&"shortcut": shortcut, &"p0": pts[0], &"p1": pts[1], &"open_dir": open_dir})


static func _get_door_line_endpoints(door_cells: Array[Vector2i], is_horizontal: bool) -> Array[Vector2]:
	var c0: Vector2i = door_cells[0]
	var c1: Vector2i = door_cells[1]
	if is_horizontal:
		var x0: int = mini(c0.x, c1.x)
		var y_mid: float = (float(c0.y) + 0.5) * TILE_SIZE
		return [Vector2(float(x0) * TILE_SIZE, y_mid), Vector2(float(x0 + 2) * TILE_SIZE, y_mid)]
	var y_min: int = mini(c0.y, c1.y)
	var y_max: int = maxi(c0.y, c1.y)
	var x_mid: float = (float(c0.x) + 0.5) * TILE_SIZE
	return [Vector2(x_mid, float(y_min - 1) * TILE_SIZE), Vector2(x_mid, float(y_max + 1) * TILE_SIZE)]


func _update_gate_markers_visibility() -> void:
	if _plan == null:
		return

	var door_verts_by_color: Array[PackedVector2Array] = [
		PackedVector2Array(),
		PackedVector2Array(),
		PackedVector2Array(),
		PackedVector2Array(),
	]
	for entry: Dictionary in _door_entries:
		var gate: SectorGatePlanner.SectorGate = entry[&"gate"]
		var color_idx: int = entry[&"color_idx"]
		var c0: Vector2i = _cell_to_map_chunk(gate.door_cells[0])
		var c1: Vector2i = _cell_to_map_chunk(gate.door_cells[1])
		var is_revealed: bool = _revealed_chunks.has(c0) or _revealed_chunks.has(c1)
		var is_vis: bool = is_revealed and not gate.door_unlocked
		entry[&"visible"] = is_vis
		if is_vis:
			var verts: PackedVector2Array = door_verts_by_color[color_idx]
			var p0: Vector2 = entry[&"p0"]
			var p1: Vector2 = entry[&"p1"]
			_append_bar_quad(verts, p0, p1, DOOR_BAR_HALF_THICKNESS)
			door_verts_by_color[color_idx] = verts

	for i: int in range(_door_meshes.size()):
		var verts: PackedVector2Array = door_verts_by_color[i]
		if verts.is_empty():
			_door_meshes[i].mesh = null
			_door_meshes[i].visible = false
		else:
			_door_meshes[i].mesh = _create_triangle_mesh(verts)
			_door_meshes[i].visible = true

	for entry: Dictionary in _key_entries:
		var gate: SectorGatePlanner.SectorGate = entry[&"gate"]
		var marker: Polygon2D = entry[&"marker"]
		var key_chunk: Vector2i = _cell_to_map_chunk(gate.key_cell)
		marker.visible = _revealed_chunks.has(key_chunk) and not _collected_keys.has(gate.color)

	var sc_verts: PackedVector2Array = PackedVector2Array()
	for entry: Dictionary in _shortcut_entries:
		var shortcut: ShortcutTunnelPlanner.LocalShortcut = entry[&"shortcut"]
		if shortcut.opened:
			continue
		var c0: Vector2i = _cell_to_map_chunk(shortcut.door_cells[0])
		var c1: Vector2i = _cell_to_map_chunk(shortcut.door_cells[1])
		if not (_revealed_chunks.has(c0) or _revealed_chunks.has(c1)):
			continue
		var p0: Vector2 = entry[&"p0"]
		var p1: Vector2 = entry[&"p1"]
		var open_dir: Vector2 = entry[&"open_dir"]
		_append_shortcut_glyph(sc_verts, p0, p1, open_dir)

	if sc_verts.is_empty():
		_shortcut_lines_mesh.mesh = null
		_shortcut_lines_mesh.visible = false
	else:
		_shortcut_lines_mesh.mesh = _create_triangle_mesh(sc_verts)
		_shortcut_lines_mesh.visible = true

	_update_hud_edge_indicators()


static func _append_bar_quad(verts: PackedVector2Array, p0: Vector2, p1: Vector2, half_thickness: float) -> void:
	var t: Vector2 = (p1 - p0).normalized()
	var n: Vector2 = Vector2(-t.y, t.x) * half_thickness
	verts.append(p0 - n)
	verts.append(p1 - n)
	verts.append(p1 + n)
	verts.append(p0 - n)
	verts.append(p1 + n)
	verts.append(p0 + n)


static func _append_shortcut_glyph(verts: PackedVector2Array, p0: Vector2, p1: Vector2, open_dir: Vector2) -> void:
	_append_bar_quad(verts, p0, p1, SHORTCUT_BAR_HALF_THICKNESS)
	var center: Vector2 = (p0 + p1) * 0.5
	var perp: Vector2 = Vector2(-open_dir.y, open_dir.x)
	var tip: Vector2 = center - open_dir * (SHORTCUT_BAR_HALF_THICKNESS + SHORTCUT_CHEVRON_GAP)
	var base_mid: Vector2 = tip - open_dir * SHORTCUT_CHEVRON_LENGTH
	verts.append(tip)
	verts.append(base_mid + perp * SHORTCUT_CHEVRON_HALF_WIDTH)
	verts.append(base_mid - perp * SHORTCUT_CHEVRON_HALF_WIDTH)


static func _create_triangle_mesh(vertices: PackedVector2Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _update_matching_door_pulses() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_pulse_time * 6.0)
	for i: int in range(_door_meshes.size()):
		if _door_meshes[i].visible and _collected_keys.has(i as WorldPlan.KeyColor):
			_door_meshes[i].self_modulate = DOOR_COLORS[i].lerp(Color.WHITE, pulse * 0.75)
		else:
			_door_meshes[i].self_modulate = DOOR_COLORS[i]


func _update_player_pulse() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_pulse_time * 4.5)
	_player_pulse_ring.scale = Vector2.ONE * lerpf(0.90, 1.35, pulse)
	_player_pulse_ring.default_color = PLAYER_PULSE_COLOR_A.lerp(PLAYER_PULSE_COLOR_B, pulse)


func _update_hud_edge_indicators() -> void:
	if _hud_door_indicators.is_empty():
		return
	var on_screen_rect: Rect2 = Rect2(
		Vector2(HUD_ON_SCREEN_PAD, HUD_ON_SCREEN_PAD),
		Vector2(maxf(0.0, size.x - HUD_ON_SCREEN_PAD * 2.0), maxf(0.0, size.y - HUD_ON_SCREEN_PAD * 2.0)),
	)
	var min_bound: Vector2 = Vector2(HUD_EDGE_MARGIN_LEFT, HUD_EDGE_MARGIN_TOP)
	var max_bound: Vector2 = Vector2(
		maxf(min_bound.x, size.x - HUD_EDGE_MARGIN_RIGHT),
		maxf(min_bound.y, size.y - HUD_EDGE_MARGIN_BOTTOM),
	)
	var pulse: float = 0.5 + 0.5 * sin(_pulse_time * 6.0)
	for i: int in range(_door_meshes.size()):
		var target_color: WorldPlan.KeyColor = i as WorldPlan.KeyColor
		var best_pos: Vector2 = Vector2.ZERO
		var has_door: bool = false
		var best_off_screen: bool = false
		var best_dist_sq: float = INF
		if is_instance_valid(_target):
			for entry: Dictionary in _door_entries:
				var gate: SectorGatePlanner.SectorGate = entry[&"gate"]
				var is_vis: bool = entry[&"visible"]
				if gate.color != target_color or not is_vis:
					continue
				var world_pos: Vector2 = entry[&"world_pos"]
				var screen_pos: Vector2 = (size * 0.5) + (world_pos - _target.global_position)
				var is_off: bool = not on_screen_rect.has_point(screen_pos)
				var d_sq: float = _target.global_position.distance_squared_to(world_pos)
				if not has_door or (is_off and not best_off_screen) or (is_off == best_off_screen and d_sq < best_dist_sq):
					has_door = true
					best_off_screen = is_off
					best_dist_sq = d_sq
					best_pos = world_pos
		_update_hud_indicator(
			has_door,
			best_pos,
			_hud_door_indicators[i],
			_hud_door_arrows[i],
			on_screen_rect,
			min_bound,
			max_bound,
		)
		if _hud_door_indicators[i].visible and _collected_keys.has(target_color):
			_hud_door_indicators[i].scale = Vector2.ONE * lerpf(1.0, 1.16, pulse)
		else:
			_hud_door_indicators[i].scale = Vector2.ONE

	for i: int in range(_key_markers.size()):
		var target_color: WorldPlan.KeyColor = i as WorldPlan.KeyColor
		var key_pos: Vector2 = Vector2.ZERO
		var has_key: bool = false
		for entry: Dictionary in _key_entries:
			var gate: SectorGatePlanner.SectorGate = entry[&"gate"]
			var marker: Polygon2D = entry[&"marker"]
			if gate.color == target_color and marker.visible:
				has_key = true
				key_pos = entry[&"world_pos"]
				break
		_update_hud_indicator(
			has_key,
			key_pos,
			_hud_key_indicators[i],
			_hud_key_arrows[i],
			on_screen_rect,
			min_bound,
			max_bound,
		)


func _update_hud_indicator(
	is_active: bool,
	world_pos: Vector2,
	indicator: Node2D,
	arrow: Node2D,
	on_screen_rect: Rect2,
	min_bound: Vector2,
	max_bound: Vector2,
) -> void:
	if visible or not is_active or not is_instance_valid(_target):
		indicator.visible = false
		return
	var screen_pos: Vector2 = (size * 0.5) + (world_pos - _target.global_position)
	if on_screen_rect.has_point(screen_pos):
		indicator.visible = false
		return
	var clamped_pos: Vector2 = screen_pos.clamp(min_bound, max_bound)
	indicator.position = clamped_pos.round()
	indicator.visible = true
	arrow.rotation = (screen_pos - clamped_pos).angle()


static func _cell_to_map_chunk(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / float(CHUNK_SIZE_TILES)), floori(float(cell.y) / float(CHUNK_SIZE_TILES)))

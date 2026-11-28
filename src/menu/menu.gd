# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Menu
extends PanelHost

const NOTIFICATION_DELAY: float = 2.0
const BACKDROP_SEED: int = 42
const BACKDROP_TILE_SET_OFFSET: int = 11
const ROOM_MIN_X: int = 1
const ROOM_MAX_X: int = 38
const ROOM_MIN_Y: int = 1
const ROOM_MAX_Y: int = 21
const FLICKER_SPEED: float = 7.5
const WALL_LIGHT_ENERGY: float = 2.8
const POST_LIGHT_ENERGY: float = 2.6

var _time: float = 0.0
var _codex_return_panel: UiPanel = null

@onready var _floor_layer: TileMapLayer = $Backdrop/Floor
@onready var _walls_layer: TileMapLayer = $Backdrop/Walls
@onready var _light_top_left: PointLight2D = $Backdrop/WallTorchLeft/PointLight2D
@onready var _light_top_right: PointLight2D = $Backdrop/WallTorchRight/PointLight2D
@onready var _light_bottom_left: PointLight2D = $Backdrop/CandlePostLeft/PointLight2D
@onready var _light_bottom_right: PointLight2D = $Backdrop/CandlePostRight/PointLight2D
@onready var _main_menu_panel: MainMenuPanel = $Center/MainMenuPanel
@onready var _hero_select_panel: HeroSelectPanel = $Center/HeroSelectPanel
@onready var _settings_panel: SettingsPanel = $Center/SettingsPanel
@onready var _about_panel: AboutPanel = $Center/AboutPanel
@onready var _changelog_panel: ChangelogPanel = $Center/ChangelogPanel
@onready var _eula_screen: EulaScreen = $Center/EulaScreen
@onready var _codex_panel: CodexPanel = $Center/CodexPanel
@onready var _codex_heroes_panel: CodexHeroesPanel = $Center/CodexHeroesPanel
@onready var _codex_enemies_panel: CodexEnemiesPanel = $Center/CodexEnemiesPanel
@onready var _codex_items_panel: CodexItemsPanel = $Center/CodexItemsPanel
@onready var _codex_events_panel: CodexEventsPanel = $Center/CodexEventsPanel
@onready var _codex_mechanics_panel: CodexMechanicsPanel = $Center/CodexMechanicsPanel


func _ready() -> void:
	_build_backdrop_room()
	await HeroData.initialize()
	await EnemyData.initialize()
	await CodexItemsPanel.initialize_data()
	await CodexEventsPanel.initialize_data()
	await CodexMechanicsPanel.initialize_data()
	_hero_select_panel.initialize()
	_codex_heroes_panel.initialize()
	_codex_enemies_panel.initialize()
	_codex_items_panel.initialize()
	_codex_events_panel.initialize()
	_codex_mechanics_panel.initialize()
	get_tree().create_timer(NOTIFICATION_DELAY).timeout.connect(InputManager.enable_notifications)
	if not _eula_screen.is_accepted():
		_show_first(_eula_screen)
	else:
		_show_first(_get_start_panel())


func _process(delta: float) -> void:
	_time += delta
	var tl_wave: float = sin(_time * FLICKER_SPEED) * 0.16
	var tr_wave: float = sin(_time * FLICKER_SPEED + 1.6) * 0.16
	var bl_wave: float = sin(_time * FLICKER_SPEED + 3.1) * 0.16
	var br_wave: float = sin(_time * FLICKER_SPEED + 4.7) * 0.16
	_light_top_left.energy = WALL_LIGHT_ENERGY + tl_wave
	_light_top_right.energy = WALL_LIGHT_ENERGY + tr_wave
	_light_bottom_left.energy = POST_LIGHT_ENERGY + bl_wave
	_light_bottom_right.energy = POST_LIGHT_ENERGY + br_wave


func _build_backdrop_room() -> void:
	var source_id: int = TileClassifier.TILE_SET_SOURCE_ID
	var tile_offset: Vector2i = Vector2i(0, BACKDROP_TILE_SET_OFFSET)

	for gy: int in range(ROOM_MIN_Y, ROOM_MAX_Y + 1):
		for gx: int in range(ROOM_MIN_X, ROOM_MAX_X + 1):
			var floor_atlas: Vector2i = TileClassifier.get_floor_atlas(BACKDROP_SEED, gx, gy, 1)
			_floor_layer.set_cell(Vector2i(gx, gy), source_id, floor_atlas)

	for gx: int in range(ROOM_MIN_X, ROOM_MAX_X + 1):
		var top_hash: int = TileClassifier.cell_hash(BACKDROP_SEED, gx, ROOM_MIN_Y)
		var top_atlas: Vector2i
		if (top_hash % 7) == 0 and gx != 6 and gx != 33:
			var vents: Array[Vector2i] = TileClassifier.WALL_TOP_VENT_VARIANTS
			top_atlas = vents[(top_hash >> 3) % vents.size()]
		else:
			var tops: Array[Vector2i] = TileClassifier.WALL_TOP_VARIANTS
			top_atlas = tops[top_hash % tops.size()]
		_walls_layer.set_cell(Vector2i(gx, ROOM_MIN_Y), source_id, top_atlas + tile_offset)

		var bot_hash: int = TileClassifier.cell_hash(BACKDROP_SEED, gx, ROOM_MAX_Y + 1)
		var bots: Array[Vector2i] = TileClassifier.WALL_BOTTOM_VARIANTS
		_walls_layer.set_cell(Vector2i(gx, ROOM_MAX_Y + 1), source_id, bots[bot_hash % bots.size()] + tile_offset)

	_walls_layer.set_cell(Vector2i(ROOM_MIN_X - 1, ROOM_MIN_Y), source_id, TileClassifier.WALL_TOP_LEFT_OUTER + tile_offset)
	_walls_layer.set_cell(Vector2i(ROOM_MAX_X + 1, ROOM_MIN_Y), source_id, TileClassifier.WALL_TOP_RIGHT_OUTER + tile_offset)
	_walls_layer.set_cell(Vector2i(ROOM_MIN_X - 1, ROOM_MAX_Y + 1), source_id, TileClassifier.WALL_BOTTOM_LEFT_OUTER + tile_offset)
	_walls_layer.set_cell(Vector2i(ROOM_MAX_X + 1, ROOM_MAX_Y + 1), source_id, TileClassifier.WALL_BOTTOM_RIGHT_OUTER + tile_offset)

	for gy: int in range(ROOM_MIN_Y + 1, ROOM_MAX_Y + 1):
		var left_hash: int = TileClassifier.cell_hash(BACKDROP_SEED, ROOM_MIN_X - 1, gy)
		var lefts: Array[Vector2i] = TileClassifier.WALL_LEFT_VARIANTS
		_walls_layer.set_cell(Vector2i(ROOM_MIN_X - 1, gy), source_id, lefts[left_hash % lefts.size()] + tile_offset)

		var right_hash: int = TileClassifier.cell_hash(BACKDROP_SEED, ROOM_MAX_X + 1, gy)
		var rights: Array[Vector2i] = TileClassifier.WALL_RIGHT_VARIANTS
		_walls_layer.set_cell(Vector2i(ROOM_MAX_X + 1, gy), source_id, rights[right_hash % rights.size()] + tile_offset)


func _get_start_panel() -> UiPanel:
	if not _changelog_panel.is_seen():
		_changelog_panel.mark_seen()
		_changelog_panel.back_button_text = &"Continue"
		return _changelog_panel
	if Transition.select_hero_on_menu:
		Transition.select_hero_on_menu = false
		return _hero_select_panel
	return _main_menu_panel


func _on_eula_accepted() -> void:
	show_panel(_get_start_panel())


func _on_eula_back_requested() -> void:
	show_panel(_about_panel)


func _on_license_requested() -> void:
	show_panel(_eula_screen)


func _on_play_requested() -> void:
	show_panel(_hero_select_panel)


func _on_hero_selected(hero: HeroData) -> void:
	await Transition.reload_game(hero.id)


func _on_settings_requested() -> void:
	show_panel(_settings_panel)


func _on_about_requested() -> void:
	show_panel(_about_panel)


func _on_changelog_requested() -> void:
	_changelog_panel.back_button_text = &"Back"
	show_panel(_changelog_panel)


func _on_exit_requested() -> void:
	await Alerts.quit_game()


func _on_panel_back_requested() -> void:
	show_panel(_main_menu_panel)


func _open_codex(from_panel: UiPanel) -> void:
	_codex_return_panel = from_panel
	_codex_panel.reset_focus_target()
	show_panel(_codex_panel)


func _on_main_menu_codex_requested() -> void:
	_open_codex(_main_menu_panel)


func _on_hero_select_codex_requested() -> void:
	_open_codex(_hero_select_panel)


func _on_codex_back_requested() -> void:
	show_panel(_codex_return_panel)


func _on_codex_heroes_requested() -> void:
	show_panel(_codex_heroes_panel)


func _on_codex_enemies_requested() -> void:
	show_panel(_codex_enemies_panel)


func _on_codex_items_requested() -> void:
	show_panel(_codex_items_panel)


func _on_codex_events_requested() -> void:
	show_panel(_codex_events_panel)


func _on_codex_mechanics_requested() -> void:
	show_panel(_codex_mechanics_panel)


func _on_codex_subpanel_back_requested() -> void:
	show_panel(_codex_panel)

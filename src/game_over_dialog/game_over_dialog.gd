# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name GameOverDialog
extends UiPanel

signal codex_requested

const SCORE_ROW_SCENE: PackedScene = preload("res://game_over_dialog/score_card_row.tscn")
const CLASS_ROW_SCENE: PackedScene = preload("res://game_over_dialog/class_breakdown_row.tscn")
const GOLD_COLOR: Color = Color(1.0, 0.85, 0.40, 1.0)
const MUTED_COLOR: Color = Color(0.70, 0.75, 0.84, 1.0)

var _score_row_pool: Array[ScoreCardRow] = []
var _class_row_pool: Array[ClassBreakdownRow] = []

@onready var _score_rows_container: VBoxContainer = $VBox/Content/ScoreColumn/ScoreRows
@onready var _total_value: Label = $VBox/Content/ScoreColumn/TotalRow/TotalValue
@onready var _best_value: Label = $VBox/Content/ScoreColumn/BestRow/BestValue
@onready var _time_value: Label = $VBox/Content/ScoreColumn/TimeRow/Value
@onready var _rooms_value: Label = $VBox/Content/ScoreColumn/RoomsRow/Value
@onready var _escapees_value: Label = $VBox/Content/ScoreColumn/EscapeesRow/Value
@onready var _trap_value: Label = $VBox/Content/ScoreColumn/TrapRow/Value
@onready var _mvp_value: Label = $VBox/Content/ScoreColumn/MvpRow/Value
@onready var _class_rows_container: VBoxContainer = $VBox/Content/BreakdownColumn/ClassRows
@onready var _leader_label: RichTextLabel = $VBox/Content/BreakdownColumn/LeaderLabel
@onready var _living_label: RichTextLabel = $VBox/Content/BreakdownColumn/LivingLabel
@onready var _fallen_label: RichTextLabel = $VBox/Content/BreakdownColumn/FallenLabel
@onready var _codex_badge: Control = $VBox/Buttons/Codex/UnreadBadge


func _ready() -> void:
	super._ready()
	Codex.unread_changed.connect(_sync_codex_badge)
	_sync_codex_badge()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready() and is_visible_in_tree():
		_sync_codex_badge()


func populate(stats: RunStats, score: RunScore) -> void:
	for i: int in range(score.lines.size()):
		var row: ScoreCardRow
		if i < _score_row_pool.size():
			row = _score_row_pool[i]
		else:
			row = SCORE_ROW_SCENE.instantiate() as ScoreCardRow
			_score_row_pool.append(row)
			_score_rows_container.add_child(row)
		row.visible = true
		row.setup(score.lines[i])

	for i: int in range(score.lines.size(), _score_row_pool.size()):
		_score_row_pool[i].visible = false

	_total_value.text = &"%d" % score.total_score
	if score.is_new_best:
		_best_value.text = &"%d  NEW!" % score.best_score
		_best_value.add_theme_color_override(&"font_color", GOLD_COLOR)
	else:
		_best_value.text = &"%d" % score.best_score
		_best_value.add_theme_color_override(&"font_color", MUTED_COLOR)

	_time_value.text = RunStats.format_duration(stats.elapsed_time)
	_rooms_value.text = &"%d / %d (%d%%)" % [stats.rooms_discovered, stats.total_rooms, stats.explored_percent]
	_escapees_value.text = &"%d / %d" % [stats.escapees_rescued, stats.total_escapees]
	_trap_value.text = DamageMeter.format_compact(stats.trap_damage_taken)

	var mvp_data: HeroData = HeroData.get_hero(stats.mvp_class_id) if not stats.mvp_class_id.is_empty() else null
	if mvp_data != null:
		_mvp_value.text = mvp_data.name
		_mvp_value.add_theme_color_override(&"font_color", mvp_data.color)
	else:
		_mvp_value.text = &"None"
		_mvp_value.add_theme_color_override(&"font_color", MUTED_COLOR)

	var max_damage: float = stats.class_breakdown[0].total_damage if not stats.class_breakdown.is_empty() else 1.0
	for i: int in range(stats.class_breakdown.size()):
		var c_row: ClassBreakdownRow
		if i < _class_row_pool.size():
			c_row = _class_row_pool[i]
		else:
			c_row = CLASS_ROW_SCENE.instantiate() as ClassBreakdownRow
			_class_row_pool.append(c_row)
			_class_rows_container.add_child(c_row)
		c_row.visible = true
		c_row.setup(stats.class_breakdown[i], max_damage)

	for i: int in range(stats.class_breakdown.size(), _class_row_pool.size()):
		_class_row_pool[i].visible = false

	_populate_roll_call(stats)


func _populate_roll_call(stats: RunStats) -> void:
	var leader_data: HeroData = HeroData.get_hero(stats.leader_class_id)
	if leader_data != null:
		_leader_label.text = (
			"[color=#9aa4b6]Leader:[/color] [color=#%s]%s Lv.%d[/color] [color=#e06c75](Fallen)[/color]"
			% [
				leader_data.color.to_html(false),
				leader_data.name,
				stats.leader_level,
			]
		)
	else:
		_leader_label.text = "[color=#9aa4b6]Leader:[/color] Fallen"

	var living_total: int = 0
	for count: int in stats.living_counts.values():
		living_total += count
	_living_label.text = "[color=#9aa4b6]Living (%d):[/color] %s" % [living_total, _format_class_counts(stats.living_counts)]
	_fallen_label.text = (
		"[color=#9aa4b6]Fallen (%d):[/color] %s"
		% [
			stats.fallen_companions,
			_format_class_counts(stats.fallen_counts),
		]
	)


static func _format_class_counts(counts: Dictionary[StringName, int]) -> String:
	if counts.is_empty():
		return "[color=#7b8496]None[/color]"
	var parts: Array[String] = []
	for cid: StringName in counts:
		var count: int = counts[cid]
		if count <= 0:
			continue
		var data: HeroData = HeroData.get_hero(cid)
		if data != null:
			parts.append("[color=#%s]%sx%d[/color]" % [data.color.to_html(false), data.abbr, count])
		else:
			parts.append("%sx%d" % [String(cid).to_upper().substr(0, 4), count])
	if parts.is_empty():
		return "[color=#7b8496]None[/color]"
	return ", ".join(parts)


func _sync_codex_badge() -> void:
	_codex_badge.visible = Codex.has_any_unread()


func _on_retry_pressed() -> void:
	await Transition.go_to_menu(true)


func _on_codex_pressed() -> void:
	codex_requested.emit()


func _on_back_to_menu_pressed() -> void:
	await Transition.go_to_menu()

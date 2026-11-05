# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name DamageMeter
extends PanelContainer


class MeterEntry:
	extends RefCounted
	var class_id: StringName = &""
	var abbr: String = ""
	var color: Color = Color.WHITE
	var count: int = 0
	var dps: float = 0.0
	var avg_dps: float = 0.0
	var pct: float = 0.0


const FONT_M3X6: FontFile = preload("res://data/assets/pixel_ui_theme/m3x6.ttf")
const COMBAT_TIMEOUT: float = 4.0
const REFRESH_INTERVAL: float = 0.2

var _in_combat: bool = false
var _combat_duration: float = 0.0
var _time_since_last_hit: float = COMBAT_TIMEOUT
var _refresh_timer: float = 0.0
var _total_encounter_damage: float = 0.0
var _class_damages: Dictionary[StringName, float] = {}
var _squad_counts: Dictionary[StringName, int] = {}
var _row_pool: Array[DamageMeterRow] = []
var _entry_pool: Array[MeterEntry] = []

@onready var _title_label: Label = $Margin/VBox/Header/TitleLabel
@onready var _columns_label: Label = $Margin/VBox/Header/ColumnsLabel
@onready var _rows_container: VBoxContainer = $Margin/VBox/RowsContainer


func _ready() -> void:
	_title_label.add_theme_font_override(&"font", FONT_M3X6)
	_columns_label.add_theme_font_override(&"font", FONT_M3X6)
	_update_header()


func _process(delta: float) -> void:
	if not _in_combat:
		return

	_combat_duration += delta
	_time_since_last_hit += delta

	if _time_since_last_hit >= COMBAT_TIMEOUT:
		_in_combat = false
		_combat_duration = maxf(1.0, _combat_duration - COMBAT_TIMEOUT)
		_refresh_display()
		return

	_refresh_timer += delta
	if _refresh_timer >= REFRESH_INTERVAL:
		_refresh_timer = 0.0
		_refresh_display()


func record_damage(class_id: StringName, amount: float) -> void:
	if amount <= 0.0:
		return

	var is_new_encounter: bool = not _in_combat and _time_since_last_hit >= COMBAT_TIMEOUT
	if is_new_encounter:
		_class_damages.clear()
		_total_encounter_damage = 0.0
		_combat_duration = 0.0

	_in_combat = true
	_time_since_last_hit = 0.0
	_class_damages[class_id] = _class_damages.get(class_id, 0.0) + amount
	_total_encounter_damage += amount

	if is_new_encounter:
		_refresh_display()


func update_squad(squad: Array[Hero]) -> void:
	_squad_counts.clear()
	for hero: Hero in squad:
		if not hero.is_dead:
			var cid: StringName = hero.hero_data.id
			_squad_counts[cid] = _squad_counts.get(cid, 0) + 1
	_refresh_display()


func _update_header() -> void:
	_title_label.text = "DPS [%ds]" % int(roundf(_combat_duration))
	if _in_combat:
		_title_label.add_theme_color_override(&"font_color", Color(1.0, 0.45, 0.40, 1.0))
	elif _total_encounter_damage > 0.0:
		_title_label.add_theme_color_override(&"font_color", Color(0.40, 0.90, 0.50, 1.0))
	else:
		_title_label.add_theme_color_override(&"font_color", Color(0.65, 0.70, 0.78, 1.0))


func _refresh_display() -> void:
	_update_header()

	var tracked_classes: Array[StringName] = []
	for cid: StringName in _squad_counts.keys():
		tracked_classes.append(cid)
	for cid: StringName in _class_damages.keys():
		if not tracked_classes.has(cid):
			tracked_classes.append(cid)

	var effective_time: float = maxf(1.0, _combat_duration)
	var entries: Array[MeterEntry] = []
	var entry_idx: int = 0

	for cid: StringName in tracked_classes:
		var dmg: float = _class_damages.get(cid, 0.0)
		var dps: float = dmg / effective_time
		var count: int = _squad_counts.get(cid, 0)
		var avg_dps: float = dps / float(maxi(1, count))
		var pct: float = (dmg / _total_encounter_damage * 100.0) if _total_encounter_damage > 0.0 else 0.0

		var hero_data: HeroData = HeroData.get_hero(cid)
		var entry: MeterEntry
		if entry_idx < _entry_pool.size():
			entry = _entry_pool[entry_idx]
		else:
			entry = MeterEntry.new()
			_entry_pool.append(entry)

		entry.class_id = cid
		entry.abbr = hero_data.abbr
		entry.color = hero_data.color
		entry.count = count
		entry.dps = dps
		entry.avg_dps = avg_dps
		entry.pct = pct
		entries.append(entry)
		entry_idx += 1

	entries.sort_custom(_compare_entries)

	for i: int in range(entries.size()):
		var row: DamageMeterRow
		if i < _row_pool.size():
			row = _row_pool[i]
		else:
			row = DamageMeterRow.new()
			_row_pool.append(row)
			_rows_container.add_child(row)

		var item: MeterEntry = entries[i]
		row.visible = true
		row.setup(item.abbr, item.color, item.count, item.dps, item.avg_dps, item.pct)

	for i: int in range(entries.size(), _row_pool.size()):
		_row_pool[i].visible = false


static func _compare_entries(a: MeterEntry, b: MeterEntry) -> bool:
	if absf(a.dps - b.dps) > 0.001:
		return a.dps > b.dps
	return a.count > b.count


static func format_compact(value: float) -> String:
	if value >= 1_000_000.0:
		return "%.1fM" % (value / 1_000_000.0)
	if value >= 1_000.0:
		return "%.1fK" % (value / 1_000.0)
	return "%d" % int(roundf(value))

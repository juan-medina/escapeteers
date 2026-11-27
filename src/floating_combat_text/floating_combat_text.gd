# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

## Single-node pooled floating combat text with WoW-style burst merging (amt xN) and batched TextLine drawing.
class_name FloatingCombatText
extends Node2D


class TextEntry:
	extends RefCounted
	var active: bool = false
	var kind: int = 0
	var target_id: int = 0
	var total_amount: float = 0.0
	var hit_count: int = 0
	var is_heavy: bool = false
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var elapsed: float = 0.0
	var merge_age: float = 0.0
	var duration: float = 0.72
	var color: Color = Color.WHITE
	var text_line: TextLine = TextLine.new()
	var width: float = 0.0


const KIND_DAMAGE: int = 0
const KIND_HEAL: int = 1
const KIND_IMMUNE: int = 2
const KIND_HERO_DAMAGE: int = 3

const FONT: FontFile = preload("res://data/assets/pixel_ui_theme/m5x7.ttf")
const FONT_SIZE: int = 16
const OUTLINE_OFFSETS: Array[Vector2] = [Vector2(-1.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, -1.0), Vector2(0.0, 1.0)]
const POOL_SIZE: int = 48
const MERGE_WINDOW: float = 0.30
const MAX_MERGE_AGE: float = 0.65
const IMMUNE_COOLDOWN: float = 0.55
const DURATION_DAMAGE: float = 0.72
const DURATION_IMMUNE: float = 0.80
const DURATION_HEAL: float = 0.75
const RISE_SPEED: float = 22.0
const RISE_DRAG: float = 28.0

const COLOR_DAMAGE: Color = Color(1.0, 0.98, 0.92, 1.0)
const COLOR_HEAVY: Color = Color(1.0, 0.85, 0.28, 1.0)
const COLOR_IMMUNE: Color = Color(0.86, 0.56, 1.0, 1.0)
const COLOR_HEAL: Color = Color(0.42, 1.0, 0.55, 1.0)
const COLOR_HERO_DAMAGE: Color = Color(1.0, 0.36, 0.36, 1.0)
const COLOR_SHADOW: Color = Color(0.04, 0.03, 0.06, 0.92)

var _entries: Array[TextEntry] = []
var _active_count: int = 0
var _next_evict_idx: int = 0
var _hooked_heroes: Dictionary[int, bool] = {}
var _immune_last_time: Dictionary[int, float] = {}


func _ready() -> void:
	z_index = 20
	for _i: int in range(POOL_SIZE):
		_entries.append(TextEntry.new())
	set_process(false)
	var characters: Node2D = get_parent().get_node(^"Characters") as Node2D
	characters.child_entered_tree.connect(_on_character_added)
	for child: Node in characters.get_children():
		_on_character_added(child)


func _on_character_added(node: Node) -> void:
	if node is Hero:
		var hero: Hero = node as Hero
		var hid: int = hero.get_instance_id()
		if _hooked_heroes.has(hid):
			return
		_hooked_heroes[hid] = true
		hero.enemy_hit.connect(_on_hero_enemy_hit)
		hero.ally_healed.connect(_on_hero_ally_healed)
		hero.damaged.connect(_on_hero_damaged.bind(hero))


func _on_hero_enemy_hit(enemy: Enemy, damage: float, is_heavy: bool) -> void:
	if not is_instance_valid(enemy) or not enemy.is_visible_on_screen():
		return
	var eid: int = enemy.get_instance_id()
	if damage <= 0.0 or enemy.is_damage_immune:
		var now_sec: float = float(Time.get_ticks_msec()) * 0.001
		var last_t: float = _immune_last_time.get(eid, -10.0)
		if now_sec - last_t < IMMUNE_COOLDOWN:
			return
		_immune_last_time[eid] = now_sec
		_spawn_entry(eid, KIND_IMMUNE, 0.0, false, enemy.global_position + Vector2(randf_range(-4.0, 4.0), -22.0), DURATION_IMMUNE)
		return
	_spawn_or_merge_number(eid, KIND_DAMAGE, damage, is_heavy, enemy.global_position + Vector2(0.0, -20.0), DURATION_DAMAGE)


func _on_hero_ally_healed(ally: Character, amount: float) -> void:
	if amount < 1.0 or not is_instance_valid(ally) or not ally.is_visible_on_screen():
		return
	_spawn_or_merge_number(ally.get_instance_id(), KIND_HEAL, amount, false, ally.global_position + Vector2(0.0, -22.0), DURATION_HEAL)


func _on_hero_damaged(amount: float, _current_health: float, hero: Hero) -> void:
	if amount < 1.0 or not is_instance_valid(hero) or not hero.is_visible_on_screen():
		return
	_spawn_or_merge_number(hero.get_instance_id(), KIND_HERO_DAMAGE, amount, false, hero.global_position + Vector2(0.0, -20.0), DURATION_DAMAGE)


func _spawn_or_merge_number(
	target_id: int,
	kind: int,
	amount: float,
	is_heavy: bool,
	base_pos: Vector2,
	duration: float,
) -> void:
	for entry: TextEntry in _entries:
		if not entry.active or entry.target_id != target_id or entry.kind != kind:
			continue
		if entry.elapsed <= MERGE_WINDOW and entry.merge_age <= MAX_MERGE_AGE:
			entry.total_amount += amount
			entry.hit_count += 1
			if is_heavy:
				entry.is_heavy = true
			entry.elapsed = minf(entry.elapsed, 0.08)
			entry.pos = base_pos + Vector2(randf_range(-3.0, 3.0), -2.0)
			entry.vel = Vector2(randf_range(-6.0, 6.0), -RISE_SPEED)
			_rebuild_entry_text(entry)
			queue_redraw()
			return
	_spawn_entry(target_id, kind, amount, is_heavy, base_pos + Vector2(randf_range(-4.0, 4.0), 0.0), duration)


func _spawn_entry(
	target_id: int,
	kind: int,
	amount: float,
	is_heavy: bool,
	start_pos: Vector2,
	duration: float,
) -> void:
	var slot: TextEntry = _acquire_slot()
	slot.active = true
	slot.target_id = target_id
	slot.kind = kind
	slot.total_amount = amount
	slot.hit_count = 1
	slot.is_heavy = is_heavy
	slot.pos = start_pos
	slot.vel = Vector2(randf_range(-8.0, 8.0), -RISE_SPEED)
	slot.elapsed = 0.0
	slot.merge_age = 0.0
	slot.duration = duration
	_rebuild_entry_text(slot)
	set_process(true)
	queue_redraw()


func _acquire_slot() -> TextEntry:
	for entry: TextEntry in _entries:
		if not entry.active:
			_active_count += 1
			return entry
	var recycled: TextEntry = _entries[_next_evict_idx]
	_next_evict_idx = (_next_evict_idx + 1) % POOL_SIZE
	return recycled


func _rebuild_entry_text(entry: TextEntry) -> void:
	var label_text: String = ""
	if entry.kind == KIND_IMMUNE:
		label_text = "IMMUNE"
		entry.color = COLOR_IMMUNE
	else:
		var amt: int = maxi(1, roundi(entry.total_amount))
		var suffix: String = (" x%d" % entry.hit_count) if entry.hit_count > 1 else ""
		if entry.kind == KIND_HEAL:
			label_text = "+%d%s" % [amt, suffix]
			entry.color = COLOR_HEAL
		elif entry.kind == KIND_HERO_DAMAGE:
			label_text = "-%d%s" % [amt, suffix]
			entry.color = COLOR_HERO_DAMAGE
		else:
			label_text = "%d%s" % [amt, suffix]
			entry.color = COLOR_HEAVY if entry.is_heavy else COLOR_DAMAGE
	entry.text_line.clear()
	entry.text_line.add_string(label_text, FONT, FONT_SIZE)
	entry.width = entry.text_line.get_line_width()


func _process(delta: float) -> void:
	for entry: TextEntry in _entries:
		if not entry.active:
			continue
		entry.elapsed += delta
		entry.merge_age += delta
		if entry.elapsed >= entry.duration:
			entry.active = false
			_active_count = maxi(0, _active_count - 1)
			continue
		entry.pos += entry.vel * delta
		entry.vel.y = move_toward(entry.vel.y, -4.0, RISE_DRAG * delta)
	if _active_count <= 0:
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if _active_count <= 0:
		return
	var ci: RID = get_canvas_item()
	for pass_idx: int in range(2):
		var is_shadow: bool = pass_idx == 0
		for entry: TextEntry in _entries:
			if not entry.active:
				continue
			var t: float = clampf(entry.elapsed / maxf(0.01, entry.duration), 0.0, 1.0)
			var alpha: float = 1.0 if t < 0.65 else clampf(1.0 - (t - 0.65) / 0.35, 0.0, 1.0)
			var base_x: float = roundf(entry.pos.x - entry.width * 0.5)
			var base_y: float = roundf(entry.pos.y)
			if is_shadow:
				var shadow_col: Color = Color(COLOR_SHADOW.r, COLOR_SHADOW.g, COLOR_SHADOW.b, COLOR_SHADOW.a * alpha)
				var base_pos: Vector2 = Vector2(base_x, base_y)
				for off: Vector2 in OUTLINE_OFFSETS:
					entry.text_line.draw(ci, base_pos + off, shadow_col)
			else:
				entry.text_line.draw(ci, Vector2(base_x, base_y), Color(entry.color.r, entry.color.g, entry.color.b, alpha))

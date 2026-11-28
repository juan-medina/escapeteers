# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name RunScore
extends RefCounted


class ScoreLine:
	extends RefCounted
	var id: StringName = &""
	var label: String = ""
	var detail: String = ""
	var points: int = 0
	var is_penalty: bool = false

	func _init(line_id: StringName, line_label: String, line_detail: String, line_points: int, line_penalty: bool = false) -> void:
		id = line_id
		label = line_label
		detail = line_detail
		points = line_points
		is_penalty = line_penalty


const RECORDS_PATH: StringName = &"user://records.cfg"
const SECTION_RECORDS: StringName = &"records"
const KEY_BEST_SCORE: StringName = &"best_score"
const POINTS_PER_RESCUED: int = 100
const POINTS_PER_EXPLORED_PCT: int = 10
const PENALTY_PER_FALLEN: int = -50

var lines: Array[ScoreLine] = []
var total_score: int = 0
var best_score: int = 0
var is_new_best: bool = false


static func calculate(stats: RunStats) -> RunScore:
	var score: RunScore = RunScore.new()
	var rescue_pts: int = stats.escapees_rescued * POINTS_PER_RESCUED
	(
		score
		. lines
		. append(
			(
				ScoreLine
				. new(
					&"escapees_rescued",
					"Escapees Rescued",
					"%d x +%d" % [stats.escapees_rescued, POINTS_PER_RESCUED],
					rescue_pts,
					false,
				)
			)
		)
	)
	var explored_pts: int = stats.explored_percent * POINTS_PER_EXPLORED_PCT
	(
		score
		. lines
		. append(
			(
				ScoreLine
				. new(
					&"dungeon_explored",
					"Dungeon Explored",
					"%d%% x +%d" % [stats.explored_percent, POINTS_PER_EXPLORED_PCT],
					explored_pts,
					false,
				)
			)
		)
	)
	var fallen_pts: int = stats.fallen_companions * PENALTY_PER_FALLEN
	(
		score
		. lines
		. append(
			(
				ScoreLine
				. new(
					&"fallen_companions",
					"Fallen Companions",
					"%d x -%d" % [stats.fallen_companions, absi(PENALTY_PER_FALLEN)],
					fallen_pts,
					true,
				)
			)
		)
	)

	var raw_total: int = 0
	for line: ScoreLine in score.lines:
		raw_total += line.points
	score.total_score = maxi(0, raw_total)
	return score


static func load_best_score() -> int:
	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load(RECORDS_PATH)
	if err != OK:
		if err != ERR_FILE_NOT_FOUND:
			printerr(&"RunScore: Failed to load records from %s. Error: %d !" % [RECORDS_PATH, err])
		return 0
	var val: Variant = config.get_value(SECTION_RECORDS, KEY_BEST_SCORE, 0)
	if val is int:
		var int_val: int = val
		return maxi(0, int_val)
	return 0


func commit_best_score() -> void:
	var previous_best: int = load_best_score()
	if total_score > previous_best:
		is_new_best = true
		best_score = total_score
		var config: ConfigFile = ConfigFile.new()
		config.load(RECORDS_PATH)
		config.set_value(SECTION_RECORDS, KEY_BEST_SCORE, best_score)
		var err: Error = config.save(RECORDS_PATH)
		if err != OK:
			printerr(&"RunScore: Failed to save records to %s. Error: %d !" % [RECORDS_PATH, err])
	else:
		is_new_best = false
		best_score = previous_best

# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name AutoplayPlan
extends WorldPlan

var forced_seed: int = 0
var forced_max_depth: int = 12


func generate(seed_val: int = 0, max_depth: int = 12) -> void:
	var target_seed: int = forced_seed if forced_seed != 0 else seed_val
	var target_depth: int = forced_max_depth if forced_max_depth > 0 else max_depth
	if target_seed != 0:
		seed(target_seed)
	super.generate(target_seed, target_depth)

# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name Coin
extends Node2D

const PICKUP_DISTANCE: float = 18.0


func is_touching(hero: Hero) -> bool:
	return position.distance_squared_to(hero.position) <= PICKUP_DISTANCE * PICKUP_DISTANCE

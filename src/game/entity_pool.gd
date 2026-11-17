# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name EntityPool
extends RefCounted

const OFF_SCREEN_POS: Vector2 = Vector2(-999999.0, -999999.0)

var _pools: Dictionary[PackedScene, Array] = {}
var _node_scenes: Dictionary[Node2D, PackedScene] = {}
var _parent_node: Node = null


func setup(parent: Node) -> void:
	_parent_node = parent
	_pools.clear()
	_node_scenes.clear()


func prewarm(scene: PackedScene, count: int) -> void:
	if not _pools.has(scene):
		_pools[scene] = []
	var pool: Array = _pools[scene]
	for _i: int in range(count):
		var inst: Node2D = scene.instantiate() as Node2D
		_node_scenes[inst] = scene
		_parent_node.add_child(inst)
		_deactivate(inst)
		pool.append(inst)


func acquire(scene: PackedScene) -> Node2D:
	if not _pools.has(scene):
		_pools[scene] = []
	var pool: Array = _pools[scene]
	var inst: Node2D
	if pool.is_empty():
		inst = scene.instantiate() as Node2D
		_node_scenes[inst] = scene
		_parent_node.add_child(inst)
	else:
		inst = pool.pop_back()

	_activate(inst)
	return inst


func release(node: Node2D) -> void:
	var target_scene: PackedScene = _node_scenes[node]
	_deactivate(node)
	_pools[target_scene].append(node)


func _activate(node: Node2D) -> void:
	node.visible = true
	if node is Enemy:
		(node as Enemy).reset_for_pool()
	elif node is Projectile:
		(node as Projectile).reset_for_pool()


func _deactivate(node: Node2D) -> void:
	node.visible = false
	node.set_physics_process(false)
	node.set_process(false)
	node.position = OFF_SCREEN_POS
	if node is Enemy:
		(node as Enemy).deactivate_for_pool()
	elif node is Projectile:
		(node as Projectile).deactivate_for_pool()

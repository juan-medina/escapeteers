# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name EntityPool
extends RefCounted

var _pools: Dictionary[PackedScene, Array] = {}
var _parent_node: Node = null


func setup(parent: Node) -> void:
	_parent_node = parent
	_pools.clear()


func prewarm(scene: PackedScene, count: int) -> void:
	if not _pools.has(scene):
		_pools[scene] = []
	var pool: Array = _pools[scene]
	for _i: int in range(count):
		var inst: Node2D = scene.instantiate() as Node2D
		_parent_node.add_child(inst)
		_deactivate(inst)
		pool.append(inst)


func acquire(scene: PackedScene) -> Node2D:
	if not _pools.has(scene):
		_pools[scene] = []
	var pool: Array = _pools[scene]
	var inst: Node2D = null

	while not pool.is_empty():
		@warning_ignore("unsafe_cast")
		var candidate: Node2D = pool.pop_back() as Node2D
		if is_instance_valid(candidate):
			inst = candidate
			break

	if inst == null:
		inst = scene.instantiate() as Node2D
		_parent_node.add_child(inst)

	_activate(inst)
	return inst


func release(node: Node2D, scene: PackedScene) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not _pools.has(scene):
		_pools[scene] = []
	_deactivate(node)
	_pools[scene].append(node)


func _activate(node: Node2D) -> void:
	node.visible = true
	node.set_physics_process(true)
	node.set_process(true)
	if node is Enemy:
		(node as Enemy).reset_for_pool()
	elif node.has_method(&"reset_for_pool"):
		node.call(&"reset_for_pool")


func _deactivate(node: Node2D) -> void:
	node.visible = false
	node.set_physics_process(false)
	node.set_process(false)
	if node is Character:
		(node as Character).disable_collisions()
	elif node.has_method(&"disable_collisions"):
		node.call(&"disable_collisions")

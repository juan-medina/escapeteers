# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

class_name EntityPool
extends RefCounted

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
	var inst: Node2D = null

	while not pool.is_empty():
		var raw_candidate: Variant = pool.pop_back()
		if is_instance_valid(raw_candidate):
			inst = raw_candidate
			break

	if inst == null:
		inst = scene.instantiate() as Node2D
		_node_scenes[inst] = scene
		_parent_node.add_child(inst)

	_activate(inst)
	return inst


func release(node: Node2D, scene: PackedScene = null) -> void:
	if node == null or not is_instance_valid(node):
		return
	var target_scene: PackedScene = scene
	if target_scene == null and _node_scenes.has(node):
		target_scene = _node_scenes[node]
	if target_scene == null:
		return
	if not _pools.has(target_scene):
		_pools[target_scene] = []
	_deactivate(node)
	if not _pools[target_scene].has(node):
		_pools[target_scene].append(node)


func _activate(node: Node2D) -> void:
	node.visible = true
	if node is Enemy:
		(node as Enemy).reset_for_pool()
	elif node is Projectile:
		(node as Projectile).reset_for_pool()
	else:
		node.set_physics_process(true)
		node.set_process(true)


func _deactivate(node: Node2D) -> void:
	node.visible = false
	node.set_physics_process(false)
	node.set_process(false)
	node.position = Vector2(-999999.0, -999999.0)
	if node is Enemy:
		(node as Enemy).deactivate_for_pool()
	elif node is Projectile:
		(node as Projectile).deactivate_for_pool()
	elif node is Character:
		(node as Character).disable_collisions()

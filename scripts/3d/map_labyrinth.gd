extends Node3D

func _ready() -> void:
	var model_node = get_node_or_null("LabyrinthModel/model") as MeshInstance3D
	if model_node:
		var col_body = model_node.get_node_or_null("model_col") as StaticBody3D
		if not col_body:
			model_node.create_trimesh_collision()
			col_body = model_node.get_node_or_null("model_col") as StaticBody3D
		if col_body:
			col_body.collision_layer = 1
			col_body.collision_mask = 3
			col_body.position.y = 0.02

# Calibrated spawns for Labyrinth Maze (Inside inner corridors)
var chaser_spawns: Array[Vector3] = [
	Vector3(-15.0, 5.6, -16.0),
	Vector3(-17.0, 4.6, -7.0)
]

var runner_spawns: Array[Vector3] = [
	Vector3(-15.0, 6.0, 12.0),
	Vector3(16.0, 5.3, 14.0),
	Vector3(7.0, 5.1, 3.0),
	Vector3(16.0, 5.4, -2.0),
	Vector3(-16.0, 5.2, 6.0),
	Vector3(-5.0, 5.0, -2.0)
]

var item_spawns: Array[Vector3] = [
	Vector3(-4.0, 5.1, -2.0),
	Vector3(-14.0, 5.4, 15.0),
	Vector3(8.0, 5.2, -6.0),
	Vector3(12.0, 5.4, 10.0),
	Vector3(-10.0, 5.2, 5.0),
	Vector3(5.0, 5.0, -12.0)
]

func get_tagger_spawn() -> Vector3:
	return chaser_spawns.pick_random()

func get_runner_spawn(index: int = 0) -> Vector3:
	if index < runner_spawns.size():
		return runner_spawns[index]
	return runner_spawns.pick_random()

func get_random_safe_spawn() -> Vector3:
	return runner_spawns.pick_random()

func get_random_item_spawn() -> Vector3:
	return item_spawns.pick_random()

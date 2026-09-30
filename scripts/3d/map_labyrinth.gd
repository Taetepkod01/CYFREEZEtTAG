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

# Calibrated spawns for Labyrinth Maze (Upright true floor + walls)
var chaser_spawns: Array[Vector3] = [
	Vector3(-32.0, 9.0, -20.0),
	Vector3(-30.0, 9.0, -18.0)
]

var runner_spawns: Array[Vector3] = [
	Vector3(-36.0, 12.3, 12.0),
	Vector3(0.0, 5.1, 20.0),
	Vector3(14.0, 5.2, -10.0),
	Vector3(34.0, 8.2, 6.0),
	Vector3(-36.0, 4.8, 0.0),
	Vector3(-14.0, 11.0, 10.0)
]

var item_spawns: Array[Vector3] = [
	Vector3(-8.0, 11.0, -8.0),
	Vector3(0.0, 5.0, -8.0),
	Vector3(-34.0, 5.2, 16.0),
	Vector3(14.0, 12.0, -6.0),
	Vector3(-36.0, 5.0, 2.0),
	Vector3(-30.0, 9.1, -18.0)
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

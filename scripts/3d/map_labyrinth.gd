extends Node3D

func _ready() -> void:
	var model_node = get_node_or_null("LabyrinthModel/model") as MeshInstance3D
	if model_node and model_node.mesh:
		var static_body = get_node_or_null("StaticBody3D") as StaticBody3D
		if static_body and static_body.get_child_count() == 0:
			var col = CollisionShape3D.new()
			col.name = "ModelCollision"
			col.shape = model_node.mesh.create_trimesh_shape()
			static_body.add_child(col)

# Spawn positions for Labyrinth Maze (Upright corridor floors)
var chaser_spawns: Array[Vector3] = [
	Vector3(-3.0, 5.8, -22.0),
	Vector3(7.0, 5.5, -22.0)
]

var runner_spawns: Array[Vector3] = [
	Vector3(-3.0, 3.3, 18.0),
	Vector3(-20.0, 3.1, 13.0),
	Vector3(15.0, 8.3, 13.0),
	Vector3(-21.0, 3.2, -10.0),
	Vector3(15.0, 3.3, -13.0),
	Vector3(-3.0, 7.2, -3.0)
]

var item_spawns: Array[Vector3] = [
	Vector3(-13.0, 8.5, -2.0),
	Vector3(7.0, 8.2, -3.0),
	Vector3(-3.0, 3.4, 10.0),
	Vector3(-3.0, 8.2, -13.0),
	Vector3(-18.0, 4.5, -18.0),
	Vector3(12.0, 4.2, -18.0),
	Vector3(-18.0, 3.2, 12.0),
	Vector3(12.0, 4.1, 12.0)
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

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

# Spawn positions for Labyrinth Maze (Right-side up corridor floors)
var chaser_spawns: Array[Vector3] = [
	Vector3(-12.0, 0.8, -18.0),
	Vector3(-10.0, 0.8, -18.0)
]

var runner_spawns: Array[Vector3] = [
	Vector3(-14.0, 0.5, 18.0),
	Vector3(12.0, 0.6, 4.0),
	Vector3(0.0, 0.9, 8.0),
	Vector3(6.0, 1.4, -4.0),
	Vector3(-4.0, 1.4, 2.0),
	Vector3(2.0, 1.3, 6.0)
]

var item_spawns: Array[Vector3] = [
	Vector3(0.0, 0.9, 8.0),         # Center Intersection
	Vector3(-12.0, 0.4, 0.0),       # West Corridor
	Vector3(-4.0, 0.5, 10.0),       # South-Central Path
	Vector3(8.0, 0.7, -14.0),       # Northeast Path
	Vector3(12.0, 0.6, 4.0),        # East Corridor
	Vector3(-10.0, 0.5, -14.0),     # North-Central Path
	Vector3(-8.0, 1.5, 0.0)         # Central Hub
]

func get_tagger_spawn() -> Vector3:
	return chaser_spawns.pick_random()

func get_runner_spawn(index: int = 0) -> Vector3:
	if index < runner_spawns.size():
		return runner_spawns[index]
	return runner_spawns.pick_random()

func get_random_safe_spawn() -> Vector3:
	var all_spawns: Array[Vector3] = [
		Vector3(-14.0, 0.5, 18.0),
		Vector3(12.0, 0.6, 4.0),
		Vector3(0.0, 0.9, 8.0),
		Vector3(6.0, 1.4, -4.0),
		Vector3(-4.0, 1.4, 2.0),
		Vector3(2.0, 1.3, 6.0),
		Vector3(-12.0, 0.4, 0.0),
		Vector3(-10.0, 0.5, -14.0)
	]
	return all_spawns.pick_random()

func get_random_item_spawn() -> Vector3:
	return item_spawns.pick_random()

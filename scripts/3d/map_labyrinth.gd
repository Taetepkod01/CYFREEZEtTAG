extends Node3D

# Spawn positions for Labyrinth Maze
var chaser_spawns: Array[Vector3] = [
	Vector3(-18.0, 0.5, -18.0),
	Vector3(-15.0, 0.5, -18.0),
	Vector3(-18.0, 0.5, -15.0)
]

var runner_spawns: Array[Vector3] = [
	Vector3(18.0, 0.5, 18.0),
	Vector3(18.0, 0.5, -18.0),
	Vector3(-18.0, 0.5, 18.0),
	Vector3(0.0, 0.5, 0.0),
	Vector3(10.0, 0.5, -10.0),
	Vector3(-10.0, 0.5, 10.0)
]

var item_spawns: Array[Vector3] = [
	Vector3(0.0, 0.6, 0.0),        # Maze Center
	Vector3(-10.0, 0.6, -10.0),    # Northwest Crossroad
	Vector3(10.0, 0.6, 10.0),      # Southeast Crossroad
	Vector3(-10.0, 0.6, 10.0),     # Southwest Junction
	Vector3(10.0, 0.6, -10.0),     # Northeast Junction
	Vector3(0.0, 0.6, -12.0),      # North Path
	Vector3(0.0, 0.6, 12.0),       # South Path
	Vector3(-12.0, 0.6, 0.0),      # West Path
	Vector3(12.0, 0.6, 0.0)        # East Path
]

func _ready() -> void:
	# Ensure trimesh collision exists for glb model
	var model_node = get_node_or_null("LabyrinthModel/model") as MeshInstance3D
	if model_node and model_node.mesh:
		var static_body = get_node_or_null("StaticBody3D") as StaticBody3D
		if static_body and static_body.get_child_count() == 0:
			var col = CollisionShape3D.new()
			col.name = "ModelCollision"
			col.shape = model_node.mesh.create_trimesh_shape()
			static_body.add_child(col)

func get_tagger_spawn() -> Vector3:
	return chaser_spawns.pick_random()

func get_runner_spawn(index: int = 0) -> Vector3:
	if index < runner_spawns.size():
		return runner_spawns[index]
	return runner_spawns.pick_random()

func get_random_safe_spawn() -> Vector3:
	var all_spawns: Array[Vector3] = [
		Vector3(0.0, 0.5, 0.0),
		Vector3(-18.0, 0.5, -18.0),
		Vector3(18.0, 0.5, 18.0),
		Vector3(18.0, 0.5, -18.0),
		Vector3(-18.0, 0.5, 18.0),
		Vector3(-10.0, 0.5, -10.0),
		Vector3(10.0, 0.5, 10.0),
		Vector3(-10.0, 0.5, 10.0),
		Vector3(10.0, 0.5, -10.0)
	]
	return all_spawns.pick_random()

func get_random_item_spawn() -> Vector3:
	return item_spawns.pick_random()

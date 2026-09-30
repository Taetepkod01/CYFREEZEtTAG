extends Node3D

func _ready() -> void:
	var model_node = get_node_or_null("SnowTownModel/model") as MeshInstance3D
	if model_node and model_node.mesh:
		var static_body = get_node_or_null("StaticBody3D") as StaticBody3D
		if static_body and static_body.get_child_count() == 0:
			var col = CollisionShape3D.new()
			col.name = "ModelCollision"
			col.shape = model_node.mesh.create_trimesh_shape()
			static_body.add_child(col)

# Spawn positions for Snow Town (exact ground level Y ~ 0.5 - 0.8)
var chaser_spawns: Array[Vector3] = [
	Vector3(-14.0, 0.6, -14.0),
	Vector3(-12.0, 0.6, -12.0)
]

var runner_spawns: Array[Vector3] = [
	Vector3(14.0, 0.5, -8.0),
	Vector3(-18.0, 0.6, 10.0),
	Vector3(18.0, 0.6, 14.0),
	Vector3(0.0, 0.8, -2.0),
	Vector3(-16.0, 0.6, 0.0),
	Vector3(4.0, 0.6, 0.0)
]

var item_spawns: Array[Vector3] = [
	Vector3(0.0, 0.8, -2.0),        # Town Center Square
	Vector3(4.0, 0.6, 0.0),         # East Lane
	Vector3(-12.0, 0.6, 18.0),      # South Market
	Vector3(6.0, 0.5, -12.0),       # North Street
	Vector3(10.0, 0.6, -2.0),       # East Alley
	Vector3(-20.0, 0.6, 10.0),      # Southwest Corner
	Vector3(18.0, 0.5, -6.0)        # Northeast Avenue
]

func get_tagger_spawn() -> Vector3:
	return chaser_spawns.pick_random()

func get_runner_spawn(index: int = 0) -> Vector3:
	if index < runner_spawns.size():
		return runner_spawns[index]
	return runner_spawns.pick_random()

func get_random_safe_spawn() -> Vector3:
	var all_spawns: Array[Vector3] = [
		Vector3(0.0, 0.8, -2.0),
		Vector3(-14.0, 0.6, -14.0),
		Vector3(14.0, 0.5, -8.0),
		Vector3(-18.0, 0.6, 10.0),
		Vector3(18.0, 0.6, 14.0),
		Vector3(-16.0, 0.6, 0.0),
		Vector3(4.0, 0.6, 0.0),
		Vector3(-10.0, 0.6, 18.0)
	]
	return all_spawns.pick_random()

func get_random_item_spawn() -> Vector3:
	return item_spawns.pick_random()

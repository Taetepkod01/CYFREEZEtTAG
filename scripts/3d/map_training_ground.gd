extends Node3D

# Spawn positions for Training Ground
# Ground level: Y ~ 0.5
# Mid Terraces: Y ~ 2.9
# High Skybridge: Y ~ 5.5

var chaser_spawns: Array[Vector3] = [
	Vector3(0.0, 5.5, 0.0),        # High Center Skybridge (Dominant vantage point)
	Vector3(0.0, 0.5, 0.0),        # Center Plaza Ground
	Vector3(-4.0, 0.5, -4.0)
]

var runner_spawns: Array[Vector3] = [
	Vector3(-18.0, 2.9, -18.0),    # Northwest Terrace
	Vector3(18.0, 2.9, -18.0),     # Northeast Terrace
	Vector3(-18.0, 2.9, 18.0),     # Southwest Terrace
	Vector3(18.0, 2.9, 18.0),      # Southeast Terrace
	Vector3(-20.0, 0.5, 0.0),      # West Courtyard
	Vector3(20.0, 0.5, 0.0),       # East Courtyard
	Vector3(0.0, 0.5, -18.0),      # North Plaza
	Vector3(0.0, 0.5, 18.0)        # South Plaza
]

var item_spawns: Array[Vector3] = [
	Vector3(0.0, 5.5, 0.0),        # Bridge Arch Center
	Vector3(-14.0, 5.5, 0.0),      # West Skywalk
	Vector3(14.0, 5.5, 0.0),       # East Skywalk
	Vector3(-16.0, 2.9, -14.0),    # NW Terrace Item
	Vector3(16.0, 2.9, 14.0),      # SE Terrace Item
	Vector3(0.0, 0.6, -10.0),      # North Hurdle
	Vector3(0.0, 0.6, 10.0),       # South Hurdle
	Vector3(-6.0, 0.6, 6.0),       # SW Cube Alley
	Vector3(6.0, 0.6, -6.0)        # NE Cube Alley
]

func get_tagger_spawn(index: int = 0) -> Vector3:
	if index < chaser_spawns.size():
		return chaser_spawns[index]
	return chaser_spawns.pick_random()

func get_runner_spawn(index: int = 0) -> Vector3:
	if index < runner_spawns.size():
		return runner_spawns[index]
	return runner_spawns.pick_random()

func get_random_safe_spawn() -> Vector3:
	var pool = runner_spawns + chaser_spawns
	return pool.pick_random()

func get_random_item_spawn() -> Vector3:
	return item_spawns.pick_random()

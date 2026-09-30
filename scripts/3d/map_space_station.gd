extends Node3D

@onready var earth_hologram: MeshInstance3D = get_node_or_null("CentralHub/EarthHologram")
@onready var holo_ring: MeshInstance3D = get_node_or_null("CentralHub/HoloRing")
@onready var cryo_core: MeshInstance3D = get_node_or_null("Laboratory/CryoChamber/Core")

# Spawn positions for players
var chaser_spawns: Array[Vector3] = [
	Vector3(0.0, 0.5, -20.0),
	Vector3(-3.0, 0.5, -21.0),
	Vector3(3.0, 0.5, -21.0)
]

var runner_spawns: Array[Vector3] = [
	Vector3(0.0, 0.5, 20.0),
	Vector3(-22.0, 0.5, 0.0),
	Vector3(-16.0, 0.5, -15.0),
	Vector3(-16.0, 0.5, 15.0),
	Vector3(16.0, 0.5, 15.0),
	Vector3(22.0, 0.5, 0.0)
]

var item_spawns: Array[Vector3] = [
	Vector3(0.0, 0.6, 0.0),        # Central hub (near holo globe)
	Vector3(-16.0, 0.6, -15.0),    # Cafeteria
	Vector3(-16.0, 0.6, 15.0),     # Cargo Bay
	Vector3(16.0, 0.6, 15.0),      # Medbay
	Vector3(22.0, 0.6, 0.0),       # Laboratory
	Vector3(-22.0, 0.6, 0.0),      # West Oxygen Bay
	Vector3(0.0, 0.6, -10.0),      # North Corridor
	Vector3(0.0, 0.6, 10.0)        # South Corridor
]

var time_passed: float = 0.0

func _process(delta: float) -> void:
	time_passed += delta
	
	# Slowly rotate Earth hologram and equatorial holo-ring
	if is_instance_valid(earth_hologram):
		earth_hologram.rotate_y(0.35 * delta)
		# Gentle bobbing
		earth_hologram.position.y = 2.4 + sin(time_passed * 1.5) * 0.1
	
	if is_instance_valid(holo_ring):
		holo_ring.rotate_y(-0.5 * delta)
		holo_ring.rotate_z(0.15 * delta)
	
	# Pulse Cryo Chamber Core
	if is_instance_valid(cryo_core):
		var mat = cryo_core.get_active_material(0)
		if mat is StandardMaterial3D:
			var pulse = (sin(time_passed * 2.5) + 1.0) * 0.5
			mat.emission_energy_multiplier = 1.8 + pulse * 1.2

func get_tagger_spawn() -> Vector3:
	return chaser_spawns.pick_random()

func get_runner_spawn(index: int = 0) -> Vector3:
	if index < runner_spawns.size():
		return runner_spawns[index]
	return runner_spawns.pick_random()

func get_random_item_spawn() -> Vector3:
	return item_spawns.pick_random()

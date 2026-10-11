extends Node3D

# Low gravity space physics parameters
const MAP_GRAVITY: float = 3.2
const MAP_JUMP_VELOCITY: float = 5.2
const HAS_LOW_GRAVITY: bool = true

@onready var earth_hologram: MeshInstance3D = get_node_or_null("CentralHub/EarthHologram")
@onready var holo_ring: MeshInstance3D = get_node_or_null("CentralHub/HoloRing")
@onready var cryo_core: MeshInstance3D = get_node_or_null("Laboratory/CryoChamber/Core")

var jump_pad_cooldowns: Dictionary = {}

# Spawn positions for players
var chaser_spawns: Array[Vector3] = [
	Vector3(0.0, 0.5, -22.0),
	Vector3(-3.0, 0.5, -22.0),
	Vector3(3.0, 0.5, -22.0)
]

var runner_spawns: Array[Vector3] = [
	Vector3(0.0, 0.5, 22.0),
	Vector3(-22.0, 0.5, 0.0),
	Vector3(-20.0, 0.5, -20.0),
	Vector3(-20.0, 0.5, 20.0),
	Vector3(20.0, 0.5, 20.0),
	Vector3(20.0, 0.5, -20.0)
]

var item_spawns: Array[Vector3] = [
	Vector3(0.0, 0.6, 0.0),        # Central hub (near holo globe)
	Vector3(0.0, 2.6, -6.5),       # Central hub (North Catwalk Bridge)
	Vector3(0.0, 2.6, 6.5),        # Central hub (South Catwalk Bridge)
	Vector3(-20.0, 0.6, -20.0),    # Cafeteria
	Vector3(-20.0, 0.6, 20.0),     # Cargo Bay
	Vector3(-24.0, 3.2, 23.0),     # Cargo Bay High Container
	Vector3(20.0, 0.6, 20.0),      # Medbay
	Vector3(20.0, 0.6, -20.0),     # Cryo Lab
	Vector3(-22.0, 0.6, 0.0),      # West Oxygen Bay
	Vector3(-27.0, 2.3, 0.0),      # Oxygen Bay Scaffold
	Vector3(22.0, 0.6, 0.0),       # East Storage
	Vector3(27.0, 2.6, 0.0),       # Laboratory High Server Walkway
	Vector3(0.0, 0.6, -13.0),      # North Corridor
	Vector3(0.0, 0.6, 13.0)        # South Corridor
]

var time_passed: float = 0.0

func _ready() -> void:
	_setup_jump_pads()

func _setup_jump_pads() -> void:
	var pads = get_tree().get_nodes_in_group("jump_pads")
	for pad in pads:
		if pad is Area3D and not pad.body_entered.is_connected(_on_jump_pad_entered):
			pad.body_entered.connect(_on_jump_pad_entered.bind(pad))

func _on_jump_pad_entered(body: Node3D, pad: Area3D) -> void:
	if body is CharacterBody3D and not body.is_frozen:
		var now = Time.get_ticks_msec() / 1000.0
		var body_id = body.get_instance_id()
		if jump_pad_cooldowns.has(body_id) and now - jump_pad_cooldowns[body_id] < 0.6:
			return
		jump_pad_cooldowns[body_id] = now
		
		# Propel player upward with low gravity impulse
		body.velocity.y = 7.2
		
		# Flash visual
		var visual = pad.get_node_or_null("../Visual")
		if visual and visual is CSGCylinder3D:
			var mat = visual.material
			if mat is StandardMaterial3D:
				var tween = create_tween()
				tween.tween_property(mat, "emission_energy_multiplier", 8.0, 0.08)
				tween.tween_property(mat, "emission_energy_multiplier", 3.5, 0.35)

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
	
	# Pulse jump pad visuals
	var pad_pulse = (sin(time_passed * 4.0) + 1.0) * 0.5
	var pads = get_tree().get_nodes_in_group("jump_pads")
	for pad in pads:
		var visual = pad.get_node_or_null("../Visual")
		if visual and visual is CSGCylinder3D:
			var mat = visual.material
			if mat is StandardMaterial3D:
				mat.emission_energy_multiplier = 2.8 + pad_pulse * 1.8

func get_tagger_spawn(index: int = 0) -> Vector3:
	if index < chaser_spawns.size():
		return chaser_spawns[index]
	return chaser_spawns.pick_random()

func get_runner_spawn(index: int = 0) -> Vector3:
	if index < runner_spawns.size():
		return runner_spawns[index]
	return runner_spawns.pick_random()

func get_random_safe_spawn() -> Vector3:
	var all_spawns: Array[Vector3] = [
		Vector3(0.0, 0.5, 0.0),      # Center Hub
		Vector3(0.0, 0.5, -22.0),    # North Chaser Sector
		Vector3(0.0, 0.5, 22.0),     # South Runner Sector
		Vector3(-22.0, 0.5, 0.0),    # West Oxygen Bay
		Vector3(22.0, 0.5, 0.0),     # East Storage
		Vector3(-20.0, 0.5, -20.0),  # Cafeteria
		Vector3(-20.0, 0.5, 20.0),   # Cargo Bay
		Vector3(20.0, 0.5, 20.0),    # Medbay
		Vector3(20.0, 0.5, -20.0)    # Cryo Lab
	]
	return all_spawns.pick_random()

func get_random_item_spawn() -> Vector3:
	return item_spawns.pick_random()

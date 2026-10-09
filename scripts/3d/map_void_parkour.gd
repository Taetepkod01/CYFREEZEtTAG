extends Node3D

signal player_checkpoint_reached(player: CharacterBody3D, checkpoint_idx: int)
signal player_finished_parkour(player: CharacterBody3D)

# ── Spawns for Start Platform ────────────────────────────────────────────────
var chaser_spawns: Array[Vector3] = [
	Vector3(0.0, 1.2, 2.5),
	Vector3(-2.0, 1.2, 2.5),
	Vector3(2.0, 1.2, 2.5)
]

var runner_spawns: Array[Vector3] = [
	Vector3(0.0, 1.2, 0.0),
	Vector3(-3.0, 1.2, 0.0),
	Vector3(3.0, 1.2, 0.0),
	Vector3(-1.5, 1.2, -2.0),
	Vector3(1.5, 1.2, -2.0),
	Vector3(0.0, 1.2, -3.0)
]

var item_spawns: Array[Vector3] = [
	Vector3(0.0, 1.2, -2.0),       # Start Platform
	Vector3(0.0, 1.8, -20.0),      # Block 3
	Vector3(0.0, 5.2, -47.5),      # Before Checkpoint 1
	Vector3(0.0, 5.8, -56.0),      # Checkpoint 1
	Vector3(-2.2, 7.6, -76.5),     # Beam Left 3
	Vector3(2.2, 7.6, -76.5),      # Beam Right 3
	Vector3(0.0, 10.8, -96.0),     # Checkpoint 2
	Vector3(0.0, 12.8, -112.0),    # Section 6 High Jump
	Vector3(0.0, 16.0, -140.0)     # Finish Platform
]

# Checkpoint tracker per player instance
var player_checkpoints: Dictionary = {}

@onready var moving_pillar_1: AnimatableBody3D = get_node_or_null("ParkourCourse/MovingPillar1")
@onready var moving_pillar_2: AnimatableBody3D = get_node_or_null("ParkourCourse/MovingPillar2")
@onready var finish_trophy: Node3D = get_node_or_null("FinishPlatform/VictoryTrophy")
@onready var start_beacon: MeshInstance3D = get_node_or_null("StartPlatform/StartBeacon")
@onready var cp1_beacon: MeshInstance3D = get_node_or_null("Checkpoint1Platform/BeaconRing")
@onready var cp2_beacon: MeshInstance3D = get_node_or_null("Checkpoint2Platform/BeaconRing")

var moving_pillar_1_origin: Vector3 = Vector3(0.0, 7.5, -75.0)
var moving_pillar_2_origin: Vector3 = Vector3(0.0, 11.0, -104.5)
var time_passed: float = 0.0

func _ready() -> void:
	if moving_pillar_1:
		moving_pillar_1_origin = moving_pillar_1.position
	if moving_pillar_2:
		moving_pillar_2_origin = moving_pillar_2.position
	
	_setup_recovery_and_checkpoint_areas()

# ── Dynamic Areas: Void Recovery & Checkpoints ────────────────────────────────
func _setup_recovery_and_checkpoint_areas() -> void:
	# 1. Fall Recovery Void Area (Catches players falling into the endless abyss)
	var void_area = get_node_or_null("VoidRecoveryArea") as Area3D
	if void_area:
		void_area.body_entered.connect(_on_void_recovery_body_entered)
	
	# 2. Checkpoint 1 Area
	var cp1_area = get_node_or_null("Checkpoint1Platform/CheckpointArea") as Area3D
	if cp1_area:
		cp1_area.body_entered.connect(func(body):
			if body is CharacterBody3D:
				player_checkpoints[body] = Vector3(0.0, 5.8, -56.0)
				player_checkpoint_reached.emit(body, 1)
				_flash_beacon(cp1_beacon, Color(0.2, 1.0, 0.5))
		)
	
	# 3. Checkpoint 2 Area
	var cp2_area = get_node_or_null("Checkpoint2Platform/CheckpointArea") as Area3D
	if cp2_area:
		cp2_area.body_entered.connect(func(body):
			if body is CharacterBody3D:
				player_checkpoints[body] = Vector3(0.0, 10.8, -96.0)
				player_checkpoint_reached.emit(body, 2)
				_flash_beacon(cp2_beacon, Color(0.3, 0.9, 1.0))
		)
	
	# 4. Finish Goal Area
	var finish_area = get_node_or_null("FinishPlatform/FinishGoalArea") as Area3D
	if finish_area:
		finish_area.body_entered.connect(func(body):
			if body is CharacterBody3D:
				player_finished_parkour.emit(body)
		)

func _on_void_recovery_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		var target_spawn = player_checkpoints.get(body, Vector3(0.0, 1.2, 0.0))
		# Reset velocities so player doesn't keep falling speed
		body.velocity = Vector3.ZERO
		body.global_position = target_spawn + Vector3(0, 0.5, 0)

func _flash_beacon(beacon: MeshInstance3D, _color: Color) -> void:
	if is_instance_valid(beacon):
		var tween = create_tween()
		tween.tween_property(beacon, "scale", Vector3(1.4, 1.4, 1.4), 0.2)
		tween.tween_property(beacon, "scale", Vector3(1.0, 1.0, 1.0), 0.3)

# ── Process Animations (Floating Platforms, Trophy & Beacons) ─────────────────
func _process(delta: float) -> void:
	time_passed += delta
	
	# Vertical floating oscillation for Pillar 1
	if is_instance_valid(moving_pillar_1):
		var y_offset = sin(time_passed * 2.2) * 1.2
		moving_pillar_1.position.y = moving_pillar_1_origin.y + y_offset
	
	# Horizontal sliding oscillation for Pillar 2
	if is_instance_valid(moving_pillar_2):
		var x_offset = sin(time_passed * 1.8) * 2.5
		moving_pillar_2.position.x = moving_pillar_2_origin.x + x_offset
	
	# Rotating Victory Trophy at Finish Line
	if is_instance_valid(finish_trophy):
		finish_trophy.rotate_y(1.2 * delta)
		finish_trophy.position.y = 16.5 + sin(time_passed * 2.0) * 0.25
	
	# Pulse glowing Start Beacon
	if is_instance_valid(start_beacon):
		start_beacon.rotate_y(0.8 * delta)

# ── Standard Map API Compatible with Arena3D ──────────────────────────────────
func get_tagger_spawn() -> Vector3:
	return chaser_spawns.pick_random()

func get_runner_spawn(index: int = 0) -> Vector3:
	if index < runner_spawns.size():
		return runner_spawns[index]
	return runner_spawns.pick_random()

func get_random_safe_spawn() -> Vector3:
	return Vector3(0.0, 1.2, 0.0)

func get_random_item_spawn() -> Vector3:
	return item_spawns.pick_random()

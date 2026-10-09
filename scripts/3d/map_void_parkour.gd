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
	Vector3(0.0, 15.5, -119.5),    # Hazard Ramp Center
	Vector3(0.0, 20.0, -147.0)     # Finish Platform
]

# Checkpoint tracker per player instance
var player_checkpoints: Dictionary = {}

@onready var finish_trophy: Node3D = get_node_or_null("FinishPlatform/VictoryTrophy")
@onready var start_beacon: MeshInstance3D = get_node_or_null("StartPlatform/StartBeacon")
@onready var cp1_beacon: MeshInstance3D = get_node_or_null("Checkpoint1Platform/BeaconRing")
@onready var cp2_beacon: MeshInstance3D = get_node_or_null("Checkpoint2Platform/BeaconRing")

# ── Rolling Hazard Balls Controller ──────────────────────────────────────────
const RAMP_TOP_POS := Vector3(0.0, 19.9, -139.0)
const RAMP_BOTTOM_POS := Vector3(0.0, 10.9, -99.5)

@onready var hazard_ball_1: Area3D = get_node_or_null("ParkourCourse/HazardBall1")
@onready var hazard_ball_2: Area3D = get_node_or_null("ParkourCourse/HazardBall2")
@onready var hazard_ball_3: Area3D = get_node_or_null("ParkourCourse/HazardBall3")

var hazard_balls: Array[Area3D] = []
var ball_progress: Array[float] = [0.0, 0.35, 0.70]
var ball_lanes: Array[float] = [-1.8, 1.8, 0.0]
var time_passed: float = 0.0

func _ready() -> void:
	hazard_balls = [hazard_ball_1, hazard_ball_2, hazard_ball_3]
	for ball in hazard_balls:
		if ball:
			ball.body_entered.connect(_on_hazard_ball_body_entered)
	
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

func _on_hazard_ball_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		# Player hit by rolling hazard ball -> returned to latest checkpoint
		var target_spawn = player_checkpoints.get(body, Vector3(0.0, 10.8, -96.0))
		body.velocity = Vector3.ZERO
		body.global_position = target_spawn + Vector3(0, 0.5, 0)

func _flash_beacon(beacon: MeshInstance3D, _color: Color) -> void:
	if is_instance_valid(beacon):
		var tween = create_tween()
		tween.tween_property(beacon, "scale", Vector3(1.4, 1.4, 1.4), 0.2)
		tween.tween_property(beacon, "scale", Vector3(1.0, 1.0, 1.0), 0.3)

# ── Process Animations (Rolling Hazard Balls, Trophy & Beacons) ───────────────
func _process(delta: float) -> void:
	time_passed += delta
	
	# Animate Rolling Hazard Balls down the ramp
	for i in range(hazard_balls.size()):
		var ball = hazard_balls[i]
		if is_instance_valid(ball):
			ball_progress[i] += delta * 0.28 # ~3.6s to roll down the 41m slope (~11.4 m/s)
			if ball_progress[i] >= 1.0:
				ball_progress[i] -= 1.0 # Disappears at bottom, respawns at top
				var available_lanes: Array[float] = [-2.0, 0.0, 2.0]
				ball_lanes[i] = available_lanes[(i + int(time_passed * 1.5)) % available_lanes.size()]
			
			var t = ball_progress[i]
			var current_pos = RAMP_TOP_POS.lerp(RAMP_BOTTOM_POS, t)
			current_pos.x = ball_lanes[i]
			ball.position = current_pos
			
			# Visual rolling rotation on X axis
			var sphere_mesh = ball.get_node_or_null("SphereMesh") as Node3D
			if sphere_mesh:
				sphere_mesh.rotate_x(12.0 * delta)
	
	# Rotating Victory Trophy at Finish Line
	if is_instance_valid(finish_trophy):
		finish_trophy.rotate_y(1.2 * delta)
		finish_trophy.position.y = 2.0 + sin(time_passed * 2.0) * 0.25
	
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

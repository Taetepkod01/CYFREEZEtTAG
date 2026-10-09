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

# Parkour mode has no item pickups
var item_spawns: Array[Vector3] = []

# Checkpoint tracker per player instance
var player_checkpoints: Dictionary = {}
var reached_checkpoints: Dictionary = {} # player -> highest checkpoint index
var finished_players: Array[CharacterBody3D] = []
var ball_hit_cooldown: Dictionary = {} # player -> timestamp

@onready var finish_trophy: Node3D = get_node_or_null("FinishPlatform/VictoryTrophy")
@onready var start_beacon: MeshInstance3D = get_node_or_null("StartPlatform/StartBeacon")
@onready var cp1_beacon: MeshInstance3D = get_node_or_null("Checkpoint1Platform/BeaconRing")
@onready var cp2_beacon: MeshInstance3D = get_node_or_null("Checkpoint2Platform/BeaconRing")
@onready var cp1_label: Label3D = get_node_or_null("Checkpoint1Platform/Checkpoint1Label")
@onready var cp2_label: Label3D = get_node_or_null("Checkpoint2Platform/Checkpoint2Label")
@onready var cp1_pillar: MeshInstance3D = get_node_or_null("Checkpoint1Platform/LightPillar1")
@onready var cp2_pillar: MeshInstance3D = get_node_or_null("Checkpoint2Platform/LightPillar2")

# ── Rolling Hazard Balls Controller ──────────────────────────────────────────
const RAMP_TOP_POS := Vector3(0.0, 19.9, -139.0)
const RAMP_BOTTOM_POS := Vector3(0.0, 10.9, -99.5)
const SKY_SPAWN_HEIGHT := 34.0
const FALL_DURATION := 0.7
const ROLL_DURATION := 3.5
const CYCLE_DURATION := 6.0 # 3 balls * 2.0s interval = 6.0s cycle

@onready var hazard_ball_1: Area3D = get_node_or_null("ParkourCourse/HazardBall1")
@onready var hazard_ball_2: Area3D = get_node_or_null("ParkourCourse/HazardBall2")
@onready var hazard_ball_3: Area3D = get_node_or_null("ParkourCourse/HazardBall3")

var hazard_balls: Array[Area3D] = []
var ball_timers: Array[float] = [0.0, -2.0, -4.0] # 2-second interval between spawns
var ball_lanes: Array[float] = [-2.0, 2.0, 0.0]
var time_passed: float = 0.0

const CP1_POS := Vector3(0.0, 5.8, -56.0)
const CP2_POS := Vector3(0.0, 10.8, -96.0)
const FINISH_POS := Vector3(0.0, 20.0, -147.0)

func _ready() -> void:
	hazard_balls = [hazard_ball_1, hazard_ball_2, hazard_ball_3]
	for ball in hazard_balls:
		if ball:
			ball.collision_layer = 4
			ball.collision_mask = 3
			ball.monitoring = true
			ball.monitorable = true
			if not ball.body_entered.is_connected(_on_hazard_ball_body_entered):
				ball.body_entered.connect(_on_hazard_ball_body_entered)
	
	_setup_recovery_and_checkpoint_areas()

# ── Dynamic Areas: Void Recovery & Checkpoints ────────────────────────────────
func _setup_recovery_and_checkpoint_areas() -> void:
	# 1. Fall Recovery Void Area
	var void_area = get_node_or_null("VoidRecoveryArea") as Area3D
	if void_area:
		void_area.collision_layer = 4
		void_area.collision_mask = 3
		void_area.monitoring = true
		if not void_area.body_entered.is_connected(_on_void_recovery_body_entered):
			void_area.body_entered.connect(_on_void_recovery_body_entered)
	
	# 2. Checkpoint 1 Area
	var cp1_area = get_node_or_null("Checkpoint1Platform/CheckpointArea") as Area3D
	if cp1_area:
		cp1_area.collision_layer = 4
		cp1_area.collision_mask = 3
		cp1_area.monitoring = true
		cp1_area.body_entered.connect(func(body):
			if body is CharacterBody3D:
				_activate_checkpoint(body, 1, CP1_POS)
		)
	
	# 3. Checkpoint 2 Area
	var cp2_area = get_node_or_null("Checkpoint2Platform/CheckpointArea") as Area3D
	if cp2_area:
		cp2_area.collision_layer = 4
		cp2_area.collision_mask = 3
		cp2_area.monitoring = true
		cp2_area.body_entered.connect(func(body):
			if body is CharacterBody3D:
				_activate_checkpoint(body, 2, CP2_POS)
		)
	
	# 4. Finish Goal Area
	var finish_area = get_node_or_null("FinishPlatform/FinishGoalArea") as Area3D
	if finish_area:
		finish_area.collision_layer = 4
		finish_area.collision_mask = 3
		finish_area.monitoring = true
		finish_area.body_entered.connect(func(body):
			if body is CharacterBody3D and not (body in finished_players):
				finished_players.append(body)
				player_finished_parkour.emit(body)
		)

func _activate_checkpoint(player: CharacterBody3D, idx: int, respawn_pos: Vector3) -> void:
	var current_idx = reached_checkpoints.get(player, 0)
	if idx > current_idx:
		reached_checkpoints[player] = idx
		player_checkpoints[player] = respawn_pos
		player_checkpoint_reached.emit(player, idx)
		
		if idx == 1:
			_flash_beacon(cp1_beacon, Color(0.1, 1.0, 0.45))
			if cp1_label:
				cp1_label.text = "✔ CHECKPOINT 1 SAVED"
				cp1_label.modulate = Color(0.1, 1.0, 0.45)
			if cp1_pillar:
				var tw = create_tween()
				tw.tween_property(cp1_pillar, "scale", Vector3(1.6, 1.0, 1.6), 0.25)
				tw.tween_property(cp1_pillar, "scale", Vector3(1.0, 1.0, 1.0), 0.35)
		elif idx == 2:
			_flash_beacon(cp2_beacon, Color(0.0, 0.85, 1.0))
			if cp2_label:
				cp2_label.text = "✔ CHECKPOINT 2 SAVED"
				cp2_label.modulate = Color(0.0, 0.85, 1.0)
			if cp2_pillar:
				var tw = create_tween()
				tw.tween_property(cp2_pillar, "scale", Vector3(1.6, 1.0, 1.6), 0.25)
				tw.tween_property(cp2_pillar, "scale", Vector3(1.0, 1.0, 1.0), 0.35)

func reset_race() -> void:
	finished_players.clear()
	reached_checkpoints.clear()
	player_checkpoints.clear()
	ball_hit_cooldown.clear()
	if cp1_label:
		cp1_label.text = "🚩 CHECKPOINT 1"
		cp1_label.modulate = Color(0.2, 1.0, 0.5)
	if cp2_label:
		cp2_label.text = "🚩 CHECKPOINT 2"
		cp2_label.modulate = Color(0.0, 0.85, 1.0)

func _on_void_recovery_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		_respawn_player_at_checkpoint(body as CharacterBody3D)

func _respawn_player_at_checkpoint(player: CharacterBody3D) -> void:
	player.velocity = Vector3.ZERO
	var target_spawn = player_checkpoints.get(player, Vector3(0.0, 1.2, 0.0))
	player.global_position = target_spawn + Vector3(0, 0.5, 0)

func _on_hazard_ball_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		_hit_player_with_ball(body as CharacterBody3D)

func _hit_player_with_ball(player: CharacterBody3D) -> void:
	var now = Time.get_ticks_msec() / 1000.0
	if now - ball_hit_cooldown.get(player, 0.0) < 0.8:
		return
	ball_hit_cooldown[player] = now
	
	player.velocity = Vector3.ZERO
	var target_spawn = player_checkpoints.get(player, CP2_POS)
	player.global_position = target_spawn + Vector3(0, 0.5, 0)
	
	var arena = get_parent()
	if arena and arena.has_method("add_game_log"):
		arena.add_game_log("[color=#ff5252]💥 %s was hit by a rolling boulder! Returned to Checkpoint 2![/color]" % player.player_name)

func _flash_beacon(beacon: MeshInstance3D, _color: Color) -> void:
	if is_instance_valid(beacon):
		var tween = create_tween()
		tween.tween_property(beacon, "scale", Vector3(1.4, 1.4, 1.4), 0.2)
		tween.tween_property(beacon, "scale", Vector3(1.0, 1.0, 1.0), 0.3)

func _get_all_players() -> Array[CharacterBody3D]:
	var result: Array[CharacterBody3D] = []
	var arena = get_parent()
	if arena:
		var players_container = arena.get_node_or_null("Players")
		if players_container:
			for child in players_container.get_children():
				if child is CharacterBody3D:
					result.append(child)
	return result

# ── Process Animations & Failsafe Proximity Checking ──────────────────────────
func _process(delta: float) -> void:
	time_passed += delta
	
	# Animate Rolling Hazard Balls dropping from sky and rolling down ramp (2s interval)
	for i in range(hazard_balls.size()):
		var ball = hazard_balls[i]
		if not is_instance_valid(ball):
			continue
		
		ball_timers[i] += delta
		var t = ball_timers[i]
		
		if t < 0.0:
			# Waiting for initial spawn delay
			ball.visible = false
			ball.monitoring = false
			ball.position = Vector3(0.0, -100.0, 0.0)
		elif t < FALL_DURATION:
			# Phase 1: Dropping rapidly from the sky onto the top of the ramp
			ball.visible = true
			ball.monitoring = true
			var fall_progress = t / FALL_DURATION
			var fall_y = lerp(SKY_SPAWN_HEIGHT, RAMP_TOP_POS.y, fall_progress * fall_progress)
			ball.position = Vector3(ball_lanes[i], fall_y, RAMP_TOP_POS.z)
			var sphere_mesh = ball.get_node_or_null("SphereMesh") as Node3D
			if sphere_mesh:
				sphere_mesh.rotate_y(3.0 * delta)
		elif t < (FALL_DURATION + ROLL_DURATION):
			# Phase 2: Rolling down the inclined ramp
			ball.visible = true
			ball.monitoring = true
			var roll_progress = (t - FALL_DURATION) / ROLL_DURATION
			var current_pos = RAMP_TOP_POS.lerp(RAMP_BOTTOM_POS, roll_progress)
			current_pos.x = ball_lanes[i]
			ball.position = current_pos
			
			var sphere_mesh = ball.get_node_or_null("SphereMesh") as Node3D
			if sphere_mesh:
				sphere_mesh.rotate_x(12.0 * delta)
		elif t < CYCLE_DURATION:
			# Phase 3: Reached bottom near Checkpoint 2 -> disappears until next cycle
			ball.visible = false
			ball.monitoring = false
			ball.position = Vector3(0.0, -100.0, 0.0)
		else:
			# Reset cycle (spawns from sky again 2s after previous ball)
			ball_timers[i] -= CYCLE_DURATION
			var lane_choices: Array[float] = [-2.2, 0.0, 2.2]
			ball_lanes[i] = lane_choices[(i + int(time_passed * 1.7)) % lane_choices.size()]
	
	# Rotating Victory Trophy at Finish Line
	if is_instance_valid(finish_trophy):
		finish_trophy.rotate_y(1.2 * delta)
		finish_trophy.position.y = 2.0 + sin(time_passed * 2.0) * 0.25
	
	# Pulse glowing Start Beacon
	if is_instance_valid(start_beacon):
		start_beacon.rotate_y(0.8 * delta)
	
	# ── Bulletproof Proximity Checks for Players ──────────────────────────────
	var players = _get_all_players()
	for p in players:
		if not is_instance_valid(p):
			continue
		
		var p_pos = p.global_position
		
		# Checkpoint 1 detection (Z = -56)
		if p_pos.distance_to(CP1_POS) < 4.2:
			_activate_checkpoint(p, 1, CP1_POS)
		
		# Checkpoint 2 detection (Z = -96)
		elif p_pos.distance_to(CP2_POS) < 3.8:
			_activate_checkpoint(p, 2, CP2_POS)
		
		# Finish Goal detection (Z = -147)
		elif p_pos.distance_to(FINISH_POS) < 5.2 and not (p in finished_players):
			finished_players.append(p)
			player_finished_parkour.emit(p)
		
		# Instant Abyss Fall Teleport (Y < -4.5)
		if p_pos.y < -4.5:
			_respawn_player_at_checkpoint(p)
		
		# Hazard Ball Proximity on the Ramp
		for ball in hazard_balls:
			if is_instance_valid(ball) and ball.visible and ball.monitoring:
				if ball.global_position.distance_to(p_pos) < 1.75:
					_hit_player_with_ball(p)
					break

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
	return Vector3(0.0, -100.0, 0.0)

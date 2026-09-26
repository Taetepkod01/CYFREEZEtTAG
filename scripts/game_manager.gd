extends Node2D

const TILE_SIZE: int = 32
const MAP_W: int = 40
const MAP_H: int = 30
const MATCH_DURATION: float = 180.0

@export var player_scene: PackedScene = preload("res://scenes/player.tscn")
@export var item_scene: PackedScene = preload("res://scenes/item.tscn")

var map_data: Array = []
var valid_spawns: Array[Vector2] = []
var time_left: float = MATCH_DURATION
var game_active: bool = false
var local_player_node: CharacterBody2D = null

# Item spawn timer
var item_spawn_timer: float = 5.0
var active_items: Array[Node2D] = []

# Node references
@onready var map_draw_node: Node2D = $MapDraw
@onready var walls_node: StaticBody2D = $Walls
@onready var players_node: Node2D = $Players
@onready var items_node: Node2D = $Items
@onready var traps_node: Node2D = $Traps

# UI references
@onready var hud: CanvasLayer = $HUD
@onready var timer_label: Label = $HUD/TopBar/TimerLabel
@onready var role_label: Label = $HUD/TopBar/RoleLabel
@onready var item_label: Label = $HUD/TopBar/ItemLabel
@onready var notification_label: Label = $HUD/NotificationLabel
@onready var game_over_panel: Panel = $HUD/GameOverPanel
@onready var winner_title: Label = $HUD/GameOverPanel/WinnerTitle
@onready var winner_sub: Label = $HUD/GameOverPanel/WinnerSub
@onready var return_button: Button = $HUD/GameOverPanel/ReturnButton
@onready var pause_menu: Panel = $HUD/PauseMenu

var camera: Camera2D = null

func _ready() -> void:
	game_over_panel.visible = false
	pause_menu.visible = false
	return_button.pressed.connect(_on_return_pressed)
	$HUD/TopBar/MenuButton.pressed.connect(_toggle_pause_menu)
	$HUD/PauseMenu/ResumeButton.pressed.connect(_toggle_pause_menu)
	$HUD/PauseMenu/QuitButton.pressed.connect(_on_return_pressed)
	
	_build_maze()
	_create_wall_colliders()
	_spawn_all_players()
	
	game_active = true

func _process(delta: float) -> void:
	if not game_active:
		return
	
	# Update match timer
	time_left -= delta
	if time_left < 0:
		time_left = 0
	
	var mins = int(time_left) / 60
	var secs = int(time_left) % 60
	timer_label.text = "⏱ %d:%02d" % [mins, secs]
	
	# Update local player HUD
	if local_player_node:
		var held = local_player_node.held_item
		if held.is_empty():
			item_label.text = "Item: None"
		else:
			item_label.text = "Item: [%s] Press [E]" % held.to_upper()
	
	# Item spawning
	item_spawn_timer -= delta
	if item_spawn_timer <= 0:
		item_spawn_timer = randf_range(8.0, 14.0)
		_spawn_random_item()
	
	# Check win condition
	_check_win_condition()

# ── Maze Generation (Exact match with Phaser / Colyseus version) ────────────
func _build_maze() -> void:
	map_data.clear()
	for r in range(MAP_H):
		var row: Array = []
		for c in range(MAP_W):
			row.append(0)
		map_data.append(row)
	
	# Border walls
	for c in range(MAP_W):
		map_data[0][c] = 1
		map_data[MAP_H - 1][c] = 1
	for r in range(MAP_H):
		map_data[r][0] = 1
		map_data[r][MAP_W - 1] = 1
	
	# 2x2 Obstacle blocks
	for r in range(3, MAP_H - 3, 4):
		for c in range(3, MAP_W - 3, 4):
			map_data[r][c] = 1
			map_data[r][c + 1] = 1
			map_data[r + 1][c] = 1
			map_data[r + 1][c + 1] = 1
	
	# Clear 5 Plazas (Center + 4 corners)
	_clear_plaza(10, 14, 10, 12) # Center
	_clear_plaza(2, 2, 7, 7)     # Top-Left
	_clear_plaza(2, 31, 7, 7)    # Top-Right
	_clear_plaza(21, 2, 7, 7)    # Bottom-Left
	_clear_plaza(21, 31, 7, 7)   # Bottom-Right
	
	# Collect valid spawns
	valid_spawns.clear()
	for r in range(1, MAP_H - 1):
		for c in range(1, MAP_W - 1):
			if map_data[r][c] == 0:
				valid_spawns.append(Vector2(c * TILE_SIZE + TILE_SIZE / 2.0, r * TILE_SIZE + TILE_SIZE / 2.0))

func _clear_plaza(start_r: int, start_c: int, num_r: int, num_c: int) -> void:
	for r in range(start_r, start_r + num_r):
		for c in range(start_c, start_c + num_c):
			if r > 0 and r < MAP_H - 1 and c > 0 and c < MAP_W - 1:
				map_data[r][c] = 0

func _create_wall_colliders() -> void:
	# Group walls into collision shapes
	for r in range(MAP_H):
		for c in range(MAP_W):
			if map_data[r][c] == 1:
				var shape = CollisionShape2D.new()
				var rect = RectangleShape2D.new()
				rect.size = Vector2(TILE_SIZE, TILE_SIZE)
				shape.shape = rect
				shape.position = Vector2(c * TILE_SIZE + TILE_SIZE / 2.0, r * TILE_SIZE + TILE_SIZE / 2.0)
				walls_node.add_child(shape)

# ── Spawning ────────────────────────────────────────────────────────────────
func _spawn_all_players() -> void:
	var spawns_copy = valid_spawns.duplicate()
	spawns_copy.shuffle()
	
	var spawn_index = 0
	for p_id in Network.players:
		var p_info = Network.players[p_id]
		var player_instance = player_scene.instantiate()
		var spawn_pos = spawns_copy[spawn_index % spawns_copy.size()]
		spawn_index += 1
		
		player_instance.position = spawn_pos
		players_node.add_child(player_instance)
		player_instance.setup(p_id, p_info["name"], p_info["role"], p_info["is_bot"])
		
		# If this is the local player, attach camera and set role HUD
		if player_instance.is_local_player():
			local_player_node = player_instance
			_setup_camera(player_instance)
			
			if p_info["role"] == "chaser":
				role_label.text = "Role: 🔥 CHASER"
				role_label.modulate = Color(1.0, 0.4, 0.4)
				show_notification("YOU ARE THE CHASER! Tag and freeze all runners!")
			else:
				role_label.text = "Role: 🏃 RUNNER"
				role_label.modulate = Color(1.0, 0.9, 0.4)
				show_notification("YOU ARE A RUNNER! Survive and unfreeze teammates!")

func _setup_camera(target: Node2D) -> void:
	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = MAP_W * TILE_SIZE
	camera.limit_bottom = MAP_H * TILE_SIZE
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	target.add_child(camera)

func _spawn_random_item() -> void:
	if valid_spawns.is_empty():
		return
	
	# Limit active items
	var current_items = items_node.get_children()
	if current_items.size() >= 5:
		return
	
	var item_types = ["speed", "ghost", "shield", "heater", "banana", "blackhole"]
	var selected_type = item_types.pick_random()
	var spawn_pos = valid_spawns.pick_random()
	
	var item_instance = item_scene.instantiate()
	item_instance.position = spawn_pos
	items_node.add_child(item_instance)
	item_instance.setup(selected_type)

func spawn_banana_trap(pos: Vector2) -> void:
	var trap = Area2D.new()
	trap.collision_layer = 8
	trap.collision_mask = 2
	var col = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 16.0
	col.shape = circle
	trap.add_child(col)
	
	var lbl = Label.new()
	lbl.text = "🍌"
	lbl.offset_left = -12
	lbl.offset_top = -12
	trap.add_child(lbl)
	
	trap.position = pos
	traps_node.add_child(trap)
	
	trap.body_entered.connect(func(body):
		if body is CharacterBody2D and body.has_method("stun"):
			body.stun(2.5)
			show_notification("🍌 " + body.player_name + " slipped on a banana peel!")
			trap.queue_free()
	)

func spawn_vortex(pos: Vector2) -> void:
	var vortex = Node2D.new()
	vortex.position = pos
	traps_node.add_child(vortex)
	show_notification("🌀 Black Hole activated!")
	
	var tween = create_tween()
	var time := 0.0
	var timer = get_tree().create_timer(4.5)
	
	var pull_func = func():
		for p in players_node.get_children():
			if p is CharacterBody2D and not p.is_frozen:
				var dist = vortex.global_position.distance_to(p.global_position)
				if dist < 240.0:
					var pull_dir = (vortex.global_position - p.global_position).normalized()
					p.global_position += pull_dir * 120.0 * get_process_delta_time()
	
	get_tree().process_frame.connect(pull_func)
	timer.timeout.connect(func():
		get_tree().process_frame.disconnect(pull_func)
		vortex.queue_free()
	)

# ── Notifications & Events ──────────────────────────────────────────────────
func on_player_tagged(chaser_name: String, runner_name: String) -> void:
	show_notification("❄ " + runner_name + " was FROZEN by " + chaser_name + "!")

func on_player_unfrozen(rescuer_name: String, runner_name: String) -> void:
	show_notification("🔥 " + rescuer_name + " THAWED " + runner_name + "!")

func on_item_collected(player_name: String, item_type: String) -> void:
	show_notification("⚡ " + player_name + " picked up " + item_type.to_upper() + "!")

func show_notification(msg: String) -> void:
	notification_label.text = msg
	notification_label.modulate.a = 1.0
	var tween = create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(notification_label, "modulate:a", 0.0, 0.8)

# ── Win Conditions ──────────────────────────────────────────────────────────
func _check_win_condition() -> void:
	var unfrozen_runners = 0
	var total_runners = 0
	
	for p in players_node.get_children():
		if p is CharacterBody2D:
			if p.role == "runner":
				total_runners += 1
				if not p.is_frozen:
					unfrozen_runners += 1
	
	# 1. Chaser catches all runners
	if total_runners > 0 and unfrozen_runners == 0:
		_end_game("CHASER")
	# 2. Time expired and runners survived
	elif time_left <= 0:
		_end_game("RUNNERS")

func _end_game(winner: String) -> void:
	game_active = false
	game_over_panel.visible = true
	
	if winner == "CHASER":
		winner_title.text = "🔥 CHASER WINS! 🔥"
		winner_title.modulate = Color(1.0, 0.4, 0.4)
		winner_sub.text = "All runners have been frozen!"
	else:
		winner_title.text = "❄ RUNNERS WIN! ❄"
		winner_title.modulate = Color(0.4, 0.9, 1.0)
		winner_sub.text = "Runners survived the full 3 minutes!"

func _on_return_pressed() -> void:
	Network.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _toggle_pause_menu() -> void:
	pause_menu.visible = not pause_menu.visible

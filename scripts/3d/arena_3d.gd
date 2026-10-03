extends Node3D

@export var player_3d_scene: PackedScene = preload("res://scenes/3d/player_3d.tscn")
@export var item_3d_scene: PackedScene = preload("res://scenes/3d/item_3d.tscn")

# Match Settings
var round_time: float = 165.0 # 02:45
var current_round: int = 1
var max_rounds: int = 3
var is_game_active: bool = true

# Scores across rounds
var runners_score: int = 0
var taggers_score: int = 0

# Node references
@onready var players_container: Node3D = $Players
@onready var items_container: Node3D = $Items
@onready var traps_container: Node3D = $Traps
@onready var env_container: Node3D = $Environment
@onready var hud: CanvasLayer = $HUD

var current_map_node: Node3D = null

# HUD elements
@onready var runners_count_lbl: Label = $HUD/TopBar/RunnersBox/Count
@onready var taggers_count_lbl: Label = $HUD/TopBar/TaggersBox/Count
@onready var timer_lbl: Label = $HUD/TopBar/TimerBox/TimerLabel
@onready var round_lbl: Label = $HUD/TopBar/TimerBox/RoundLabel
@onready var status_container: VBoxContainer = $HUD/PlayerStatusPanel/Scroll/VBox
@onready var status_title_lbl: Label = $HUD/PlayerStatusPanel/Title
@onready var game_log_lbl: RichTextLabel = $HUD/GameLogPanel/LogContent
@onready var minimap: Control = $HUD/MinimapPanel/Minimap
@onready var hp_bar: ProgressBar = $HUD/BottomHPPanel/ProgressBar
@onready var hp_lbl: Label = $HUD/BottomHPPanel/HPHeader/HPLabel
@onready var item_btn: Button = $HUD/BottomInventoryPanel/ItemButton
@onready var item_name_lbl: Label = $HUD/BottomInventoryPanel/ItemButton/ItemName
@onready var role_btn: Button = $HUD/PracticeRoleBtn
@onready var player_tag_dot: Label = $HUD/BottomPlayerTag/HBox/Dot
@onready var player_tag_name: Label = $HUD/BottomPlayerTag/HBox/Name
@onready var player_tag_role: Label = $HUD/BottomPlayerTag/HBox/RoleBadge

const TEX_NEXT_ROUND = preload("res://assets/ui/buttons/btn_next_round.png")
const TEX_PLAY_AGAIN = preload("res://assets/ui/buttons/btn_play_again.png")

const TEX_ROLE_RANDOM = preload("res://assets/ui/buttons/btn_role_random.png")
const TEX_ROLE_RANDOM_SEL = preload("res://assets/ui/buttons/btn_role_random_sel.png")
const TEX_ROLE_TAGGER = preload("res://assets/ui/buttons/btn_role_tagger.png")
const TEX_ROLE_TAGGER_SEL = preload("res://assets/ui/buttons/btn_role_tagger_sel.png")
const TEX_ROLE_RUNNER = preload("res://assets/ui/buttons/btn_role_runner.png")
const TEX_ROLE_RUNNER_SEL = preload("res://assets/ui/buttons/btn_role_runner_sel.png")

# Match Summary Panel (5.png)
@onready var game_over_panel: Panel = $HUD/GameOverPanel
@onready var game_over_title: Label = $HUD/GameOverPanel/Title
@onready var score_lbl: Label = $HUD/GameOverPanel/ScoreLabel
@onready var mvp_lbl: Label = $HUD/GameOverPanel/MVPLabel
@onready var next_round_btn: Button = $HUD/GameOverPanel/Buttons/NextButton
@onready var lobby_btn: Button = $HUD/GameOverPanel/Buttons/LobbyButton
@onready var exit_menu_btn: Button = $HUD/GameOverPanel/Buttons/ExitButton

# Menu / Instructions Modal (6.png)
@onready var menu_btn: Button = $HUD/MenuButton
@onready var menu_modal: Panel = $HUD/MenuModal
@onready var resume_btn: Button = $HUD/MenuModal/Buttons/ResumeBtn
@onready var leave_btn: TextureButton = $HUD/MenuModal/Buttons/LeaveBtn

# Practice Role Modal (4.png)
@onready var practice_role_modal: Panel = $HUD/PracticeRoleModal
@onready var opt_random: TextureButton = $HUD/PracticeRoleModal/RoleVBox/OptRandom
@onready var opt_tagger: TextureButton = $HUD/PracticeRoleModal/RoleVBox/OptTagger
@onready var opt_runner: TextureButton = $HUD/PracticeRoleModal/RoleVBox/OptRunner
@onready var start_role_btn: TextureButton = $HUD/PracticeRoleModal/StartBtn
@onready var cancel_role_btn: TextureButton = $HUD/PracticeRoleModal/CancelBtn

var player_nodes: Array[CharacterBody3D] = []
var local_player: CharacterBody3D = null
var item_spawn_timer: float = 4.0

# Practice Mode Role ("random", "tagger", or "runner")
var practice_role: String = "random"

func _ready() -> void:
	game_over_panel.visible = false
	menu_modal.visible = false
	practice_role_modal.visible = false
	
	next_round_btn.pressed.connect(_on_next_round_pressed)
	lobby_btn.pressed.connect(_on_lobby_pressed)
	exit_menu_btn.pressed.connect(_on_exit_to_menu_pressed)
	
	menu_btn.pressed.connect(_toggle_menu_modal)
	resume_btn.pressed.connect(func(): _set_menu_modal_visible(false))
	leave_btn.pressed.connect(_on_exit_to_menu_pressed)
	
	item_btn.pressed.connect(_on_item_button_pressed)
	
	if Network and Network.is_online_game():
		# Online match
		role_btn.visible = false
		current_round = Network.current_round
		max_rounds = Network.max_rounds
		_connect_network_signals()
	else:
		# AI practice mode
		role_btn.visible = true
		lobby_btn.visible = false
		if Network and "selected_practice_role" in Network:
			practice_role = Network.selected_practice_role
		_update_role_button_ui()
		role_btn.pressed.connect(_toggle_practice_role_modal)
		opt_random.pressed.connect(func(): _set_pending_role("random"))
		opt_tagger.pressed.connect(func(): _set_pending_role("tagger"))
		opt_runner.pressed.connect(func(): _set_pending_role("runner"))
		start_role_btn.pressed.connect(func(): _select_practice_role(practice_role))
		cancel_role_btn.pressed.connect(func(): _toggle_practice_role_modal())
	
	# Load 3D Space Station Map
	_load_arena_map()
	
	# Connect Minimap
	if minimap and minimap.has_method("setup"):
		minimap.setup(self)
	
	_spawn_match_players()
	_update_hud()
	_update_item_slot("")
	
	if not Network or not Network.is_online_game():
		for i in range(4):
			_spawn_random_item()
	
	add_game_log("[color=#ffe066]Match started![/color] Round %d / %d" % [current_round, max_rounds])

func _load_arena_map() -> void:
	if not env_container:
		env_container = get_node_or_null("Environment")
	if not env_container:
		return
	
	var chosen_map: String = "SPACE STATION"
	if Network and "selected_map" in Network and not str(Network.selected_map).strip_edges().is_empty():
		chosen_map = str(Network.selected_map).strip_edges()
	elif Network and "current_match_map" in Network and not str(Network.current_match_map).strip_edges().is_empty():
		chosen_map = str(Network.current_match_map).strip_edges()
	
	print("[Arena3D] Loading map: ", chosen_map)
	
	var upper = chosen_map.to_upper()
	var map_scene_path: String = ""
	var map_display_name: String = ""
	
	if upper.contains("SPACE"):
		map_scene_path = "res://scenes/3d/maps/map_space_station.tscn"
		map_display_name = "SPACE STATION (Alpha Sector)"
	elif upper.contains("SNOW") or upper.contains("TOWN") or upper.contains("หิมะ"):
		map_scene_path = "res://scenes/3d/maps/map_snow_town.tscn"
		map_display_name = "SNOW TOWN"
	elif upper.contains("LABYRINTH") or upper.contains("MAZE") or upper.contains("เขาวงกต"):
		map_scene_path = "res://scenes/3d/maps/map_labyrinth.tscn"
		map_display_name = "LABYRINTH"
	else:
		map_scene_path = "res://scenes/3d/maps/map_space_station.tscn"
		map_display_name = chosen_map
	
	if not map_scene_path.is_empty():
		var map_scene = load(map_scene_path)
		if map_scene:
			for child in env_container.get_children():
				env_container.remove_child(child)
				child.queue_free()
			current_map_node = map_scene.instantiate()
			env_container.add_child(current_map_node)
			
			# Apply map's environment to root WorldEnvironment
			var root_world_env = get_node_or_null("WorldEnvironment") as WorldEnvironment
			var map_world_env = current_map_node.get_node_or_null("WorldEnvironment") as WorldEnvironment
			if root_world_env and map_world_env and map_world_env.environment:
				root_world_env.environment = map_world_env.environment
				map_world_env.queue_free()
				
			var root_light = get_node_or_null("DirectionalLight3D") as DirectionalLight3D
			var map_light = current_map_node.get_node_or_null("SpaceSunLight") as DirectionalLight3D
			if not map_light:
				map_light = current_map_node.get_node_or_null("SunLight") as DirectionalLight3D
			if root_light and map_light:
				root_light.light_color = map_light.light_color
				root_light.light_energy = map_light.light_energy
				root_light.transform = map_light.transform
				map_light.queue_free()
				
			add_game_log("[color=#4fc3f7]Map: %s[/color]" % map_display_name)
			return
		else:
			push_error("[Arena3D] Failed to load %s!" % map_scene_path)
	
	add_game_log("[color=#4fc3f7]Map: %s[/color]" % chosen_map.to_upper())

func _connect_network_signals() -> void:
	if not Network:
		return
	if not Network.player_moved.is_connected(_on_net_player_moved):
		Network.player_moved.connect(_on_net_player_moved)
	if not Network.player_tagged.is_connected(_on_net_player_tagged):
		Network.player_tagged.connect(_on_net_player_tagged)
	if not Network.player_rescued.is_connected(_on_net_player_rescued):
		Network.player_rescued.connect(_on_net_player_rescued)
	if not Network.player_rescuing.is_connected(_on_net_player_rescuing):
		Network.player_rescuing.connect(_on_net_player_rescuing)
	if not Network.item_spawned.is_connected(_on_net_item_spawned):
		Network.item_spawned.connect(_on_net_item_spawned)
	if not Network.item_picked.is_connected(_on_net_item_picked):
		Network.item_picked.connect(_on_net_item_picked)
	if not Network.item_used.is_connected(_on_net_item_used):
		Network.item_used.connect(_on_net_item_used)
	if not Network.banana_placed.is_connected(_on_net_banana_placed):
		Network.banana_placed.connect(_on_net_banana_placed)
	if not Network.player_damaged.is_connected(_on_net_player_damaged):
		Network.player_damaged.connect(_on_net_player_damaged)
	if not Network.vortex_spawned.is_connected(spawn_vortex):
		Network.vortex_spawned.connect(spawn_vortex)
	if not Network.time_sync.is_connected(_on_net_time_sync):
		Network.time_sync.connect(_on_net_time_sync)
	if not Network.round_ended.is_connected(_on_net_round_ended):
		Network.round_ended.connect(_on_net_round_ended)
	if not Network.round_started.is_connected(_on_net_round_started):
		Network.round_started.connect(_on_net_round_started)
	if not Network.returned_to_lobby.is_connected(_on_net_returned_to_lobby):
		Network.returned_to_lobby.connect(_on_net_returned_to_lobby)
	if not Network.chat_received.is_connected(func(msg): add_game_log(msg)):
		Network.chat_received.connect(func(msg): add_game_log(msg))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_toggle_menu_modal()

func _process(delta: float) -> void:
	if not is_game_active:
		return
	
	round_time -= delta
	if round_time <= 0.0:
		round_time = 0.0
		if not Network or not Network.is_online_game():
			_end_round("RUNNERS")
	
	var mins = int(round_time) / 60
	var secs = int(round_time) % 60
	timer_lbl.text = "%02d:%02d" % [mins, secs]
	
	# Item spawn cycle for offline mode
	if not Network or not Network.is_online_game():
		item_spawn_timer -= delta
		if item_spawn_timer <= 0.0:
			item_spawn_timer = randf_range(8.0, 14.0)
			_spawn_random_item()
	
	_update_hud()

# -- Modal Controls & Role Selection -----------------------------------------
func _release_movement_keys() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down", "jump"]:
		Input.action_release(action)
	if local_player:
		local_player.velocity.x = 0.0
		local_player.velocity.z = 0.0

func _toggle_menu_modal() -> void:
	_set_menu_modal_visible(not menu_modal.visible)

func _set_menu_modal_visible(v: bool) -> void:
	_release_movement_keys()
	menu_modal.visible = v
	if v:
		practice_role_modal.visible = false
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		if is_game_active and not game_over_panel.visible and not practice_role_modal.visible:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _toggle_practice_role_modal() -> void:
	_release_movement_keys()
	practice_role_modal.visible = not practice_role_modal.visible
	if practice_role_modal.visible:
		menu_modal.visible = false
		_update_radio_ui()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		if is_game_active and not game_over_panel.visible and not menu_modal.visible:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _set_pending_role(role_name: String) -> void:
	practice_role = role_name
	_update_radio_ui()

func _update_radio_ui() -> void:
	if not opt_random or not opt_tagger or not opt_runner:
		return
	opt_random.texture_normal = TEX_ROLE_RANDOM_SEL if practice_role == "random" else TEX_ROLE_RANDOM
	opt_tagger.texture_normal = TEX_ROLE_TAGGER_SEL if practice_role == "tagger" else TEX_ROLE_TAGGER
	opt_runner.texture_normal = TEX_ROLE_RUNNER_SEL if practice_role == "runner" else TEX_ROLE_RUNNER

func _select_practice_role(role_name: String) -> void:
	practice_role = role_name
	if Network:
		Network.selected_practice_role = practice_role
	
	_update_role_button_ui()
	practice_role_modal.visible = false
	add_game_log("[color=#ffe066]Role selected: %s! Starting round...[/color]" % practice_role.to_upper())
	
	round_time = 165.0
	is_game_active = true
	game_over_panel.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_spawn_match_players()

func _update_role_button_ui() -> void:
	if not role_btn:
		return
	match practice_role:
		"tagger":
			role_btn.text = "ROLE: TAGGER"
			role_btn.modulate = Color(1.0, 0.45, 0.45)
		"runner":
			role_btn.text = "ROLE: RUNNER"
			role_btn.modulate = Color(0.45, 1.0, 0.45)
		"random", _:
			role_btn.text = "ROLE: RANDOM"
			role_btn.modulate = Color(1.0, 0.9, 0.4)

# -- Spawning Players & Items ------------------------------------------------
func _spawn_match_players() -> void:
	for child in players_container.get_children():
		child.queue_free()
	player_nodes.clear()
	
	if Network and Network.is_online_game():
		_spawn_online_players()
		return
	
	# Tactical Map Spawns
	var chaser_spawn_pos = Vector3(0, 0.5, -18)
	var runner_spawn_positions = [
		Vector3(0, 0.5, 18),
		Vector3(-18, 0.5, 0),
		Vector3(-15, 0.5, -15),
		Vector3(15, 0.5, 15)
	]
	if current_map_node and current_map_node.has_method("get_tagger_spawn"):
		chaser_spawn_pos = current_map_node.get_tagger_spawn()
	if current_map_node and current_map_node.has_method("get_runner_spawn"):
		runner_spawn_positions = [
			current_map_node.get_runner_spawn(0),
			current_map_node.get_runner_spawn(1),
			current_map_node.get_runner_spawn(2),
			current_map_node.get_runner_spawn(3)
		]
	
	var p1_is_tagger: bool = false
	var bot_tagger_idx: int = -1
	
	match practice_role:
		"tagger":
			p1_is_tagger = true
			bot_tagger_idx = -1
		"runner":
			p1_is_tagger = false
			bot_tagger_idx = randi() % 3
		"random", _:
			var pick = randi() % 4
			if pick == 0:
				p1_is_tagger = true
				bot_tagger_idx = -1
			else:
				p1_is_tagger = false
				bot_tagger_idx = pick - 1
	
	# Player 1 (You)
	var p1 = player_3d_scene.instantiate()
	p1.player_name = "Player 1 (You)"
	p1.role = "tagger" if p1_is_tagger else "runner"
	p1.is_bot = false
	p1.position = chaser_spawn_pos if p1_is_tagger else runner_spawn_positions[0]
	players_container.add_child(p1)
	player_nodes.append(p1)
	local_player = p1
	
	p1.tagged.connect(_on_player_tagged)
	p1.rescued.connect(_on_player_rescued)
	p1.item_used.connect(_on_player_item_used)
	p1.item_picked_up.connect(_on_player_item_picked_up)
	p1.item_changed.connect(_update_item_slot)
	p1.player_damaged.connect(func(target, amt):
		add_game_log(">> [color=#ff9800]%s tackled %s! (-%d HP)[/color]" % [p1.player_name, target.player_name, amt])
		_update_hud()
		if target.hp <= 0 and target.role == "tagger":
			add_game_log("[color=#69f0ae]Tagger defeated! Runners Win![/color]")
			_end_round("RUNNERS")
	)
	
	# 3 Bots
	var bot_names = ["Player 2 (Bot)", "Player 3 (Bot)", "Player 4 (Bot)"]
	var runner_cursor = 1 if not p1_is_tagger else 0
	for i in range(3):
		var bot = player_3d_scene.instantiate()
		bot.player_name = bot_names[i]
		bot.role = "tagger" if (i == bot_tagger_idx) else "runner"
		bot.is_bot = true
		if i == bot_tagger_idx:
			bot.position = chaser_spawn_pos
		else:
			bot.position = runner_spawn_positions[runner_cursor % runner_spawn_positions.size()]
			runner_cursor += 1
		players_container.add_child(bot)
		player_nodes.append(bot)
		
		bot.tagged.connect(_on_player_tagged)
		bot.rescued.connect(_on_player_rescued)
		bot.item_used.connect(func(item): add_game_log("%s used [color=#ffe066]%s[/color]!" % [bot.player_name, item]))
		bot.player_damaged.connect(func(target, amt):
			add_game_log(">> [color=#ff9800]%s tackled %s! (-%d HP)[/color]" % [bot.player_name, target.player_name, amt])
			_update_hud()
			if target.hp <= 0 and target.role == "tagger":
				add_game_log("[color=#69f0ae]Tagger defeated! Runners Win![/color]")
				_end_round("RUNNERS")
		)
	
	_update_hud()

func _spawn_online_players() -> void:
	var online_list = Network.current_match_players
	for p_data in online_list:
		var p_id = str(p_data.get("id", ""))
		var is_me = (p_id == Network.my_peer_id)
		
		var p_node = player_3d_scene.instantiate()
		p_node.network_id = p_id
		p_node.role = str(p_data.get("role", "runner"))
		p_node.player_name = str(p_data.get("name", "Player")) + (" (You)" if is_me else "")
		p_node.is_bot = false
		p_node.is_remote = not is_me
		p_node.position = Vector3(float(p_data.get("x", 0)), float(p_data.get("y", 0.5)), float(p_data.get("z", 0)))
		
		players_container.add_child(p_node)
		player_nodes.append(p_node)
		
		if is_me:
			local_player = p_node
			p_node.item_changed.connect(_update_item_slot)
			p_node.item_picked_up.connect(_on_player_item_picked_up)
			p_node.item_used.connect(_on_player_item_used)
	
	# Spawn initial server items
	for child in items_container.get_children():
		child.queue_free()
	for it in Network.current_match_items:
		var item = item_3d_scene.instantiate()
		item.position = Vector3(float(it.get("x", 0)), float(it.get("y", 0.6)), float(it.get("z", 0)))
		items_container.add_child(item)
		item.setup(str(it.get("type", "speed")), str(it.get("id", "")))

func _spawn_random_item() -> void:
	if items_container.get_child_count() >= 6:
		return
	
	var item_types = ["speed", "shield", "heater", "banana", "vortex", "tackle"]
	var selected = item_types.pick_random()
	
	var item = item_3d_scene.instantiate()
	if current_map_node and current_map_node.has_method("get_random_item_spawn"):
		item.position = current_map_node.get_random_item_spawn() + Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2))
	else:
		item.position = Vector3(randf_range(-18, 18), 0.6, randf_range(-18, 18))
	items_container.add_child(item)
	item.setup(selected)

func spawn_banana_trap(pos: Vector3, placer = null, placer_id: String = "") -> void:
	var trap = Area3D.new()
	trap.collision_layer = 8
	trap.collision_mask = 2
	
	var col = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 1.1
	col.shape = sphere
	col.position.y = 0.25
	trap.add_child(col)
	
	# 3D Banana Model from Gorilla Tag (res://scenes/3d/banana_peel.tscn)
	var banana_scene = preload("res://scenes/3d/banana_peel.tscn")
	var banana_visuals = banana_scene.instantiate()
	banana_visuals.name = "BananaModel"
	trap.add_child(banana_visuals)
	
	# Floating 3D Label
	var lbl = Label3D.new()
	lbl.text = "BANANA"
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 20
	lbl.modulate = Color(1.0, 0.9, 0.2)
	lbl.position = Vector3(0, 0.7, 0)
	trap.add_child(lbl)
	
	trap.position = Vector3(pos.x, 0.05, pos.z)
	traps_container.add_child(trap)
	
	# Immunity for placer:
	var placer_obj = placer
	var p_id = placer_id
	if placer is CharacterBody3D and "network_id" in placer and not placer.network_id.is_empty():
		p_id = placer.network_id
	
	trap.body_entered.connect(func(body):
		if not is_instance_valid(trap) or trap.is_queued_for_deletion():
			return
		if body is CharacterBody3D and not body.is_frozen:
			# Placer is completely immune to their own banana!
			if placer_obj != null and body == placer_obj:
				return
			if not p_id.is_empty() and "network_id" in body and body.network_id == p_id:
				return
			
			if body.has_method("slip_on_banana"):
				body.slip_on_banana()
			else:
				body.freeze()
			add_game_log("[color=#ffe066]%s[/color] slipped on a banana peel! (Dizzy 2.5s)" % body.player_name)
			trap.queue_free()
	)

func spawn_vortex(pos: Vector3) -> void:
	add_game_log("[color=#b388ff]Black Hole Vortex activated![/color]")
	var timer = get_tree().create_timer(4.0)
	var pull_func = func():
		for p in player_nodes:
			if not p.is_frozen:
				var dist = pos.distance_to(p.global_position)
				if dist < 14.0:
					var dir = (pos - p.global_position).normalized()
					p.global_position += dir * 8.0 * get_process_delta_time()
	
	get_tree().process_frame.connect(pull_func)
	timer.timeout.connect(func():
		get_tree().process_frame.disconnect(pull_func)
	)

# -- Network Event Handlers --------------------------------------------------
func _on_net_player_moved(id: String, pos: Vector3, rot_y: float) -> void:
	for p in player_nodes:
		if p.network_id == id and p.is_remote:
			p.update_remote_transform(pos, rot_y)
			break

func _on_net_player_tagged(_tagger_id: String, tagger_name: String, victim_id: String, victim_name: String) -> void:
	for p in player_nodes:
		if p.network_id == victim_id:
			p.freeze()
			break
	add_game_log("[color=#ff4c4c]%s[/color] tagged [color=#4fc3f7]%s[/color]" % [tagger_name, victim_name])
	_update_hud()

func _on_net_player_rescued(_rescuer_id: String, rescuer_name: String, victim_id: String, victim_name: String) -> void:
	for p in player_nodes:
		if p.network_id == victim_id:
			p.unfreeze()
			break
	add_game_log("[color=#69f0ae]%s[/color] rescued [color=#4fc3f7]%s[/color]!" % [rescuer_name, victim_name])
	_update_hud()

func _on_net_player_rescuing(player_id: String, is_rescuing: bool) -> void:
	for p in player_nodes:
		if p.network_id == player_id and p.is_remote:
			p.is_rescuing = is_rescuing
			p._update_role_visuals()
			break

func _on_net_item_spawned(id: String, type: String, pos: Vector3) -> void:
	var item = item_3d_scene.instantiate()
	item.position = pos
	items_container.add_child(item)
	item.setup(type, id)

func _on_net_item_picked(player_id: String, player_name: String, item_id: String, item_type: String) -> void:
	for child in items_container.get_children():
		if "item_id" in child and child.item_id == item_id:
			child.queue_free()
			break
	if local_player and local_player.network_id != player_id:
		add_game_log("%s picked up [color=#ffe066]%s[/color]" % [player_name, item_type.to_upper()])

func _on_net_item_used(player_id: String, player_name: String, type: String) -> void:
	if local_player and local_player.network_id != player_id:
		add_game_log("%s used [color=#ffe066]%s[/color]!" % [player_name, type.to_upper()])

func _on_net_banana_placed(pos: Vector3, placer_id: String = "") -> void:
	spawn_banana_trap(pos, null, placer_id)

func _on_net_player_damaged(data: Dictionary) -> void:
	var target_id = str(data.get("targetId", ""))
	var amt = int(data.get("amount", 20))
	var attacker_name = str(data.get("attackerName", "Runner"))
	var target_name = str(data.get("targetName", "Tagger"))
	for p in player_nodes:
		if p.network_id == target_id:
			p.take_damage(amt)
			break
	add_game_log(">> [color=#ff9800]%s tackled %s! (-%d HP)[/color]" % [attacker_name, target_name, amt])
	_update_hud()

func _on_net_time_sync(time_left: int) -> void:
	round_time = float(time_left)

func _on_net_round_ended(data: Dictionary) -> void:
	var winner = str(data.get("winner", "RUNNERS"))
	runners_score = int(data.get("runnersScore", runners_score))
	taggers_score = int(data.get("taggersScore", taggers_score))
	current_round = int(data.get("currentRound", current_round))
	max_rounds = int(data.get("maxRounds", max_rounds))
	var is_match_over = bool(data.get("isMatchOver", false))
	var mvp = data.get("mvp")
	
	is_game_active = false
	game_over_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	var reason = str(data.get("reason", ""))
	if winner == "TAGGERS":
		game_over_title.text = "TAGGERS WIN ROUND!"
		game_over_title.modulate = Color(1.0, 0.4, 0.4)
	else:
		if reason == "All Taggers Disconnected":
			game_over_title.text = "TAGGER LEFT! RUNNERS WIN!"
		else:
			game_over_title.text = "RUNNERS WIN ROUND!"
		game_over_title.modulate = Color(0.4, 0.95, 1.0)
	
	if not reason.is_empty():
		add_game_log("[color=#ffe066]Round Ended: %s[/color]" % reason)
	
	score_lbl.text = "SCORE: Runners %d  -  Taggers %d" % [runners_score, taggers_score]
	
	if mvp and typeof(mvp) == TYPE_DICTIONARY:
		mvp_lbl.text = "MVP: %s (%d Tags / %d Rescues)" % [mvp.get("name", "Player"), mvp.get("freezeCount", 0), mvp.get("rescueCount", 0)]
	else:
		mvp_lbl.text = "MVP: Match Complete"
	
	if Network.is_host:
		next_round_btn.visible = true
		next_round_btn.text = "PLAY AGAIN" if is_match_over else "NEXT ROUND (%d)" % (current_round + 1)
		lobby_btn.visible = true
	else:
		next_round_btn.visible = false
		lobby_btn.visible = true

# -- Events & Log (Practice / Local) -----------------------------------------
func _on_player_tagged(tagger: CharacterBody3D, victim: CharacterBody3D) -> void:
	add_game_log("[color=#ff4c4c]%s[/color] tagged [color=#4fc3f7]%s[/color]" % [tagger.player_name, victim.player_name])
	_update_hud()
	
	var unfrozen_runners = 0
	for p in player_nodes:
		if p.role == "runner" and not p.is_frozen:
			unfrozen_runners += 1
	
	if unfrozen_runners == 0:
		_end_round("TAGGERS")

func _on_player_rescued(rescuer: CharacterBody3D, victim: CharacterBody3D) -> void:
	add_game_log("[color=#69f0ae]%s[/color] rescued [color=#4fc3f7]%s[/color]!" % [rescuer.player_name, victim.player_name])
	_update_hud()

func _on_player_item_used(item: String) -> void:
	add_game_log("You used [color=#ffe066]%s[/color]!" % item.to_upper())

func _on_player_item_picked_up(item: String) -> void:
	add_game_log("You picked up [color=#69f0ae]%s[/color]! Press [E] to use." % item.to_upper())

func _on_item_button_pressed() -> void:
	if local_player:
		local_player.use_held_item()

func add_game_log(msg: String) -> void:
	game_log_lbl.append_text(msg + "\n")

# -- Single Item Slot UI Update ----------------------------------------------
func _update_item_slot(item_name: String) -> void:
	if not item_name_lbl:
		return
	if item_name.is_empty():
		item_name_lbl.text = "NONE"
		item_name_lbl.modulate = Color(0.6, 0.75, 0.9, 0.7)
	else:
		match item_name:
			"speed":
				item_name_lbl.text = "SPEED BOOST"
				item_name_lbl.modulate = Color(1.0, 0.9, 0.2)
			"shield":
				item_name_lbl.text = "ICE SHIELD"
				item_name_lbl.modulate = Color(0.3, 1.0, 0.5)
			"heater":
				item_name_lbl.text = "HEATER"
				item_name_lbl.modulate = Color(1.0, 0.45, 0.2)
			"banana":
				item_name_lbl.text = "BANANA PEEL"
				item_name_lbl.modulate = Color(1.0, 0.95, 0.1)
			"vortex":
				item_name_lbl.text = "BLACK HOLE"
				item_name_lbl.modulate = Color(0.75, 0.4, 1.0)
			"tackle":
				item_name_lbl.text = "DASH TACKLE"
				item_name_lbl.modulate = Color(1.0, 0.5, 0.1)

# -- HUD Update --------------------------------------------------------------
func _update_hud() -> void:
	var runners_count = 0
	var taggers_count = 0
	var total_players = player_nodes.size()
	
	for child in status_container.get_children():
		child.queue_free()
	
	for p in player_nodes:
		if p.role == "tagger":
			taggers_count += 1
		else:
			if not p.is_frozen:
				runners_count += 1
		
		var row = HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 20)
		row.alignment = BoxContainer.ALIGNMENT_BEGIN
		
		# Vector dot indicator (immune to font/emoji missing glyph issues)
		var dot = Panel.new()
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var dot_style = StyleBoxFlat.new()
		dot_style.corner_radius_top_left = 4
		dot_style.corner_radius_top_right = 4
		dot_style.corner_radius_bottom_right = 4
		dot_style.corner_radius_bottom_left = 4
		
		var name_lbl = Label.new()
		name_lbl.text = " " + p.player_name
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		
		var status_badge = Label.new()
		status_badge.add_theme_font_size_override("font_size", 10)
		
		if p.is_frozen:
			dot_style.bg_color = Color(0.3, 0.9, 1.0)
			status_badge.text = "[FROZEN]"
			status_badge.modulate = Color(0.3, 0.9, 1.0)
		elif p.is_rescuing:
			dot_style.bg_color = Color(1.0, 0.9, 0.2)
			status_badge.text = "[RESCUING]"
			status_badge.modulate = Color(1.0, 0.9, 0.2)
		elif p.role == "tagger":
			dot_style.bg_color = Color(1.0, 0.35, 0.35)
			status_badge.text = "[TAGGER]"
			status_badge.modulate = Color(1.0, 0.35, 0.35)
		else:
			dot_style.bg_color = Color(0.4, 0.95, 0.4)
			status_badge.text = "[RUNNER]"
			status_badge.modulate = Color(0.4, 0.95, 0.4)
		
		dot.add_theme_stylebox_override("panel", dot_style)
		row.add_child(dot)
		row.add_child(name_lbl)
		row.add_child(status_badge)
		status_container.add_child(row)
	
	runners_count_lbl.text = str(runners_count)
	taggers_count_lbl.text = str(taggers_count)
	round_lbl.text = "ROUND %d / %d" % [current_round, max_rounds]
	status_title_lbl.text = "PLAYER STATUS   %d/%d" % [total_players, total_players]
	
	if local_player:
		hp_bar.value = local_player.hp
		hp_lbl.text = "%d / 100" % local_player.hp
		player_tag_name.text = local_player.player_name
		if local_player.is_frozen:
			player_tag_dot.visible = false
			player_tag_role.text = "[FROZEN]"
			player_tag_role.modulate = Color(0.3, 0.9, 1.0)
		elif local_player.role == "tagger":
			player_tag_dot.visible = false
			player_tag_role.text = "[TAGGER]"
			player_tag_role.modulate = Color(1.0, 0.35, 0.35)
		else:
			player_tag_dot.visible = false
			player_tag_role.text = "[RUNNER]"
			player_tag_role.modulate = Color(0.4, 0.95, 0.4)

# -- Win / Loss & MVP Summary (Offline / Practice Mode) ----------------------
func _end_round(winner: String) -> void:
	is_game_active = false
	game_over_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if winner == "TAGGERS":
		taggers_score += 1
		game_over_title.text = "TAGGERS WIN ROUND!"
		game_over_title.modulate = Color(1.0, 0.4, 0.4)
	else:
		runners_score += 1
		game_over_title.text = "RUNNERS WIN ROUND!"
		game_over_title.modulate = Color(0.4, 0.95, 1.0)
	
	score_lbl.text = "SCORE: Runners %d  -  Taggers %d" % [runners_score, taggers_score]
	
	var best_player: CharacterBody3D = null
	var highest_score = -1
	for p in player_nodes:
		var score = p.freeze_count * 2 + p.rescue_count * 2
		if score > highest_score:
			highest_score = score
			best_player = p
	
	if best_player:
		mvp_lbl.text = "MVP: %s (%d Tags / %d Rescues)" % [best_player.player_name, best_player.freeze_count, best_player.rescue_count]
	else:
		mvp_lbl.text = "MVP: Player 1 (You)"
	
	lobby_btn.visible = false
	if current_round >= max_rounds:
		next_round_btn.text = "PLAY AGAIN"
	else:
		next_round_btn.text = "NEXT ROUND (%d)" % (current_round + 1)

func _on_net_round_started(data: Dictionary) -> void:
	game_over_panel.visible = false
	is_game_active = true
	current_round = int(data.get("round", current_round))
	max_rounds = int(data.get("maxRounds", max_rounds))
	round_time = float(data.get("timeLeft", 165.0))
	
	# Clear previous match dynamic entities
	for item in items_container.get_children():
		item.queue_free()
	for trap in traps_container.get_children():
		trap.queue_free()
	
	_spawn_match_players()
	_update_hud()
	_update_item_slot("")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	add_game_log("[color=#ffe066]Round %d started![/color]" % current_round)

func _on_net_returned_to_lobby(_data: Dictionary) -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/3d/lobby_3d.tscn")

func _on_lobby_pressed() -> void:
	if Network and Network.is_online_game():
		if Network.is_host:
			Network.return_to_lobby()
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			get_tree().change_scene_to_file("res://scenes/3d/lobby_3d.tscn")
		return
	
	# Practice mode: return to lobby/room selection
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/3d/lobby_3d.tscn")

func _on_next_round_pressed() -> void:
	if Network and Network.is_online_game():
		if Network.is_host:
			Network.start_game()
		return
	
	current_round += 1
	if current_round > max_rounds:
		current_round = 1
		runners_score = 0
		taggers_score = 0
	
	round_time = 165.0
	is_game_active = true
	game_over_panel.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Clear items & traps for local next round
	for item in items_container.get_children():
		item.queue_free()
	for trap in traps_container.get_children():
		trap.queue_free()
	for i in range(4):
		_spawn_random_item()
		
	_spawn_match_players()
	_update_hud()
	_update_item_slot("")
	add_game_log("[color=#ffe066]Next Round %d started![/color]" % current_round)

func _on_exit_to_menu_pressed() -> void:
	if Network and Network.is_online_game():
		Network.disconnect_from_server()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/3d/main_menu_3d.tscn")

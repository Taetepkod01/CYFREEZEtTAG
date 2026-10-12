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
@onready var runners_box: Panel = $HUD/TopBar/RunnersBox
@onready var taggers_box: Panel = $HUD/TopBar/TaggersBox
@onready var timer_lbl: Label = $HUD/TopBar/TimerBox/TimerLabel
@onready var round_lbl: Label = $HUD/TopBar/TimerBox/RoundLabel
@onready var status_panel: Panel = $HUD/PlayerStatusPanel
@onready var status_container: VBoxContainer = $HUD/PlayerStatusPanel/Scroll/VBox
@onready var status_title_lbl: Label = $HUD/PlayerStatusPanel/Title
@onready var minimap: Control = $HUD/MinimapPanel/Minimap
@onready var inventory_panel: Panel = $HUD/BottomInventoryPanel
@onready var item_btn: Button = $HUD/BottomInventoryPanel/ItemButton
@onready var item_name_lbl: Label = $HUD/BottomInventoryPanel/ItemButton/ItemName
@onready var role_btn: Button = $HUD/PracticeRoleBtn
@onready var quack_skill_btn: TextureButton = $HUD/QuackSkillBtn
@onready var quack_cd_overlay: Panel = $HUD/QuackSkillBtn/CooldownOverlay
@onready var quack_cd_lbl: Label = $HUD/QuackSkillBtn/CooldownOverlay/CooldownLabel
@onready var tagger_skill_btn: Button = $HUD/TaggerSkillBtn
@onready var tagger_skill_name_lbl: Label = $HUD/TaggerSkillBtn/SkillContent/SkillName
@onready var tagger_skill_key_lbl: Label = $HUD/TaggerSkillBtn/SkillContent/KeyBadge
@onready var tagger_skill_cd_overlay: Panel = $HUD/TaggerSkillBtn/CooldownOverlay
@onready var tagger_skill_cd_lbl: Label = $HUD/TaggerSkillBtn/CooldownOverlay/CooldownLabel
@onready var berry_splatter_overlay: ColorRect = $HUD/BerrySplatterOverlay
@onready var berry_splatter_lbl: Label = $HUD/BerrySplatterOverlay/SplatterLabel
@onready var control_hint_lbl: Label = $HUD/ControlHint

# Audio SFX
const AUDIO_FREEZE_TAG = preload("res://assets/audio/sfx/freeze_tag.wav")
const AUDIO_DUCK_QUACK = preload("res://assets/audio/sfx/duck_quack.mp3")
var sfx_freeze_player: AudioStreamPlayer = null
var sfx_quack_player: AudioStreamPlayer = null
var quack_cooldown: float = 0.0
const QUACK_COOLDOWN_MAX: float = 3.0

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
@onready var exit_choice_panel: Panel = $HUD/ExitChoicePanel
@onready var exit_to_lobby_btn: Button = $HUD/ExitChoicePanel/ExitChoiceBox/ReturnLobbyBtn
@onready var exit_to_menu_btn: Button = $HUD/ExitChoicePanel/ExitChoiceBox/MainMenuBtn
@onready var cancel_exit_btn: Button = $HUD/ExitChoicePanel/ExitChoiceBox/CancelExitBtn

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

# TAB Scoreboard overlay state
var tab_pressed_time: float = 0.0
var scoreboard_toggled: bool = false
var rewards_lbl: Label = null
var exit_choice_from_game_over: bool = false
var active_map_name: String = "SPACE STATION"
var is_void_parkour: bool = false
var is_space_station: bool = false
var tagger_skill_cd: float = 0.0
var tagger_skill_cd_max: float = 15.0
var tagger_active_skill_name: String = "SKILL"
var mirror_clone_node: Node3D = null
var mirror_clone_timer: float = 0.0
var berry_splatter_timer: float = 0.0

func _play_freeze_sfx() -> void:
	if sfx_freeze_player:
		sfx_freeze_player.stop()
		sfx_freeze_player.play()

func _ready() -> void:
	if BGMManager:
		BGMManager.fade_out_bgm(0.6)
	
	sfx_freeze_player = AudioStreamPlayer.new()
	sfx_freeze_player.name = "FreezeSFXPlayer"
	sfx_freeze_player.stream = AUDIO_FREEZE_TAG
	sfx_freeze_player.volume_db = 0.0
	add_child(sfx_freeze_player)
	
	if status_panel:
		status_panel.visible = false
	game_over_panel.visible = false
	menu_modal.visible = false
	exit_choice_panel.visible = false
	practice_role_modal.visible = false
	
	rewards_lbl = Label.new()
	rewards_lbl.name = "RewardsLabel"
	rewards_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rewards_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rewards_lbl.add_theme_font_size_override("font_size", 12)
	rewards_lbl.modulate = Color(1.0, 0.9, 0.3)
	rewards_lbl.anchors_preset = Control.PRESET_TOP_WIDE
	rewards_lbl.offset_top = 142.0
	rewards_lbl.offset_bottom = 188.0
	rewards_lbl.offset_left = 20.0
	rewards_lbl.offset_right = -20.0
	if game_over_panel:
		game_over_panel.offset_top = -175.0
		game_over_panel.offset_bottom = 175.0
		game_over_panel.add_child(rewards_lbl)
	
	next_round_btn.pressed.connect(_on_next_round_pressed)
	lobby_btn.pressed.connect(_on_lobby_pressed)
	exit_menu_btn.pressed.connect(_show_exit_choices)
	
	menu_btn.pressed.connect(_toggle_menu_modal)
	resume_btn.pressed.connect(func(): _set_menu_modal_visible(false))
	leave_btn.pressed.connect(_show_exit_choices)
	exit_to_lobby_btn.pressed.connect(_on_exit_choice_lobby_pressed)
	exit_to_menu_btn.pressed.connect(_on_exit_choice_menu_pressed)
	cancel_exit_btn.pressed.connect(_cancel_exit_choices)
	
	item_btn.pressed.connect(_on_item_button_pressed)
	
	sfx_quack_player = AudioStreamPlayer.new()
	sfx_quack_player.name = "DuckQuackSFXPlayer"
	sfx_quack_player.stream = AUDIO_DUCK_QUACK
	sfx_quack_player.volume_db = 1.0
	add_child(sfx_quack_player)
	
	if quack_skill_btn:
		quack_skill_btn.visible = false
	if tagger_skill_btn:
		tagger_skill_btn.pressed.connect(_on_tagger_skill_pressed)
	if berry_splatter_overlay:
		berry_splatter_overlay.visible = false
	
	if Network and (Network.is_online_game() or Network.current_match_players.size() > 0):
		# Match from lobby (online or offline test with bots)
		role_btn.visible = false
		current_round = Network.current_round
		max_rounds = Network.max_rounds
		if Network.is_online_game():
			_connect_network_signals()
		else:
			lobby_btn.visible = true
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
	
	if is_void_parkour:
		if inventory_panel:
			inventory_panel.visible = false
		if runners_box:
			runners_box.visible = false
		if taggers_box:
			taggers_box.visible = false
		if role_btn:
			role_btn.visible = false
		for item in items_container.get_children():
			item.queue_free()
		if local_player:
			local_player.held_item = ""
	elif not Network or not Network.is_online_game():
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
	
	if chosen_map.to_upper().contains("RANDOM"):
		var maps_pool = ["SPACE STATION", "SNOW TOWN", "TRAINING GROUND"]
		chosen_map = maps_pool[randi() % maps_pool.size()]
	
	print("[Arena3D] Loading map: ", chosen_map)
	
	var upper = chosen_map.to_upper()
	var map_scene_path: String = ""
	var map_display_name: String = ""
	
	if upper.contains("SPACE"):
		map_scene_path = "res://scenes/3d/maps/map_space_station.tscn"
		map_display_name = "SPACE STATION (Alpha Sector)"
	elif upper.contains("TRAINING") or upper.contains("GROUND") or upper.contains("LABYRINTH") or upper.contains("MAZE") or upper.contains("เขาวงกต"):
		map_scene_path = "res://scenes/3d/maps/map_training_ground.tscn"
		map_display_name = "TRAINING GROUND"
	elif upper.contains("SNOW") or upper.contains("TOWN") or upper.contains("หิมะ"):
		map_scene_path = "res://scenes/3d/maps/map_snow_town.tscn"
		map_display_name = "SNOW TOWN"
	elif upper.contains("PARKOUR") or upper.contains("VOID") or upper.contains("พาร์คัวร์"):
		map_scene_path = "res://scenes/3d/maps/map_void_parkour.tscn"
		map_display_name = "VOID PARKOUR"
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
				
			active_map_name = map_display_name
			is_void_parkour = upper.contains("PARKOUR") or upper.contains("VOID") or upper.contains("พาร์คัวร์")
			is_space_station = upper.contains("SPACE")
			if is_space_station:
				add_game_log("[color=#80d8ff]🚀 Low Gravity Environment Activated! (Floaty Space Jumps)[/color]")
			if is_void_parkour:
				round_time = 120.0
				if current_map_node.has_signal("player_checkpoint_reached"):
					current_map_node.player_checkpoint_reached.connect(func(p, idx):
						var p_name = p.player_name if is_instance_valid(p) else "Player"
						add_game_log("[color=#00e5ff]🚩 %s reached Checkpoint %d! (Progress Saved)[/color]" % [p_name, idx])
					)
				if current_map_node.has_signal("player_finished_parkour"):
					current_map_node.player_finished_parkour.connect(func(winner_p):
						_on_parkour_finish_reached(winner_p)
					)
			
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
	if not Network.player_kicked.is_connected(_on_net_player_kicked):
		Network.player_kicked.connect(_on_net_player_kicked)
	if not Network.chat_received.is_connected(func(msg): add_game_log(msg)):
		Network.chat_received.connect(func(msg): add_game_log(msg))
	if not Network.player_taunted.is_connected(_on_net_player_taunted):
		Network.player_taunted.connect(_on_net_player_taunted)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		if event.keycode == KEY_ESCAPE and event.pressed:
			_toggle_menu_modal()
		elif event.keycode == KEY_F and event.pressed:
			_on_quack_skill_pressed()
		elif event.keycode == KEY_E and event.pressed:
			if local_player and local_player.role == "tagger":
				_on_tagger_skill_pressed()
		elif event.keycode == KEY_TAB:
			if is_instance_valid(status_panel):
				if event.pressed:
					tab_pressed_time = Time.get_ticks_msec() / 1000.0
					status_panel.visible = true
					_update_hud()
				else:
					var held_duration = (Time.get_ticks_msec() / 1000.0) - tab_pressed_time
					if held_duration < 0.25:
						scoreboard_toggled = not scoreboard_toggled
						status_panel.visible = scoreboard_toggled
					else:
						scoreboard_toggled = false
						status_panel.visible = false

func _process(delta: float) -> void:
	if not is_game_active:
		return
	
	round_time -= delta
	if round_time <= 0.0:
		round_time = 0.0
		if not Network or not Network.is_online_game():
			if is_void_parkour:
				_on_parkour_time_expired()
			else:
				_end_round("RUNNERS")
	
	var mins = int(round_time) / 60
	var secs = int(round_time) % 60
	timer_lbl.text = "%02d:%02d" % [mins, secs]
	
	# Item spawn cycle for offline mode (completely disabled in Parkour mode)
	if not is_void_parkour and (not Network or not Network.is_online_game()):
		item_spawn_timer -= delta
		if item_spawn_timer <= 0.0:
			item_spawn_timer = randf_range(8.0, 14.0)
			_spawn_random_item()
	
	_process_tagger_skill(delta)
	_process_berry_splatter(delta)
	_process_quack_cooldown(delta)
	if is_game_active and not is_void_parkour:
		_check_round_end_condition()
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
	
	if Network and Network.current_match_players.size() > 0:
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
	var my_name = Network.get_effective_player_name() if Network else "Player 1"
	p1.player_name = my_name + " (You)"
	p1.role = "tagger" if p1_is_tagger else "runner"
	if p1_is_tagger:
		var p1_type = Network.selected_tagger_type if (Network and not Network.selected_tagger_type.is_empty() and Network.selected_tagger_type != "random") else ["ponpon", "mafog", "mumu", "phoemphoon", "snowman"][randi() % 5]
		p1.set_tagger_type(p1_type)
	else:
		var p1_run_type = Network.selected_runner_type if (Network and not Network.selected_runner_type.is_empty() and Network.selected_runner_type != "random") else "penguin"
		p1.set_runner_type(p1_run_type)
	p1.is_bot = false
	p1.position = chaser_spawn_pos if p1_is_tagger else runner_spawn_positions[0]
	players_container.add_child(p1)
	player_nodes.append(p1)
	local_player = p1
	_apply_map_physics_to_player(p1)
	if is_void_parkour:
		p1.held_item = ""
	
	p1.tagged.connect(_on_player_tagged)
	p1.rescued.connect(_on_player_rescued)
	p1.item_used.connect(_on_player_item_used)
	p1.item_picked_up.connect(_on_player_item_picked_up)
	p1.item_changed.connect(_update_item_slot)
	p1.player_damaged.connect(func(target, amt): _on_player_hit_damage(target, amt, p1))
	
	# If Void Parkour in solo/practice mode, don't spawn hostile tagger bots to interrupt parkour testing
	if is_void_parkour:
		_update_hud()
		return
	
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
			var bot_types = ["ponpon", "mafog", "mumu", "phoemphoon", "snowman"]
			bot.set_tagger_type(bot_types[randi() % bot_types.size()])
		else:
			bot.position = runner_spawn_positions[runner_cursor % runner_spawn_positions.size()]
			runner_cursor += 1
			var bot_run_pool = ["penguin", "snowman", "ponpon", "mafog", "mumu", "phoemphoon"]
			bot.set_runner_type(bot_run_pool[randi() % bot_run_pool.size()])
		players_container.add_child(bot)
		player_nodes.append(bot)
		_apply_map_physics_to_player(bot)
		
		bot.tagged.connect(_on_player_tagged)
		bot.rescued.connect(_on_player_rescued)
		bot.item_used.connect(func(item): add_game_log("%s used [color=#ffe066]%s[/color]!" % [bot.player_name, item]))
		bot.player_damaged.connect(func(target, amt): _on_player_hit_damage(target, amt, bot))
	
	_update_hud()

func _apply_map_physics_to_player(p: CharacterBody3D) -> void:
	if not is_instance_valid(p):
		return
	if is_space_station or (current_map_node and "MAP_GRAVITY" in current_map_node):
		var g = float(current_map_node.MAP_GRAVITY) if (current_map_node and "MAP_GRAVITY" in current_map_node) else 3.2
		var j = float(current_map_node.MAP_JUMP_VELOCITY) if (current_map_node and "MAP_JUMP_VELOCITY" in current_map_node) else 5.2
		if p.has_method("set_low_gravity_mode"):
			p.set_low_gravity_mode(true, g, j)
		else:
			p.gravity = g
			p.jump_velocity = j
	else:
		if p.has_method("set_low_gravity_mode"):
			p.set_low_gravity_mode(false)
		else:
			p.gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
			p.jump_velocity = 5.8

func _spawn_online_players() -> void:
	var online_list = Network.current_match_players
	for p_data in online_list:
		var p_id = str(p_data.get("id", ""))
		var is_me = false
		if Network and not Network.my_peer_id.is_empty() and p_id == Network.my_peer_id:
			is_me = true
		elif bool(p_data.get("isHost", false)) and Network and Network.is_host:
			is_me = true
		elif (not Network or not Network.is_online_game()) and bool(p_data.get("isHost", false)):
			is_me = true
		
		var is_bot = bool(p_data.get("isBot", false))
		
		var p_node = player_3d_scene.instantiate()
		p_node.network_id = p_id
		p_node.role = str(p_data.get("role", "runner"))
		if p_node.role == "tagger":
			var t_type = str(p_data.get("taggerType", ""))
			if is_me and Network and not Network.selected_tagger_type.is_empty() and Network.selected_tagger_type != "random":
				t_type = Network.selected_tagger_type
			elif t_type.is_empty():
				var pool = ["ponpon", "mafog", "mumu", "phoemphoon", "snowman"]
				t_type = pool[abs(p_id.hash()) % pool.size()]
			p_node.set_tagger_type(t_type)
		else:
			var r_type = str(p_data.get("runnerType", ""))
			if is_me and Network and not Network.selected_runner_type.is_empty() and Network.selected_runner_type != "random":
				r_type = Network.selected_runner_type
			elif r_type.is_empty():
				r_type = "penguin"
			p_node.set_runner_type(r_type)
		var p_name_str = str(p_data.get("name", "Player"))
		if is_me and Network:
			var eff = Network.get_effective_player_name()
			if not eff.is_empty() and eff != "Player 1":
				p_name_str = eff
		p_node.player_name = p_name_str + (" (You)" if is_me else "")
		
		if is_bot:
			if not Network or not Network.is_online_game() or Network.is_host:
				# Host simulates bot AI and drives movement
				p_node.is_bot = true
				p_node.is_remote = false
			else:
				# Other clients receive bot transforms remotely
				p_node.is_bot = false
				p_node.is_remote = true
		else:
			p_node.is_bot = false
			p_node.is_remote = not is_me
		
		p_node.position = Vector3(float(p_data.get("x", 0)), float(p_data.get("y", 0.5)), float(p_data.get("z", 0)))
		
		players_container.add_child(p_node)
		player_nodes.append(p_node)
		_apply_map_physics_to_player(p_node)
		
		if is_me:
			local_player = p_node
			p_node.tagged.connect(_on_player_tagged)
			p_node.rescued.connect(_on_player_rescued)
			p_node.item_changed.connect(_update_item_slot)
			p_node.item_picked_up.connect(_on_player_item_picked_up)
			p_node.item_used.connect(_on_player_item_used)
			p_node.player_damaged.connect(func(target, amt): _on_player_hit_damage(target, amt, p_node))
		elif is_bot and not p_node.is_remote:
			# Bot simulated by local host
			p_node.tagged.connect(_on_player_tagged)
			p_node.rescued.connect(_on_player_rescued)
			p_node.item_picked_up.connect(_on_player_item_picked_up)
			p_node.item_used.connect(func(item): add_game_log("%s used [color=#ffe066]%s[/color]!" % [p_node.player_name, item]))
			p_node.player_damaged.connect(func(target, amt): _on_player_hit_damage(target, amt, p_node))
	
	# Fallback: ensure a local camera is always active so viewport never stays grey
	if not local_player and player_nodes.size() > 0:
		for p_candidate in player_nodes:
			if not p_candidate.is_bot:
				local_player = p_candidate
				break
		if not local_player:
			local_player = player_nodes[0]
		local_player.is_remote = false
		if "camera" in local_player and local_player.camera:
			local_player.camera.current = true
		if "spring_arm" in local_player and local_player.spring_arm:
			local_player.spring_arm.visible = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Spawn initial server items (or local items if offline)
	if Network and not Network.current_match_items.is_empty():
		for child in items_container.get_children():
			child.queue_free()
		for it in Network.current_match_items:
			var item = item_3d_scene.instantiate()
			item.position = Vector3(float(it.get("x", 0)), float(it.get("y", 0.6)), float(it.get("z", 0)))
			items_container.add_child(item)
			item.setup(str(it.get("type", "speed")), str(it.get("id", "")))
	elif not is_void_parkour and items_container.get_child_count() == 0:
		for i in range(4):
			_spawn_random_item()

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
		if is_instance_valid(p) and p.network_id == victim_id:
			p.freeze()
			break
	_play_freeze_sfx()
	add_game_log("[color=#ff4c4c]%s[/color] tagged [color=#4fc3f7]%s[/color]" % [tagger_name, victim_name])
	_update_hud()
	_check_round_end_condition()

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
	
	var rewards_map = data.get("rewards", {})
	if typeof(rewards_map) == TYPE_DICTIONARY and Network and rewards_map.has(Network.player_id):
		var my_reward = rewards_map[Network.player_id]
		var exp_gained = int(my_reward.get("expGained", 0))
		var coins_gained = int(my_reward.get("coinsGained", 0))
		var leveled_up = bool(my_reward.get("leveledUp", false))
		var new_level = int(my_reward.get("level", 1))
		var coins_total = int(my_reward.get("coins", 0))
		
		var reward_str = "REWARDS: +%d EXP  |  +%d 🪙 COINS (Total: %d)" % [exp_gained, coins_gained, coins_total]
		if leveled_up:
			reward_str += "\n🌟 LEVEL UP! You reached Level %d! 🌟" % new_level
		_show_rewards_display(reward_str, leveled_up)
	else:
		_show_rewards_display("", false)
	
	if Network.is_host:
		next_round_btn.visible = true
		next_round_btn.text = "PLAY AGAIN" if is_match_over else "NEXT ROUND (%d)" % (current_round + 1)
		lobby_btn.visible = true
	else:
		next_round_btn.visible = false
		lobby_btn.visible = true

func _show_rewards_display(text: String, leveled_up: bool) -> void:
	if not rewards_lbl:
		return
	rewards_lbl.text = text
	if leveled_up:
		rewards_lbl.modulate = Color(1.0, 0.95, 0.2)
	else:
		rewards_lbl.modulate = Color(0.4, 0.9, 1.0)

# -- Events & Log (Practice / Local) -----------------------------------------
func _check_round_end_condition() -> void:
	if not is_game_active or is_void_parkour:
		return
	if player_nodes.size() < 2:
		return
	
	var total_runners = 0
	var unfrozen_runners = 0
	var alive_taggers = 0
	for p in player_nodes:
		if not is_instance_valid(p):
			continue
		if p.role == "runner":
			total_runners += 1
			if not p.is_frozen:
				unfrozen_runners += 1
		elif p.role == "tagger":
			if p.hp > 0 and not p.is_frozen:
				alive_taggers += 1
	
	if total_runners > 0 and unfrozen_runners == 0:
		_end_round("TAGGERS")
	elif total_runners > 0 and alive_taggers == 0 and not (Network and Network.is_online_game()):
		_end_round("RUNNERS")

func _on_player_tagged(tagger: CharacterBody3D, victim: CharacterBody3D) -> void:
	_play_freeze_sfx()
	add_game_log("[color=#ff4c4c]%s[/color] tagged [color=#4fc3f7]%s[/color]" % [tagger.player_name, victim.player_name])
	_update_hud()
	_check_round_end_condition()

func _on_player_rescued(rescuer: CharacterBody3D, victim: CharacterBody3D) -> void:
	add_game_log("[color=#69f0ae]%s[/color] rescued [color=#4fc3f7]%s[/color]!" % [rescuer.player_name, victim.player_name])
	_update_hud()

func _on_player_hit_damage(target: CharacterBody3D, amt: int, attacker: CharacterBody3D) -> void:
	var atk_name = attacker.player_name if is_instance_valid(attacker) else "Player"
	var tgt_name = target.player_name if is_instance_valid(target) else "Player"
	add_game_log(">> [color=#ff9800]%s tackled %s! (-%d HP)[/color]" % [atk_name, tgt_name, amt])
	_update_hud()
	if is_instance_valid(target) and target.hp <= 0 and target.role == "tagger":
		target.freeze()
		var alive_taggers = 0
		for p in player_nodes:
			if is_instance_valid(p) and p.role == "tagger" and p.hp > 0:
				alive_taggers += 1
		if alive_taggers == 0:
			add_game_log("[color=#69f0ae]All Taggers defeated! Runners Win![/color]")
			_end_round("RUNNERS")
		else:
			add_game_log("[color=#ffe066]Tagger %s knocked out! (%d remaining)[/color]" % [tgt_name, alive_taggers])

func _on_player_item_used(item: String) -> void:
	add_game_log("You used [color=#ffe066]%s[/color]!" % item.to_upper())

func _on_player_item_picked_up(item: String) -> void:
	add_game_log("You picked up [color=#69f0ae]%s[/color]! Press [E] to use." % item.to_upper())

func _on_item_button_pressed() -> void:
	if local_player:
		local_player.use_held_item()

# -- Runner Skill (Disabled: Runners have no active skill) --------------------
func _process_quack_cooldown(_delta: float) -> void:
	if quack_skill_btn:
		quack_skill_btn.visible = false

func _on_quack_skill_pressed() -> void:
	pass

# -- Tagger Active Skills (Bottom Right Circle Button, [E]) ------------------
func _process_tagger_skill(delta: float) -> void:
	if not tagger_skill_btn:
		return
	if not local_player or local_player.role != "tagger":
		tagger_skill_btn.visible = false
		return
	
	tagger_skill_btn.visible = not is_void_parkour
	
	if mirror_clone_node != null and is_instance_valid(mirror_clone_node):
		mirror_clone_timer -= delta
		if mirror_clone_timer <= 0.0:
			if is_instance_valid(mirror_clone_node):
				mirror_clone_node.queue_free()
			mirror_clone_node = null
			tagger_skill_cd = 16.0
			_update_hud()
	
	if tagger_skill_cd > 0.0:
		tagger_skill_cd -= delta
		if tagger_skill_cd <= 0.0:
			tagger_skill_cd = 0.0
			if tagger_skill_cd_overlay:
				tagger_skill_cd_overlay.visible = false
			tagger_skill_btn.disabled = local_player.is_frozen
		else:
			if tagger_skill_cd_overlay:
				tagger_skill_cd_overlay.visible = true
			if tagger_skill_cd_lbl:
				tagger_skill_cd_lbl.text = "%.1fs" % tagger_skill_cd
			tagger_skill_btn.disabled = true
	else:
		if mirror_clone_node != null and is_instance_valid(mirror_clone_node):
			if tagger_skill_cd_overlay:
				tagger_skill_cd_overlay.visible = false
			tagger_skill_btn.disabled = local_player.is_frozen
		else:
			if tagger_skill_cd_overlay:
				tagger_skill_cd_overlay.visible = false
			tagger_skill_btn.disabled = local_player.is_frozen

func _process_berry_splatter(delta: float) -> void:
	if berry_splatter_timer > 0.0:
		berry_splatter_timer -= delta
		if berry_splatter_overlay:
			berry_splatter_overlay.visible = true
			berry_splatter_overlay.modulate.a = clamp(berry_splatter_timer / 0.4, 0.0, 1.0)
		if berry_splatter_timer <= 0.0:
			berry_splatter_timer = 0.0
			if berry_splatter_overlay:
				berry_splatter_overlay.visible = false

func trigger_berry_splatter(duration: float = 2.0) -> void:
	berry_splatter_timer = duration
	if berry_splatter_overlay:
		berry_splatter_overlay.visible = true
		berry_splatter_overlay.modulate.a = 1.0

func _on_tagger_skill_pressed() -> void:
	if not is_game_active or game_over_panel.visible or menu_modal.visible:
		return
	if not local_player or local_player.role != "tagger" or local_player.is_frozen:
		return
	
	var t_type = local_player.tagger_type.to_lower()
	
	# Mumu recast to swap position with decoy
	if t_type.contains("mumu") or t_type.contains("มุมุ"):
		if mirror_clone_node != null and is_instance_valid(mirror_clone_node):
			_cast_mirror_swap()
			return
	
	if tagger_skill_cd > 0.0:
		return
	
	if t_type.contains("ponpon") or t_type.contains("ป้อน"):
		_cast_banana_gun()
	elif t_type.contains("snowman") or t_type.contains("สโนว์"):
		_cast_snow_domain()
	elif t_type.contains("mafog") or t_type.contains("ฟ้อก"):
		_cast_berry_bomb()
	elif t_type.contains("mumu") or t_type.contains("มุมุ"):
		_cast_mirror_swap()
	elif t_type.contains("phoemphoon") or t_type.contains("เพิ่ม") or t_type.contains("phun"):
		_cast_bass_drop()
	else:
		_cast_banana_gun()

# Skill 1: PonPon - Banana Gun (Peel projectile, stuns 1.5s, cooldown 15s)
func _cast_banana_gun() -> void:
	tagger_skill_cd = 15.0
	var forward_dir = -local_player.global_transform.basis.z.normalized()
	var spawn_pos = local_player.global_position + Vector3(0, 0.8, 0) + forward_dir * 1.2
	
	var projectile = Area3D.new()
	projectile.collision_layer = 8
	projectile.collision_mask = 2
	projectile.position = spawn_pos
	
	var col = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 0.8
	col.shape = sphere
	projectile.add_child(col)
	
	var banana_scene = preload("res://scenes/3d/banana_peel.tscn")
	var banana_vis = banana_scene.instantiate()
	banana_vis.scale = Vector3(1.6, 1.6, 1.6)
	projectile.add_child(banana_vis)
	
	traps_container.add_child(projectile)
	add_game_log("[color=#ffe066]PonPon fired Banana Gun! (Cooldown 15s)[/color]")
	
	var elapsed: float = 0.0
	var hit: bool = false
	var move_callable: Callable
	move_callable = func():
		if not is_instance_valid(projectile) or projectile.is_queued_for_deletion():
			return
		var d = get_process_delta_time()
		elapsed += d
		projectile.global_position += forward_dir * 24.0 * d
		projectile.rotate_y(15.0 * d)
		
		for p in player_nodes:
			if is_instance_valid(p) and p.role == "runner" and not p.is_frozen:
				if projectile.global_position.distance_to(p.global_position + Vector3(0, 0.6, 0)) < 1.6:
					hit = true
					if p.has_method("stun"):
						p.stun(1.5)
					else:
						p.freeze()
					add_game_log("[color=#ffe066]Banana Gun hit %s! Stunned for 1.5s![/color]" % p.player_name)
					_play_freeze_sfx()
					break
		
		if hit or elapsed >= 2.0:
			if get_tree() and get_tree().process_frame.is_connected(move_callable):
				get_tree().process_frame.disconnect(move_callable)
			if is_instance_valid(projectile):
				projectile.queue_free()
	
	get_tree().process_frame.connect(move_callable)

# Skill 2: Snowman - Snow Domain (Frost zone slows runners by 10% for 4s, cooldown 20s)
func _cast_snow_domain() -> void:
	tagger_skill_cd = 20.0
	var center_pos = local_player.global_position
	center_pos.y = 0.08
	
	var domain_node = Node3D.new()
	domain_node.name = "SnowDomainVisual"
	domain_node.position = center_pos
	
	var mesh_inst = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 7.0
	cyl.bottom_radius = 7.0
	cyl.height = 0.1
	mesh_inst.mesh = cyl
	
	var frost_mat = StandardMaterial3D.new()
	frost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	frost_mat.albedo_color = Color(0.2, 0.8, 1.0, 0.35)
	frost_mat.emission_enabled = true
	frost_mat.emission = Color(0.1, 0.6, 1.0)
	frost_mat.emission_energy_multiplier = 1.2
	mesh_inst.set_surface_override_material(0, frost_mat)
	domain_node.add_child(mesh_inst)
	
	traps_container.add_child(domain_node)
	_play_freeze_sfx()
	add_game_log("[color=#80d8ff]Snowman deployed Snow Domain! Runners in 7m slowed by 10% for 4s![/color]")
	
	var elapsed: float = 0.0
	var domain_callable: Callable
	domain_callable = func():
		if not is_instance_valid(domain_node) or domain_node.is_queued_for_deletion():
			return
		var d = get_process_delta_time()
		elapsed += d
		domain_node.rotate_y(1.5 * d)
		
		for p in player_nodes:
			if is_instance_valid(p) and p.role == "runner" and not p.is_frozen:
				var dist = center_pos.distance_to(p.global_position)
				if dist <= 7.0:
					p.apply_frost_slow(0.9, 4.0)
		
		if elapsed >= 4.0:
			if get_tree() and get_tree().process_frame.is_connected(domain_callable):
				get_tree().process_frame.disconnect(domain_callable)
			if is_instance_valid(domain_node):
				domain_node.queue_free()
	
	get_tree().process_frame.connect(domain_callable)

# Skill 3: Mafog - Berry Bomb (Explosive red juice blinds runners in 4m for 2s, cooldown 14s)
func _cast_berry_bomb() -> void:
	tagger_skill_cd = 14.0
	var forward_dir = -local_player.global_transform.basis.z.normalized()
	var spawn_pos = local_player.global_position + Vector3(0, 1.0, 0) + forward_dir * 0.8
	
	var bomb = Node3D.new()
	bomb.position = spawn_pos
	
	var mesh_inst = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.32
	sphere.height = 0.64
	mesh_inst.mesh = sphere
	var berry_mat = StandardMaterial3D.new()
	berry_mat.albedo_color = Color(0.95, 0.08, 0.22)
	berry_mat.emission_enabled = true
	berry_mat.emission = Color(0.8, 0.05, 0.15)
	mesh_inst.set_surface_override_material(0, berry_mat)
	bomb.add_child(mesh_inst)
	
	traps_container.add_child(bomb)
	add_game_log("[color=#ff1744]Mafog launched Berry Bomb! (Cooldown 14s)[/color]")
	
	var vel = forward_dir * 18.0 + Vector3(0, 4.5, 0)
	var elapsed: float = 0.0
	var bomb_callable: Callable
	bomb_callable = func():
		if not is_instance_valid(bomb) or bomb.is_queued_for_deletion():
			return
		var d = get_process_delta_time()
		elapsed += d
		vel.y -= 9.8 * d
		bomb.global_position += vel * d
		bomb.rotate_x(10.0 * d)
		
		if bomb.global_position.y <= 0.2 or elapsed >= 0.9:
			var expl_pos = bomb.global_position
			expl_pos.y = max(0.1, expl_pos.y)
			
			if get_tree() and get_tree().process_frame.is_connected(bomb_callable):
				get_tree().process_frame.disconnect(bomb_callable)
			if is_instance_valid(bomb):
				bomb.queue_free()
			
			var splash = MeshInstance3D.new()
			var spl_sphere = SphereMesh.new()
			spl_sphere.radius = 4.0
			spl_sphere.height = 0.4
			splash.mesh = spl_sphere
			var spl_mat = StandardMaterial3D.new()
			spl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			spl_mat.albedo_color = Color(0.9, 0.05, 0.15, 0.45)
			splash.set_surface_override_material(0, spl_mat)
			splash.position = expl_pos
			traps_container.add_child(splash)
			
			var tw = splash.create_tween()
			tw.tween_property(spl_mat, "albedo_color:a", 0.0, 0.6)
			tw.tween_callback(splash.queue_free)
			
			for p in player_nodes:
				if is_instance_valid(p) and p.role == "runner" and not p.is_frozen:
					if expl_pos.distance_to(p.global_position) <= 4.0:
						p.blind_strawberry_splash(2.0)
						add_game_log("[color=#ff1744]🍓 %s blinded by strawberry splash for 2s![/color]" % p.player_name)
	
	get_tree().process_frame.connect(bomb_callable)

# Skill 4: Mumu - Mirror Swap (Deploys shadow decoy, recast to swap positions, cooldown 16s)
func _cast_mirror_swap() -> void:
	if mirror_clone_node != null and is_instance_valid(mirror_clone_node):
		var clone_pos = mirror_clone_node.global_position
		local_player.global_position = clone_pos
		
		if is_instance_valid(mirror_clone_node):
			mirror_clone_node.queue_free()
		mirror_clone_node = null
		
		tagger_skill_cd = 16.0
		_update_hud()
		add_game_log("[color=#d500f9]✨ Mumu swapped positions with Mirror Shadow! (Cooldown 16s)[/color]")
		_play_freeze_sfx()
		return
	
	mirror_clone_timer = 10.0
	
	var decoy = Node3D.new()
	decoy.name = "MirrorShadowDecoy"
	decoy.position = local_player.global_position
	decoy.rotation = local_player.visuals.rotation if "visuals" in local_player else local_player.rotation
	
	var mesh_inst = MeshInstance3D.new()
	var cap = CapsuleMesh.new()
	cap.radius = 0.5
	cap.height = 1.6
	mesh_inst.mesh = cap
	mesh_inst.position.y = 0.8
	var holo_mat = StandardMaterial3D.new()
	holo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	holo_mat.albedo_color = Color(0.7, 0.2, 1.0, 0.45)
	holo_mat.emission_enabled = true
	holo_mat.emission = Color(0.6, 0.1, 0.9)
	mesh_inst.set_surface_override_material(0, holo_mat)
	decoy.add_child(mesh_inst)
	
	var lbl = Label3D.new()
	lbl.text = "MIRROR SHADOW"
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 18
	lbl.modulate = Color(0.85, 0.4, 1.0)
	lbl.position = Vector3(0, 1.9, 0)
	decoy.add_child(lbl)
	
	traps_container.add_child(decoy)
	mirror_clone_node = decoy
	_update_hud()
	add_game_log("[color=#d500f9]🪞 Mumu left a Mirror Shadow decoy! Press [E] again to swap![/color]")

# Skill 5: PhoemPhoon - Bass Drop (Ground shockwave stumbles runners zigzags 1s, cooldown 20s)
func _cast_bass_drop() -> void:
	tagger_skill_cd = 20.0
	var center_pos = local_player.global_position
	center_pos.y = 0.08
	
	var shockwave = MeshInstance3D.new()
	var ring = TorusMesh.new()
	ring.inner_radius = 8.0
	ring.outer_radius = 8.5
	shockwave.mesh = ring
	var ring_mat = StandardMaterial3D.new()
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(1.0, 0.6, 0.1, 0.8)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.5, 0.0)
	ring_mat.emission_energy_multiplier = 2.0
	shockwave.set_surface_override_material(0, ring_mat)
	shockwave.position = center_pos
	shockwave.scale = Vector3(0.05, 1.0, 0.05)
	traps_container.add_child(shockwave)
	
	var tw = shockwave.create_tween()
	tw.set_parallel(true)
	tw.tween_property(shockwave, "scale", Vector3(1.0, 1.0, 1.0), 0.35)
	tw.tween_property(ring_mat, "albedo_color:a", 0.0, 0.45)
	tw.chain().tween_callback(shockwave.queue_free)
	
	for p in player_nodes:
		if is_instance_valid(p) and p.role == "runner" and not p.is_frozen:
			if center_pos.distance_to(p.global_position) <= 8.5:
				p.apply_stumble(1.0)
				add_game_log("[color=#ff9100]🔊 %s stumbled in zigzags from Bass Drop![/color]" % p.player_name)
	
	add_game_log("[color=#ff6d00]PhoemPhoon slammed Bass Drop! (Shockwave 8.5m, Cooldown 20s)[/color]")
	_play_freeze_sfx()

func _play_duck_quack(player: CharacterBody3D = null) -> void:
	if sfx_quack_player:
		sfx_quack_player.stop()
		sfx_quack_player.play()
	if is_instance_valid(player) and player.has_method("trigger_quack"):
		player.trigger_quack()
	var p_name = player.player_name if is_instance_valid(player) else "Runner"
	add_game_log("[color=#ffe066]🦆 %s: QUACK![/color]" % p_name)

func _on_net_player_taunted(p_id: String, p_name: String, _sound_type: String) -> void:
	if local_player and local_player.network_id == p_id:
		return
	var target_p: CharacterBody3D = null
	for p in player_nodes:
		if is_instance_valid(p) and p.network_id == p_id:
			target_p = p
			break
	_play_duck_quack(target_p)

func add_game_log(msg: String) -> void:
	print("[GameLog] ", msg.replace("[color=#", "").replace("[/color]", "").replace(">> ", ""))

# -- Single Item Slot UI Update ----------------------------------------------
func _update_item_slot(item_name: String) -> void:
	if is_void_parkour:
		if inventory_panel:
			inventory_panel.visible = false
		return
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
	if is_void_parkour:
		if runners_box:
			runners_box.visible = false
		if taggers_box:
			taggers_box.visible = false
		if role_btn:
			role_btn.visible = false
		if inventory_panel:
			inventory_panel.visible = false
		round_lbl.text = "PARKOUR RACE"
		status_title_lbl.text = "PARKOUR RACERS   %d/%d" % [player_nodes.size(), player_nodes.size()]
		return

	var runners_count = 0
	var taggers_count = 0
	var total_players = player_nodes.size()
	
	for p in player_nodes:
		if p.role == "tagger":
			taggers_count += 1
		else:
			if not p.is_frozen:
				runners_count += 1
	
	runners_count_lbl.text = str(runners_count)
	taggers_count_lbl.text = str(taggers_count)
	round_lbl.text = "ROUND %d / %d" % [current_round, max_rounds]
	status_title_lbl.text = "PLAYER STATUS   %d/%d" % [total_players, total_players]
	
	# Only populate player list when scoreboard is opened with [TAB]
	if status_panel and status_panel.visible:
		for child in status_container.get_children():
			child.queue_free()
		
		for p in player_nodes:
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

	# Update Tagger / Runner specific HUD controls
	if local_player:
		if local_player.role == "tagger":
			if inventory_panel:
				inventory_panel.visible = false
			if quack_skill_btn:
				quack_skill_btn.visible = false
			if tagger_skill_btn:
				tagger_skill_btn.visible = not is_void_parkour
			
			var t_type = local_player.tagger_type.to_lower()
			if mirror_clone_node != null and is_instance_valid(mirror_clone_node):
				tagger_active_skill_name = "SWAP"
				tagger_skill_cd_max = 16.0
			elif t_type.contains("ponpon") or t_type.contains("ป้อน"):
				tagger_active_skill_name = "BANANA GUN"
				tagger_skill_cd_max = 15.0
			elif t_type.contains("snowman") or t_type.contains("สโนว์"):
				tagger_active_skill_name = "SNOW DOMAIN"
				tagger_skill_cd_max = 20.0
			elif t_type.contains("mafog") or t_type.contains("ฟ้อก"):
				tagger_active_skill_name = "BERRY BOMB"
				tagger_skill_cd_max = 14.0
			elif t_type.contains("mumu") or t_type.contains("มุมุ"):
				tagger_active_skill_name = "MIRROR SWAP"
				tagger_skill_cd_max = 16.0
			elif t_type.contains("phoemphoon") or t_type.contains("เพิ่ม") or t_type.contains("phun"):
				tagger_active_skill_name = "BASS DROP"
				tagger_skill_cd_max = 20.0
			else:
				tagger_active_skill_name = "BANANA GUN"
				tagger_skill_cd_max = 15.0
			
			if tagger_skill_name_lbl:
				tagger_skill_name_lbl.text = tagger_active_skill_name
			if control_hint_lbl:
				control_hint_lbl.text = "[WASD] Move | [SPACE] Jump | [E] %s | [TAB] Players | [CLICK] Lock Camera | [ALT / ESC] Free Mouse" % tagger_active_skill_name
		else:
			if inventory_panel:
				inventory_panel.visible = not is_void_parkour
			if tagger_skill_btn:
				tagger_skill_btn.visible = false
			if quack_skill_btn:
				quack_skill_btn.visible = false
			if control_hint_lbl:
				control_hint_lbl.text = "[WASD] Move | [SPACE] Jump | [E] Use Item | [TAB] Players | [CLICK] Lock Camera | [ALT / ESC] Free Mouse"

# -- Win / Loss & MVP Summary (Offline / Practice Mode) ----------------------
func _end_round(winner: String) -> void:
	is_game_active = false
	game_over_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if winner == "TAGGERS":
		taggers_score += 1
		game_over_title.text = "TIME'S UP! TRY AGAIN" if is_void_parkour else "TAGGERS WIN ROUND!"
		game_over_title.modulate = Color(1.0, 0.4, 0.4)
	else:
		runners_score += 1
		game_over_title.text = "PARKOUR COMPLETED! 🏆" if is_void_parkour else "RUNNERS WIN ROUND!"
		game_over_title.modulate = Color(0.2, 1.0, 0.6) if is_void_parkour else Color(0.4, 0.95, 1.0)
	
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
	
	if Network and Network.is_solo_mode:
		var exp_gain = 35
		var coins_gain = 20
		if (local_player and local_player.role == "runner" and winner == "RUNNERS") or (local_player and local_player.role == "tagger" and winner == "TAGGERS"):
			exp_gain = 60
			coins_gain = 30
		if local_player:
			exp_gain += local_player.freeze_count * 10 + local_player.rescue_count * 15
			coins_gain += local_player.freeze_count * 5 + local_player.rescue_count * 8
		
		var u = Network.current_user
		u["exp"] = int(u.get("exp", 0)) + exp_gain
		u["coins"] = int(u.get("coins", 0)) + coins_gain
		var lv = int(u.get("level", 1))
		var max_exp = int(u.get("maxExp", 100))
		var leveled_up = false
		while u["exp"] >= max_exp:
			u["exp"] -= max_exp
			lv += 1
			max_exp = lv * 100 + (lv - 1) * 50
			u["level"] = lv
			u["maxExp"] = max_exp
			leveled_up = true
		Network.save_local_user()
		Network.profile_updated.emit(u)
		var practice_rew = "PRACTICE REWARDS: +%d EXP  |  +%d 🪙 COINS (Total: %d)" % [exp_gain, coins_gain, u["coins"]]
		if leveled_up:
			practice_rew += "\n🌟 LEVEL UP! You reached Level %d! 🌟" % lv
		_show_rewards_display(practice_rew, leveled_up)
	
	lobby_btn.visible = false
	if current_round >= max_rounds:
		next_round_btn.text = "PLAY AGAIN"
	else:
		next_round_btn.text = "NEXT ROUND (%d)" % (current_round + 1)

func _on_parkour_finish_reached(winner_node: CharacterBody3D) -> void:
	if not is_game_active:
		return
	
	var winner_name = "Player"
	if is_instance_valid(winner_node) and "player_name" in winner_node:
		winner_name = winner_node.player_name
	elif local_player and "player_name" in local_player:
		winner_name = local_player.player_name
	
	winner_name = winner_name.replace(" (You)", "").strip_edges()
	if winner_name.is_empty():
		winner_name = "Player"
	
	var elapsed = max(0.0, 120.0 - round_time)
	var m = int(elapsed) / 60
	var s = int(elapsed) % 60
	var ms = int((elapsed - int(elapsed)) * 100)
	var time_str = "%02d:%02d.%02d" % [m, s, ms]
	
	is_game_active = false
	game_over_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	game_over_title.text = "🏆 %s WINS! 🏆" % winner_name.to_upper()
	game_over_title.modulate = Color(0.2, 1.0, 0.5)
	
	score_lbl.text = "CHAMPION: %s  |  TIME: %s" % [winner_name, time_str]
	mvp_lbl.text = "PARKOUR CHAMPION: %s" % winner_name
	
	add_game_log("[color=#00e676]★ %s REACHED THE FINISH LINE AND WON THE RACE! (Time: %s) ★[/color]" % [winner_name, time_str])
	
	if Network and Network.is_solo_mode:
		var u = Network.current_user
		var exp_gain = 100
		var coins_gain = 50
		u["exp"] = int(u.get("exp", 0)) + exp_gain
		u["coins"] = int(u.get("coins", 0)) + coins_gain
		var lv = int(u.get("level", 1))
		var max_exp = int(u.get("maxExp", 100))
		var leveled_up = false
		while u["exp"] >= max_exp:
			u["exp"] -= max_exp
			lv += 1
			max_exp = lv * 100 + (lv - 1) * 50
			u["level"] = lv
			u["maxExp"] = max_exp
			leveled_up = true
		Network.save_local_user()
		Network.profile_updated.emit(u)
		var practice_rew = "PARKOUR VICTORY: +%d EXP  |  +%d 🪙 COINS (Total: %d)" % [exp_gain, coins_gain, u["coins"]]
		if leveled_up:
			practice_rew += "\n🌟 LEVEL UP! You reached Level %d! 🌟" % lv
		_show_rewards_display(practice_rew, leveled_up)
	
	next_round_btn.text = "PLAY AGAIN"
	next_round_btn.visible = true
	lobby_btn.visible = false

func _on_parkour_time_expired() -> void:
	if not is_game_active:
		return
	is_game_active = false
	game_over_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	game_over_title.text = "TIME'S UP! TRY AGAIN"
	game_over_title.modulate = Color(1.0, 0.4, 0.4)
	score_lbl.text = "DID NOT FINISH IN TIME (2:00 LIMIT)"
	mvp_lbl.text = "TRY AGAIN!"
	_show_rewards_display("", false)
	next_round_btn.text = "PLAY AGAIN"
	next_round_btn.visible = true
	lobby_btn.visible = false

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
	if Network and Network.selected_game_mode == "racing":
		get_tree().change_scene_to_file("res://scenes/3d/lobby_racing_3d.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/3d/lobby_3d.tscn")

func _on_net_player_kicked(_reason: String) -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if Network and Network.selected_game_mode == "racing":
		get_tree().change_scene_to_file("res://scenes/3d/lobby_racing_3d.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/3d/lobby_3d.tscn")

func _on_lobby_pressed() -> void:
	var target_lobby = "res://scenes/3d/lobby_racing_3d.tscn" if (Network and Network.selected_game_mode == "racing") else "res://scenes/3d/lobby_3d.tscn"
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if Network and Network.is_online_game():
		Network.return_to_lobby()
		if not Network.is_host:
			get_tree().change_scene_to_file(target_lobby)
		else:
			# Fallback: if server response is delayed, transition host after 0.8s anyway
			var fallback_timer = get_tree().create_timer(0.8)
			fallback_timer.timeout.connect(func():
				if get_tree() and get_tree().current_scene == self:
					get_tree().change_scene_to_file(target_lobby)
			)
		return
	
	# Practice mode: return to lobby/room selection
	get_tree().change_scene_to_file(target_lobby)

func _on_next_round_pressed() -> void:
	if Network and Network.is_online_game():
		if Network.is_host:
			Network.start_game()
		return
	
	if is_void_parkour:
		round_time = 120.0
		is_game_active = true
		game_over_panel.visible = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		if current_map_node and current_map_node.has_method("reset_race"):
			current_map_node.reset_race()
		for item in items_container.get_children():
			item.queue_free()
		for trap in traps_container.get_children():
			trap.queue_free()
		_spawn_match_players()
		_update_hud()
		_update_item_slot("")
		add_game_log("[color=#ffe066]Parkour race restarted![/color]")
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
	
	if not is_void_parkour and (not Network or not Network.is_online_game()):
		if Network and Network.current_match_players.size() > 1:
			var total_p = Network.current_match_players.size()
			var tagger_idx = randi() % total_p
			for i in range(total_p):
				Network.current_match_players[i]["role"] = "tagger" if i == tagger_idx else "runner"
		
	_spawn_match_players()
	_update_hud()
	_update_item_slot("")
	add_game_log("[color=#ffe066]Next Round %d started![/color]" % current_round)

func _on_exit_to_menu_pressed() -> void:
	if Network and Network.is_connected_to_server:
		Network.disconnect_from_server()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/3d/main_menu_3d.tscn")

func _show_exit_choices() -> void:
	exit_choice_from_game_over = game_over_panel.visible
	menu_modal.visible = false
	game_over_panel.visible = false
	exit_choice_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_exit_choice_lobby_pressed() -> void:
	exit_choice_panel.visible = false
	_on_lobby_pressed()

func _on_exit_choice_menu_pressed() -> void:
	exit_choice_panel.visible = false
	_on_exit_to_menu_pressed()

func _cancel_exit_choices() -> void:
	exit_choice_panel.visible = false
	if exit_choice_from_game_over:
		game_over_panel.visible = true
	else:
		menu_modal.visible = true
	exit_choice_from_game_over = false
	if is_game_active:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

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
@onready var hud: CanvasLayer = $HUD

# HUD elements
@onready var runners_count_lbl: Label = $HUD/TopBar/RunnersBox/Count
@onready var taggers_count_lbl: Label = $HUD/TopBar/TaggersBox/Count
@onready var timer_lbl: Label = $HUD/TopBar/TimerBox/TimerLabel
@onready var round_lbl: Label = $HUD/TopBar/TimerBox/RoundLabel
@onready var status_container: VBoxContainer = $HUD/PlayerStatusPanel/Scroll/VBox
@onready var game_log_lbl: RichTextLabel = $HUD/GameLogPanel/LogContent
@onready var minimap: Control = $HUD/MinimapPanel/Minimap
@onready var hp_bar: ProgressBar = $HUD/BottomHUD/HPBox/ProgressBar
@onready var hp_lbl: Label = $HUD/BottomHUD/HPBox/HPLabel
@onready var item_btn: Button = $HUD/BottomHUD/SingleItemSlot/ItemButton
@onready var item_icon: Label = $HUD/BottomHUD/SingleItemSlot/ItemButton/Icon
@onready var item_name_lbl: Label = $HUD/BottomHUD/SingleItemSlot/ItemButton/Name
@onready var role_btn: Button = $HUD/PracticeRoleBtn

# Match Summary Panel (Card 4 from Teacher's Mockup)
@onready var game_over_panel: Panel = $HUD/GameOverPanel
@onready var game_over_title: Label = $HUD/GameOverPanel/Title
@onready var score_lbl: Label = $HUD/GameOverPanel/ScoreLabel
@onready var mvp_lbl: Label = $HUD/GameOverPanel/MVPLabel
@onready var next_round_btn: Button = $HUD/GameOverPanel/Buttons/NextButton
@onready var exit_menu_btn: Button = $HUD/GameOverPanel/Buttons/ExitButton

var player_nodes: Array[CharacterBody3D] = []
var local_player: CharacterBody3D = null
var item_spawn_timer: float = 4.0

# Practice Mode Role ("random", "tagger", or "runner")
var practice_role: String = "random"

func _ready() -> void:
	game_over_panel.visible = false
	next_round_btn.pressed.connect(_on_next_round_pressed)
	exit_menu_btn.pressed.connect(_on_exit_to_menu_pressed)
	$HUD/MenuButton.pressed.connect(_on_exit_to_menu_pressed)
	item_btn.pressed.connect(_on_item_button_pressed)
	
	# Load Practice Role setting from Network singleton
	if Network and "selected_practice_role" in Network:
		practice_role = Network.selected_practice_role
	
	_update_role_button_ui()
	role_btn.pressed.connect(_on_cycle_role_pressed)
	
	# Connect Minimap
	if minimap and minimap.has_method("setup"):
		minimap.setup(self)
	
	_spawn_match_players()
	_update_hud()
	_update_item_slot("")
	
	# Spawn initial items
	for i in range(3):
		_spawn_random_item()
	
	add_game_log("[color=#ffe066]Match started![/color] Round %d / %d" % [current_round, max_rounds])

func _process(delta: float) -> void:
	if not is_game_active:
		return
	
	round_time -= delta
	if round_time <= 0.0:
		round_time = 0.0
		_end_round("RUNNERS")
	
	var mins = int(round_time) / 60
	var secs = int(round_time) % 60
	timer_lbl.text = "%02d:%02d" % [mins, secs]
	
	# Item spawn cycle
	item_spawn_timer -= delta
	if item_spawn_timer <= 0.0:
		item_spawn_timer = randf_range(8.0, 14.0)
		_spawn_random_item()
	
	_update_hud()

# ── Role Selection & Cycling ────────────────────────────────────────────────
func _on_cycle_role_pressed() -> void:
	match practice_role:
		"random":
			practice_role = "tagger"
		"tagger":
			practice_role = "runner"
		"runner":
			practice_role = "random"
		_:
			practice_role = "random"
	
	if Network:
		Network.selected_practice_role = practice_role
	
	_update_role_button_ui()
	add_game_log("[color=#ffe066]AI Role: %s! Restarting round...[/color]" % practice_role.to_upper())
	
	round_time = 165.0
	is_game_active = true
	game_over_panel.visible = false
	_spawn_match_players()

func _update_role_button_ui() -> void:
	if not role_btn:
		return
	match practice_role:
		"tagger":
			role_btn.text = "ROLE: 🔴 TAGGER"
			role_btn.modulate = Color(1.0, 0.45, 0.45)
		"runner":
			role_btn.text = "ROLE: 🟢 RUNNER"
			role_btn.modulate = Color(0.45, 1.0, 0.45)
		"random", _:
			role_btn.text = "ROLE: 🎲 RANDOM"
			role_btn.modulate = Color(1.0, 0.9, 0.4)

# ── Spawning Players & Items ────────────────────────────────────────────────
func _spawn_match_players() -> void:
	for child in players_container.get_children():
		child.queue_free()
	player_nodes.clear()
	
	var spawn_positions = [
		Vector3(0, 0.5, 0),
		Vector3(-14, 0.5, -14),
		Vector3(14, 0.5, 14),
		Vector3(14, 0.5, -14)
	]
	
	# Determine who is Tagger and who is Runner
	var p1_is_tagger: bool = false
	var bot_tagger_idx: int = -1 # which bot (0..2) is tagger if p1 is runner
	
	match practice_role:
		"tagger":
			p1_is_tagger = true
			bot_tagger_idx = -1
		"runner":
			p1_is_tagger = false
			bot_tagger_idx = randi() % 3
		"random", _:
			# Fair 4-player random pick: 1 of 4 players is Tagger
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
	p1.position = spawn_positions[0]
	players_container.add_child(p1)
	player_nodes.append(p1)
	local_player = p1
	
	p1.tagged.connect(_on_player_tagged)
	p1.rescued.connect(_on_player_rescued)
	p1.item_used.connect(_on_player_item_used)
	p1.item_picked_up.connect(_on_player_item_picked_up)
	p1.item_changed.connect(_update_item_slot)
	
	# 3 Bots
	var bot_names = ["Player 2 (Bot)", "Player 3 (Bot)", "Player 4 (Bot)"]
	for i in range(3):
		var bot = player_3d_scene.instantiate()
		bot.player_name = bot_names[i]
		bot.role = "tagger" if (i == bot_tagger_idx) else "runner"
		bot.is_bot = true
		bot.position = spawn_positions[i + 1]
		players_container.add_child(bot)
		player_nodes.append(bot)
		
		bot.tagged.connect(_on_player_tagged)
		bot.rescued.connect(_on_player_rescued)
		bot.item_used.connect(func(item): add_game_log("%s used [color=#ffe066]%s[/color]!" % [bot.player_name, item]))
	
	_update_hud()

func _spawn_random_item() -> void:
	if items_container.get_child_count() >= 5:
		return
	
	var item_types = ["speed", "shield", "heater", "banana", "vortex"]
	var selected = item_types.pick_random()
	
	var item = item_3d_scene.instantiate()
	item.position = Vector3(randf_range(-22, 22), 0.6, randf_range(-22, 22))
	items_container.add_child(item)
	item.setup(selected)

func spawn_banana_trap(pos: Vector3) -> void:
	var trap = Area3D.new()
	trap.collision_layer = 8
	trap.collision_mask = 2
	var col = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 1.0
	col.shape = sphere
	trap.add_child(col)
	
	var lbl = Label3D.new()
	lbl.text = "🍌"
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 28
	trap.add_child(lbl)
	
	trap.position = pos + Vector3(0, 0.2, 0)
	traps_container.add_child(trap)
	
	trap.body_entered.connect(func(body):
		if body is CharacterBody3D and not body.is_frozen:
			body.freeze()
			add_game_log("🍌 [color=#ffe066]%s[/color] slipped on a banana peel!" % body.player_name)
			get_tree().create_timer(2.5).timeout.connect(func(): if is_instance_valid(body): body.unfreeze())
			trap.queue_free()
	)

func spawn_vortex(pos: Vector3) -> void:
	add_game_log("🌀 [color=#b388ff]Black Hole Vortex activated![/color]")
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

# ── Events & Log ────────────────────────────────────────────────────────────
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
	add_game_log("You used [color=#ffe066]%s[/color]!" % item)

func _on_player_item_picked_up(item: String) -> void:
	add_game_log("You picked up [color=#69f0ae]%s[/color]! Press [E] to use." % item.to_upper())

func _on_item_button_pressed() -> void:
	if local_player:
		local_player.use_held_item()

func add_game_log(msg: String) -> void:
	game_log_lbl.append_text(msg + "\n")

# ── Single Item Slot UI Update ──────────────────────────────────────────────
func _update_item_slot(item_name: String) -> void:
	if item_name.is_empty():
		item_icon.text = "✖"
		item_name_lbl.text = "ITEM: NONE"
		item_btn.modulate = Color(0.7, 0.7, 0.7, 0.6)
	else:
		item_btn.modulate = Color(1.0, 1.0, 1.0, 1.0)
		match item_name:
			"speed":
				item_icon.text = "⚡"
				item_name_lbl.text = "[E] SPEED"
			"shield":
				item_icon.text = "🛡️"
				item_name_lbl.text = "[E] SHIELD"
			"heater":
				item_icon.text = "🔥"
				item_name_lbl.text = "[E] HEATER"
			"banana":
				item_icon.text = "🍌"
				item_name_lbl.text = "[E] BANANA"
			"vortex":
				item_icon.text = "🌀"
				item_name_lbl.text = "[E] VORTEX"

# ── HUD Update ──────────────────────────────────────────────────────────────
func _update_hud() -> void:
	var runners_count = 0
	var taggers_count = 0
	
	for child in status_container.get_children():
		child.queue_free()
	
	for p in player_nodes:
		if p.role == "tagger":
			taggers_count += 1
		else:
			if not p.is_frozen:
				runners_count += 1
		
		var row = HBoxContainer.new()
		var name_lbl = Label.new()
		name_lbl.text = p.player_name
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 13)
		
		var status_badge = Label.new()
		status_badge.add_theme_font_size_override("font_size", 13)
		if p.is_frozen:
			status_badge.text = "❄️ FROZEN"
			status_badge.modulate = Color(0.3, 0.9, 1.0)
		elif p.is_rescuing:
			status_badge.text = "🟡 RESCUING"
			status_badge.modulate = Color(1.0, 0.9, 0.2)
		elif p.role == "tagger":
			status_badge.text = "🔴 *TAGGER"
			status_badge.modulate = Color(1.0, 0.35, 0.35)
		else:
			status_badge.text = "🟢 RUNNER"
			status_badge.modulate = Color(0.4, 0.95, 0.4)
		
		row.add_child(name_lbl)
		row.add_child(status_badge)
		status_container.add_child(row)
	
	runners_count_lbl.text = str(runners_count)
	taggers_count_lbl.text = str(taggers_count)
	round_lbl.text = "ROUND %d / %d" % [current_round, max_rounds]
	
	if local_player:
		hp_bar.value = local_player.hp
		hp_lbl.text = "%d / 100" % local_player.hp

# ── Win / Loss & MVP Summary (Teacher's Card 4 Mockup) ──────────────────────
func _end_round(winner: String) -> void:
	is_game_active = false
	game_over_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if winner == "TAGGERS":
		taggers_score += 1
		game_over_title.text = "🔥 TAGGERS WIN ROUND! 🔥"
		game_over_title.modulate = Color(1.0, 0.4, 0.4)
	else:
		runners_score += 1
		game_over_title.text = "❄️ RUNNERS WIN ROUND! ❄️"
		game_over_title.modulate = Color(0.4, 0.9, 1.0)
	
	# Update match score
	score_lbl.text = "SCORE: Runners %d  -  Taggers %d" % [runners_score, taggers_score]
	
	# Calculate MVP
	var best_player: CharacterBody3D = null
	var highest_score = -1
	for p in player_nodes:
		var score = p.freeze_count * 2 + p.rescue_count * 2
		if score > highest_score:
			highest_score = score
			best_player = p
	
	if best_player:
		mvp_lbl.text = "👑 MVP: %s (%d Tags / %d Rescues)" % [best_player.player_name, best_player.freeze_count, best_player.rescue_count]
	else:
		mvp_lbl.text = "👑 MVP: Player 1 (You)"
	
	if current_round >= max_rounds:
		next_round_btn.text = "PLAY AGAIN"
	else:
		next_round_btn.text = "NEXT ROUND (%d)" % (current_round + 1)

func _on_next_round_pressed() -> void:
	current_round += 1
	if current_round > max_rounds:
		current_round = 1
		runners_score = 0
		taggers_score = 0
	
	round_time = 165.0
	is_game_active = true
	game_over_panel.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_spawn_match_players()

func _on_exit_to_menu_pressed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/3d/main_menu_3d.tscn")

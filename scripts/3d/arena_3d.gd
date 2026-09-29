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
	
	if Network and Network.is_online_game():
		# Online match
		role_btn.visible = false
		current_round = Network.current_round
		max_rounds = Network.max_rounds
		_connect_network_signals()
	else:
		# AI practice mode
		role_btn.visible = true
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
	
	if not Network or not Network.is_online_game():
		for i in range(3):
			_spawn_random_item()
	
	add_game_log("[color=#ffe066]Match started![/color] Round %d / %d" % [current_round, max_rounds])

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
	if not Network.chat_received.is_connected(func(msg): add_game_log(msg)):
		Network.chat_received.connect(func(msg): add_game_log(msg))

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

# ── Role Selection & Cycling (Practice Mode) ────────────────────────────────
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
			role_btn.text = "ROLE: TAGGER"
			role_btn.modulate = Color(1.0, 0.45, 0.45)
		"runner":
			role_btn.text = "ROLE: RUNNER"
			role_btn.modulate = Color(0.45, 1.0, 0.45)
		"random", _:
			role_btn.text = "ROLE: RANDOM"
			role_btn.modulate = Color(1.0, 0.9, 0.4)

# ── Spawning Players & Items ────────────────────────────────────────────────
func _spawn_match_players() -> void:
	for child in players_container.get_children():
		child.queue_free()
	player_nodes.clear()
	
	if Network and Network.is_online_game():
		_spawn_online_players()
		return
	
	# Offline Practice Mode (1 Local + 3 Bots)
	var spawn_positions = [
		Vector3(0, 0.5, 0),
		Vector3(-14, 0.5, -14),
		Vector3(14, 0.5, 14),
		Vector3(14, 0.5, -14)
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
	p1.position = spawn_positions[0]
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
	if items_container.get_child_count() >= 5:
		return
	
	var item_types = ["speed", "shield", "heater", "banana", "vortex", "tackle"]
	var selected = item_types.pick_random()
	
	var item = item_3d_scene.instantiate()
	item.position = Vector3(randf_range(-22, 22), 0.6, randf_range(-22, 22))
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
	lbl.text = "🍌 BANANA"
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

# ── Network Event Handlers ──────────────────────────────────────────────────
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
	
	if winner == "TAGGERS":
		game_over_title.text = "TAGGERS WIN ROUND!"
		game_over_title.modulate = Color(1.0, 0.4, 0.4)
	else:
		game_over_title.text = "RUNNERS WIN ROUND!"
		game_over_title.modulate = Color(0.4, 0.9, 1.0)
	
	score_lbl.text = "SCORE: Runners %d  -  Taggers %d" % [runners_score, taggers_score]
	
	if mvp and typeof(mvp) == TYPE_DICTIONARY:
		mvp_lbl.text = "MVP: %s (%d Tags / %d Rescues)" % [mvp.get("name", "Player"), mvp.get("freezeCount", 0), mvp.get("rescueCount", 0)]
	else:
		mvp_lbl.text = "MVP: Match Complete"
	
	if Network.is_host:
		next_round_btn.visible = true
		next_round_btn.text = "PLAY AGAIN" if is_match_over else "NEXT ROUND (%d)" % (current_round + 1)
	else:
		next_round_btn.visible = false

# ── Events & Log (Practice / Local) ─────────────────────────────────────────
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
		item_icon.text = "-"
		item_name_lbl.text = "ITEM: NONE"
		item_btn.modulate = Color(0.7, 0.7, 0.7, 0.6)
	else:
		item_btn.modulate = Color(1.0, 1.0, 1.0, 1.0)
		match item_name:
			"speed":
				item_icon.text = "SPD"
				item_name_lbl.text = "[E] SPEED"
			"shield":
				item_icon.text = "SHD"
				item_name_lbl.text = "[E] SHIELD"
			"heater":
				item_icon.text = "HTR"
				item_name_lbl.text = "[E] HEATER"
			"banana":
				item_icon.text = "BAN"
				item_name_lbl.text = "[E] BANANA"
			"vortex":
				item_icon.text = "VTX"
				item_name_lbl.text = "[E] VORTEX"
			"tackle":
				item_icon.text = "TCK"
				item_name_lbl.text = "[E] TACKLE (1.5x)"

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
			status_badge.text = "[FROZEN]"
			status_badge.modulate = Color(0.3, 0.9, 1.0)
		elif p.is_rescuing:
			status_badge.text = "[RESCUING]"
			status_badge.modulate = Color(1.0, 0.9, 0.2)
		elif p.role == "tagger":
			status_badge.text = "[TAGGER]"
			status_badge.modulate = Color(1.0, 0.35, 0.35)
		else:
			status_badge.text = "[RUNNER]"
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

# ── Win / Loss & MVP Summary (Offline / Practice Mode) ──────────────────────
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
		game_over_title.modulate = Color(0.4, 0.9, 1.0)
	
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
	
	if current_round >= max_rounds:
		next_round_btn.text = "PLAY AGAIN"
	else:
		next_round_btn.text = "NEXT ROUND (%d)" % (current_round + 1)

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
	_spawn_match_players()

func _on_exit_to_menu_pressed() -> void:
	if Network and Network.is_online_game():
		Network.disconnect_from_server()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/3d/main_menu_3d.tscn")

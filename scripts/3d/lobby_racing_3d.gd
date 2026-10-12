extends Control

# Constants for Among Us-style room codes (No ambiguous 0, O, 1, I)
const CODE_CHARS: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

const TEX_START_GAME = preload("res://assets/ui/buttons/btn_start_game.png")
const TEX_READY = preload("res://assets/ui/buttons/btn_ready.png")
const TEX_WAITING = preload("res://assets/ui/buttons/btn_waiting.png")

# -- Views -------------------------------------------------------------------
@onready var browser_view: Control = $BrowserView
@onready var room_view: Control = $RoomView

# -- Browser View Nodes ------------------------------------------------------
@onready var player_name_input: LineEdit = $BrowserView/PlayerNameContainer/PlayerNameInput
@onready var room_list_vbox: VBoxContainer = $BrowserView/HBox/RoomListCard/Scroll/RoomList
@onready var refresh_btn: TextureButton = $BrowserView/HBox/RoomListCard/HeaderBox/RefreshBtn
@onready var create_room_name_input: LineEdit = $BrowserView/HBox/CreateRoomCard/RoomNameInput
@onready var create_private_check: CheckBox = $BrowserView/HBox/CreateRoomCard/PrivateCheck
@onready var create_room_btn: TextureButton = $BrowserView/HBox/CreateRoomCard/CreateBtn
@onready var join_code_input: LineEdit = $BrowserView/HBox/JoinCodeCard/CodeInput
@onready var join_code_btn: TextureButton = $BrowserView/HBox/JoinCodeCard/JoinCodeBtn
@onready var code_error_lbl: Label = $BrowserView/HBox/JoinCodeCard/ErrorLabel
@onready var back_to_menu_btn: TextureButton = $BackButton

# -- In-Room Waiting Lobby Nodes (Host & Players) -----------------------------
@onready var room_header_lbl: Label = $RoomView/Header/RoomTitle
@onready var room_code_lbl: Label = $RoomView/Header/CodeBox/CodeLabel
@onready var copy_code_btn: TextureButton = $RoomView/Header/CodeBox/CopyBtn
@onready var player_list_vbox: VBoxContainer = $RoomView/HBox/PlayerListCard/Scroll/PlayerList
@onready var player_count_header: Label = $RoomView/HBox/PlayerListCard/Header

# Host Live Customization Controls
@onready var host_settings_title: Label = $RoomView/HBox/HostSettingsCard/SettingsTitle
@onready var max_players_slider: HSlider = $RoomView/HBox/HostSettingsCard/MaxPlayersRow/Slider
@onready var max_players_val_lbl: Label = $RoomView/HBox/HostSettingsCard/MaxPlayersRow/ValLabel
@onready var rounds_opt: OptionButton = $RoomView/HBox/HostSettingsCard/RoundsRow/RoundsOpt
@onready var host_private_check: CheckBox = $RoomView/HBox/HostSettingsCard/PrivateRow/PrivateCheck
@onready var map_preview_lbl: Label = $RoomView/HBox/HostSettingsCard/MapPreview/MapName
@onready var map_preview_img: TextureRect = $RoomView/HBox/HostSettingsCard/MapPreview/MapImg
@onready var map_grid: VBoxContainer = $RoomView/HBox/MapSelectionCard/Grid

# Action Buttons
@onready var action_btn: TextureButton = $RoomView/BottomBar/ActionBtn
@onready var leave_btn: TextureButton = $RoomView/BottomBar/LeaveBtn

# -- Dynamic Room State ------------------------------------------------------
static var active_rooms: Dictionary = {}
var current_room_code: String = ""
var is_host: bool = false
var is_ready: bool = false
var my_player_name: String = "Player 1"
var selected_map: String = "VOID PARKOUR"
var is_dragging_slider: bool = false
var user_badge_lbl: Label = null
var add_bot_btn: Button = null

func _update_user_badge() -> void:
	if not user_badge_lbl:
		return
	if Network and not Network.current_user.is_empty():
		var lv = int(Network.current_user.get("level", 1))
		var coins = int(Network.current_user.get("coins", 0))
		user_badge_lbl.text = "★ Lv. %d  |  🪙 %d Coins" % [lv, coins]
	else:
		user_badge_lbl.text = "★ Lv. 1  |  🪙 50 Coins"

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	code_error_lbl.text = ""
	
	if BGMManager:
		BGMManager.play_menu_bgm()
	
	if Network:
		Network.selected_game_mode = "racing"
		Network.selected_map = "VOID PARKOUR"
		my_player_name = Network.my_player_name
	selected_map = "VOID PARKOUR"

	player_name_input.text = my_player_name
	player_name_input.text_changed.connect(_on_player_name_changed)
	
	user_badge_lbl = Label.new()
	user_badge_lbl.add_theme_font_size_override("font_size", 12)
	user_badge_lbl.modulate = Color(1.0, 0.88, 0.3)
	if player_name_input and player_name_input.get_parent():
		player_name_input.get_parent().add_child(user_badge_lbl)
	_update_user_badge()
	if Network:
		Network.profile_updated.connect(func(_u): _update_user_badge())
	
	# Setup rounds options
	rounds_opt.clear()
	rounds_opt.add_item("1 Round", 1)
	rounds_opt.add_item("3 Rounds", 3)
	rounds_opt.add_item("5 Rounds", 5)
	rounds_opt.selected = 1 # Default 3 rounds
	
	# Connect Browser events
	create_room_btn.pressed.connect(_on_create_room_pressed)
	join_code_btn.pressed.connect(_on_join_by_code_pressed)
	back_to_menu_btn.pressed.connect(_on_back_to_menu_pressed)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	
	for btn in [create_room_btn, join_code_btn, back_to_menu_btn, refresh_btn, action_btn, leave_btn]:
		if btn:
			btn.mouse_entered.connect(func(): btn.modulate = Color(1.15, 1.15, 1.15))
			btn.mouse_exited.connect(func(): btn.modulate = Color.WHITE)
	
	# Connect Room events
	max_players_slider.drag_started.connect(func(): is_dragging_slider = true)
	max_players_slider.drag_ended.connect(func(_val_changed): is_dragging_slider = false)
	max_players_slider.value_changed.connect(_on_max_players_changed)
	rounds_opt.item_selected.connect(_on_rounds_selected)
	host_private_check.toggled.connect(_on_host_private_toggled)
	copy_code_btn.pressed.connect(_on_copy_code_pressed)
	action_btn.pressed.connect(_on_action_pressed)
	leave_btn.pressed.connect(_on_leave_room_pressed)
	
	# Adjust player_count_header and inject Add Bot button for room host
	player_count_header.anchor_left = 0.0
	player_count_header.anchor_right = 0.0
	player_count_header.offset_left = 16.0
	player_count_header.offset_right = 200.0
	player_count_header.offset_top = 16.0
	player_count_header.offset_bottom = 40.0
	player_count_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	
	add_bot_btn = Button.new()
	add_bot_btn.text = "+ BOT 🤖"
	add_bot_btn.tooltip_text = "Add an AI bot player to this race"
	add_bot_btn.focus_mode = Control.FOCUS_NONE
	add_bot_btn.anchor_left = 1.0
	add_bot_btn.anchor_right = 1.0
	add_bot_btn.offset_left = -112.0
	add_bot_btn.offset_top = 13.0
	add_bot_btn.offset_right = -16.0
	add_bot_btn.offset_bottom = 41.0
	add_bot_btn.add_theme_font_size_override("font_size", 12)
	
	var bot_btn_sb = StyleBoxFlat.new()
	bot_btn_sb.bg_color = Color(0.10, 0.32, 0.52, 0.9)
	bot_btn_sb.border_color = Color(0.3, 0.85, 1.0, 0.95)
	bot_btn_sb.set_border_width_all(1)
	bot_btn_sb.set_corner_radius_all(6)
	add_bot_btn.add_theme_stylebox_override("normal", bot_btn_sb)
	
	var bot_btn_hover = StyleBoxFlat.new()
	bot_btn_hover.bg_color = Color(0.18, 0.48, 0.78, 1.0)
	bot_btn_hover.border_color = Color(0.6, 0.95, 1.0, 1.0)
	bot_btn_hover.set_border_width_all(1)
	bot_btn_hover.set_corner_radius_all(6)
	add_bot_btn.add_theme_stylebox_override("hover", bot_btn_hover)
	
	var bot_btn_dis = StyleBoxFlat.new()
	bot_btn_dis.bg_color = Color(0.15, 0.18, 0.22, 0.5)
	bot_btn_dis.border_color = Color(0.35, 0.4, 0.45, 0.4)
	bot_btn_dis.set_border_width_all(1)
	bot_btn_dis.set_corner_radius_all(6)
	add_bot_btn.add_theme_stylebox_override("disabled", bot_btn_dis)
	
	add_bot_btn.pressed.connect(_on_add_bot_pressed)
	$RoomView/HBox/PlayerListCard.add_child(add_bot_btn)
	
	_setup_map_grid_buttons()
	_connect_network_signals()
	
	# Connect to backend WebSocket server if not connected
	if Network and not Network.is_connected_to_server:
		Network.connect_to_server()
	
	# If returning from game while still in a room, restore Room View
	if Network and not Network.current_room_code.is_empty():
		current_room_code = Network.current_room_code
		is_host = Network.is_host
		is_ready = is_host
		if not Network.room_data.is_empty():
			active_rooms[current_room_code] = {
				"name": Network.room_data.get("name", "Room " + current_room_code),
				"code": current_room_code,
				"host": Network.room_data.get("hostName", "Host"),
				"host_id": Network.room_data.get("hostId", ""),
				"players": Network.room_data.get("players", []).duplicate(),
				"max_players": int(Network.room_data.get("maxPlayers", 6)),
				"map": "VOID PARKOUR",
				"gameMode": "racing",
				"rounds": int(Network.room_data.get("rounds", 3)),
				"is_private": bool(Network.room_data.get("isPrivate", false))
			}
		_show_room_view()
	elif Network and Network.auto_create_test_lobby:
		Network.auto_create_test_lobby = false
		_start_immediate_test_room()
	else:
		_show_browser_view()

func _start_immediate_test_room() -> void:
	var test_code = generate_unique_code()
	current_room_code = test_code
	is_host = true
	is_ready = true
	
	if Network:
		Network.current_room_code = test_code
		Network.is_host = true
		Network.is_solo_mode = false
		Network.selected_game_mode = "racing"
		Network.selected_map = "VOID PARKOUR"
	
	var p_id = Network.my_peer_id if (Network and not Network.my_peer_id.is_empty()) else "host_local"
	var p_lv = int(Network.current_user.get("level", 1)) if Network else 1
	var p_coins = int(Network.current_user.get("coins", 50)) if Network else 50
	var host_player = {
		"id": p_id,
		"name": my_player_name,
		"isHost": true,
		"isReady": true,
		"isInGame": false,
		"isBot": false,
		"level": p_lv,
		"coins": p_coins
	}
	
	active_rooms[current_room_code] = {
		"name": "Race Room " + current_room_code,
		"code": current_room_code,
		"host": my_player_name,
		"host_id": p_id,
		"max_players": 8,
		"rounds": 3,
		"map": "VOID PARKOUR",
		"gameMode": "racing",
		"is_private": false,
		"phase": "lobby",
		"players": [host_player]
	}
	
	if Network:
		Network.room_data = active_rooms[current_room_code]
	
	_show_room_view()
	
	if Network:
		if Network.is_connected_to_server:
			Network.create_room("Race Room " + current_room_code, 8, 3, "VOID PARKOUR", false, "racing")
		else:
			var conn_holder: Array = []
			var cb = func():
				if Network and Network.connected_to_server.is_connected(conn_holder[0]):
					Network.connected_to_server.disconnect(conn_holder[0])
				if current_room_code == test_code and is_host and room_view.visible:
					Network.create_room("Race Room " + test_code, 8, 3, "VOID PARKOUR", false, "racing")
			conn_holder.append(cb)
			Network.connected_to_server.connect(cb)

func _on_refresh_pressed() -> void:
	if Network:
		print("[LobbyRacing3D] Refresh button clicked: fetching racing rooms")
		Network.fetch_public_rooms()

# -- Network Signals Connection ----------------------------------------------
func _connect_network_signals() -> void:
	if not Network:
		return
	
	if not Network.room_created.is_connected(_on_network_room_created):
		Network.room_created.connect(_on_network_room_created)
	if not Network.room_joined.is_connected(_on_network_room_joined):
		Network.room_joined.connect(_on_network_room_joined)
	if not Network.player_joined.is_connected(_on_network_player_joined):
		Network.player_joined.connect(_on_network_player_joined)
	if not Network.player_left.is_connected(_on_network_player_left):
		Network.player_left.connect(_on_network_player_left)
	if not Network.host_changed.is_connected(_on_network_host_changed):
		Network.host_changed.connect(_on_network_host_changed)
	if not Network.settings_updated.is_connected(_on_network_settings_updated):
		Network.settings_updated.connect(_on_network_settings_updated)
	if not Network.player_name_updated.is_connected(_on_network_player_name_updated):
		Network.player_name_updated.connect(_on_network_player_name_updated)
	if not Network.player_ready_updated.is_connected(_on_network_player_ready_updated):
		Network.player_ready_updated.connect(_on_network_player_ready_updated)
	if not Network.public_rooms_updated.is_connected(_on_network_public_rooms_updated):
		Network.public_rooms_updated.connect(_on_network_public_rooms_updated)
	if not Network.round_started.is_connected(_on_network_round_started):
		Network.round_started.connect(_on_network_round_started)
	if not Network.returned_to_lobby.is_connected(_on_network_returned_to_lobby):
		Network.returned_to_lobby.connect(_on_network_returned_to_lobby)
	if not Network.player_state_updated.is_connected(_on_network_player_state_updated):
		Network.player_state_updated.connect(_on_network_player_state_updated)
	if not Network.player_kicked.is_connected(_on_network_player_kicked):
		Network.player_kicked.connect(_on_network_player_kicked)
	if not Network.connection_error.is_connected(_on_network_error):
		Network.connection_error.connect(_on_network_error)
	if not Network.connected_to_server.is_connected(_on_network_connected):
		Network.connected_to_server.connect(_on_network_connected)

func _on_player_name_changed(new_text: String) -> void:
	var clean = new_text.strip_edges()
	if clean.is_empty():
		clean = "Player " + str(randi_range(1, 99))
	my_player_name = clean
	if Network:
		Network.my_player_name = clean
		if Network.is_connected_to_server:
			Network.set_player_name(clean)

func _on_network_connected() -> void:
	code_error_lbl.text = ""
	if browser_view and browser_view.visible and Network:
		Network.fetch_public_rooms()

# -- Room Code Generator (Local Fallback) ------------------------------------
func generate_unique_code() -> String:
	while true:
		var code = ""
		for i in range(6):
			code += CODE_CHARS[randi() % CODE_CHARS.length()]
		if not active_rooms.has(code):
			return code
	return "RACE01"

# -- View Switching ----------------------------------------------------------
func _show_browser_view() -> void:
	browser_view.visible = true
	room_view.visible = false
	back_to_menu_btn.visible = true
	code_error_lbl.text = ""
	_update_room_list_browser()
	if Network and Network.is_connected_to_server:
		Network.fetch_public_rooms()

func _show_room_view() -> void:
	browser_view.visible = false
	room_view.visible = true
	back_to_menu_btn.visible = false
	_update_room_lobby_ui()

# -- Browser UI --------------------------------------------------------------
func _update_room_list_browser() -> void:
	for child in room_list_vbox.get_children():
		child.queue_free()
	
	if active_rooms.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "(No racing rooms online yet)\nCreate a room or enter PIN to join"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.modulate = Color(0.7, 0.8, 0.9, 0.7)
		empty_lbl.add_theme_font_size_override("font_size", 13)
		room_list_vbox.add_child(empty_lbl)
		return
	
	for code in active_rooms:
		var r = active_rooms[code]
		var pin_code: String = str(r.get("code", code)).to_upper()
		var r_name: String = str(r.get("name", "Room"))
		var p_count: int = r.get("players", []).size()
		var max_p: int = int(r.get("max_players", 8))
		var map_name: String = str(r.get("map", "VOID PARKOUR"))
		var is_full: bool = (p_count >= max_p)
		var in_progress: bool = bool(r.get("has_started", false))
		
		var item_btn = Button.new()
		item_btn.custom_minimum_size = Vector2(0, 52)
		item_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		
		# Cyber card styling
		var sb_normal = StyleBoxFlat.new()
		sb_normal.bg_color = Color(0.06, 0.12, 0.22, 0.9)
		sb_normal.border_color = Color(0.25, 0.65, 0.95, 0.5)
		sb_normal.set_border_width_all(1)
		sb_normal.set_corner_radius_all(6)
		sb_normal.content_margin_left = 10
		sb_normal.content_margin_right = 10
		sb_normal.content_margin_top = 6
		sb_normal.content_margin_bottom = 6
		item_btn.add_theme_stylebox_override("normal", sb_normal)
		
		var sb_hover = sb_normal.duplicate()
		sb_hover.bg_color = Color(0.10, 0.20, 0.36, 0.95)
		sb_hover.border_color = Color(0.4, 0.85, 1.0, 0.9)
		item_btn.add_theme_stylebox_override("hover", sb_hover)
		
		var sb_pressed = sb_normal.duplicate()
		sb_pressed.bg_color = Color(0.04, 0.08, 0.16, 0.95)
		item_btn.add_theme_stylebox_override("pressed", sb_pressed)
		
		var sb_disabled = sb_normal.duplicate()
		sb_disabled.bg_color = Color(0.05, 0.08, 0.14, 0.5)
		sb_disabled.border_color = Color(0.3, 0.4, 0.5, 0.3)
		item_btn.add_theme_stylebox_override("disabled", sb_disabled)
		
		var status_str = ""
		if is_full:
			status_str = " [FULL]"
		elif in_progress:
			status_str = " [RACING - JOIN TO WAIT]"
		
		# Public rooms display room name and info
		item_btn.text = "%s%s\nRacers: %d/%d  |  %s" % [
			r_name, status_str, p_count, max_p, map_name
		]
		item_btn.add_theme_font_size_override("font_size", 12)
		
		var is_kicked = Network and Network.kicked_rooms.has(pin_code)
		if is_full or is_kicked:
			item_btn.disabled = true
			if is_kicked:
				item_btn.text += "  [KICKED]"
		else:
			item_btn.pressed.connect(func():
				_join_room_by_code(pin_code)
			)
		
		room_list_vbox.add_child(item_btn)

# -- Create Room (1 Player = 1 Room Only) ------------------------------------
func _on_create_room_pressed() -> void:
	if not current_room_code.is_empty() and active_rooms.has(current_room_code):
		return
	
	var r_name = create_room_name_input.text.strip_edges()
	if r_name.is_empty():
		r_name = "Race " + str(randi_range(101, 999))
	
	var is_priv = create_private_check.button_pressed
	if Network and Network.is_connected_to_server:
		code_error_lbl.text = "Creating racing room on server..."
		Network.create_room(r_name, 8, 3, "VOID PARKOUR", is_priv, "racing")
	else:
		code_error_lbl.text = "Connecting to server... Please wait a moment."
		if Network:
			Network.connect_to_server()

# -- Join by Code (Among Us Style) -------------------------------------------
func _on_join_by_code_pressed() -> void:
	var code = join_code_input.text.strip_edges().to_upper()
	if code.length() != 6:
		code_error_lbl.text = "Room code must be 6 characters"
		return
	
	_join_room_by_code(code)

func _join_room_by_code(code: String) -> void:
	var clean = code.to_upper().strip_edges()
	if Network and Network.kicked_rooms.has(clean):
		code_error_lbl.text = "You have been kicked from room \"%s\" and cannot rejoin." % clean
		code_error_lbl.modulate = Color(1.0, 0.35, 0.35)
		return
	if Network and Network.is_connected_to_server:
		code_error_lbl.text = "Connecting to room " + clean + "..."
		Network.join_room(clean)
	else:
		code_error_lbl.text = "Connecting to server... Please wait a moment."
		if Network:
			Network.connect_to_server()

# -- Network Handlers --------------------------------------------------------
func _on_network_room_created(data: Dictionary) -> void:
	code_error_lbl.text = ""
	current_room_code = str(data.get("code", ""))
	is_host = true
	is_ready = true
	
	var r_players = []
	for p in data.get("players", []):
		r_players.append(p)
	
	active_rooms[current_room_code] = {
		"name": str(data.get("name", "Race Room")),
		"code": current_room_code,
		"host": my_player_name,
		"max_players": int(data.get("maxPlayers", 8)),
		"rounds": int(data.get("rounds", 3)),
		"map": "VOID PARKOUR",
		"gameMode": "racing",
		"is_private": bool(data.get("isPrivate", false)),
		"phase": "lobby",
		"players": r_players
	}
	_show_room_view()

func _on_network_room_joined(data: Dictionary) -> void:
	code_error_lbl.text = ""
	current_room_code = str(data.get("code", ""))
	is_host = bool(data.get("isHost", false))
	is_ready = false
	
	var r_players = []
	for p in data.get("players", []):
		r_players.append(p)
	
	active_rooms[current_room_code] = {
		"name": str(data.get("name", "Race Room")),
		"code": current_room_code,
		"host": "Host",
		"max_players": int(data.get("maxPlayers", 8)),
		"rounds": int(data.get("rounds", 3)),
		"map": "VOID PARKOUR",
		"gameMode": "racing",
		"is_private": bool(data.get("isPrivate", false)),
		"phase": str(data.get("phase", "lobby")),
		"players": r_players
	}
	_show_room_view()

func _on_add_bot_pressed() -> void:
	if not is_host:
		return
	if not active_rooms.has(current_room_code):
		return
	var r = active_rooms[current_room_code]
	if r["players"].size() >= r["max_players"]:
		return
	if Network and Network.is_connected_to_server:
		Network.add_bot()
	else:
		var bot_names = ["Racer Alpha", "Speedy Bot", "Turbo Bot", "Nitro Bot", "Cyber Racer"]
		var existing_count = r["players"].size()
		var b_name = bot_names[existing_count % bot_names.size()]
		r["players"].append({
			"id": "bot_" + str(randi_range(100, 999)),
			"name": b_name,
			"isHost": false,
			"isReady": true,
			"isInGame": false,
			"isBot": true,
			"level": 1,
			"coins": 0
		})
		_update_room_lobby_ui()

func _on_network_player_joined(data: Dictionary) -> void:
	if active_rooms.has(current_room_code):
		var r = active_rooms[current_room_code]
		r["players"].append({
			"id": str(data.get("id", "")),
			"name": str(data.get("name", "New Racer")),
			"isHost": bool(data.get("isHost", false)),
			"isReady": bool(data.get("isReady", false)),
			"isInGame": bool(data.get("isInGame", false)),
			"isBot": bool(data.get("isBot", false)),
			"level": int(data.get("level", 1))
		})
		_update_room_lobby_ui()

func _on_network_returned_to_lobby(data: Dictionary) -> void:
	print("[LobbyRacing3D] Room returned to lobby: ", data.get("code", ""))
	current_room_code = str(data.get("code", current_room_code))
	is_host = (Network and Network.my_peer_id == str(data.get("hostId", ""))) or (Network and Network.is_host)
	is_ready = is_host
	
	var r_players = []
	for p in data.get("players", []):
		r_players.append(p)
	
	active_rooms[current_room_code] = {
		"name": str(data.get("name", "Race Room")),
		"code": current_room_code,
		"host": str(data.get("hostName", "Host")),
		"host_id": str(data.get("hostId", "")),
		"max_players": int(data.get("maxPlayers", 8)),
		"rounds": int(data.get("rounds", 3)),
		"map": "VOID PARKOUR",
		"gameMode": "racing",
		"is_private": bool(data.get("isPrivate", false)),
		"phase": "lobby",
		"players": r_players
	}
	_update_room_lobby_ui()

func _on_network_player_state_updated(data: Dictionary) -> void:
	if active_rooms.has(current_room_code):
		var r = active_rooms[current_room_code]
		if data.has("players") and typeof(data["players"]) == TYPE_ARRAY:
			r["players"] = data["players"].duplicate()
		else:
			var p_id = str(data.get("id", ""))
			for p in r["players"]:
				if typeof(p) == TYPE_DICTIONARY and str(p.get("id")) == p_id:
					if data.has("isInGame"): p["isInGame"] = bool(data["isInGame"])
					if data.has("isReady"): p["isReady"] = bool(data["isReady"])
					break
		_update_room_lobby_ui()

func _on_network_player_left(data: Dictionary) -> void:
	if active_rooms.has(current_room_code):
		var r = active_rooms[current_room_code]
		var p_id = str(data.get("id", ""))
		var p_name = str(data.get("name", ""))
		for i in range(r["players"].size() - 1, -1, -1):
			var item = r["players"][i]
			var match_found = false
			if typeof(item) == TYPE_DICTIONARY:
				if (!p_id.is_empty() and str(item.get("id")) == p_id) or str(item.get("name")) == p_name:
					match_found = true
			elif typeof(item) == TYPE_STRING:
				if item.begins_with(p_name):
					match_found = true
			if match_found:
				r["players"].remove_at(i)
				break
		if Network and Network.is_host:
			is_host = true
			is_ready = true
		_update_room_lobby_ui()

func _on_network_host_changed(new_host_id: String) -> void:
	print("[LobbyRacing3D] Host changed to: ", new_host_id, " (my ID: ", Network.my_peer_id, ")")
	is_host = (Network.my_peer_id == new_host_id)
	if is_host:
		is_ready = true
		if code_error_lbl:
			code_error_lbl.text = "You are now the HOST!"
			code_error_lbl.modulate = Color(1.0, 0.85, 0.2)
	
	if active_rooms.has(current_room_code):
		var r = active_rooms[current_room_code]
		r["host_id"] = new_host_id
		if Network and Network.room_data.has("players") and typeof(Network.room_data["players"]) == TYPE_ARRAY:
			r["players"] = Network.room_data["players"].duplicate()
		else:
			for p in r["players"]:
				if typeof(p) == TYPE_DICTIONARY:
					var is_p_host = (str(p.get("id")) == new_host_id)
					p["isHost"] = is_p_host
					if is_p_host:
						p["isReady"] = true
						r["host"] = str(p.get("name", "Host"))
	
	_update_room_lobby_ui()

func _on_network_settings_updated(data: Dictionary) -> void:
	if active_rooms.has(current_room_code):
		var r = active_rooms[current_room_code]
		if data.has("maxPlayers"): r["max_players"] = int(data["maxPlayers"])
		if data.has("rounds"): r["rounds"] = int(data["rounds"])
		if data.has("map"): r["map"] = str(data["map"])
		if data.has("isPrivate"): r["is_private"] = bool(data["isPrivate"])
		_update_room_lobby_ui()

func _on_network_player_name_updated(_data: Dictionary) -> void:
	if active_rooms.has(current_room_code):
		var r = active_rooms[current_room_code]
		if Network and Network.room_data.has("players"):
			r["players"] = Network.room_data["players"].duplicate()
		_update_room_lobby_ui()

func _on_network_player_ready_updated(data: Dictionary) -> void:
	if active_rooms.has(current_room_code):
		var r = active_rooms[current_room_code]
		if data.has("players") and typeof(data["players"]) == TYPE_ARRAY:
			r["players"] = data["players"].duplicate()
		else:
			var p_id = str(data.get("id", ""))
			var p_ready = bool(data.get("isReady", false))
			for p in r["players"]:
				if typeof(p) == TYPE_DICTIONARY and str(p.get("id")) == p_id:
					p["isReady"] = p_ready
					break
		if not is_host and Network:
			for p in r["players"]:
				if typeof(p) == TYPE_DICTIONARY and str(p.get("id")) == Network.player_id:
					is_ready = bool(p.get("isReady", false))
					break
		_update_room_lobby_ui()

func _on_network_public_rooms_updated(rooms: Array) -> void:
	# Update active_rooms from server REST query: ONLY RACING ROOMS
	var new_dict: Dictionary = {}
	for r in rooms:
		if bool(r.get("isPrivate", false)):
			continue
		var g_mode = str(r.get("gameMode", "")).to_lower()
		var map_name_str = str(r.get("map", "")).to_upper()
		# Only include rooms configured for Racing / Void Parkour
		if g_mode != "racing" and not map_name_str.contains("VOID") and not map_name_str.contains("PARKOUR"):
			continue
		var code = str(r.get("code", "")).to_upper()
		new_dict[code] = {
			"name": str(r.get("name", "Race Room")),
			"code": code,
			"host": "Host",
			"max_players": int(r.get("maxPlayers", 8)),
			"rounds": int(r.get("rounds", 3)),
			"map": "VOID PARKOUR",
			"gameMode": "racing",
			"players": range(int(r.get("playersCount", 1))),
			"has_started": bool(r.get("hasStarted", false))
		}
	if browser_view.visible:
		active_rooms = new_dict
		_update_room_list_browser()

func _on_network_round_started(_data: Dictionary) -> void:
	get_tree().change_scene_to_file("res://scenes/3d/arena_3d.tscn")

func _on_network_error(msg: String) -> void:
	code_error_lbl.text = msg
	code_error_lbl.modulate = Color(1.0, 0.35, 0.35)
	if room_view.visible:
		player_count_header.text = msg.to_upper()
		player_count_header.modulate = Color(1.0, 0.35, 0.35)
		var t = get_tree().create_timer(3.5)
		t.timeout.connect(func():
			if is_instance_valid(player_count_header) and active_rooms.has(current_room_code):
				var cr = active_rooms[current_room_code]
				player_count_header.text = "RACERS (%d / %d)" % [cr["players"].size(), cr["max_players"]]
				player_count_header.modulate = Color(0.4, 0.85, 1.0)
		)

func _on_network_player_kicked(reason: String) -> void:
	print("[LobbyRacing3D] Kicked from room: ", reason)
	current_room_code = ""
	is_host = false
	is_ready = false
	active_rooms.clear()
	_show_browser_view()
	code_error_lbl.text = reason if not reason.is_empty() else "You were kicked by the room host."
	code_error_lbl.modulate = Color(1.0, 0.4, 0.4)

func _on_kick_player_pressed(target_id: String, target_name: String) -> void:
	if not is_host:
		return
	print("[LobbyRacing3D] Host kicking racer: ", target_name, " (", target_id, ")")
	if Network and Network.is_connected_to_server:
		Network.kick_player(target_id)
	else:
		if active_rooms.has(current_room_code):
			var r = active_rooms[current_room_code]
			for i in range(r["players"].size() - 1, -1, -1):
				var p = r["players"][i]
				if typeof(p) == TYPE_DICTIONARY and str(p.get("id")) == target_id:
					r["players"].remove_at(i)
					break
			_update_room_lobby_ui()

# -- In-Room UI & Customization ----------------------------------------------
func _update_room_lobby_ui() -> void:
	if not active_rooms.has(current_room_code):
		_show_browser_view()
		return
	
	var r: Dictionary = active_rooms[current_room_code]
	var room_phase = str(r.get("phase", "lobby"))
	
	# Header
	room_header_lbl.text = r["name"].to_upper()
	room_code_lbl.text = r["code"]
	if room_phase == "playing":
		player_count_header.text = "RACERS (%d / %d)  [🏁 IN PROGRESS]" % [r["players"].size(), r["max_players"]]
		player_count_header.modulate = Color(1.0, 0.85, 0.3)
	else:
		player_count_header.text = "RACERS (%d / %d)" % [r["players"].size(), r["max_players"]]
		player_count_header.modulate = Color(0.4, 0.85, 1.0)
	
	# Player List
	_update_player_slots(r)
	
	# Host Customization Controls
	if not is_dragging_slider:
		max_players_slider.set_value_no_signal(r["max_players"])
	max_players_val_lbl.text = "%d Players" % r["max_players"]
	map_preview_lbl.text = "TRACK: VOID PARKOUR"
	_update_map_preview_image("VOID PARKOUR")
	_update_map_selection_highlight("VOID PARKOUR")
	
	for child in map_grid.get_children():
		if child is Button:
			child.disabled = not is_host
	
	max_players_slider.editable = is_host
	rounds_opt.disabled = not is_host
	for idx in range(rounds_opt.item_count):
		if rounds_opt.get_item_id(idx) == r["rounds"]:
			rounds_opt.selected = idx
			break
	host_private_check.set_pressed_no_signal(bool(r.get("is_private", false)))
	host_private_check.disabled = not is_host
	host_settings_title.text = "HOST SETTINGS" if is_host else "ROOM SETTINGS (Host only)"
	
	# Update Add Bot Button
	if add_bot_btn:
		add_bot_btn.visible = is_host
		if is_host:
			var is_full = r["players"].size() >= r["max_players"]
			add_bot_btn.disabled = is_full
			add_bot_btn.modulate = Color(0.6, 0.6, 0.6, 0.6) if is_full else Color(1.0, 1.0, 1.0, 1.0)
	
	# Action Button
	if Network and Network.is_host:
		is_host = true

	if is_host:
		action_btn.texture_normal = TEX_START_GAME
		action_btn.disabled = false
		var all_ready = true
		for p in r["players"]:
			var p_is_host = false
			var p_is_ready = false
			var p_is_bot = false
			if typeof(p) == TYPE_DICTIONARY:
				var pid = str(p.get("id", ""))
				p_is_host = bool(p.get("isHost", false)) or (Network and pid == Network.my_peer_id)
				p_is_ready = bool(p.get("isReady", false))
				p_is_bot = bool(p.get("isBot", false))
			if not p_is_host and not p_is_ready and not p_is_bot:
				all_ready = false
				break
		if all_ready:
			action_btn.modulate = Color(1.0, 1.0, 1.0, 1.0)
		else:
			action_btn.modulate = Color(0.65, 0.65, 0.65, 0.75)
	else:
		action_btn.texture_normal = TEX_WAITING if is_ready else TEX_READY
		action_btn.disabled = false
		action_btn.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _update_player_slots(r: Dictionary) -> void:
	for child in player_list_vbox.get_children():
		child.queue_free()
	
	for i in range(r["max_players"]):
		var slot_panel = PanelContainer.new()
		var sb = StyleBoxFlat.new()
		sb.set_corner_radius_all(8)
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		
		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_top", 6)
		margin.add_theme_constant_override("margin_bottom", 6)
		
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		
		var icon_lbl = Label.new()
		var name_lbl = Label.new()
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 13)
		
		var status_badge = Label.new()
		status_badge.add_theme_font_size_override("font_size", 11)
		
		var is_occupied = (i < r["players"].size())
		var p_id = ""
		var p_name = ""
		var p_is_host = false
		var p_is_ready = false
		var p_in_game = false
		var is_bot = false
		
		if is_occupied:
			var item = r["players"][i]
			var p_level: int = 1
			if typeof(item) == TYPE_DICTIONARY:
				p_id = str(item.get("id", ""))
				p_name = str(item.get("name", "Player %d" % (i + 1)))
				p_is_host = bool(item.get("isHost", i == 0))
				p_is_ready = bool(item.get("isReady", false))
				p_in_game = bool(item.get("isInGame", false))
				p_level = int(item.get("level", 1))
				is_bot = bool(item.get("isBot", false))
			else:
				p_name = str(item)
				p_is_host = (i == 0)
				p_is_ready = false
				p_in_game = false
				p_level = 1
				is_bot = false
			
			# Clean up any leftover duplicate "(Host)"
			while p_name.ends_with("(Host)"):
				p_name = p_name.trim_suffix("(Host)").strip_edges()
			
			var full_name = "[Lv. %d] %s" % [p_level, p_name]
			var is_room_playing = (str(r.get("phase", "lobby")) == "playing")
			
			if is_bot:
				sb.bg_color = Color(0.09, 0.18, 0.32, 0.9)
				sb.border_color = Color(0.3, 0.85, 1.0, 0.8)
				icon_lbl.text = "🤖"
				icon_lbl.modulate = Color(0.4, 0.9, 1.0)
				name_lbl.text = "%s (AI Racer)" % full_name
				name_lbl.modulate = Color(0.75, 0.95, 1.0)
				if is_room_playing or p_in_game:
					status_badge.text = "[BOT - RACING]"
					status_badge.modulate = Color(0.3, 0.85, 1.0)
				else:
					status_badge.text = "[BOT - READY]"
					status_badge.modulate = Color(0.3, 0.95, 0.6)
			elif p_in_game:
				sb.bg_color = Color(0.06, 0.20, 0.35, 0.9)
				sb.border_color = Color(0.3, 0.85, 1.0, 0.95)
				if p_is_host:
					icon_lbl.text = "★"
					icon_lbl.modulate = Color(1.0, 0.85, 0.2)
					name_lbl.text = full_name
					name_lbl.modulate = Color(1.0, 0.9, 0.35)
					status_badge.text = "[HOST - RACING]"
					status_badge.modulate = Color(0.3, 0.85, 1.0)
				else:
					icon_lbl.text = "🏎️"
					icon_lbl.modulate = Color(0.3, 0.85, 1.0)
					name_lbl.text = full_name
					name_lbl.modulate = Color(0.85, 0.95, 1.0)
					status_badge.text = "[RACING]"
					status_badge.modulate = Color(0.3, 0.85, 1.0)
			elif p_is_host:
				sb.bg_color = Color(0.12, 0.22, 0.45, 0.9)
				sb.border_color = Color(1.0, 0.85, 0.3, 0.85)
				icon_lbl.text = "★"
				icon_lbl.modulate = Color(1.0, 0.85, 0.2)
				name_lbl.text = full_name
				name_lbl.modulate = Color(1.0, 0.9, 0.35)
				status_badge.text = "[HOST]"
				status_badge.modulate = Color(1.0, 0.85, 0.2)
			else:
				if is_room_playing:
					sb.bg_color = Color(0.07, 0.16, 0.26, 0.85)
					sb.border_color = Color(0.9, 0.75, 0.2, 0.7)
					icon_lbl.text = "⏳"
					icon_lbl.modulate = Color(0.95, 0.85, 0.3)
					name_lbl.text = full_name
					name_lbl.modulate = Color(0.9, 0.92, 1.0)
					status_badge.text = "[WAITING IN LOBBY]"
					status_badge.modulate = Color(0.95, 0.85, 0.3)
				elif p_is_ready:
					sb.bg_color = Color(0.08, 0.22, 0.16, 0.85)
					sb.border_color = Color(0.2, 0.85, 0.4, 0.8)
					icon_lbl.text = "✓"
					icon_lbl.modulate = Color(0.3, 1.0, 0.5)
					name_lbl.text = full_name
					name_lbl.modulate = Color(0.8, 1.0, 0.85)
					status_badge.text = "[READY]"
					status_badge.modulate = Color(0.3, 1.0, 0.5)
				else:
					sb.bg_color = Color(0.06, 0.14, 0.28, 0.85)
					sb.border_color = Color(0.2, 0.7, 0.95, 0.6)
					icon_lbl.text = "○"
					icon_lbl.modulate = Color(0.3, 0.9, 1.0)
					name_lbl.text = full_name
					name_lbl.modulate = Color(0.85, 0.92, 1.0)
					status_badge.text = "[WAITING]"
					status_badge.modulate = Color(0.5, 0.75, 0.95)
		else:
			sb.bg_color = Color(0.04, 0.08, 0.16, 0.6)
			sb.border_color = Color(0.2, 0.45, 0.7, 0.25)
			icon_lbl.text = "-"
			icon_lbl.modulate = Color(0.4, 0.5, 0.65)
			name_lbl.text = "[ Empty Slot ]"
			name_lbl.modulate = Color(0.45, 0.6, 0.75, 0.6)
			status_badge.text = ""
		
		slot_panel.add_theme_stylebox_override("panel", sb)
		hbox.add_child(icon_lbl)
		hbox.add_child(name_lbl)
		if status_badge.text != "":
			hbox.add_child(status_badge)
		
		# Host Kick / Remove button on other players and bots
		if is_host and is_occupied and not p_is_host and not p_id.is_empty() and (not Network or p_id != Network.my_peer_id):
			var kick_btn = Button.new()
			kick_btn.text = "REMOVE" if is_bot else "KICK"
			kick_btn.tooltip_text = "Remove bot %s from room" % p_name if is_bot else "Kick %s from room" % p_name
			kick_btn.focus_mode = Control.FOCUS_NONE
			kick_btn.custom_minimum_size = Vector2(56 if is_bot else 48, 22)
			kick_btn.add_theme_font_size_override("font_size", 10)
			
			var kick_sb = StyleBoxFlat.new()
			kick_sb.bg_color = Color(0.7, 0.15, 0.2, 0.85) if not is_bot else Color(0.5, 0.18, 0.35, 0.85)
			kick_sb.border_color = Color(1.0, 0.3, 0.35, 0.9) if not is_bot else Color(0.9, 0.4, 0.6, 0.9)
			kick_sb.set_border_width_all(1)
			kick_sb.set_corner_radius_all(4)
			kick_btn.add_theme_stylebox_override("normal", kick_sb)
			
			var kick_hover = StyleBoxFlat.new()
			kick_hover.bg_color = Color(0.9, 0.22, 0.28, 1.0) if not is_bot else Color(0.7, 0.25, 0.45, 1.0)
			kick_hover.border_color = Color(1.0, 0.5, 0.55, 1.0) if not is_bot else Color(1.0, 0.6, 0.8, 1.0)
			kick_hover.set_border_width_all(1)
			kick_hover.set_corner_radius_all(4)
			kick_btn.add_theme_stylebox_override("hover", kick_hover)
			
			var target_kick_id = p_id
			var target_kick_name = p_name
			kick_btn.pressed.connect(func(): _on_kick_player_pressed(target_kick_id, target_kick_name))
			hbox.add_child(kick_btn)
		margin.add_child(hbox)
		slot_panel.add_child(margin)
		slot_panel.custom_minimum_size = Vector2(0, 36)
		player_list_vbox.add_child(slot_panel)

func _on_max_players_changed(value: float) -> void:
	if not is_host or not active_rooms.has(current_room_code):
		return
	var r = active_rooms[current_room_code]
	var new_max = int(round(value))
	if new_max < r["players"].size():
		new_max = r["players"].size()
		max_players_slider.set_value_no_signal(new_max)
	
	if r["max_players"] == new_max:
		return
	
	r["max_players"] = new_max
	max_players_val_lbl.text = "%d Players" % new_max
	player_count_header.text = "RACERS (%d / %d)" % [r["players"].size(), new_max]
	_update_player_slots(r)
	
	if Network and Network.is_connected_to_server:
		Network.update_room_settings(new_max, r["rounds"], "VOID PARKOUR", bool(r.get("is_private", false)))

func _on_rounds_selected(index: int) -> void:
	if not is_host or not active_rooms.has(current_room_code):
		return
	var rounds = rounds_opt.get_item_id(index)
	active_rooms[current_room_code]["rounds"] = rounds
	if Network and Network.is_connected_to_server:
		Network.update_room_settings(active_rooms[current_room_code]["max_players"], rounds, "VOID PARKOUR", bool(active_rooms[current_room_code].get("is_private", false)))

func _on_host_private_toggled(toggled_on: bool) -> void:
	if not is_host or not active_rooms.has(current_room_code):
		return
	var r = active_rooms[current_room_code]
	r["is_private"] = toggled_on
	if Network and Network.is_connected_to_server:
		Network.update_room_settings(r["max_players"], r["rounds"], "VOID PARKOUR", toggled_on)

func _setup_map_grid_buttons() -> void:
	for child in map_grid.get_children():
		if child is Button:
			child.pressed.connect(func():
				selected_map = "VOID PARKOUR"
				if Network:
					Network.selected_map = "VOID PARKOUR"
				if active_rooms.has(current_room_code):
					active_rooms[current_room_code]["map"] = "VOID PARKOUR"
				
				map_preview_lbl.text = "TRACK: VOID PARKOUR"
				_update_map_preview_image("VOID PARKOUR")
				_update_map_selection_highlight("VOID PARKOUR")
				if is_host and active_rooms.has(current_room_code) and Network and Network.is_connected_to_server:
					Network.update_room_settings(active_rooms[current_room_code]["max_players"], active_rooms[current_room_code]["rounds"], "VOID PARKOUR", bool(active_rooms[current_room_code].get("is_private", false)))
			)

func _update_map_preview_image(_map_name: String) -> void:
	if not map_preview_img:
		return
	if ResourceLoader.exists("res://assets/ui/mode_selection/mode_racing_art.png"):
		map_preview_img.texture = load("res://assets/ui/mode_selection/mode_racing_art.png")
	elif ResourceLoader.exists("res://assets/maps/map_space_station.png"):
		map_preview_img.texture = load("res://assets/maps/map_space_station.png")

func _update_map_selection_highlight(_map_name: String) -> void:
	for child in map_grid.get_children():
		if child is Button:
			child.modulate = Color(1.3, 1.3, 1.3)

func _on_copy_code_pressed() -> void:
	if not current_room_code.is_empty():
		DisplayServer.clipboard_set(current_room_code)
		copy_code_btn.text = "COPIED!"
		get_tree().create_timer(1.5).timeout.connect(func(): copy_code_btn.text = "COPY")

func _on_action_pressed() -> void:
	if Network and Network.is_host:
		is_host = true

	if is_host:
		if active_rooms.has(current_room_code):
			var r = active_rooms[current_room_code]
			if str(r.get("phase", "lobby")) == "playing":
				player_count_header.text = "RACE ALREADY IN PROGRESS"
				player_count_header.modulate = Color(1.0, 0.4, 0.4)
				return
			var unready_names: Array = []
			for p in r["players"]:
				var p_is_host = false
				var p_is_ready = false
				var p_name = "Player"
				if typeof(p) == TYPE_DICTIONARY:
					var pid = str(p.get("id", ""))
					p_is_host = bool(p.get("isHost", false)) or (Network and pid == Network.my_peer_id)
					p_is_ready = bool(p.get("isReady", false))
					p_name = str(p.get("name", "Player"))
				if not p_is_host and not p_is_ready:
					unready_names.append(p_name)
			
			if unready_names.size() > 0:
				player_count_header.text = "WAITING FOR READY: %s" % (", ".join(unready_names))
				player_count_header.modulate = Color(1.0, 0.4, 0.4)
				var t = get_tree().create_timer(3.0)
				t.timeout.connect(func():
					if is_instance_valid(player_count_header) and active_rooms.has(current_room_code):
						var cr = active_rooms[current_room_code]
						player_count_header.text = "RACERS (%d / %d)" % [cr["players"].size(), cr["max_players"]]
						player_count_header.modulate = Color(0.4, 0.85, 1.0)
				)
				return
		
		if Network:
			Network.selected_map = "VOID PARKOUR"
			Network.selected_game_mode = "racing"
		if Network and Network.is_connected_to_server:
			print("[LobbyRacing3D] Host starting race on server...")
			Network.start_game()
		else:
			print("[LobbyRacing3D] Host starting race locally with all lobby racers...")
			var r = active_rooms[current_room_code] if active_rooms.has(current_room_code) else {}
			var r_players: Array = r.get("players", [])
			if r_players.is_empty():
				r_players = [{
					"id": "host_local",
					"name": my_player_name,
					"isHost": true,
					"isReady": true,
					"isBot": false,
					"level": int(Network.current_user.get("level", 1)) if Network else 1
				}]
			
			var total_players = r_players.size()
			var void_spawns = [
				Vector3(0.0, 1.2, 0.0),
				Vector3(-3.0, 1.2, 0.0),
				Vector3(3.0, 1.2, 0.0),
				Vector3(-1.5, 1.2, -2.0),
				Vector3(1.5, 1.2, -2.0),
				Vector3(0.0, 1.2, -3.0),
				Vector3(-2.0, 1.2, 2.0),
				Vector3(2.0, 1.2, 2.0)
			]
			
			var match_list: Array = []
			for i in range(total_players):
				var p_info = r_players[i]
				var p_id = "p_%d" % i
				var p_name = "Racer %d" % (i + 1)
				var is_b = (i > 0)
				var is_h = (i == 0)
				var p_lv = 1
				
				if typeof(p_info) == TYPE_DICTIONARY:
					p_id = str(p_info.get("id", p_id))
					p_name = str(p_info.get("name", p_name))
					is_b = bool(p_info.get("isBot", i > 0))
					is_h = bool(p_info.get("isHost", i == 0))
					p_lv = int(p_info.get("level", 1))
				else:
					p_name = str(p_info)
				
				var spawn_pos = void_spawns[i % void_spawns.size()]
				match_list.append({
					"id": p_id,
					"name": p_name,
					"role": "runner", # All players are racers
					"isBot": is_b,
					"isHost": is_h,
					"level": p_lv,
					"x": spawn_pos.x,
					"y": spawn_pos.y,
					"z": spawn_pos.z,
					"rotY": 0.0
				})
			
			if Network:
				Network.current_match_players = match_list
				Network.current_round = 1
				Network.max_rounds = int(r.get("rounds", 3))
				Network.selected_map = "VOID PARKOUR"
				Network.selected_game_mode = "racing"
				Network.is_solo_mode = false
			
			get_tree().change_scene_to_file("res://scenes/3d/arena_3d.tscn")
	else:
		is_ready = not is_ready
		if Network and Network.is_connected_to_server:
			Network.set_ready(is_ready)
		_update_room_lobby_ui()

func _on_leave_room_pressed() -> void:
	if Network and Network.is_connected_to_server:
		Network.leave_room()
	
	if active_rooms.has(current_room_code):
		active_rooms.erase(current_room_code)
	
	if Network:
		Network.current_room_code = ""
		Network.is_host = false
		Network.room_data.clear()
	
	current_room_code = ""
	is_host = false
	is_ready = false
	_show_browser_view()

func _on_back_to_menu_pressed() -> void:
	if Network and Network.is_connected_to_server:
		Network.leave_room()
	if Network:
		Network.current_room_code = ""
		Network.is_host = false
		Network.room_data.clear()
	get_tree().change_scene_to_file("res://scenes/3d/main_menu_3d.tscn")

extends Control

# Constants for Among Us-style room codes (No ambiguous 0, O, 1, I)
const CODE_CHARS: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

# ── Views ───────────────────────────────────────────────────────────────────
@onready var browser_view: Control = $BrowserView
@onready var room_view: Control = $RoomView

# ── Browser View Nodes ──────────────────────────────────────────────────────
@onready var player_name_input: LineEdit = $BrowserView/PlayerNameContainer/PlayerNameInput
@onready var room_list_vbox: VBoxContainer = $BrowserView/HBox/RoomListCard/Scroll/RoomList
@onready var create_room_name_input: LineEdit = $BrowserView/HBox/CreateRoomCard/RoomNameInput
@onready var create_private_check: CheckBox = $BrowserView/HBox/CreateRoomCard/PrivateCheck
@onready var create_room_btn: Button = $BrowserView/HBox/CreateRoomCard/CreateBtn
@onready var join_code_input: LineEdit = $BrowserView/HBox/JoinCodeCard/CodeInput
@onready var join_code_btn: Button = $BrowserView/HBox/JoinCodeCard/JoinCodeBtn
@onready var code_error_lbl: Label = $BrowserView/HBox/JoinCodeCard/ErrorLabel
@onready var back_to_menu_btn: Button = $BackButton

# ── In-Room Waiting Lobby Nodes (Host & Players) ─────────────────────────────
@onready var room_header_lbl: Label = $RoomView/Header/RoomTitle
@onready var room_code_lbl: Label = $RoomView/Header/CodeBox/CodeLabel
@onready var copy_code_btn: Button = $RoomView/Header/CodeBox/CopyBtn
@onready var player_list_vbox: VBoxContainer = $RoomView/HBox/PlayerListCard/Scroll/PlayerList
@onready var player_count_header: Label = $RoomView/HBox/PlayerListCard/Header

# Host Live Customization Controls
@onready var host_settings_title: Label = $RoomView/HBox/HostSettingsCard/SettingsTitle
@onready var max_players_slider: HSlider = $RoomView/HBox/HostSettingsCard/MaxPlayersRow/Slider
@onready var max_players_val_lbl: Label = $RoomView/HBox/HostSettingsCard/MaxPlayersRow/ValLabel
@onready var rounds_opt: OptionButton = $RoomView/HBox/HostSettingsCard/RoundsRow/RoundsOpt
@onready var host_private_check: CheckBox = $RoomView/HBox/HostSettingsCard/PrivateRow/PrivateCheck
@onready var map_preview_lbl: Label = $RoomView/HBox/HostSettingsCard/MapPreview/MapName
@onready var map_grid: GridContainer = $RoomView/HBox/MapSelectionCard/Grid

# Action Buttons
@onready var action_btn: Button = $RoomView/BottomBar/ActionBtn
@onready var leave_btn: Button = $RoomView/BottomBar/LeaveBtn

# ── Dynamic Room State ──────────────────────────────────────────────────────
static var active_rooms: Dictionary = {}
var current_room_code: String = ""
var is_host: bool = false
var is_ready: bool = false
var my_player_name: String = "Player 1"
var selected_map: String = "CASTLE"

var refresh_timer: float = 0.0

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	code_error_lbl.text = ""
	
	if Network:
		my_player_name = Network.my_player_name
	player_name_input.text = my_player_name
	player_name_input.text_changed.connect(_on_player_name_changed)
	
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
	
	# Connect Room events
	max_players_slider.value_changed.connect(_on_max_players_changed)
	rounds_opt.item_selected.connect(_on_rounds_selected)
	host_private_check.toggled.connect(_on_host_private_toggled)
	copy_code_btn.pressed.connect(_on_copy_code_pressed)
	action_btn.pressed.connect(_on_action_pressed)
	leave_btn.pressed.connect(_on_leave_room_pressed)
	
	_setup_map_grid_buttons()
	_connect_network_signals()
	
	# Connect to backend WebSocket server if not connected
	if Network and not Network.is_connected_to_server:
		Network.connect_to_server()
	
	# Initially show Browser View & fetch rooms
	_show_browser_view()
	if Network:
		Network.fetch_public_rooms()

func _process(delta: float) -> void:
	if browser_view.visible:
		refresh_timer -= delta
		if refresh_timer <= 0.0:
			refresh_timer = 3.5
			if Network:
				Network.fetch_public_rooms()

# ── Network Signals Connection ──────────────────────────────────────────────
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
	if not Network.settings_updated.is_connected(_on_network_settings_updated):
		Network.settings_updated.connect(_on_network_settings_updated)
	if not Network.player_name_updated.is_connected(_on_network_player_name_updated):
		Network.player_name_updated.connect(_on_network_player_name_updated)
	if not Network.public_rooms_updated.is_connected(_on_network_public_rooms_updated):
		Network.public_rooms_updated.connect(_on_network_public_rooms_updated)
	if not Network.round_started.is_connected(_on_network_round_started):
		Network.round_started.connect(_on_network_round_started)
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
	if Network:
		Network.fetch_public_rooms()

# ── Room Code Generator (Local Fallback) ────────────────────────────────────
func generate_unique_code() -> String:
	while true:
		var code = ""
		for i in range(6):
			code += CODE_CHARS[randi() % CODE_CHARS.length()]
		if not active_rooms.has(code):
			return code
	return "ROOM01"

# ── View Switching ──────────────────────────────────────────────────────────
func _show_browser_view() -> void:
	browser_view.visible = true
	room_view.visible = false
	back_to_menu_btn.visible = true
	code_error_lbl.text = ""
	_update_room_list_browser()

func _show_room_view() -> void:
	browser_view.visible = false
	room_view.visible = true
	back_to_menu_btn.visible = false
	_update_room_lobby_ui()

# ── Browser UI ──────────────────────────────────────────────────────────────
func _update_room_list_browser() -> void:
	for child in room_list_vbox.get_children():
		child.queue_free()
	
	if active_rooms.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "(No rooms online yet)\nCreate a room or enter PIN to join"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.modulate = Color(0.7, 0.8, 0.9, 0.7)
		empty_lbl.add_theme_font_size_override("font_size", 13)
		room_list_vbox.add_child(empty_lbl)
		return
	
	for code in active_rooms:
		var r = active_rooms[code]
		var item_btn = Button.new()
		var p_count = r["players"].size()
		var max_p = r["max_players"]
		item_btn.text = "%s   [%s]   (%d/%d)   %s" % [r["name"], r["code"], p_count, max_p, r["map"]]
		item_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item_btn.add_theme_font_size_override("font_size", 13)
		
		if p_count >= max_p or r.get("has_started", false):
			item_btn.disabled = true
			item_btn.text += " [FULL]" if (p_count >= max_p) else " [IN PROGRESS]"
		else:
			item_btn.pressed.connect(func(): _join_room_by_code(code))
		
		room_list_vbox.add_child(item_btn)

# ── Create Room (1 Player = 1 Room Only) ────────────────────────────────────
func _on_create_room_pressed() -> void:
	if not current_room_code.is_empty() and active_rooms.has(current_room_code):
		return
	
	var r_name = create_room_name_input.text.strip_edges()
	if r_name.is_empty():
		r_name = "Room " + str(randi_range(101, 999))
	
	var is_priv = create_private_check.button_pressed
	if Network and Network.is_connected_to_server:
		code_error_lbl.text = "Creating room on server..."
		Network.create_room(r_name, 8, 3, selected_map, is_priv)
	else:
		code_error_lbl.text = "Connecting to server... Please wait a moment."
		if Network:
			Network.connect_to_server()

# ── Join by Code (Among Us Style) ───────────────────────────────────────────
func _on_join_by_code_pressed() -> void:
	var code = join_code_input.text.strip_edges().to_upper()
	if code.length() != 6:
		code_error_lbl.text = "Room code must be 6 characters"
		return
	
	_join_room_by_code(code)

func _join_room_by_code(code: String) -> void:
	if Network and Network.is_connected_to_server:
		code_error_lbl.text = "Connecting to room " + code + "..."
		Network.join_room(code)
	else:
		code_error_lbl.text = "Connecting to server... Please wait a moment."
		if Network:
			Network.connect_to_server()

# ── Network Handlers ────────────────────────────────────────────────────────
func _on_network_room_created(data: Dictionary) -> void:
	code_error_lbl.text = ""
	current_room_code = str(data.get("code", ""))
	is_host = true
	is_ready = true
	
	var r_players = []
	for p in data.get("players", []):
		r_players.append(str(p.get("name", "Player")) + (" (Host)" if p.get("isHost", false) else ""))
	
	active_rooms[current_room_code] = {
		"name": str(data.get("name", "Room")),
		"code": current_room_code,
		"host": my_player_name,
		"max_players": int(data.get("maxPlayers", 8)),
		"rounds": int(data.get("rounds", 3)),
		"map": str(data.get("map", "CASTLE")),
		"is_private": bool(data.get("isPrivate", false)),
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
		r_players.append(str(p.get("name", "Player")) + (" (Host)" if p.get("isHost", false) else ""))
	
	active_rooms[current_room_code] = {
		"name": str(data.get("name", "Room")),
		"code": current_room_code,
		"host": "Host",
		"max_players": int(data.get("maxPlayers", 8)),
		"rounds": int(data.get("rounds", 3)),
		"map": str(data.get("map", "CASTLE")),
		"is_private": bool(data.get("isPrivate", false)),
		"players": r_players
	}
	_show_room_view()

func _on_network_player_joined(data: Dictionary) -> void:
	if active_rooms.has(current_room_code):
		var r = active_rooms[current_room_code]
		var p_name = str(data.get("name", "New Player"))
		r["players"].append(p_name)
		_update_room_lobby_ui()

func _on_network_player_left(data: Dictionary) -> void:
	if active_rooms.has(current_room_code):
		var r = active_rooms[current_room_code]
		var p_name = str(data.get("name", ""))
		for i in range(r["players"].size() - 1, -1, -1):
			if r["players"][i].begins_with(p_name):
				r["players"].remove_at(i)
				break
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
			var r_players = []
			for p in Network.room_data["players"]:
				r_players.append(str(p.get("name", "Player")) + (" (Host)" if p.get("isHost", false) else ""))
			r["players"] = r_players
		_update_room_lobby_ui()

func _on_network_public_rooms_updated(rooms: Array) -> void:
	# Update active_rooms from server REST query
	var new_dict: Dictionary = {}
	for r in rooms:
		if bool(r.get("isPrivate", false)):
			continue
		var code = str(r.get("code", ""))
		new_dict[code] = {
			"name": str(r.get("name", "Room")),
			"code": code,
			"host": "Host",
			"max_players": int(r.get("maxPlayers", 8)),
			"rounds": int(r.get("rounds", 3)),
			"map": str(r.get("map", "CASTLE")),
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

# ── In-Room UI & Customization ──────────────────────────────────────────────
func _update_room_lobby_ui() -> void:
	if not active_rooms.has(current_room_code):
		_show_browser_view()
		return
	
	var r = active_rooms[current_room_code]
	
	# Header
	room_header_lbl.text = r["name"].to_upper()
	room_code_lbl.text = r["code"]
	player_count_header.text = "PLAYERS (%d / %d)" % [r["players"].size(), r["max_players"]]
	
	# Player List
	for child in player_list_vbox.get_children():
		child.queue_free()
	
	for i in range(r["max_players"]):
		var slot_lbl = Label.new()
		if i < r["players"].size():
			slot_lbl.text = "- " + str(r["players"][i])
			slot_lbl.modulate = Color(1.0, 0.9, 0.4) if (i == 0) else Color(0.9, 0.95, 1.0)
		else:
			slot_lbl.text = "- [Open / Waiting for player...]"
			slot_lbl.modulate = Color(0.5, 0.6, 0.7, 0.5)
		slot_lbl.add_theme_font_size_override("font_size", 13)
		player_list_vbox.add_child(slot_lbl)
	
	# Host Customization Controls
	max_players_slider.value = r["max_players"]
	max_players_val_lbl.text = "%d Players" % r["max_players"]
	map_preview_lbl.text = "MAP: " + r["map"]
	
	max_players_slider.editable = is_host
	rounds_opt.disabled = not is_host
	host_private_check.set_pressed_no_signal(bool(r.get("is_private", false)))
	host_private_check.disabled = not is_host
	host_settings_title.text = "HOST SETTINGS" if is_host else "ROOM SETTINGS (Host only)"
	
	# Action Button
	if is_host:
		action_btn.text = "START GAME"
		action_btn.modulate = Color(0.4, 1.0, 0.4)
		action_btn.disabled = false
	else:
		action_btn.text = "READY" if not is_ready else "WAITING FOR HOST..."
		action_btn.modulate = Color(0.4, 0.85, 1.0)
		action_btn.disabled = is_ready

func _on_max_players_changed(value: float) -> void:
	if not is_host or not active_rooms.has(current_room_code):
		return
	var r = active_rooms[current_room_code]
	var new_max = int(value)
	if new_max < r["players"].size():
		new_max = r["players"].size()
		max_players_slider.value = new_max
	
	r["max_players"] = new_max
	max_players_val_lbl.text = "%d Players" % new_max
	player_count_header.text = "PLAYERS (%d / %d)" % [r["players"].size(), new_max]
	
	if Network and Network.is_connected_to_server:
		Network.update_room_settings(new_max, r["rounds"], r["map"], bool(r.get("is_private", false)))
	_update_room_lobby_ui()

func _on_rounds_selected(index: int) -> void:
	if not is_host or not active_rooms.has(current_room_code):
		return
	var rounds = rounds_opt.get_item_id(index)
	active_rooms[current_room_code]["rounds"] = rounds
	if Network and Network.is_connected_to_server:
		Network.update_room_settings(active_rooms[current_room_code]["max_players"], rounds, active_rooms[current_room_code]["map"], bool(active_rooms[current_room_code].get("is_private", false)))

func _on_host_private_toggled(toggled_on: bool) -> void:
	if not is_host or not active_rooms.has(current_room_code):
		return
	var r = active_rooms[current_room_code]
	r["is_private"] = toggled_on
	if Network and Network.is_connected_to_server:
		Network.update_room_settings(r["max_players"], r["rounds"], r["map"], toggled_on)

func _setup_map_grid_buttons() -> void:
	for child in map_grid.get_children():
		if child is Button:
			child.pressed.connect(func():
				if not is_host or not active_rooms.has(current_room_code):
					return
				var clean_name = child.text.strip_edges()
				selected_map = clean_name
				active_rooms[current_room_code]["map"] = clean_name
				map_preview_lbl.text = "MAP: " + clean_name
				if Network and Network.is_connected_to_server:
					Network.update_room_settings(active_rooms[current_room_code]["max_players"], active_rooms[current_room_code]["rounds"], clean_name, bool(active_rooms[current_room_code].get("is_private", false)))
			)

func _on_copy_code_pressed() -> void:
	if not current_room_code.is_empty():
		DisplayServer.clipboard_set(current_room_code)
		copy_code_btn.text = "COPIED!"
		get_tree().create_timer(1.5).timeout.connect(func(): copy_code_btn.text = "COPY")

func _on_action_pressed() -> void:
	if is_host:
		if Network and Network.is_connected_to_server:
			Network.start_game()
		else:
			get_tree().change_scene_to_file("res://scenes/3d/arena_3d.tscn")
	else:
		is_ready = true
		_update_room_lobby_ui()

func _on_leave_room_pressed() -> void:
	if active_rooms.has(current_room_code):
		if is_host:
			active_rooms.erase(current_room_code)
		else:
			var r = active_rooms[current_room_code]
			for i in range(r["players"].size() - 1, -1, -1):
				if str(r["players"][i]).begins_with("Player"):
					r["players"].remove_at(i)
					break
	
	if Network:
		Network.disconnect_from_server()
		# Reconnect to keep browser alive
		Network.connect_to_server()
	
	current_room_code = ""
	is_host = false
	is_ready = false
	_show_browser_view()

func _on_back_to_menu_pressed() -> void:
	if Network:
		Network.disconnect_from_server()
	get_tree().change_scene_to_file("res://scenes/3d/main_menu_3d.tscn")

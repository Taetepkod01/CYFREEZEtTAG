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
var selected_map: String = "SPACE STATION"
var is_dragging_slider: bool = false

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	code_error_lbl.text = ""
	
	if Network:
		my_player_name = Network.my_player_name
		if not Network.selected_map.is_empty():
			selected_map = Network.selected_map
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
	
	_setup_map_grid_buttons()
	_connect_network_signals()
	
	# Connect to backend WebSocket server if not connected
	if Network and not Network.is_connected_to_server:
		Network.connect_to_server()
	
	# If returning from game while still in a room, restore Room View
	if Network and not Network.current_room_code.is_empty():
		current_room_code = Network.current_room_code
		is_host = Network.is_host
		if not Network.room_data.is_empty():
			active_rooms[current_room_code] = {
				"name": Network.room_data.get("name", "Room " + current_room_code),
				"code": current_room_code,
				"host": Network.room_data.get("hostName", "Host"),
				"host_id": Network.room_data.get("hostId", ""),
				"players": Network.room_data.get("players", []),
				"max_players": int(Network.room_data.get("maxPlayers", 6)),
				"map": Network.room_data.get("map", "Space Station"),
				"rounds": int(Network.room_data.get("rounds", 3)),
				"is_private": bool(Network.room_data.get("isPrivate", false))
			}
		_show_room_view()
	else:
		_show_browser_view()

func _on_refresh_pressed() -> void:
	if Network:
		print("[Lobby3D] Refresh button clicked: fetching public rooms")
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

# -- Room Code Generator (Local Fallback) ------------------------------------
func generate_unique_code() -> String:
	while true:
		var code = ""
		for i in range(6):
			code += CODE_CHARS[randi() % CODE_CHARS.length()]
		if not active_rooms.has(code):
			return code
	return "ROOM01"

# -- View Switching ----------------------------------------------------------
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

# -- Browser UI --------------------------------------------------------------
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

# -- Create Room (1 Player = 1 Room Only) ------------------------------------
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

# -- Join by Code (Among Us Style) -------------------------------------------
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

# -- Network Handlers --------------------------------------------------------
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

# -- In-Room UI & Customization ----------------------------------------------
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
	_update_player_slots(r)
	
	# Host Customization Controls
	if not is_dragging_slider:
		max_players_slider.set_value_no_signal(r["max_players"])
	max_players_val_lbl.text = "%d Players" % r["max_players"]
	map_preview_lbl.text = "MAP: " + r["map"]
	_update_map_preview_image(r["map"])
	_update_map_selection_highlight(r["map"])
	
	max_players_slider.editable = is_host
	rounds_opt.disabled = not is_host
	for idx in range(rounds_opt.item_count):
		if rounds_opt.get_item_id(idx) == r["rounds"]:
			rounds_opt.selected = idx
			break
	host_private_check.set_pressed_no_signal(bool(r.get("is_private", false)))
	host_private_check.disabled = not is_host
	host_settings_title.text = "HOST SETTINGS" if is_host else "ROOM SETTINGS (Host only)"
	
	# Action Button
	if is_host:
		action_btn.texture_normal = TEX_START_GAME
		action_btn.disabled = false
	else:
		action_btn.texture_normal = TEX_WAITING if is_ready else TEX_READY
		action_btn.disabled = is_ready

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
		
		if i < r["players"].size():
			var p_name = str(r["players"][i])
			if i == 0:
				sb.bg_color = Color(0.12, 0.22, 0.45, 0.9)
				sb.border_color = Color(1.0, 0.85, 0.3, 0.85)
				icon_lbl.text = "*"
				icon_lbl.modulate = Color(1.0, 0.85, 0.2)
				name_lbl.text = "%s  (Host)" % p_name
				name_lbl.modulate = Color(1.0, 0.9, 0.35)
			else:
				sb.bg_color = Color(0.06, 0.14, 0.28, 0.85)
				sb.border_color = Color(0.2, 0.7, 0.95, 0.6)
				icon_lbl.text = "o"
				icon_lbl.modulate = Color(0.3, 0.9, 1.0)
				name_lbl.text = p_name
				name_lbl.modulate = Color(0.9, 0.95, 1.0)
		else:
			sb.bg_color = Color(0.04, 0.08, 0.16, 0.6)
			sb.border_color = Color(0.2, 0.45, 0.7, 0.25)
			icon_lbl.text = "-"
			icon_lbl.modulate = Color(0.4, 0.5, 0.65)
			name_lbl.text = "[ Empty Slot ]"
			name_lbl.modulate = Color(0.45, 0.6, 0.75, 0.6)
		
		slot_panel.add_theme_stylebox_override("panel", sb)
		hbox.add_child(icon_lbl)
		hbox.add_child(name_lbl)
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
	player_count_header.text = "PLAYERS (%d / %d)" % [r["players"].size(), new_max]
	_update_player_slots(r)
	
	if Network and Network.is_connected_to_server:
		Network.update_room_settings(new_max, r["rounds"], r["map"], bool(r.get("is_private", false)))

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
				var clean_name = child.text.strip_edges()
				selected_map = clean_name
				if Network:
					Network.selected_map = clean_name
				if active_rooms.has(current_room_code):
					active_rooms[current_room_code]["map"] = clean_name
				map_preview_lbl.text = "MAP: " + clean_name
				_update_map_preview_image(clean_name)
				_update_map_selection_highlight(clean_name)
				if is_host and active_rooms.has(current_room_code) and Network and Network.is_connected_to_server:
					Network.update_room_settings(active_rooms[current_room_code]["max_players"], active_rooms[current_room_code]["rounds"], clean_name, bool(active_rooms[current_room_code].get("is_private", false)))
			)

func _update_map_preview_image(map_name: String) -> void:
	if not map_preview_img:
		return
	match map_name:
		"SPACE STATION":
			map_preview_img.texture = load("res://assets/maps/map_space_station.png")
		"LABYRINTH":
			map_preview_img.texture = load("res://assets/maps/map_labyrinth.png")
		"SNOW TOWN", _:
			map_preview_img.texture = load("res://assets/maps/map_preview_snow_town.png")

func _update_map_selection_highlight(map_name: String) -> void:
	for child in map_grid.get_children():
		if child is Button:
			var is_selected = (child.text.strip_edges() == map_name)
			if is_selected:
				child.modulate = Color(1.2, 1.2, 1.2)
			else:
				child.modulate = Color(0.7, 0.75, 0.85)

func _on_copy_code_pressed() -> void:
	if not current_room_code.is_empty():
		DisplayServer.clipboard_set(current_room_code)
		copy_code_btn.text = "COPIED!"
		get_tree().create_timer(1.5).timeout.connect(func(): copy_code_btn.text = "COPY")

func _on_action_pressed() -> void:
	if is_host:
		if Network:
			Network.selected_map = selected_map
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

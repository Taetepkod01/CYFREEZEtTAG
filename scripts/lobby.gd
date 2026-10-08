extends Control

@onready var name_input: LineEdit = $Panel/VBoxContainer/NameRow/NameInput
@onready var host_port_input: LineEdit = $Panel/VBoxContainer/HostSection/PortInput
@onready var host_btn: Button = $Panel/VBoxContainer/HostSection/HostButton
@onready var join_ip_input: LineEdit = $Panel/VBoxContainer/JoinSection/IPInput
@onready var join_port_input: LineEdit = $Panel/VBoxContainer/JoinSection/PortInput
@onready var join_btn: Button = $Panel/VBoxContainer/JoinSection/JoinButton

@onready var room_panel: Panel = $RoomPanel
@onready var player_list_container: VBoxContainer = $RoomPanel/PlayerList
@onready var start_game_btn: Button = $RoomPanel/StartButton
@onready var leave_btn: Button = $RoomPanel/LeaveButton
@onready var status_label: Label = $StatusLabel

func _ready() -> void:
	room_panel.visible = false
	status_label.text = ""
	name_input.text = Network.my_player_name
	
	host_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	start_game_btn.pressed.connect(_on_start_pressed)
	leave_btn.pressed.connect(_on_leave_pressed)
	$BackButton.pressed.connect(_on_back_pressed)
	
	Network.player_list_updated.connect(_update_player_list)

func _on_host_pressed() -> void:
	var p_name = name_input.text.strip_edges()
	if p_name.is_empty():
		p_name = "Host"
	Network.my_player_name = p_name
	
	var port = int(host_port_input.text)
	if port <= 0:
		port = Network.DEFAULT_PORT
	
	var err = Network.host_game(port)
	if err == OK:
		status_label.text = "Hosting server on port %d" % port
		room_panel.visible = true
		start_game_btn.visible = true
		_update_player_list()
	else:
		status_label.text = "Error hosting server: %s" % str(err)

func _on_join_pressed() -> void:
	var p_name = name_input.text.strip_edges()
	if p_name.is_empty():
		p_name = "Player"
	Network.my_player_name = p_name
	
	var ip = join_ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	var port = int(join_port_input.text)
	if port <= 0:
		port = Network.DEFAULT_PORT
	
	var err = Network.join_game(ip, port)
	if err == OK:
		status_label.text = "Connecting to %s:%d..." % [ip, port]
		room_panel.visible = true
		start_game_btn.visible = false
	else:
		status_label.text = "Error joining server: %s" % str(err)

func _update_player_list() -> void:
	for child in player_list_container.get_children():
		child.queue_free()
	
	for pid in Network.players:
		var p = Network.players[pid]
		var lbl = Label.new()
		var is_host = (pid == 1)
		lbl.text = "• %s %s" % [p["name"], "[HOST]" if is_host else ""]
		lbl.add_theme_font_size_override("font_size", 16)
		player_list_container.add_child(lbl)
	
	if multiplayer.is_server():
		start_game_btn.visible = true
		start_game_btn.disabled = (Network.players.size() < 1)

func _on_start_pressed() -> void:
	Network.server_start_game()

func _on_leave_pressed() -> void:
	Network.disconnect_game()
	room_panel.visible = false
	status_label.text = ""

func _on_back_pressed() -> void:
	Network.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

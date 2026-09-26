extends Node

signal player_list_updated
signal game_started
signal game_ended(winner: String)
signal player_tagged(chaser_name: String, runner_name: String)
signal player_unfrozen(rescuer_name: String, runner_name: String)
signal item_spawned(item_id: String, item_type: String, pos: Vector2)
signal item_removed(item_id: String)

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4

var my_player_name: String = "Player"
var is_solo_mode: bool = false
var selected_practice_role: String = "random" # "random", "tagger", "runner"

# Player dictionary: peer_id -> { "name": String, "role": String, "frozen": bool, "score": int, "is_bot": bool }
var players: Dictionary = {}
var host_id: int = 1

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# ── Host / Join ─────────────────────────────────────────────────────────────
func host_game(port: int = DEFAULT_PORT) -> Error:
	is_solo_mode = false
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	players.clear()
	host_id = 1
	_add_player(1, my_player_name, false)
	player_list_updated.emit()
	return OK

func join_game(ip: String, port: int = DEFAULT_PORT) -> Error:
	is_solo_mode = false
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, port)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	players.clear()
	return OK

func start_solo_practice() -> void:
	is_solo_mode = true
	# Reset multiplayer peer to null/offline
	multiplayer.multiplayer_peer = null
	players.clear()
	_add_player(1, my_player_name + " (You)", false)
	# Add 3 bot players
	_add_player(2, "Bot Frosty", true)
	_add_player(3, "Bot Blizz", true)
	_add_player(4, "Bot Chilly", true)
	
	# Randomly pick 1 chaser
	_assign_roles()
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func disconnect_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	players.clear()
	is_solo_mode = false

# ── Role Assignment ─────────────────────────────────────────────────────────
func _assign_roles() -> void:
	var ids = players.keys()
	if ids.is_empty():
		return
	ids.shuffle()
	var chaser_id = ids[0]
	for id in ids:
		if id == chaser_id:
			players[id]["role"] = "chaser"
		else:
			players[id]["role"] = "runner"
		players[id]["frozen"] = false

# ── Peer Callbacks ──────────────────────────────────────────────────────────
func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		# Send current players list to newcomer
		for pid in players:
			rpc_id(id, "register_player", pid, players[pid]["name"], players[pid]["is_bot"])
		# Register newcomer
		rpc_id(id, "request_player_info")

func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		players.erase(id)
		player_list_updated.emit()
		if multiplayer.is_server():
			rpc("unregister_player", id)

func _on_connected_to_server() -> void:
	var my_id = multiplayer.get_unique_id()
	rpc_id(1, "send_player_info", my_id, my_player_name)

func _on_connection_failed() -> void:
	disconnect_game()

func _on_server_disconnected() -> void:
	disconnect_game()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# ── RPCs for Player Registration ───────────────────────────────────────────
@rpc("any_peer")
func send_player_info(id: int, p_name: String) -> void:
	if multiplayer.is_server():
		_add_player(id, p_name, false)
		rpc("register_player", id, p_name, false)
		player_list_updated.emit()

@rpc("any_peer")
func request_player_info() -> void:
	var my_id = multiplayer.get_unique_id()
	rpc_id(1, "send_player_info", my_id, my_player_name)

@rpc("authority", "call_local")
func register_player(id: int, p_name: String, is_bot: bool) -> void:
	_add_player(id, p_name, is_bot)
	player_list_updated.emit()

@rpc("authority", "call_local")
func unregister_player(id: int) -> void:
	if players.has(id):
		players.erase(id)
		player_list_updated.emit()

func _add_player(id: int, p_name: String, is_bot: bool) -> void:
	players[id] = {
		"name": p_name,
		"role": "runner",
		"frozen": false,
		"score": 0,
		"is_bot": is_bot
	}

# ── Game Launch ─────────────────────────────────────────────────────────────
func server_start_game() -> void:
	if not multiplayer.is_server() and not is_solo_mode:
		return
	_assign_roles()
	rpc("client_load_game", players)

@rpc("authority", "call_local")
func client_load_game(assigned_players: Dictionary) -> void:
	players = assigned_players
	get_tree().change_scene_to_file("res://scenes/game.tscn")

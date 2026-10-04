extends Node

# ── Signals for High-Speed WebSocket Client-to-Server ─────────────────────────
signal connected_to_server
signal connection_error(message: String)
signal server_disconnected

# Room & Lobby Signals
signal room_created(data: Dictionary)
signal room_joined(data: Dictionary)
signal player_joined(data: Dictionary)
signal player_left(data: Dictionary)
signal host_changed(new_host_id: String)
signal player_name_updated(data: Dictionary)
signal player_ready_updated(data: Dictionary)
signal settings_updated(data: Dictionary)
signal public_rooms_updated(rooms: Array)

# 3D Match In-Game Signals
signal round_started(data: Dictionary)
signal time_sync(time_left: int)
signal player_moved(id: String, pos: Vector3, rot_y: float)
signal player_tagged(tagger_id: String, tagger_name: String, victim_id: String, victim_name: String)
signal player_rescued(rescuer_id: String, rescuer_name: String, victim_id: String, victim_name: String)
signal player_rescuing(player_id: String, is_rescuing: bool)
signal item_spawned(id: String, type: String, pos: Vector3)
signal item_picked(player_id: String, player_name: String, item_id: String, item_type: String)
signal item_used(player_id: String, player_name: String, type: String)
signal banana_placed(pos: Vector3, placer_id: String)
signal player_damaged(data: Dictionary)
signal vortex_spawned(pos: Vector3)
signal round_ended(data: Dictionary)
signal returned_to_lobby(data: Dictionary)
signal chat_received(msg: String)

# Legacy signals for backwards-compatibility if referenced
signal player_list_updated
signal game_started
signal game_ended(winner: String)

# ── Server Connection Config ──────────────────────────────────────────────────
# Default to local Node/Colyseus server port 2567, or automatically deduce on Web
var server_ws_url: String = "ws://127.0.0.1:2567/ws"
var server_http_url: String = "http://127.0.0.1:2567"

var ws_peer: WebSocketPeer = WebSocketPeer.new()
var http_request: HTTPRequest = null
var last_ws_state: int = WebSocketPeer.STATE_CLOSED

# ── State Variables ───────────────────────────────────────────────────────────
var is_connected_to_server: bool = false
var my_peer_id: String = ""
var my_player_name: String = "Player 1"
var current_room_code: String = ""
var is_host: bool = false
var is_solo_mode: bool = false
var selected_practice_role: String = "random" # "random", "tagger", "runner"
var selected_map: String = "SPACE STATION" # Default to SPACE STATION

var room_data: Dictionary = {}
var current_match_players: Array = []
var current_match_items: Array = []
var current_round: int = 1
var max_rounds: int = 3

# Movement throttling to avoid flooding WebSockets
var move_throttle_timer: float = 0.0
const MOVE_SEND_RATE: float = 0.05 # 20 Hz updates

# Keep-alive ping to maintain connection through cloud reverse proxies
var ping_timer: float = 0.0
const PING_INTERVAL: float = 5.0

func _ready() -> void:
	_init_urls()
	
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_http_request_completed)

func _init_urls() -> void:
	if OS.has_feature("web"):
		# Running on WebGL / Browser (e.g. Render.com deployment)
		var host = JavaScriptBridge.eval("window.location.host")
		var proto = JavaScriptBridge.eval("window.location.protocol")
		if host and host != "":
			if proto == "https:":
				server_ws_url = "wss://" + str(host) + "/ws"
				server_http_url = "https://" + str(host)
			else:
				server_ws_url = "ws://" + str(host) + "/ws"
				server_http_url = "http://" + str(host)

func is_online_game() -> bool:
	return not is_solo_mode and is_connected_to_server and current_room_code != ""

# ── WebSocket Management ──────────────────────────────────────────────────────
func connect_to_server(custom_url: String = "") -> Error:
	if is_connected_to_server and ws_peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		return OK
	
	if ws_peer.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		return OK
	
	# Instantiate fresh WebSocketPeer to prevent stale state in WebGL
	ws_peer = WebSocketPeer.new()
	_init_urls()
	
	var target_url = custom_url if not custom_url.is_empty() else server_ws_url
	print("[Network] Connecting to WebSocket: ", target_url)
	
	var err = ws_peer.connect_to_url(target_url)
	if err != OK:
		print("[Network] Failed to initiate connection: ", err)
		connection_error.emit("Failed to initiate connection to " + target_url)
		return err
	
	last_ws_state = ws_peer.get_ready_state()
	return OK

func disconnect_from_server() -> void:
	if ws_peer.get_ready_state() == WebSocketPeer.STATE_OPEN or ws_peer.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		ws_peer.close()
	is_connected_to_server = false
	current_room_code = ""
	is_host = false
	room_data.clear()

func _process(delta: float) -> void:
	ws_peer.poll()
	var state = ws_peer.get_ready_state()
	
	if state != last_ws_state:
		_handle_state_change(state, last_ws_state)
		last_ws_state = state
	
	if state == WebSocketPeer.STATE_OPEN:
		ping_timer -= delta
		if ping_timer <= 0.0:
			ping_timer = PING_INTERVAL
			send_action("ping", {"time": Time.get_ticks_msec()})
			
		while ws_peer.get_available_packet_count() > 0:
			var pkt = ws_peer.get_packet()
			var text = pkt.get_string_from_utf8()
			_handle_server_message(text)

func _handle_state_change(new_state: int, old_state: int) -> void:
	if new_state == WebSocketPeer.STATE_OPEN:
		print("[Network] WebSocket Connected successfully!")
		is_connected_to_server = true
		ping_timer = PING_INTERVAL
		connected_to_server.emit()
	elif new_state == WebSocketPeer.STATE_CLOSED:
		ping_timer = 0.0
		var code = ws_peer.get_close_code()
		var reason = ws_peer.get_close_reason()
		print("[Network] WebSocket Closed. Code: %d, Reason: %s" % [code, reason])
		var was_connected = is_connected_to_server
		is_connected_to_server = false
		if was_connected:
			server_disconnected.emit()
		elif old_state == WebSocketPeer.STATE_CONNECTING:
			connection_error.emit("Cannot reach server at " + server_ws_url)

# ── Send JSON Packet to WebSocket Server ──────────────────────────────────────
func send_action(action: String, data: Dictionary = {}) -> void:
	if ws_peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var payload = data.duplicate()
	payload["action"] = action
	var json_str = JSON.stringify(payload)
	ws_peer.send_text(json_str)

# ── Message Dispatcher ────────────────────────────────────────────────────────
func _handle_server_message(raw_text: String) -> void:
	var parsed = JSON.parse_string(raw_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	
	var event = parsed.get("event", "")
	var data = parsed.get("data", {})
	
	match event:
		"room_created":
			my_peer_id = str(data.get("myId", ""))
			current_room_code = str(data.get("code", ""))
			is_host = true
			is_solo_mode = false
			room_data = data
			if data.has("map"):
				selected_map = str(data["map"])
			room_created.emit(data)
			player_list_updated.emit()
			
		"room_joined":
			my_peer_id = str(data.get("myId", ""))
			current_room_code = str(data.get("code", ""))
			is_host = bool(data.get("isHost", false))
			is_solo_mode = false
			room_data = data
			if data.has("map"):
				selected_map = str(data["map"])
			room_joined.emit(data)
			player_list_updated.emit()
			
		"player_joined":
			if room_data.has("players") and typeof(room_data["players"]) == TYPE_ARRAY:
				room_data["players"].append({
					"id": data.get("id"),
					"name": data.get("name"),
					"isHost": data.get("isHost", false)
				})
			player_joined.emit(data)
			player_list_updated.emit()
			
		"player_left":
			var left_id = str(data.get("id", ""))
			if room_data.has("players") and typeof(room_data["players"]) == TYPE_ARRAY:
				for i in range(room_data["players"].size() - 1, -1, -1):
					if str(room_data["players"][i].get("id")) == left_id:
						room_data["players"].remove_at(i)
						break
			player_left.emit(data)
			player_list_updated.emit()
			
		"host_changed":
			var new_host = str(data.get("newHostId", ""))
			is_host = (my_peer_id == new_host)
			host_changed.emit(new_host)
			
		"player_name_updated":
			var updated_id = str(data.get("id", ""))
			var updated_name = str(data.get("name", ""))
			if room_data.has("players") and typeof(room_data["players"]) == TYPE_ARRAY:
				for p in room_data["players"]:
					if str(p.get("id")) == updated_id:
						p["name"] = updated_name
						break
			player_name_updated.emit(data)
			player_list_updated.emit()
			
		"settings_updated":
			if room_data.has("maxPlayers") and data.has("maxPlayers"):
				room_data["maxPlayers"] = data["maxPlayers"]
			if room_data.has("rounds") and data.has("rounds"):
				room_data["rounds"] = data["rounds"]
			if room_data.has("map") and data.has("map"):
				room_data["map"] = data["map"]
				selected_map = str(data["map"])
			if data.has("isPrivate"):
				room_data["isPrivate"] = data["isPrivate"]
			settings_updated.emit(data)
			
		"round_started":
			current_match_players = data.get("players", [])
			current_match_items = data.get("items", [])
			current_round = int(data.get("round", 1))
			max_rounds = int(data.get("maxRounds", 3))
			if data.has("map"):
				selected_map = str(data["map"])
			round_started.emit(data)
			game_started.emit()
			
		"time_sync":
			time_sync.emit(int(data.get("timeLeft", 0)))
			
		"player_moved":
			var p_id = str(data.get("id", ""))
			var pos = Vector3(float(data.get("x", 0)), float(data.get("y", 0)), float(data.get("z", 0)))
			var rot_y = float(data.get("rotY", 0))
			player_moved.emit(p_id, pos, rot_y)
			
		"player_tagged":
			player_tagged.emit(
				str(data.get("taggerId", "")),
				str(data.get("taggerName", "")),
				str(data.get("victimId", "")),
				str(data.get("victimName", ""))
			)
			
		"player_rescued":
			player_rescued.emit(
				str(data.get("rescuerId", "")),
				str(data.get("rescuerName", "")),
				str(data.get("victimId", "")),
				str(data.get("victimName", ""))
			)
			
		"player_rescuing":
			player_rescuing.emit(str(data.get("playerId", "")), bool(data.get("isRescuing", false)))
			
		"item_spawned":
			var id = str(data.get("id", ""))
			var type = str(data.get("type", "speed"))
			var pos = Vector3(float(data.get("x", 0)), float(data.get("y", 0.6)), float(data.get("z", 0)))
			item_spawned.emit(id, type, pos)
			
		"item_picked":
			item_picked.emit(
				str(data.get("playerId", "")),
				str(data.get("playerName", "")),
				str(data.get("itemId", "")),
				str(data.get("itemType", ""))
			)
			
		"item_used":
			item_used.emit(
				str(data.get("playerId", "")),
				str(data.get("playerName", "")),
				str(data.get("type", ""))
			)
			
		"banana_placed":
			var pos = Vector3(float(data.get("x", 0)), float(data.get("y", 0.05)), float(data.get("z", 0)))
			var placer_id = str(data.get("placerId", ""))
			banana_placed.emit(pos, placer_id)
			
		"player_damaged":
			player_damaged.emit(data)
			
		"vortex_spawned":
			var pos = Vector3(float(data.get("x", 0)), float(data.get("y", 0.2)), float(data.get("z", 0)))
			vortex_spawned.emit(pos)
			
		"round_ended":
			round_ended.emit(data)
			
		"returned_to_lobby":
			room_data = data
			returned_to_lobby.emit(data)
			game_ended.emit(str(data.get("winner", "")))
			
		"player_ready_updated":
			if data.has("players") and typeof(data["players"]) == TYPE_ARRAY:
				room_data["players"] = data["players"]
			elif room_data.has("players") and typeof(room_data["players"]) == TYPE_ARRAY:
				var p_id = str(data.get("id", ""))
				var p_ready = bool(data.get("isReady", false))
				for p in room_data["players"]:
					if typeof(p) == TYPE_DICTIONARY and str(p.get("id")) == p_id:
						p["isReady"] = p_ready
						break
			player_ready_updated.emit(data)
			player_list_updated.emit()
			
		"public_rooms_updated":
			if typeof(data) == TYPE_ARRAY:
				public_rooms_updated.emit(data)
			
		"chat_message":
			chat_received.emit(str(data.get("msg", "")))
			
		"error":
			connection_error.emit(str(data.get("message", "Unknown server error")))
			
		"pong":
			pass

# ── Outbound Action Helpers ───────────────────────────────────────────────────
func set_ready(ready: bool) -> void:
	send_action("set_ready", { "isReady": ready })

func leave_room() -> void:
	send_action("leave_room", { "playerName": my_player_name })

func set_player_name(new_name: String) -> void:
	my_player_name = new_name
	send_action("set_player_name", { "name": new_name })

func create_room(r_name: String, max_p: int = 8, rounds: int = 3, map_name: String = "SPACE STATION", is_priv: bool = false) -> void:
	selected_map = map_name
	send_action("create_room", {
		"roomName": r_name,
		"playerName": my_player_name,
		"maxPlayers": max_p,
		"rounds": rounds,
		"map": map_name,
		"isPrivate": is_priv
	})

func join_room(code: String) -> void:
	send_action("join_room", {
		"roomCode": code,
		"playerName": my_player_name
	})

func update_room_settings(max_p: int, rounds: int, map_name: String, is_priv: bool = false) -> void:
	selected_map = map_name
	send_action("update_settings", {
		"maxPlayers": max_p,
		"rounds": rounds,
		"map": map_name,
		"isPrivate": is_priv
	})

func start_game() -> void:
	send_action("start_game")

func return_to_lobby() -> void:
	send_action("return_to_lobby")

func send_move(pos: Vector3, rot_y: float) -> void:
	send_action("move", {
		"x": round(pos.x * 100.0) / 100.0,
		"y": round(pos.y * 100.0) / 100.0,
		"z": round(pos.z * 100.0) / 100.0,
		"rotY": round(rot_y * 100.0) / 100.0
	})

func send_tag(victim_id: String) -> void:
	send_action("tag_player", { "victimId": victim_id })

func send_rescue(victim_id: String) -> void:
	send_action("rescue_player", { "victimId": victim_id })

func send_rescuing(is_rescuing: bool) -> void:
	send_action("rescuing_state", { "isRescuing": is_rescuing })

func send_pick_item(item_id: String) -> void:
	send_action("pick_item", { "itemId": item_id })

func send_use_item() -> void:
	send_action("use_item")

func send_tackle(target_id: String) -> void:
	send_action("tackle_player", { "targetId": target_id })

func send_banana_placed(pos: Vector3) -> void:
	send_action("place_banana", {
		"x": round(pos.x * 100.0) / 100.0,
		"y": round(pos.y * 100.0) / 100.0,
		"z": round(pos.z * 100.0) / 100.0
	})

# ── Query Public Room Browser via WebSocket and HTTP REST ───────────────────────
func fetch_public_rooms() -> void:
	# 1. Fetch via active WebSocket connection (instant)
	if is_connected_to_server and ws_peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		send_action("get_rooms")
	
	# 2. Also query REST API as fallback
	if http_request and not server_http_url.is_empty():
		if http_request.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
			var url = server_http_url + "/api/rooms"
			http_request.request(url)

func _on_http_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code == 200:
		var json_str = body.get_string_from_utf8()
		var parsed = JSON.parse_string(json_str)
		if typeof(parsed) == TYPE_ARRAY:
			public_rooms_updated.emit(parsed)
	else:
		print("[Network] HTTP rooms response code: ", response_code)

# ── Solo Practice Mode (Offline with Bots) ───────────────────────────────────
func start_solo_practice() -> void:
	is_solo_mode = true
	disconnect_from_server()
	get_tree().change_scene_to_file("res://scenes/3d/arena_3d.tscn")

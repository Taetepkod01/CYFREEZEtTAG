extends CharacterBody2D

signal item_used(item_type: String)
signal player_tagged(tagger_id: int, victim_id: int)
signal player_rescued(rescuer_id: int, victim_id: int)

@export var peer_id: int = 1
@export var player_name: String = "Player"
@export var role: String = "runner" # "chaser" or "runner"
@export var is_frozen: bool = false
@export var is_bot: bool = false

var base_speed: float = 210.0
var speed_multiplier: float = 1.0
var has_shield: bool = false
var is_ghost: bool = false
var is_stunned: bool = false
var held_item: String = ""

# Timer references for buffs
var buff_timers: Dictionary = {}

# Node references
@onready var name_label: Label = $NameLabel
@onready var role_badge: Label = $RoleBadge
@onready var interaction_area: Area2D = $InteractionArea
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# AI State
var bot_target_pos: Vector2 = Vector2.ZERO
var bot_repath_timer: float = 0.0

func _ready() -> void:
	name_label.text = player_name
	_update_appearance()
	interaction_area.body_entered.connect(_on_interaction_body_entered)

func setup(p_id: int, p_name: String, p_role: String, bot: bool = false) -> void:
	peer_id = p_id
	player_name = p_name
	role = p_role
	is_bot = bot
	name = str(p_id)
	
	if name_label:
		name_label.text = player_name
	_update_appearance()

func is_local_player() -> bool:
	if Network.is_solo_mode:
		return not is_bot
	return multiplayer.get_unique_id() == peer_id

func _physics_process(delta: float) -> void:
	# Handle buffs timing
	_process_buffs(delta)
	
	if is_frozen or is_stunned:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	
	var move_dir := Vector2.ZERO
	
	if is_local_player():
		move_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		# Also support WASD explicitly
		if move_dir == Vector2.ZERO:
			var dx = Input.get_axis("move_left", "move_right")
			var dy = Input.get_axis("move_up", "move_down")
			move_dir = Vector2(dx, dy).normalized()
		
		# Item activation
		if Input.is_action_just_pressed("use_item") or Input.is_key_pressed(KEY_E):
			use_held_item()
		
		if not Network.is_solo_mode and multiplayer.has_multiplayer_peer():
			rpc("sync_position", global_position, velocity)
	elif is_bot and (Network.is_solo_mode or multiplayer.is_server()):
		move_dir = _calculate_bot_movement(delta)
	
	# Current speed
	var current_speed = base_speed * speed_multiplier
	if role == "chaser":
		current_speed *= 1.08 # Chaser is slightly faster
	
	velocity = move_dir * current_speed
	
	# Ghost mode: disable wall collisions (layer 1)
	set_collision_mask_value(1, not is_ghost)
	
	move_and_slide()
	queue_redraw()

# ── Buff System ─────────────────────────────────────────────────────────────
func _process_buffs(delta: float) -> void:
	var expired_keys := []
	for buff in buff_timers:
		buff_timers[buff] -= delta
		if buff_timers[buff] <= 0:
			expired_keys.append(buff)
	
	for buff in expired_keys:
		buff_timers.erase(buff)
		match buff:
			"speed":
				speed_multiplier = 1.0
			"ghost":
				is_ghost = false
			"stun":
				is_stunned = false
		_update_appearance()

func apply_item_effect(type: String) -> void:
	match type:
		"speed":
			speed_multiplier = 1.6
			buff_timers["speed"] = 6.0
		"ghost":
			is_ghost = true
			buff_timers["ghost"] = 4.5
		"shield":
			has_shield = true
		"heater":
			if is_frozen:
				unfreeze()
			has_shield = true
			buff_timers["speed"] = 3.0
			speed_multiplier = 1.3
		"banana":
			# Drops a banana trap at current position
			var mgr = get_tree().current_scene
			if mgr and mgr.has_method("spawn_banana_trap"):
				mgr.spawn_banana_trap(global_position)
		"blackhole":
			var mgr = get_tree().current_scene
			if mgr and mgr.has_method("spawn_vortex"):
				mgr.spawn_vortex(global_position)
	
	_update_appearance()

func use_held_item() -> void:
	if held_item.is_empty():
		return
	var item_to_use = held_item
	held_item = ""
	apply_item_effect(item_to_use)
	item_used.emit(item_to_use)
	if not Network.is_solo_mode and multiplayer.has_multiplayer_peer():
		rpc("sync_item_used", item_to_use)

@rpc("any_peer", "call_local")
func sync_item_used(item_type: String) -> void:
	apply_item_effect(item_type)

# ── Tagging & Freezing ──────────────────────────────────────────────────────
func set_frozen(frozen_state: bool) -> void:
	is_frozen = frozen_state
	if is_frozen:
		velocity = Vector2.ZERO
		has_shield = false
		is_ghost = false
		speed_multiplier = 1.0
	_update_appearance()

func freeze() -> void:
	if has_shield:
		has_shield = false
		# Shield saved the player!
		_update_appearance()
		return
	set_frozen(true)
	if not Network.is_solo_mode and multiplayer.has_multiplayer_peer():
		rpc("sync_freeze_state", true)

func unfreeze() -> void:
	set_frozen(false)
	if not Network.is_solo_mode and multiplayer.has_multiplayer_peer():
		rpc("sync_freeze_state", false)

@rpc("any_peer", "call_local")
func sync_freeze_state(state: bool) -> void:
	set_frozen(state)

func stun(duration: float = 2.0) -> void:
	is_stunned = true
	buff_timers["stun"] = duration
	_update_appearance()

# ── Collision with other players ────────────────────────────────────────────
func _on_interaction_body_entered(body: Node2D) -> void:
	if body == self or not (body is CharacterBody2D):
		return
	
	var other = body
	# 1. Chaser tags Runner
	if role == "chaser" and other.role == "runner" and not other.is_frozen:
		if is_local_player() or (is_bot and (Network.is_solo_mode or multiplayer.is_server())):
			other.freeze()
			player_tagged.emit(peer_id, other.peer_id)
			var mgr = get_tree().current_scene
			if mgr and mgr.has_method("on_player_tagged"):
				mgr.on_player_tagged(player_name, other.player_name)
	
	# 2. Unfrozen Runner unfreezes frozen Runner
	elif role == "runner" and not is_frozen and other.role == "runner" and other.is_frozen:
		if is_local_player() or (is_bot and (Network.is_solo_mode or multiplayer.is_server())):
			other.unfreeze()
			player_rescued.emit(peer_id, other.peer_id)
			var mgr = get_tree().current_scene
			if mgr and mgr.has_method("on_player_unfrozen"):
				mgr.on_player_unfrozen(player_name, other.player_name)

# ── Position Sync ───────────────────────────────────────────────────────────
@rpc("unreliable")
func sync_position(pos: Vector2, vel: Vector2) -> void:
	if not is_local_player():
		global_position = global_position.lerp(pos, 0.4)
		velocity = vel

# ── Bot AI ──────────────────────────────────────────────────────────────────
func _calculate_bot_movement(delta: float) -> Vector2:
	bot_repath_timer -= delta
	var players_node = get_parent()
	if not players_node:
		return Vector2.ZERO
	
	if role == "chaser":
		# Chase closest unfrozen runner
		var closest_target: Node2D = null
		var min_dist: float = 999999.0
		for p in players_node.get_children():
			if p != self and p.role == "runner" and not p.is_frozen:
				var dist = global_position.distance_to(p.global_position)
				if dist < min_dist:
					min_dist = dist
					closest_target = p
		
		if closest_target:
			return (closest_target.global_position - global_position).normalized()
	else:
		# Runner AI:
		# If a teammate is frozen, occasionally attempt rescue if chaser is far
		var chaser: Node2D = null
		var frozen_runner: Node2D = null
		for p in players_node.get_children():
			if p != self:
				if p.role == "chaser":
					chaser = p
				elif p.role == "runner" and p.is_frozen:
					frozen_runner = p
		
		if chaser and global_position.distance_to(chaser.global_position) < 250.0:
			# Flee away from chaser
			var flee_dir = (global_position - chaser.global_position).normalized()
			return flee_dir
		elif frozen_runner:
			# Go rescue frozen teammate
			return (frozen_runner.global_position - global_position).normalized()
		elif bot_repath_timer <= 0:
			bot_repath_timer = randf_range(1.5, 3.5)
			bot_target_pos = global_position + Vector2(randf_range(-200, 200), randf_range(-200, 200))
			return (bot_target_pos - global_position).normalized()
		
	return Vector2.ZERO

# ── Custom Visual Appearance ────────────────────────────────────────────────
func _update_appearance() -> void:
	if not role_badge:
		return
	
	if is_frozen:
		role_badge.text = " FROZEN "
		role_badge.modulate = Color(0.3, 0.9, 1.0)
	elif role == "chaser":
		role_badge.text = " CHASER"
		role_badge.modulate = Color(1.0, 0.3, 0.3)
	else:
		role_badge.text = " RUNNER"
		role_badge.modulate = Color(1.0, 0.9, 0.4)
	
	queue_redraw()

func _draw() -> void:
	var radius := 18.0
	
	if is_frozen:
		# Ice block effect
		draw_rect(Rect2(-22, -22, 44, 44), Color(0.2, 0.7, 0.95, 0.45), true)
		draw_rect(Rect2(-22, -22, 44, 44), Color(0.7, 0.95, 1.0, 0.9), false, 2.5)
		draw_circle(Vector2.ZERO, radius, Color(0.3, 0.8, 1.0, 0.7))
		return
	
	# Glow / Outer ring
	var ring_color = Color(1.0, 0.2, 0.2, 0.9) if role == "chaser" else Color(0.3, 0.8, 1.0, 0.9)
	if has_shield:
		ring_color = Color(0.4, 1.0, 0.4, 0.9)
	elif is_ghost:
		ring_color = Color(0.9, 0.5, 1.0, 0.5)
	
	draw_arc(Vector2.ZERO, radius + 4, 0, TAU, 32, ring_color, 3.0)
	
	# Body circle
	var body_color = Color(0.85, 0.2, 0.2) if role == "chaser" else Color(0.15, 0.55, 0.95)
	if is_ghost:
		body_color.a = 0.5
	draw_circle(Vector2.ZERO, radius, body_color)
	
	# Eyes / directional face indicator
	var face_dir = velocity.normalized() if velocity.length() > 5 else Vector2.RIGHT
	draw_circle(face_dir * 8 + Vector2(-face_dir.y, face_dir.x) * 4, 3.0, Color.WHITE)
	draw_circle(face_dir * 8 - Vector2(-face_dir.y, face_dir.x) * 4, 3.0, Color.WHITE)
	draw_circle(face_dir * 9 + Vector2(-face_dir.y, face_dir.x) * 4, 1.5, Color.BLACK)
	draw_circle(face_dir * 9 - Vector2(-face_dir.y, face_dir.x) * 4, 1.5, Color.BLACK)

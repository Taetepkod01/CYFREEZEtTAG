extends CharacterBody3D

signal tagged(tagger: CharacterBody3D, victim: CharacterBody3D)
signal rescued(rescuer: CharacterBody3D, victim: CharacterBody3D)
signal item_used(item_name: String)
signal item_picked_up(item_name: String)
signal item_changed(item_name: String)
signal player_damaged(target: CharacterBody3D, amount: int)

@export var player_name: String = "Player"
@export var role: String = "runner" # "tagger" or "runner"
@export var is_frozen: bool = false
@export var is_rescuing: bool = false
@export var is_bot: bool = false
@export var is_remote: bool = false
@export var network_id: String = ""

# Individual stats for MVP
var freeze_count: int = 0
var rescue_count: int = 0

# Tag cooldown: prevents tagger from re-triggering tag while still overlapping
var tag_cooldown_timer: float = 0.0
const TAG_COOLDOWN: float = 0.35

# Movement Parameters
@export var walk_speed: float = 7.5
@export var run_speed: float = 11.0
@export var jump_velocity: float = 5.8
@export var mouse_sensitivity: float = 0.0025
const ANIM_SPEED_SCALE_FACTOR: float = 0.33 # Calibrated for 1.1s cycle stride: 7.5 m/s -> ~2.5x speed scale

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

# Single Held Item Slot
var held_item: String = ""
var has_shield: bool = false
var speed_boost_timer: float = 0.0
var shield_timer: float = 0.0
var hp: int = 100
var invincible_timer: float = 0.0

# Tackle Dash Attack (1.5x Speed, deals 20 damage to opposing Tagger)
var is_tackling: bool = false
var tackle_timer: float = 0.0
var tackle_direction: Vector3 = Vector3.FORWARD

# Dizzy Stars on Banana Slip
var is_dizzy: bool = false
var dizzy_timer: float = 0.0

# Teammate rescue scatter split
var scatter_timer: float = 0.0
var scatter_direction: Vector3 = Vector3.ZERO

# Remote Interpolation
var target_remote_pos: Vector3 = Vector3.ZERO
var target_remote_rot_y: float = 0.0
var last_sent_pos: Vector3 = Vector3.ZERO
var last_sent_rot_y: float = 0.0

# Camera & Pivot
@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D
@onready var visuals: Node3D = $Visuals
@onready var body_mesh: MeshInstance3D = $Visuals/BodyMesh
@onready var role_ring: MeshInstance3D = $Visuals/RoleRing
@onready var ice_block: MeshInstance3D = $Visuals/IceBlock
@onready var shield_domain: MeshInstance3D = $Visuals/ShieldDomain
@onready var dizzy_stars: Label3D = $Visuals/DizzyStars
@onready var name_tag: Label3D = $Visuals/NameTag
@onready var interaction_area: Area3D = $InteractionArea3D
@onready var snowman_model: Node3D = $Visuals/SnowmanModel
@onready var penguin_model: Node3D = $Visuals/PenguinModel
var snowman_anim: AnimationPlayer = null
var penguin_anim: AnimationPlayer = null

# Bot AI Navigation & Anti-Stuck
var bot_timer: float = 0.0
var bot_dir: Vector3 = Vector3.FORWARD
var bot_last_pos: Vector3 = Vector3.ZERO
var bot_stuck_time: float = 0.0
var bot_unstuck_timer: float = 0.0
var bot_unstuck_dir: Vector3 = Vector3.ZERO
var bot_jump_cooldown: float = 0.0

# Right-mouse button drag support
var is_rmb_down: bool = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all_movement_inputs()

func _release_all_movement_inputs() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down", "jump"]:
		Input.action_release(action)
	velocity.x = 0.0
	velocity.z = 0.0
	is_rmb_down = false

func _ready() -> void:
	if snowman_model and snowman_model.has_node("AnimationPlayer"):
		snowman_anim = snowman_model.get_node("AnimationPlayer")
	if penguin_model and penguin_model.has_node("AnimationPlayer"):
		penguin_anim = penguin_model.get_node("AnimationPlayer")
	
	name_tag.text = player_name
	target_remote_pos = global_position
	target_remote_rot_y = rotation.y
	_update_role_visuals()
	
	if is_local_player():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		camera.current = true
		spring_arm.visible = true
		spring_arm.add_excluded_object(get_rid())
	else:
		camera.current = false
		spring_arm.visible = false
	
	interaction_area.body_entered.connect(_on_interaction_body_entered)

func is_local_player() -> bool:
	return not is_bot and not is_remote

func update_remote_transform(pos: Vector3, rot_y: float) -> void:
	target_remote_pos = pos
	target_remote_rot_y = rot_y

func _unhandled_input(event: InputEvent) -> void:
	if not is_local_player():
		return
	
	# Track Right Mouse Button for dragging camera even if pointer lock is lost
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			is_rmb_down = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				get_viewport().set_input_as_handled()
				return
	
	# Toggle mouse free/lock with Alt or Escape
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ALT or event.keycode == KEY_ESCAPE:
			if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			_release_all_movement_inputs()
			get_viewport().set_input_as_handled()
			return

	if is_frozen:
		return
	
	# Third-Person Mouse Look (supports captured mouse mode OR RMB drag)
	if event is InputEventMouseMotion:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED or is_rmb_down:
			rotate_y(-event.relative.x * mouse_sensitivity)
			spring_arm.rotate_x(-event.relative.y * mouse_sensitivity)
			spring_arm.rotation.x = clamp(spring_arm.rotation.x, deg_to_rad(-65.0), deg_to_rad(45.0))

func _physics_process(delta: float) -> void:
	_process_buffs(delta)
	
	# If this is a remote online player, smoothly lerp to received network position
	if is_remote:
		var dist = global_position.distance_to(target_remote_pos)
		global_position = global_position.lerp(target_remote_pos, 16.0 * delta)
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_remote_rot_y, 16.0 * delta)
		
		var r_anim: AnimationPlayer = snowman_anim if role == "tagger" else penguin_anim
		if r_anim:
			if is_frozen:
				if r_anim.is_playing():
					r_anim.pause()
			elif dist > 0.04:
				if not r_anim.is_playing() or r_anim.current_animation != "ArmatureAction":
					r_anim.play("ArmatureAction")
				var remote_speed = dist / max(delta, 0.001)
				r_anim.speed_scale = clamp(remote_speed * ANIM_SPEED_SCALE_FACTOR, 0.2, 5.5)
			else:
				if r_anim.is_playing():
					r_anim.stop()
		return
	
	# Apply Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# Single Item Use Trigger: Press [E]
	if is_local_player():
		if Input.is_action_just_pressed("use_item") or Input.is_key_pressed(KEY_E):
			if not is_frozen or held_item == "heater":
				use_held_item()
	elif is_bot and not held_item.is_empty():
		if (is_frozen and held_item == "heater") or (not is_frozen and randf() < 0.02):
			use_held_item()

	if is_frozen:
		velocity.x = move_toward(velocity.x, 0, walk_speed)
		velocity.z = move_toward(velocity.z, 0, walk_speed)
		move_and_slide()
		var frozen_anim: AnimationPlayer = snowman_anim if role == "tagger" else penguin_anim
		if frozen_anim and frozen_anim.is_playing():
			frozen_anim.pause()
		_send_network_position(delta)
		return

	# Handle Tackle Dash
	if is_tackling:
		tackle_timer -= delta
		if tackle_timer <= 0.0:
			is_tackling = false
		else:
			var dash_speed = run_speed * 1.5
			velocity.x = tackle_direction.x * dash_speed
			velocity.z = tackle_direction.z * dash_speed
			move_and_slide()
			_send_network_position(delta)
			return

	# Continuous proximity interactions (tagging, rescuing, rescuing visual state)
	_check_continuous_interactions()

	# Handle Jump
	if is_local_player() and is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
	
	# Movement Vector Calculation
	var move_dir := Vector3.ZERO
	if is_local_player():
		var x = Input.get_axis("move_left", "move_right")
		var y = Input.get_axis("move_up", "move_down")
		var input_vec = Vector2(x, y).normalized()
		move_dir = (transform.basis * Vector3(input_vec.x, 0, input_vec.y)).normalized()
	elif is_bot:
		move_dir = _calculate_bot_direction(delta)
	
	var current_speed = walk_speed
	if role == "tagger":
		current_speed *= 1.1 # Taggers are slightly faster
	if speed_boost_timer > 0.0:
		current_speed = run_speed * 1.3
	
	if move_dir != Vector3.ZERO:
		velocity.x = move_dir.x * current_speed
		velocity.z = move_dir.z * current_speed
		
		var target_rotation = atan2(-move_dir.x, -move_dir.z)
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_rotation - rotation.y, 14.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)
	
	move_and_slide()
	
	# Update walk animation
	var active_anim: AnimationPlayer = snowman_anim if role == "tagger" else penguin_anim
	if active_anim:
		var horiz_vel = Vector2(velocity.x, velocity.z)
		var current_ground_speed = horiz_vel.length()
		if is_on_floor() and current_ground_speed > 0.3:
			if not active_anim.is_playing() or active_anim.current_animation != "ArmatureAction":
				active_anim.play("ArmatureAction")
			active_anim.speed_scale = clamp(current_ground_speed * ANIM_SPEED_SCALE_FACTOR, 0.2, 5.5)
		else:
			if active_anim.is_playing():
				active_anim.stop()
	
	# Void Fall Protection: If fallen below the station/map, teleport back to safe random spawn
	if global_position.y < -3.0:
		_recover_from_void()
		
	_send_network_position(delta)

func _recover_from_void() -> void:
	velocity = Vector3.ZERO
	var safe_pos = Vector3(0.0, 0.5, 0.0)
	
	var arena = get_tree().current_scene
	if arena and "current_map_node" in arena and arena.current_map_node != null:
		var map = arena.current_map_node
		if map.has_method("get_random_safe_spawn"):
			safe_pos = map.get_random_safe_spawn()
		elif role == "tagger" and map.has_method("get_tagger_spawn"):
			safe_pos = map.get_tagger_spawn()
		elif map.has_method("get_runner_spawn"):
			safe_pos = map.get_runner_spawn()
	else:
		var default_spawns = [
			Vector3(0.0, 0.5, 0.0),
			Vector3(0.0, 0.5, -20.0),
			Vector3(0.0, 0.5, 20.0),
			Vector3(-22.0, 0.5, 0.0),
			Vector3(22.0, 0.5, 0.0)
		]
		safe_pos = default_spawns.pick_random()
	
	global_position = safe_pos
	
	if is_local_player():
		if arena and arena.has_method("add_game_log"):
			arena.add_game_log("[color=#ff9800]⚠️ Fell into space! Teleported back to station.[/color]")
		if Network and Network.is_online_game():
			Network.send_move(global_position, rotation.y)

func _send_network_position(delta: float) -> void:
	if not is_local_player() or not Network or not Network.is_online_game():
		return
	Network.move_throttle_timer -= delta
	if Network.move_throttle_timer <= 0.0:
		# Only send if position or rotation has actually changed to save bandwidth & reduce lag
		var rot = visuals.rotation.y + rotation.y
		if global_position.distance_to(last_sent_pos) > 0.04 or abs(rot - last_sent_rot_y) > 0.05:
			Network.move_throttle_timer = Network.MOVE_SEND_RATE
			last_sent_pos = global_position
			last_sent_rot_y = rot
			Network.send_move(global_position, rot)

# -- Item Pickup & Use -------------------------------------------------------
func pick_up_item(type: String) -> void:
	if not held_item.is_empty():
		return
	
	# REQUIREMENT: Chaser (Tagger) CANNOT pick up heater!
	if type == "heater" and role == "tagger":
		return
	
	# REQUIREMENT: Tackle is for Runners
	if type == "tackle" and role == "tagger":
		return
	
	held_item = type
	item_picked_up.emit(type)
	item_changed.emit(type)

func use_held_item() -> void:
	if held_item.is_empty():
		return
	
	var item_to_use = held_item
	held_item = ""
	item_changed.emit("")
	
	if is_local_player() and Network and Network.is_online_game():
		Network.send_use_item()
	
	match item_to_use:
		"speed":
			speed_boost_timer = 6.0
			item_used.emit("SPEED BOOST")
		"shield":
			has_shield = true
			shield_timer = 15.0 # Stay active until hit or 15s
			_update_role_visuals()
			item_used.emit("BLUE SHIELD DOMAIN")
		"heater":
			if is_frozen:
				unfreeze()
			has_shield = true
			shield_timer = 5.0
			_update_role_visuals()
			item_used.emit("HEATER")
		"banana":
			# REQUIREMENT: Release banana BEHIND player on ground, placer is immune
			var backward_dir = transform.basis.z.normalized()
			var drop_pos = global_position + backward_dir * 1.8
			drop_pos.y = 0.05
			var arena = get_parent().get_parent() if get_parent() else null
			if arena and arena.has_method("spawn_banana_trap"):
				arena.spawn_banana_trap(drop_pos, self, network_id)
			if is_local_player() and Network and Network.is_online_game():
				Network.send_banana_placed(drop_pos)
			item_used.emit("BANANA TRAP (DROPPED BEHIND)")
		"vortex":
			# REQUIREMENT: Black Hole teleports the user to a random position on the map!
			var rx = randf_range(-22.0, 22.0)
			var rz = randf_range(-22.0, 22.0)
			global_position = Vector3(rx, 0.5, rz)
			item_used.emit("BLACK HOLE TELEPORT")
		"tackle":
			# REQUIREMENT: Runner tackles forward at 1.5x speed, deals 20 damage to Tagger, immune to freeze and gets 2s invulnerability
			is_tackling = true
			tackle_timer = 1.0
			invincible_timer = 3.0 # Immune during 1s dash + 2s immunity
			tackle_direction = -transform.basis.z.normalized()
			_update_role_visuals()
			item_used.emit("DASH TACKLE (1.5x - IMMUNITY)")

func take_damage(amount: int) -> void:
	hp = max(0, hp - amount)
	# Flash red
	if body_mesh:
		var flash_mat = StandardMaterial3D.new()
		flash_mat.albedo_color = Color(1.0, 0.1, 0.1)
		flash_mat.emission_enabled = true
		flash_mat.emission = Color(1.0, 0.2, 0.2)
		body_mesh.set_surface_override_material(0, flash_mat)
		get_tree().create_timer(0.2).timeout.connect(func(): _update_role_visuals())

func slip_on_banana() -> void:
	# Placer / immune players do not slip
	if is_frozen or is_tackling or invincible_timer > 0.0:
		return
	freeze()
	is_dizzy = true
	dizzy_timer = 2.5
	if dizzy_stars:
		dizzy_stars.text = "*  *  *"
		dizzy_stars.visible = true
	_update_role_visuals()

func _process_buffs(delta: float) -> void:
	if tag_cooldown_timer > 0.0:
		tag_cooldown_timer -= delta
	if scatter_timer > 0.0:
		scatter_timer -= delta
	if speed_boost_timer > 0.0:
		speed_boost_timer -= delta
	if shield_timer > 0.0:
		shield_timer -= delta
		if shield_timer <= 0.0:
			has_shield = false
			_update_role_visuals()
	
	if invincible_timer > 0.0:
		invincible_timer -= delta
		# Golden/Cyan flashing aura while invincible
		if body_mesh:
			var flash_on = (int(invincible_timer * 12.0) % 2 == 0)
			body_mesh.transparency = 0.4 if flash_on else 0.0
		if invincible_timer <= 0.0:
			if body_mesh:
				body_mesh.transparency = 0.0
			_update_role_visuals()
	
	if is_dizzy:
		dizzy_timer -= delta
		# REQUIREMENT: Player visibly spins around rapidly in circles for ~2.5s
		visuals.rotate_y(16.0 * delta)
		if dizzy_stars:
			dizzy_stars.rotate_y(8.0 * delta)
		if dizzy_timer <= 0.0:
			is_dizzy = false
			visuals.rotation.y = 0.0
			if dizzy_stars:
				dizzy_stars.visible = false
			if is_frozen:
				unfreeze()

# -- Freeze & Tag Mechanics --------------------------------------------------
func freeze() -> void:
	# REQUIREMENT: Runner using dash tackle or having 2s immunity CANNOT be frozen!
	if is_tackling or invincible_timer > 0.0:
		return
	
	# REQUIREMENT: Blue Shield Domain absorbs tag, then pops and disappears!
	if has_shield:
		has_shield = false
		shield_timer = 0.0
		_update_role_visuals()
		item_used.emit("SHIELD BROKE!")
		return
	
	is_frozen = true
	is_rescuing = false
	_update_role_visuals()

func unfreeze() -> void:
	is_frozen = false
	is_rescuing = false
	is_dizzy = false
	if dizzy_stars:
		dizzy_stars.visible = false
	var cur_anim: AnimationPlayer = snowman_anim if role == "tagger" else penguin_anim
	if cur_anim and cur_anim.is_playing():
		cur_anim.stop()
	_update_role_visuals()

func _update_role_visuals() -> void:
	if not is_inside_tree():
		return
	
	if snowman_model and penguin_model:
		snowman_model.visible = (role == "tagger")
		penguin_model.visible = (role == "runner")
	
	ice_block.visible = is_frozen
	if shield_domain:
		# Glowing domain sphere around player when shield or invulnerability is active
		shield_domain.visible = has_shield or invincible_timer > 0.0 or is_tackling
	
	var body_mat = StandardMaterial3D.new()
	var ring_mat = StandardMaterial3D.new()
	
	if is_frozen:
		name_tag.text = player_name + "\n[FROZEN]"
		name_tag.modulate = Color(0.3, 0.9, 1.0)
		body_mat.albedo_color = Color(0.4, 0.8, 1.0)
		ring_mat.albedo_color = Color(0.3, 0.9, 1.0)
	elif role == "tagger":
		name_tag.text = player_name + "\n[TAGGER]"
		name_tag.modulate = Color(1.0, 0.3, 0.3)
		body_mat.albedo_color = Color(0.9, 0.25, 0.2)
		ring_mat.albedo_color = Color(1.0, 0.2, 0.2)
		ring_mat.emission_enabled = true
		ring_mat.emission = Color(1.0, 0.2, 0.2)
		ring_mat.emission_energy_multiplier = 2.0
	elif is_rescuing:
		name_tag.text = player_name + "\n[RESCUING]"
		name_tag.modulate = Color(1.0, 0.9, 0.2)
		body_mat.albedo_color = Color(0.9, 0.8, 0.2)
		ring_mat.albedo_color = Color(1.0, 0.9, 0.2)
		ring_mat.emission_enabled = true
		ring_mat.emission = Color(1.0, 0.9, 0.2)
	else:
		name_tag.text = player_name + "\n[RUNNER]"
		name_tag.modulate = Color(0.4, 0.9, 0.4)
		body_mat.albedo_color = Color(0.2, 0.6, 0.95)
		ring_mat.albedo_color = Color(0.2, 0.8, 1.0)
	
	body_mesh.set_surface_override_material(0, body_mat)
	role_ring.set_surface_override_material(0, ring_mat)

func _on_interaction_body_entered(other: Node3D) -> void:
	if other == self or not (other is CharacterBody3D):
		return
	_handle_interaction(other)

func _check_continuous_interactions() -> void:
	if not interaction_area or is_frozen:
		return
	
	var overlapping = interaction_area.get_overlapping_bodies()
	for other in overlapping:
		if other == self or not (other is CharacterBody3D):
			continue
		_handle_interaction(other)

func _handle_interaction(other: CharacterBody3D) -> void:
	# 1. Tackle hit check: If tackling runner hits opposing tagger
	if is_tackling and role == "runner" and other.role == "tagger":
		_handle_tackle_hit(other)
		return
	
	# If tagger attempts to tag an invincible or tackling runner, ignore tag
	if role == "tagger" and other.role == "runner":
		if other.is_tackling or other.invincible_timer > 0.0:
			return
	
	# Online game collision: authoritatively notify server
	if is_local_player() and Network and Network.is_online_game():
		if role == "tagger" and other.role == "runner" and not other.is_frozen:
			if not other.is_tackling and other.invincible_timer <= 0.0:
				Network.send_tag(other.network_id)
		elif role == "runner" and not is_frozen and other.role == "runner" and other.is_frozen:
			Network.send_rescue(other.network_id)
		return
	
	# Offline practice mode collision
	# Tagger tagging Runner (Instant freeze on contact!)
	if role == "tagger" and not is_frozen and other.role == "runner" and not other.is_frozen:
		if not other.is_tackling and other.invincible_timer <= 0.0:
			if tag_cooldown_timer > 0.0:
				return
			tag_cooldown_timer = TAG_COOLDOWN
			other.freeze()
			freeze_count += 1
			tagged.emit(self, other)
			# Knockback tagger slightly to prevent sticking
			var push_dir = (global_position - other.global_position).normalized()
			push_dir.y = 0.0
			velocity += push_dir * walk_speed * 1.5
	
	# Runner rescuing frozen teammate (Instant rescue & scatter in opposite directions!)
	elif role == "runner" and not is_frozen and other.role == "runner" and other.is_frozen:
		other.unfreeze()
		rescue_count += 1
		rescued.emit(self, other)
		
		# Scatter both runners in opposite divergent directions
		var base_dir = (other.global_position - global_position).normalized()
		if base_dir.is_zero_approx():
			base_dir = -transform.basis.z.normalized()
		base_dir.y = 0.0
		
		var scatter_angle = deg_to_rad(65.0)
		scatter_timer = 2.0
		scatter_direction = base_dir.rotated(Vector3.UP, -scatter_angle).normalized()
		
		other.scatter_timer = 2.0
		other.scatter_direction = base_dir.rotated(Vector3.UP, scatter_angle).normalized()

func _handle_tackle_hit(other: CharacterBody3D) -> void:
	is_tackling = false
	invincible_timer = 2.0 # 2 seconds of complete invulnerability upon hit!
	_update_role_visuals()
	other.take_damage(20)
	player_damaged.emit(other, 20)
	item_used.emit("TACKLED TAGGER! (-20 HP, 2s IMMUNITY)")
	
	if is_local_player() and Network and Network.is_online_game():
		Network.send_tackle(other.network_id)

# -- 3D Bot AI ---------------------------------------------------------------
func _calculate_bot_direction(delta: float) -> Vector3:
	bot_timer -= delta
	bot_jump_cooldown -= delta
	
	# Anti-stuck position check
	var dist_moved = global_position.distance_to(bot_last_pos)
	bot_last_pos = global_position
	
	if dist_moved < 0.05:
		bot_stuck_time += delta
		if bot_stuck_time > 0.35:
			# Stuck against an obstacle/wall!
			bot_unstuck_timer = randf_range(0.8, 1.3)
			var escape_angle = [-2.0, -1.2, 1.2, 2.0].pick_random()
			bot_unstuck_dir = bot_dir.rotated(Vector3.UP, escape_angle).normalized()
			if is_on_floor() and bot_jump_cooldown <= 0.0:
				velocity.y = jump_velocity * 0.85
				bot_jump_cooldown = 1.4
			bot_stuck_time = 0.0
	else:
		bot_stuck_time = max(0.0, bot_stuck_time - delta * 1.5)
	
	if bot_unstuck_timer > 0.0:
		bot_unstuck_timer -= delta
		return _avoid_walls(bot_unstuck_dir)

	# If currently scattering after a rescue, run full speed along scatter direction
	if scatter_timer > 0.0 and scatter_direction != Vector3.ZERO:
		return _avoid_walls(scatter_direction)

	var arena = get_parent()
	if not arena:
		return _avoid_walls(bot_dir)
	
	var desired_dir := Vector3.ZERO
	
	if role == "tagger":
		# TAGGER AI: Relentlessly seek the closest unfrozen runner
		var closest_runner: CharacterBody3D = null
		var min_d: float = 99999.0
		for child in arena.get_children():
			if child is CharacterBody3D and child != self and child.role == "runner" and not child.is_frozen:
				var d = global_position.distance_to(child.global_position)
				if d < min_d:
					min_d = d
					closest_runner = child
		
		if closest_runner:
			var to_target = (closest_runner.global_position - global_position)
			to_target.y = 0.0
			desired_dir = to_target.normalized()
			
			# Aggressive jump when close or pursuing around obstacle
			if min_d < 3.5 and is_on_floor() and bot_jump_cooldown <= 0.0 and randf() < 0.05:
				velocity.y = jump_velocity * 0.75
				bot_jump_cooldown = 1.8
		else:
			# If all runners are frozen or none in range, keep actively moving
			if bot_timer <= 0.0:
				bot_timer = randf_range(2.0, 3.5)
				var angle = randf_range(0, TAU)
				bot_dir = Vector3(cos(angle), 0, sin(angle)).normalized()
			desired_dir = bot_dir
	else:
		# RUNNER AI: Dynamic survival, teammate rescue & evasion
		var nearest_tagger: CharacterBody3D = null
		var tagger_d: float = 99999.0
		var nearest_frozen: CharacterBody3D = null
		var frozen_d: float = 99999.0
		var living_runner_repel := Vector3.ZERO
		
		for child in arena.get_children():
			if child is CharacterBody3D and child != self:
				var d = global_position.distance_to(child.global_position)
				# ONLY flee from taggers who are active and not frozen!
				if child.role == "tagger" and not child.is_frozen:
					if d < tagger_d:
						tagger_d = d
						nearest_tagger = child
				elif child.role == "runner":
					if child.is_frozen:
						if d < frozen_d:
							frozen_d = d
							nearest_frozen = child
					else:
						# Living teammate: NEVER run away from each other!
						# Just provide gentle non-overlapping separation if extremely close (< 2.2m)
						if d < 2.2 and d > 0.01:
							var away_mate = (global_position - child.global_position).normalized()
							away_mate.y = 0.0
							living_runner_repel += away_mate * (2.2 - d) * 0.35
		
		# Decision Priority:
		# 1. Threat avoidance: Tagger is actively dangerous & in proximity (< 9.0m) -> SMART FLEE!
		if nearest_tagger and tagger_d < 9.0:
			desired_dir = _find_smart_escape_dir(nearest_tagger.global_position)
			
			# Defensive item usage:
			if held_item == "banana" and tagger_d < 5.0:
				use_held_item()
			elif held_item == "heater" and is_frozen:
				use_held_item()
			elif held_item == "shield" and tagger_d < 6.5:
				use_held_item()
			elif held_item == "speed" and tagger_d < 8.0:
				use_held_item()
			elif held_item == "tackle" and tagger_d < 4.5:
				var face_tagger = (nearest_tagger.global_position - global_position).normalized()
				face_tagger.y = 0.0
				desired_dir = face_tagger
				use_held_item()
			
			# Panic jump when cornered or very close
			if tagger_d < 3.5 and is_on_floor() and bot_jump_cooldown <= 0.0:
				velocity.y = jump_velocity * 0.85
				bot_jump_cooldown = 1.6
		
		# 2. Rescue teammate: head directly to frozen teammate if tagger is not camping right on them (< 4.0m)
		elif nearest_frozen:
			var tagger_camping = false
			if nearest_tagger:
				var dist_tagger_frozen = nearest_tagger.global_position.distance_to(nearest_frozen.global_position)
				if dist_tagger_frozen < 4.0 and tagger_d < 7.0:
					tagger_camping = true
			
			if not tagger_camping:
				var to_frozen = (nearest_frozen.global_position - global_position)
				to_frozen.y = 0.0
				desired_dir = to_frozen.normalized()
			else:
				# Tagger camping frozen body: circle around at safe distance
				if bot_timer <= 0.0:
					bot_timer = randf_range(1.5, 3.0)
					var angle = randf_range(0, TAU)
					bot_dir = Vector3(cos(angle), 0, sin(angle)).normalized()
				desired_dir = bot_dir
		
		# 3. Safe roaming: active wandering so runners never stay still
		else:
			if bot_timer <= 0.0:
				bot_timer = randf_range(2.0, 4.0)
				var angle = randf_range(0, TAU)
				bot_dir = Vector3(cos(angle), 0, sin(angle)).normalized()
			desired_dir = bot_dir
		
		# Apply soft teammate separation so bots don't merge into one blob
		if living_runner_repel != Vector3.ZERO:
			desired_dir = (desired_dir + living_runner_repel).normalized()
	
	desired_dir = _avoid_walls(desired_dir)
	bot_dir = desired_dir
	return desired_dir

func _find_smart_escape_dir(threat_pos: Vector3) -> Vector3:
	var space_state = get_world_3d().direct_space_state
	var origin = global_position + Vector3(0, 0.6, 0)
	var base_away = (global_position - threat_pos)
	base_away.y = 0.0
	if base_away.is_zero_approx():
		base_away = -transform.basis.z
	base_away = base_away.normalized()
	
	if not space_state:
		return base_away
	
	var angles = [-100.0, -75.0, -50.0, -25.0, 0.0, 25.0, 50.0, 75.0, 100.0]
	var best_score = -999999.0
	var best_dir = base_away
	
	for a in angles:
		var test_dir = base_away.rotated(Vector3.UP, deg_to_rad(a)).normalized()
		var clearance = _get_ray_clearance(origin, test_dir, 9.0, space_state)
		
		# Check lateral clearance to avoid tight corners and dead ends
		var side_l = test_dir.rotated(Vector3.UP, deg_to_rad(35.0)).normalized()
		var side_r = test_dir.rotated(Vector3.UP, deg_to_rad(-35.0)).normalized()
		var clear_l = _get_ray_clearance(origin, side_l, 3.5, space_state)
		var clear_r = _get_ray_clearance(origin, side_r, 3.5, space_state)
		
		# Score:
		# 1. Forward clearance (open space)
		var score = clearance * 3.0
		# 2. Alignment away from tagger
		score += test_dir.dot(base_away) * 4.0
		# 3. Penalize obstacles & corner traps
		if clearance < 2.5:
			score -= 20.0
		if clear_l < 1.5 and clear_r < 1.5:
			score -= 30.0 # Corner trap penalty!
		else:
			score += (clear_l + clear_r) * 0.5
		
		if score > best_score:
			best_score = score
			best_dir = test_dir
			
	return best_dir

func _get_ray_clearance(origin: Vector3, dir: Vector3, max_dist: float, space_state: PhysicsDirectSpaceState3D) -> float:
	var query = PhysicsRayQueryParameters3D.create(origin, origin + dir * max_dist, 1)
	query.exclude = [get_rid()]
	var hit = space_state.intersect_ray(query)
	if hit:
		return origin.distance_to(hit.position)
	return max_dist

func _avoid_walls(dir: Vector3) -> Vector3:
	if dir == Vector3.ZERO:
		return dir
	
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return dir
	
	var origin = global_position + Vector3(0, 0.6, 0)
	var ray_dist = 2.4
	
	# Probe forward
	var fwd_query = PhysicsRayQueryParameters3D.create(origin, origin + dir.normalized() * ray_dist, 1)
	fwd_query.exclude = [get_rid()]
	var hit = space_state.intersect_ray(fwd_query)
	
	if hit:
		var n = hit.normal
		n.y = 0.0
		n = n.normalized()
		var deflected = dir.slide(n).normalized()
		if deflected.is_zero_approx():
			deflected = n
		
		if is_on_floor() and bot_jump_cooldown <= 0.0 and randf() < 0.12:
			velocity.y = jump_velocity * 0.75
			bot_jump_cooldown = 1.8
		
		return deflected
	
	# Probe 35-degree left and right feelers
	var left_dir = dir.rotated(Vector3.UP, deg_to_rad(35.0))
	var left_query = PhysicsRayQueryParameters3D.create(origin, origin + left_dir * (ray_dist * 0.8), 1)
	left_query.exclude = [get_rid()]
	if space_state.intersect_ray(left_query):
		return dir.rotated(Vector3.UP, deg_to_rad(-45.0)).normalized()
	
	var right_dir = dir.rotated(Vector3.UP, deg_to_rad(-35.0))
	var right_query = PhysicsRayQueryParameters3D.create(origin, origin + right_dir * (ray_dist * 0.8), 1)
	right_query.exclude = [get_rid()]
	if space_state.intersect_ray(right_query):
		return dir.rotated(Vector3.UP, deg_to_rad(45.0)).normalized()
	
	return dir

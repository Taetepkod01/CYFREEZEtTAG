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

# Movement Parameters
@export var walk_speed: float = 7.5
@export var run_speed: float = 11.0
@export var jump_velocity: float = 5.8
@export var mouse_sensitivity: float = 0.0025

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

# Single Held Item Slot
var held_item: String = ""
var has_shield: bool = false
var speed_boost_timer: float = 0.0
var shield_timer: float = 0.0
var hp: int = 100

# Tackle Dash Attack (1.5x Speed, deals 20 damage to opposing Tagger)
var is_tackling: bool = false
var tackle_timer: float = 0.0
var tackle_direction: Vector3 = Vector3.FORWARD

# Dizzy Stars on Banana Slip
var is_dizzy: bool = false
var dizzy_timer: float = 0.0

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

# Bot AI timer
var bot_timer: float = 0.0
var bot_dir: Vector3 = Vector3.ZERO

func _ready() -> void:
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
	
	# Any mouse button click immediately recaptures mouse if lost by Alt / Alt-Tab
	if event is InputEventMouseButton and event.pressed:
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
			get_viewport().set_input_as_handled()
			return

	if is_frozen:
		return
	
	# Third-Person Mouse Look
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		spring_arm.rotate_x(-event.relative.y * mouse_sensitivity)
		spring_arm.rotation.x = clamp(spring_arm.rotation.x, deg_to_rad(-65.0), deg_to_rad(45.0))

func _physics_process(delta: float) -> void:
	_process_buffs(delta)
	
	# If this is a remote online player, smoothly lerp to received network position
	if is_remote:
		global_position = global_position.lerp(target_remote_pos, 16.0 * delta)
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_remote_rot_y, 16.0 * delta)
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

	# Check rescuing proximity for runners
	if role == "runner" and not is_frozen:
		var near_frozen = false
		for b in interaction_area.get_overlapping_bodies():
			if b is CharacterBody3D and b != self and b.role == "runner" and b.is_frozen:
				near_frozen = true
				break
		if near_frozen != is_rescuing:
			is_rescuing = near_frozen
			_update_role_visuals()
			if is_local_player() and Network and Network.is_online_game():
				Network.send_rescuing(is_rescuing)

	# Handle Jump
	if is_local_player() and is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
	
	# Movement Vector Calculation
	var input_vec := Vector2.ZERO
	if is_local_player():
		var x = Input.get_axis("move_left", "move_right")
		var y = Input.get_axis("move_up", "move_down")
		input_vec = Vector2(x, y).normalized()
	elif is_bot:
		input_vec = _calculate_bot_input(delta)
	
	# Convert input to 3D space relative to player orientation
	var move_dir = (transform.basis * Vector3(input_vec.x, 0, input_vec.y)).normalized()
	
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
	_send_network_position(delta)

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

# ── Item Pickup & Use ───────────────────────────────────────────────────────
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
			var arena = get_parent().get_parent() if get_parent() else null
			if arena and arena.has_method("spawn_banana_trap"):
				arena.spawn_banana_trap(global_position)
			item_used.emit("BANANA TRAP")
		"vortex":
			# REQUIREMENT: Black Hole teleports the user to a random position on the map!
			var rx = randf_range(-22.0, 22.0)
			var rz = randf_range(-22.0, 22.0)
			global_position = Vector3(rx, 0.5, rz)
			item_used.emit("BLACK HOLE TELEPORT")
		"tackle":
			# REQUIREMENT: Runner tackles forward at 1.5x speed, deals 20 damage to Tagger
			is_tackling = true
			tackle_timer = 1.0
			# Forward vector relative to visuals or player orientation
			tackle_direction = -transform.basis.z.normalized()
			item_used.emit("DASH TACKLE (1.5x)")

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
	freeze()
	is_dizzy = true
	dizzy_timer = 2.5
	if dizzy_stars:
		dizzy_stars.visible = true

func _process_buffs(delta: float) -> void:
	if speed_boost_timer > 0.0:
		speed_boost_timer -= delta
	if shield_timer > 0.0:
		shield_timer -= delta
		if shield_timer <= 0.0:
			has_shield = false
			_update_role_visuals()
	
	if is_dizzy:
		dizzy_timer -= delta
		if dizzy_stars:
			dizzy_stars.rotate_y(6.0 * delta)
		if dizzy_timer <= 0.0:
			is_dizzy = false
			if dizzy_stars:
				dizzy_stars.visible = false
			if is_frozen:
				unfreeze()

# ── Freeze & Tag Mechanics ──────────────────────────────────────────────────
func freeze() -> void:
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
	_update_role_visuals()

func _update_role_visuals() -> void:
	if not is_inside_tree() or not body_mesh:
		return
	
	ice_block.visible = is_frozen
	if shield_domain:
		# Blue glowing domain sphere around player
		shield_domain.visible = has_shield
	
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
	
	# Tackle hit check: If tackling runner hits opposing tagger
	if is_tackling and role == "runner" and other.role == "tagger":
		is_tackling = false
		other.take_damage(20)
		player_damaged.emit(other, 20)
		return
	
	# Online game collision: authoritatively notify server
	if is_local_player() and Network and Network.is_online_game():
		if role == "tagger" and other.role == "runner" and not other.is_frozen:
			Network.send_tag(other.network_id)
		elif role == "runner" and not is_frozen and other.role == "runner" and other.is_frozen:
			Network.send_rescue(other.network_id)
		return
	
	# Offline practice mode collision
	if role == "tagger" and other.role == "runner" and not other.is_frozen:
		other.freeze()
		freeze_count += 1
		tagged.emit(self, other)
	elif role == "runner" and not is_frozen and other.role == "runner" and other.is_frozen:
		other.unfreeze()
		rescue_count += 1
		rescued.emit(self, other)

# ── 3D Bot AI ───────────────────────────────────────────────────────────────
func _calculate_bot_input(delta: float) -> Vector2:
	bot_timer -= delta
	var arena = get_parent()
	if not arena:
		return Vector2.ZERO
	
	if role == "tagger":
		var closest: CharacterBody3D = null
		var min_d: float = 99999.0
		for child in arena.get_children():
			if child is CharacterBody3D and child != self and child.role == "runner" and not child.is_frozen:
				var d = global_position.distance_to(child.global_position)
				if d < min_d:
					min_d = d
					closest = child
		if closest:
			var to_target = (closest.global_position - global_position).normalized()
			return Vector2(to_target.x, to_target.z)
	else:
		var tagger_bot: CharacterBody3D = null
		var frozen_bot: CharacterBody3D = null
		for child in arena.get_children():
			if child is CharacterBody3D and child != self:
				if child.role == "tagger":
					tagger_bot = child
				elif child.role == "runner" and child.is_frozen:
					frozen_bot = child
		
		if tagger_bot and global_position.distance_to(tagger_bot.global_position) < 14.0:
			var flee = (global_position - tagger_bot.global_position).normalized()
			return Vector2(flee.x, flee.z)
		elif frozen_bot:
			var rescue_dir = (frozen_bot.global_position - global_position).normalized()
			return Vector2(rescue_dir.x, rescue_dir.z)
		elif bot_timer <= 0.0:
			bot_timer = randf_range(2.0, 4.0)
			bot_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		return Vector2(bot_dir.x, bot_dir.z)
		
	return Vector2.ZERO

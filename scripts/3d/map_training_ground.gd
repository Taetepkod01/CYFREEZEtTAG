extends Node3D

# Spawn positions for Training Ground
# Ground level: Y ~ 0.5
# Mid Terraces: Y ~ 2.9
# High Skybridge: Y ~ 5.5

var chaser_spawns: Array[Vector3] = [
	Vector3(0.0, 5.5, 0.0),        # High Center Skybridge (Dominant vantage point)
	Vector3(0.0, 0.5, 0.0),        # Center Plaza Ground
	Vector3(-4.0, 0.5, -4.0)
]

var runner_spawns: Array[Vector3] = [
	Vector3(-18.0, 2.9, -18.0),    # Northwest Terrace
	Vector3(18.0, 2.9, -18.0),     # Northeast Terrace
	Vector3(-18.0, 2.9, 18.0),     # Southwest Terrace
	Vector3(18.0, 2.9, 18.0),      # Southeast Terrace
	Vector3(-20.0, 0.5, 0.0),      # West Courtyard
	Vector3(20.0, 0.5, 0.0),       # East Courtyard
	Vector3(0.0, 0.5, -18.0),      # North Plaza
	Vector3(0.0, 0.5, 18.0)        # South Plaza
]

var item_spawns: Array[Vector3] = [
	Vector3(0.0, 5.5, 0.0),        # Bridge Arch Center
	Vector3(-14.0, 5.5, 0.0),      # West Skywalk
	Vector3(14.0, 5.5, 0.0),       # East Skywalk
	Vector3(-16.0, 2.9, -14.0),    # NW Terrace Item
	Vector3(16.0, 2.9, 14.0),      # SE Terrace Item
	Vector3(0.0, 0.6, -10.0),      # North Hurdle
	Vector3(0.0, 0.6, 10.0),       # South Hurdle
	Vector3(-6.0, 0.6, 6.0),       # SW Cube Alley
	Vector3(6.0, 0.6, -6.0)        # NE Cube Alley
]

# -- 4 Corner Portals Configuration -------------------------------------------
# Each portal sits inside one of the 4 corner arches and warps the player up onto
# the high bridge facing inward along the corresponding bridge arm.
const PORTAL_CONFIGS = [
	{
		"id": "portal_nw",
		"name": "Northwest Portal",
		"pos": Vector3(-17.0, 3.8, -12.0),
		"dest": Vector3(-6.0, 5.5, -14.0),
		"rot_y": PI, # Facing South (+Z) along Skywalk North toward center
		"size": Vector3(2.4, 3.2, 1.4),
		"color": Color(0.15, 0.75, 1.0)
	},
	{
		"id": "portal_ne",
		"name": "Northeast Portal",
		"pos": Vector3(17.0, 3.8, -12.0),
		"dest": Vector3(13.0, 5.5, 0.0),
		"rot_y": PI / 2.0, # Facing West (-X) along Bridge East toward center
		"size": Vector3(2.4, 3.2, 1.4),
		"color": Color(0.2, 0.85, 1.0)
	},
	{
		"id": "portal_sw",
		"name": "Southwest Portal",
		"pos": Vector3(-17.0, 3.8, 12.0),
		"dest": Vector3(-13.0, 5.5, 0.0),
		"rot_y": -PI / 2.0, # Facing East (+X) along Bridge West toward center
		"size": Vector3(2.4, 3.2, 1.4),
		"color": Color(0.15, 0.75, 1.0)
	},
	{
		"id": "portal_se",
		"name": "Southeast Portal",
		"pos": Vector3(17.0, 3.8, 12.0),
		"dest": Vector3(6.0, 5.5, 14.0),
		"rot_y": 0.0, # Facing North (-Z) along Skywalk South toward center
		"size": Vector3(2.4, 3.2, 1.4),
		"color": Color(0.2, 0.85, 1.0)
	}
]

var portal_cooldowns: Dictionary = {}
var portal_mats: Array[StandardMaterial3D] = []
var portal_core_mats: Array[StandardMaterial3D] = []
var portal_lights: Array[OmniLight3D] = []
var portal_cores: Array[MeshInstance3D] = []
var warp_sfx_player: AudioStreamPlayer = null

func _ready() -> void:
	_setup_warp_audio()
	_setup_corner_portals()

func _setup_warp_audio() -> void:
	warp_sfx_player = AudioStreamPlayer.new()
	var sfx = load("res://assets/audio/sfx/portal_warp.wav") as AudioStream
	if sfx:
		warp_sfx_player.stream = sfx
		warp_sfx_player.volume_db = -2.0
	add_child(warp_sfx_player)

func _setup_corner_portals() -> void:
	var portals_root = Node3D.new()
	portals_root.name = "Portals"
	add_child(portals_root)
	
	for cfg in PORTAL_CONFIGS:
		var p_node = Node3D.new()
		p_node.name = str(cfg["id"])
		p_node.position = cfg["pos"]
		portals_root.add_child(p_node)
		
		# 1. Outer Swirling Vortex Plane (Cyan)
		var outer_mesh = MeshInstance3D.new()
		var quad_mesh = QuadMesh.new()
		quad_mesh.size = Vector2(2.4, 2.7)
		outer_mesh.mesh = quad_mesh
		
		var outer_mat = StandardMaterial3D.new()
		outer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		outer_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		outer_mat.albedo_color = Color(0.12, 0.72, 1.0, 0.75)
		outer_mat.emission_enabled = true
		outer_mat.emission = Color(0.18, 0.85, 1.0)
		outer_mat.emission_energy_multiplier = 2.6
		outer_mat.roughness = 0.1
		outer_mesh.material_override = outer_mat
		portal_mats.append(outer_mat)
		p_node.add_child(outer_mesh)
		
		# 2. Inner Pulsing Core (Violet Accent)
		var core_mesh = MeshInstance3D.new()
		var core_quad = QuadMesh.new()
		core_quad.size = Vector2(1.5, 1.9)
		core_mesh.mesh = core_quad
		
		var core_mat = StandardMaterial3D.new()
		core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		core_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		core_mat.albedo_color = Color(0.65, 0.28, 1.0, 0.8)
		core_mat.emission_enabled = true
		core_mat.emission = Color(0.75, 0.35, 1.0)
		core_mat.emission_energy_multiplier = 3.0
		core_mat.roughness = 0.1
		core_mesh.material_override = core_mat
		portal_core_mats.append(core_mat)
		portal_cores.append(core_mesh)
		p_node.add_child(core_mesh)
		
		# 3. Particle Effect (Upward Swirling Energy Sparks)
		var particles = CPUParticles3D.new()
		particles.amount = 32
		particles.lifetime = 1.1
		particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		particles.emission_box_extents = Vector3(1.0, 1.2, 0.2)
		particles.gravity = Vector3(0, 1.6, 0)
		particles.direction = Vector3(0, 1, 0)
		particles.spread = 25.0
		particles.initial_velocity_min = 0.4
		particles.initial_velocity_max = 1.2
		particles.scale_amount_min = 0.08
		particles.scale_amount_max = 0.22
		particles.color = Color(0.35, 0.9, 1.0, 0.85)
		
		var part_mat = StandardMaterial3D.new()
		part_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		part_mat.albedo_color = Color(0.4, 0.95, 1.0, 0.9)
		part_mat.emission_enabled = true
		part_mat.emission = Color(0.4, 0.95, 1.0)
		part_mat.emission_energy_multiplier = 2.0
		particles.material_override = part_mat
		p_node.add_child(particles)
		
		# 4. OmniLight3D (Glowing Neon Aura)
		var light = OmniLight3D.new()
		light.light_color = Color(0.2, 0.85, 1.0)
		light.light_energy = 2.2
		light.omni_range = 5.5
		portal_lights.append(light)
		p_node.add_child(light)
		
		# 5. Area3D Trigger
		var area = Area3D.new()
		area.name = "Trigger"
		area.collision_layer = 0
		area.collision_mask = 0xFFFFFFFF # Detect all player bodies
		
		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = cfg["size"]
		col.shape = box
		area.add_child(col)
		
		area.body_entered.connect(_on_portal_entered.bind(cfg))
		p_node.add_child(area)

func _process(_delta: float) -> void:
	var t = Time.get_ticks_msec() * 0.003
	var pulse = 1.0 + 0.35 * sin(t)
	for mat in portal_mats:
		mat.emission_energy_multiplier = 2.4 * pulse
	for c_mat in portal_core_mats:
		c_mat.emission_energy_multiplier = 2.8 * (1.0 + 0.4 * cos(t * 1.3))
	for light in portal_lights:
		light.light_energy = 1.8 + 0.6 * sin(t * 1.2)
	for core in portal_cores:
		core.scale.x = 1.0 + 0.05 * sin(t * 1.5)
		core.scale.y = 1.0 + 0.05 * cos(t * 1.5)

func _on_portal_entered(body: Node, cfg: Dictionary) -> void:
	if not (body is CharacterBody3D or body.has_method("teleport_to")):
		return
	
	var now = Time.get_ticks_msec()
	if portal_cooldowns.has(body) and (now - portal_cooldowns[body]) < 1200:
		return
	portal_cooldowns[body] = now
	
	# Play warp SFX
	if warp_sfx_player:
		warp_sfx_player.play()
	
	# Destination and Rotation
	var dest: Vector3 = cfg["dest"]
	var rot_y: float = cfg["rot_y"]
	
	if body.has_method("teleport_to"):
		body.teleport_to(dest, rot_y)
	else:
		body.global_position = dest
		body.rotation.y = rot_y
		if "velocity" in body:
			body.velocity = Vector3.ZERO
	
	# Arrival visual flash
	_spawn_warp_arrival_fx(dest)
	
	# Log notification for local player
	if body.has_method("is_local_player") and body.is_local_player():
		var arena = get_tree().current_scene
		if arena and arena.has_method("add_game_log"):
			arena.add_game_log("[color=#00e5ff]🌀 Warped up to the High Bridge![/color]")

func _spawn_warp_arrival_fx(pos: Vector3) -> void:
	var flash_light = OmniLight3D.new()
	flash_light.position = pos + Vector3(0, 0.8, 0)
	flash_light.light_color = Color(0.2, 0.9, 1.0)
	flash_light.light_energy = 3.5
	flash_light.omni_range = 4.5
	add_child(flash_light)
	
	var tween = create_tween()
	tween.tween_property(flash_light, "light_energy", 0.0, 0.45)
	tween.tween_callback(flash_light.queue_free)

func get_tagger_spawn(index: int = 0) -> Vector3:
	if index < chaser_spawns.size():
		return chaser_spawns[index]
	return chaser_spawns.pick_random()

func get_runner_spawn(index: int = 0) -> Vector3:
	if index < runner_spawns.size():
		return runner_spawns[index]
	return runner_spawns.pick_random()

func get_random_safe_spawn() -> Vector3:
	var pool = runner_spawns + chaser_spawns
	return pool.pick_random()

func get_random_item_spawn() -> Vector3:
	return item_spawns.pick_random()

extends Control

# Minimap configuration
@export var arena_size: float = 60.0 # Arena is 60x60 units (-30 to +30)
@export var radar_radius: float = 64.0

var arena_ref: Node3D = null

func _ready() -> void:
	custom_minimum_size = Vector2(radar_radius * 2 + 10, radar_radius * 2 + 10)

func setup(arena: Node3D) -> void:
	arena_ref = arena

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var center = size / 2.0
	
	# Radar Background Circle
	draw_circle(center, radar_radius, Color(0.03, 0.07, 0.16, 0.88))
	draw_arc(center, radar_radius, 0, TAU, 48, Color(0.3, 0.75, 0.95, 0.8), 2.0)
	
	# Concentric Radar rings & crosshairs
	draw_arc(center, radar_radius * 0.66, 0, TAU, 32, Color(0.3, 0.75, 0.95, 0.25), 1.0)
	draw_arc(center, radar_radius * 0.33, 0, TAU, 24, Color(0.3, 0.75, 0.95, 0.25), 1.0)
	draw_line(Vector2(center.x - radar_radius, center.y), Vector2(center.x + radar_radius, center.y), Color(0.3, 0.75, 0.95, 0.2), 1.0)
	draw_line(Vector2(center.x, center.y - radar_radius), Vector2(center.x, center.y + radar_radius), Color(0.3, 0.75, 0.95, 0.2), 1.0)
	
	if not arena_ref:
		return
	
	# Draw static obstacle blocks on minimap
	var scale_factor = (radar_radius * 0.9) / (arena_size / 2.0)
	var obstacles = [
		Vector2(-8, -8),
		Vector2(8, 8),
		Vector2(-8, 8),
		Vector2(8, -8)
	]
	for obs in obstacles:
		var obs_radar_pos = center + obs * scale_factor
		draw_rect(Rect2(obs_radar_pos - Vector2(3, 3), Vector2(6, 6)), Color(0.2, 0.45, 0.7, 0.5))
	
	# Draw Player Blips
	var player_nodes = arena_ref.player_nodes if "player_nodes" in arena_ref else []
	for p in player_nodes:
		if not is_instance_valid(p):
			continue
		
		var world_x = p.global_position.x
		var world_z = p.global_position.z
		
		var blip_offset = Vector2(world_x, world_z) * scale_factor
		if blip_offset.length() > radar_radius - 4:
			blip_offset = blip_offset.normalized() * (radar_radius - 4)
		
		var blip_pos = center + blip_offset
		
		# Colors matching the teacher's UI legend:
		# Red = Tagger, Green = Runner, Ice-Cyan = Frozen
		var blip_color = Color(0.4, 0.95, 0.4)
		if p.is_frozen:
			blip_color = Color(0.3, 0.9, 1.0) # Ice
		elif p.role == "tagger":
			blip_color = Color(1.0, 0.25, 0.25) # Tagger Red
		
		# Draw Blip
		draw_circle(blip_pos, 4.0, blip_color)
		
		# If Local Player, draw outer indicator ring and facing direction
		if p.is_local_player():
			draw_arc(blip_pos, 7.0, 0, TAU, 16, Color.WHITE, 1.5)
			# Small direction arrow
			var forward_2d = Vector2(-sin(p.rotation.y), -cos(p.rotation.y)) * 8.0
			draw_line(blip_pos, blip_pos + forward_2d, Color(1, 0.9, 0.3), 2.0)

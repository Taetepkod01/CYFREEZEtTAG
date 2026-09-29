extends Control

# Minimap / Radar configuration matching UI 5.png
@export var arena_size: float = 60.0 # Arena is 60x60 units (-30 to +30)
@export var radar_radius: float = 64.0

var arena_ref: Node3D = null
var scan_angle: float = 0.0
var default_font: Font = null

func _ready() -> void:
	custom_minimum_size = Vector2(radar_radius * 2 + 16, radar_radius * 2 + 16)
	default_font = ThemeDB.fallback_font

func setup(arena: Node3D) -> void:
	arena_ref = arena

func _process(delta: float) -> void:
	scan_angle = fmod(scan_angle + delta * 1.8, TAU)
	queue_redraw()

func _draw() -> void:
	var center = size / 2.0
	
	# Radar Dark Blue Background
	draw_circle(center, radar_radius, Color(0.02, 0.06, 0.15, 0.92))
	
	# Concentric Radar rings
	draw_arc(center, radar_radius * 0.33, 0, TAU, 32, Color(0.15, 0.60, 0.90, 0.22), 1.0)
	draw_arc(center, radar_radius * 0.66, 0, TAU, 40, Color(0.15, 0.60, 0.90, 0.25), 1.0)
	draw_arc(center, radar_radius, 0, TAU, 48, Color(0.15, 0.75, 1.0, 0.85), 2.0)
	
	# Crosshairs
	draw_line(Vector2(center.x - radar_radius, center.y), Vector2(center.x + radar_radius, center.y), Color(0.15, 0.65, 0.95, 0.25), 1.0)
	draw_line(Vector2(center.x, center.y - radar_radius), Vector2(center.x, center.y + radar_radius), Color(0.15, 0.65, 0.95, 0.25), 1.0)
	
	# Rotating Scanner Sweep line
	var sweep_end = center + Vector2(cos(scan_angle), sin(scan_angle)) * (radar_radius - 2.0)
	draw_line(center, sweep_end, Color(0.3, 0.85, 1.0, 0.35), 1.5)
	
	# Compass Cardinal Directions (N, S, W, E)
	var font = default_font if default_font else get_theme_default_font()
	if font:
		var col_text = Color(0.4, 0.85, 1.0, 0.7)
		draw_string(font, Vector2(center.x - 4, center.y - radar_radius + 14), "N", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, col_text)
		draw_string(font, Vector2(center.x - 4, center.y + radar_radius - 5), "S", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, col_text)
		draw_string(font, Vector2(center.x - radar_radius + 4, center.y + 4), "W", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, col_text)
		draw_string(font, Vector2(center.x + radar_radius - 12, center.y + 4), "E", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, col_text)
	
	if not arena_ref:
		return
	
	var scale_factor = (radar_radius * 0.88) / (arena_size / 2.0)
	
	# Draw static obstacle blocks on minimap
	var obstacles = [
		Vector2(-8, -8),
		Vector2(8, 8),
		Vector2(-8, 8),
		Vector2(8, -8)
	]
	for obs in obstacles:
		var obs_radar_pos = center + obs * scale_factor
		draw_rect(Rect2(obs_radar_pos - Vector2(3, 3), Vector2(6, 6)), Color(0.15, 0.40, 0.65, 0.5))
	
	# Draw Item Pickups on Radar (Yellow Diamond blips)
	if "items_container" in arena_ref and arena_ref.items_container:
		for item in arena_ref.items_container.get_children():
			if not is_instance_valid(item) or item.is_queued_for_deletion():
				continue
			var item_pos = center + Vector2(item.global_position.x, item.global_position.z) * scale_factor
			if (item_pos - center).length() < radar_radius - 4:
				draw_circle(item_pos, 2.5, Color(1.0, 0.85, 0.2, 0.85))
	
	# Draw Banana Traps on Radar (Small amber dots)
	if "traps_container" in arena_ref and arena_ref.traps_container:
		for trap in arena_ref.traps_container.get_children():
			if not is_instance_valid(trap) or trap.is_queued_for_deletion():
				continue
			var trap_pos = center + Vector2(trap.global_position.x, trap.global_position.z) * scale_factor
			if (trap_pos - center).length() < radar_radius - 4:
				draw_circle(trap_pos, 2.0, Color(1.0, 0.6, 0.1, 0.85))
	
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
		
		# Colors matching UI design:
		# Red = Tagger, Green = Runner, Ice-Cyan = Frozen
		var blip_color = Color(0.2, 0.95, 0.4) # Green Runner
		if p.is_frozen:
			blip_color = Color(0.3, 0.9, 1.0) # Ice Frozen
		elif p.role == "tagger":
			blip_color = Color(1.0, 0.25, 0.25) # Red Tagger
		
		# If Local Player, draw cyan/white dot with heading needle
		if p.is_local_player():
			# Cyan core
			draw_circle(blip_pos, 5.0, Color(0.1, 0.85, 1.0))
			draw_arc(blip_pos, 7.5, 0, TAU, 16, Color.WHITE, 1.5)
			# Small heading indicator
			var forward_2d = Vector2(-sin(p.rotation.y), -cos(p.rotation.y)) * 9.0
			draw_line(blip_pos, blip_pos + forward_2d, Color(1.0, 0.95, 0.3), 2.0)
		else:
			# Remote / Bot player
			draw_circle(blip_pos, 4.0, blip_color)
			if p.role == "tagger":
				draw_arc(blip_pos, 6.0, 0, TAU, 12, Color(1.0, 0.4, 0.4, 0.6), 1.0)

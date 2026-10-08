extends Node2D

func _draw() -> void:
	var mgr = get_parent()
	if not mgr or mgr.map_data.is_empty():
		return
	
	var world_w = mgr.MAP_W * mgr.TILE_SIZE
	var world_h = mgr.MAP_H * mgr.TILE_SIZE
	
	# Floor background
	draw_rect(Rect2(0, 0, world_w, world_h), Color("1a2a4a"))
	
	# Subtle grid lines
	var grid_col = Color("243558", 0.4)
	for r in range(mgr.MAP_H + 1):
		draw_line(Vector2(0, r * mgr.TILE_SIZE), Vector2(world_w, r * mgr.TILE_SIZE), grid_col, 1.0)
	for c in range(mgr.MAP_W + 1):
		draw_line(Vector2(c * mgr.TILE_SIZE, 0), Vector2(c * mgr.TILE_SIZE, world_h), grid_col, 1.0)
	
	# Walls
	var wall_base = Color("0d47a1")
	var wall_highlight = Color("4fc3f7", 0.35)
	var wall_border = Color("4fc3f7", 0.6)
	
	for r in range(mgr.MAP_H):
		for c in range(mgr.MAP_W):
			if mgr.map_data[r][c] == 1:
				var wx = c * mgr.TILE_SIZE
				var wy = r * mgr.TILE_SIZE
				var rect = Rect2(wx + 1, wy + 1, mgr.TILE_SIZE - 2, mgr.TILE_SIZE - 2)
				draw_rect(rect, wall_base)
				draw_rect(Rect2(wx + 1, wy + 1, mgr.TILE_SIZE - 2, 6), wall_highlight)
				draw_rect(rect, wall_border, false, 1.0)

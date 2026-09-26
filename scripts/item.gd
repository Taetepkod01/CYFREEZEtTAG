extends Area2D

@export var item_type: String = "speed" # speed, ghost, shield, heater, banana, blackhole

var time_passed: float = 0.0

@onready var icon_label: Label = $IconLabel

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_update_visuals()

func setup(p_type: String) -> void:
	item_type = p_type
	_update_visuals()

func _update_visuals() -> void:
	if not icon_label:
		return
	
	match item_type:
		"speed":
			icon_label.text = "⚡"
		"ghost":
			icon_label.text = "👻"
		"shield":
			icon_label.text = "🛡️"
		"heater":
			icon_label.text = "🔥"
		"banana":
			icon_label.text = "🍌"
		"blackhole":
			icon_label.text = "🌀"
		_:
			icon_label.text = "❓"

func _process(delta: float) -> void:
	time_passed += delta
	# Floating bounce animation
	position.y += sin(time_passed * 4.0) * 0.4
	queue_redraw()

func _draw() -> void:
	var color := Color(1.0, 0.9, 0.3, 0.4)
	match item_type:
		"speed":
			color = Color(1.0, 0.9, 0.2, 0.5)
		"ghost":
			color = Color(0.8, 0.4, 1.0, 0.5)
		"shield":
			color = Color(0.2, 0.9, 0.4, 0.5)
		"heater":
			color = Color(1.0, 0.4, 0.2, 0.5)
		"banana":
			color = Color(1.0, 0.9, 0.0, 0.5)
		"blackhole":
			color = Color(0.3, 0.1, 0.7, 0.6)
	
	draw_circle(Vector2.ZERO, 16.0, color)
	draw_arc(Vector2.ZERO, 18.0, 0, TAU, 24, Color(1, 1, 1, 0.8), 1.5)

func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D and body.has_method("apply_item_effect"):
		# If player has no held item, give it to them
		if body.held_item.is_empty():
			body.held_item = item_type
			var mgr = get_tree().current_scene
			if mgr and mgr.has_method("on_item_collected"):
				mgr.on_item_collected(body.player_name, item_type)
			queue_free()

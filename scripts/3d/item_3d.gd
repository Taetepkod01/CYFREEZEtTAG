extends Area3D

@export var item_type: String = "speed" # "speed", "shield", "heater", "banana", "vortex", "tackle"
@export var item_id: String = ""

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var label: Label3D = $Label3D

var float_timer: float = 0.0
var base_y: float = 0.0

func _ready() -> void:
	base_y = position.y
	body_entered.connect(_on_body_entered)
	_setup_visuals()

func setup(type: String, id: String = "") -> void:
	item_type = type
	if not id.is_empty():
		item_id = id
	_setup_visuals()

func _setup_visuals() -> void:
	if not label or not mesh_instance:
		return
	
	var mat = StandardMaterial3D.new()
	mat.metallic = 0.5
	mat.roughness = 0.2
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 2.0
	
	match item_type:
		"speed":
			label.text = "⚡ SPEED"
			label.modulate = Color(1.0, 0.9, 0.2)
			mat.albedo_color = Color(1.0, 0.85, 0.1)
			mat.emission = Color(1.0, 0.8, 0.1)
		"shield":
			label.text = "🛡️ SHIELD"
			label.modulate = Color(0.3, 1.0, 0.4)
			mat.albedo_color = Color(0.2, 0.9, 0.3)
			mat.emission = Color(0.2, 0.9, 0.3)
		"heater":
			label.text = "🔥 HEATER"
			label.modulate = Color(1.0, 0.4, 0.2)
			mat.albedo_color = Color(1.0, 0.3, 0.1)
			mat.emission = Color(1.0, 0.3, 0.1)
		"banana":
			label.text = "🍌 BANANA"
			label.modulate = Color(1.0, 0.95, 0.0)
			mat.albedo_color = Color(1.0, 0.9, 0.0)
			mat.emission = Color(1.0, 0.9, 0.0)
		"vortex":
			label.text = "🌀 VORTEX"
			label.modulate = Color(0.7, 0.3, 1.0)
			mat.albedo_color = Color(0.6, 0.2, 0.9)
			mat.emission = Color(0.6, 0.2, 0.9)
		"tackle":
			label.text = "💥 TACKLE"
			label.modulate = Color(1.0, 0.5, 0.1)
			mat.albedo_color = Color(1.0, 0.4, 0.0)
			mat.emission = Color(1.0, 0.4, 0.0)
	
	mesh_instance.set_surface_override_material(0, mat)

func _process(delta: float) -> void:
	float_timer += delta
	# Rotate and bob up & down
	rotate_y(2.5 * delta)
	position.y = base_y + sin(float_timer * 3.5) * 0.25

func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D and body.has_method("pick_up_item"):
		# REQUIREMENT: Chaser (Tagger) CANNOT pick up heater!
		if item_type == "heater" and body.role == "tagger":
			return
		# Tackle is for Runners only
		if item_type == "tackle" and body.role == "tagger":
			return
		
		if body.held_item.is_empty():
			if body.is_local_player() and Network and Network.is_online_game():
				Network.send_pick_item(item_id)
				body.pick_up_item(item_type)
				queue_free()
			elif not Network or not Network.is_online_game():
				body.pick_up_item(item_type)
				queue_free()

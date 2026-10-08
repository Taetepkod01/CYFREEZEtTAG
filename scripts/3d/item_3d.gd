extends Area3D

@export var item_type: String = "speed" # "speed", "shield", "heater", "banana", "vortex", "tackle"
@export var item_id: String = ""

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var label: Label3D = $Label3D
@onready var speed_model: Node3D = get_node_or_null("SpeedModel")
@onready var shield_model: Node3D = get_node_or_null("ShieldModel")
@onready var heater_model: Node3D = get_node_or_null("HeaterModel")
@onready var vortex_model: Node3D = get_node_or_null("VortexModel")

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
	
	if speed_model: speed_model.visible = false
	if shield_model: shield_model.visible = false
	if heater_model: heater_model.visible = false
	if vortex_model: vortex_model.visible = false
	mesh_instance.visible = false
	
	if has_node("BananaModel"):
		get_node("BananaModel").queue_free()
	
	var mat = StandardMaterial3D.new()
	mat.metallic = 0.5
	mat.roughness = 0.2
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 2.0
	
	match item_type:
		"speed":
			label.text = "SPEED"
			label.modulate = Color(1.0, 0.9, 0.2)
			if speed_model:
				speed_model.visible = true
			else:
				mesh_instance.visible = true
				mat.albedo_color = Color(1.0, 0.85, 0.1)
				mat.emission = Color(1.0, 0.8, 0.1)
				mesh_instance.set_surface_override_material(0, mat)
		"shield":
			label.text = "SHIELD"
			label.modulate = Color(0.3, 1.0, 0.4)
			if shield_model:
				shield_model.visible = true
			else:
				mesh_instance.visible = true
				mat.albedo_color = Color(0.2, 0.9, 0.3)
				mat.emission = Color(0.2, 0.9, 0.3)
				mesh_instance.set_surface_override_material(0, mat)
		"heater":
			label.text = "HEATER"
			label.modulate = Color(1.0, 0.4, 0.2)
			if heater_model:
				heater_model.visible = true
			else:
				mesh_instance.visible = true
				mat.albedo_color = Color(1.0, 0.3, 0.1)
				mat.emission = Color(1.0, 0.3, 0.1)
				mesh_instance.set_surface_override_material(0, mat)
		"banana":
			label.text = "BANANA"
			label.modulate = Color(1.0, 0.95, 0.0)
			if not has_node("BananaModel"):
				var b_scene = preload("res://scenes/3d/banana_peel.tscn")
				var b_inst = b_scene.instantiate()
				b_inst.name = "BananaModel"
				b_inst.position = Vector3(0, -0.2, 0)
				add_child(b_inst)
		"vortex":
			label.text = "VORTEX"
			label.modulate = Color(0.7, 0.3, 1.0)
			if vortex_model:
				vortex_model.visible = true
			else:
				mesh_instance.visible = true
				mat.albedo_color = Color(0.6, 0.2, 0.9)
				mat.emission = Color(0.6, 0.2, 0.9)
				mesh_instance.set_surface_override_material(0, mat)
		"tackle":
			label.text = "TACKLE"
			label.modulate = Color(1.0, 0.5, 0.1)
			mesh_instance.visible = true
			mat.albedo_color = Color(1.0, 0.4, 0.0)
			mat.emission = Color(1.0, 0.4, 0.0)
			mesh_instance.set_surface_override_material(0, mat)
		_:
			mesh_instance.visible = true
			mat.albedo_color = Color(1.0, 1.0, 1.0)
			mat.emission = Color(1.0, 1.0, 1.0)
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

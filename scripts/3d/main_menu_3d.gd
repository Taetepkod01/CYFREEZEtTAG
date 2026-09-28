extends Control

@onready var title_label: Label = $Title
@onready var play_online_btn: Button = $MenuButtons/PlayOnlineBtn
@onready var practice_btn: Button = $MenuButtons/PracticeBtn
@onready var how_to_play_btn: Button = $MenuButtons/HowToPlayBtn
@onready var quit_btn: Button = $MenuButtons/QuitBtn
@onready var rules_panel: Panel = $RulesPanel
@onready var close_rules_btn: Button = $RulesPanel/CloseBtn

# Practice Modal
@onready var practice_modal: Panel = $PracticeModal
@onready var random_role_btn: Button = $PracticeModal/RoleButtons/RandomRoleBtn
@onready var tagger_role_btn: Button = $PracticeModal/RoleButtons/TaggerRoleBtn
@onready var runner_role_btn: Button = $PracticeModal/RoleButtons/RunnerRoleBtn
@onready var close_practice_btn: Button = $PracticeModal/ClosePracticeBtn

var time_passed: float = 0.0

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	rules_panel.visible = false
	practice_modal.visible = false
	
	play_online_btn.pressed.connect(_on_play_online_pressed)
	practice_btn.pressed.connect(_on_practice_pressed)
	how_to_play_btn.pressed.connect(_on_how_to_play_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)
	close_rules_btn.pressed.connect(func(): rules_panel.visible = false)
	close_practice_btn.pressed.connect(func(): practice_modal.visible = false)
	
	random_role_btn.pressed.connect(func(): _start_practice("random"))
	tagger_role_btn.pressed.connect(func(): _start_practice("tagger"))
	runner_role_btn.pressed.connect(func(): _start_practice("runner"))

func _process(delta: float) -> void:
	time_passed += delta
	var s = 1.0 + sin(time_passed * 2.5) * 0.03
	title_label.scale = Vector2(s, s)

func _on_play_online_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/3d/lobby_3d.tscn")

func _on_practice_pressed() -> void:
	practice_modal.visible = true

func _start_practice(role: String) -> void:
	# Show immediate visual loading feedback on the button
	match role:
		"tagger":
			tagger_role_btn.text = "LOADING 3D ARENA..."
		"runner":
			runner_role_btn.text = "LOADING 3D ARENA..."
		"random", _:
			random_role_btn.text = "LOADING 3D ARENA..."
	
	random_role_btn.disabled = true
	tagger_role_btn.disabled = true
	runner_role_btn.disabled = true
	
	if Network:
		Network.is_solo_mode = true
		Network.selected_practice_role = role
		Network.disconnect_from_server()
	
	# Give the engine 1 frame to render the button change before loading the heavy 3D scene
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/3d/arena_3d.tscn")

func _on_how_to_play_pressed() -> void:
	rules_panel.visible = true

func _on_quit_pressed() -> void:
	get_tree().quit()

extends Control

@onready var title_label: Label = $Title
@onready var play_online_btn: Button = $MenuButtons/PlayOnlineBtn
@onready var practice_btn: Button = $MenuButtons/PracticeBtn
@onready var how_to_play_btn: Button = $MenuButtons/HowToPlayBtn
@onready var quit_btn: Button = $MenuButtons/QuitBtn
@onready var rules_panel: Panel = $RulesPanel
@onready var close_rules_btn: Button = $RulesPanel/CloseBtn

# Practice Modal (Matches 4.png)
@onready var practice_modal: Panel = $PracticeModal
@onready var random_role_btn: Button = $PracticeModal/RoleButtons/RandomRoleBtn
@onready var tagger_role_btn: Button = $PracticeModal/RoleButtons/TaggerRoleBtn
@onready var runner_role_btn: Button = $PracticeModal/RoleButtons/RunnerRoleBtn
@onready var start_practice_btn: Button = $PracticeModal/StartPracticeBtn
@onready var close_practice_btn: Button = $PracticeModal/ClosePracticeBtn

var selected_practice_role: String = "runner"
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
	
	random_role_btn.pressed.connect(func(): _select_role("random"))
	tagger_role_btn.pressed.connect(func(): _select_role("tagger"))
	runner_role_btn.pressed.connect(func(): _select_role("runner"))
	start_practice_btn.pressed.connect(func(): _start_practice(selected_practice_role))
	
	_select_role("runner")

func _select_role(role: String) -> void:
	selected_practice_role = role
	
	# Update radio button visual selection indicators
	random_role_btn.text = "RANDOM   (Auto-assign role)              " + ("(●)" if role == "random" else "(○)")
	tagger_role_btn.text = "TAGGER   (You hunt runners)               " + ("(●)" if role == "tagger" else "(○)")
	runner_role_btn.text = "RUNNER   (Survive from taggers)           " + ("(●)" if role == "runner" else "(○)")

func _process(delta: float) -> void:
	time_passed += delta
	var s = 1.0 + sin(time_passed * 2.5) * 0.02
	title_label.scale = Vector2(s, s)

func _on_play_online_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/3d/lobby_3d.tscn")

func _on_practice_pressed() -> void:
	practice_modal.visible = true

func _start_practice(role: String) -> void:
	start_practice_btn.text = "LOADING 3D ARENA..."
	start_practice_btn.disabled = true
	random_role_btn.disabled = true
	tagger_role_btn.disabled = true
	runner_role_btn.disabled = true
	
	if Network:
		Network.is_solo_mode = true
		Network.selected_practice_role = role
		Network.disconnect_from_server()
	
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/3d/arena_3d.tscn")

func _on_how_to_play_pressed() -> void:
	rules_panel.visible = true

func _on_quit_pressed() -> void:
	get_tree().quit()

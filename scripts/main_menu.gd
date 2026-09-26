extends Control

@onready var title_label: Label = $Title
@onready var play_online_btn: Button = $VBoxContainer/PlayOnlineButton
@onready var practice_btn: Button = $VBoxContainer/PracticeButton
@onready var how_to_play_btn: Button = $VBoxContainer/HowToPlayButton
@onready var quit_btn: Button = $VBoxContainer/QuitButton
@onready var how_to_play_panel: Panel = $HowToPlayPanel
@onready var close_rules_btn: Button = $HowToPlayPanel/CloseButton

var time_passed: float = 0.0

func _ready() -> void:
	how_to_play_panel.visible = false
	
	play_online_btn.pressed.connect(_on_play_online_pressed)
	practice_btn.pressed.connect(_on_practice_pressed)
	how_to_play_btn.pressed.connect(_on_how_to_play_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)
	close_rules_btn.pressed.connect(func(): how_to_play_panel.visible = false)

func _process(delta: float) -> void:
	time_passed += delta
	# Slight title breathing pulse
	var s = 1.0 + sin(time_passed * 2.5) * 0.03
	title_label.scale = Vector2(s, s)

func _on_play_online_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_practice_pressed() -> void:
	Network.start_solo_practice()

func _on_how_to_play_pressed() -> void:
	how_to_play_panel.visible = true

func _on_quit_pressed() -> void:
	get_tree().quit()

extends Control

const TEX_ROLE_RANDOM_ON = preload("res://assets/ui/buttons/btn_role_random_on.png")
const TEX_ROLE_RANDOM_OFF = preload("res://assets/ui/buttons/btn_role_random_off.png")
const TEX_ROLE_TAGGER_ON = preload("res://assets/ui/buttons/btn_role_tagger_on.png")
const TEX_ROLE_TAGGER_OFF = preload("res://assets/ui/buttons/btn_role_tagger_off.png")
const TEX_ROLE_RUNNER_ON = preload("res://assets/ui/buttons/btn_role_runner_on.png")
const TEX_ROLE_RUNNER_OFF = preload("res://assets/ui/buttons/btn_role_runner_off.png")

@onready var title_label: TextureRect = $TitleLogo
@onready var menu_buttons: VBoxContainer = $MenuButtons
@onready var play_online_btn: TextureButton = $MenuButtons/PlayOnlineBtn
@onready var practice_btn: TextureButton = $MenuButtons/PracticeBtn
@onready var how_to_play_btn: TextureButton = $MenuButtons/HowToPlayBtn
@onready var quit_btn: TextureButton = $MenuButtons/QuitBtn
@onready var rules_panel: Panel = $RulesPanel
@onready var close_rules_btn: TextureButton = $RulesPanel/CloseBtn

# Practice Modal (Matches 4.png)
@onready var practice_modal: Panel = $PracticeModal
@onready var random_role_btn: TextureButton = $PracticeModal/RoleButtons/RandomRoleBtn
@onready var tagger_role_btn: TextureButton = $PracticeModal/RoleButtons/TaggerRoleBtn
@onready var runner_role_btn: TextureButton = $PracticeModal/RoleButtons/RunnerRoleBtn
@onready var start_practice_btn: TextureButton = $PracticeModal/StartPracticeBtn
@onready var close_practice_btn: TextureButton = $PracticeModal/ClosePracticeBtn
@onready var auth_panel: Panel = $AuthPanel
@onready var auth_title: Label = $AuthPanel/AuthBox/AuthTitle
@onready var email_input: LineEdit = $AuthPanel/AuthBox/EmailInput
@onready var password_input: LineEdit = $AuthPanel/AuthBox/PasswordInput
@onready var auth_submit_btn: Button = $AuthPanel/AuthBox/AuthSubmitBtn
@onready var auth_toggle_btn: Button = $AuthPanel/AuthBox/AuthToggleBtn
@onready var service_status: Label = $ServiceStatus

var selected_practice_role: String = "runner"
var time_passed: float = 0.0
var is_register_mode: bool = false

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	rules_panel.visible = false
	practice_modal.visible = false
	menu_buttons.visible = false
	title_label.visible = false
	auth_panel.visible = true
	service_status.visible = false
	
	play_online_btn.pressed.connect(_on_play_online_pressed)
	practice_btn.pressed.connect(_on_practice_pressed)
	how_to_play_btn.pressed.connect(_on_how_to_play_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)
	close_rules_btn.pressed.connect(func():
		rules_panel.visible = false
		menu_buttons.visible = true
		title_label.visible = true
	)
	close_practice_btn.pressed.connect(func():
		practice_modal.visible = false
		menu_buttons.visible = true
		title_label.visible = true
	)
	
	random_role_btn.pressed.connect(func(): _select_role("random"))
	tagger_role_btn.pressed.connect(func(): _select_role("tagger"))
	runner_role_btn.pressed.connect(func(): _select_role("runner"))
	start_practice_btn.pressed.connect(func(): _start_practice(selected_practice_role))
	auth_submit_btn.pressed.connect(_on_auth_submit_pressed)
	auth_toggle_btn.pressed.connect(_on_auth_toggle_pressed)
	FirebaseService.auth_error.connect(_on_firebase_auth_error)
	
	_select_role("runner")

func _on_auth_submit_pressed() -> void:
	_set_auth_controls_enabled(false)
	service_status.visible = false
	var succeeded: bool
	if is_register_mode:
		succeeded = await FirebaseService.sign_up_with_email(email_input.text, password_input.text)
	else:
		succeeded = await FirebaseService.sign_in_with_email(email_input.text, password_input.text)

	if succeeded:
		await _complete_authentication()
	_set_auth_controls_enabled(true)

func _complete_authentication() -> void:
	var user: Dictionary = FirebaseService.current_user
	var profile := {
		"email": str(user.get("email", "")),
		"display_name": str(user.get("display_name", user.get("email", "").get_slice("@", 0))),
		"last_login_at": Time.get_datetime_string_from_system(true)
	}
	if is_register_mode:
		profile["created_at"] = profile["last_login_at"]

	var profile_saved: bool = await FirebaseService.save_player_profile(profile)
	auth_panel.visible = false
	menu_buttons.visible = true
	title_label.visible = true
	if profile_saved:
		_show_service_status("Signed in as %s" % user.get("email", ""), false)
	else:
		_show_service_status("Signed in, but the Firestore profile could not be saved.", true)

func _on_auth_toggle_pressed() -> void:
	is_register_mode = not is_register_mode
	auth_title.text = "CREATE ACCOUNT" if is_register_mode else "PLAYER LOGIN"
	auth_submit_btn.text = "CREATE ACCOUNT" if is_register_mode else "SIGN IN"
	auth_toggle_btn.text = "Already registered? Sign in" if is_register_mode else "New player? Create account"
	service_status.visible = false

func _on_firebase_auth_error(message: String) -> void:
	_show_service_status(message, true)

func _show_service_status(message: String, is_error: bool) -> void:
	service_status.text = message
	service_status.add_theme_color_override(
		"font_color",
		Color(1.0, 0.55, 0.55) if is_error else Color(0.55, 1.0, 0.75)
	)
	service_status.visible = true

func _set_auth_controls_enabled(enabled: bool) -> void:
	email_input.editable = enabled
	password_input.editable = enabled
	auth_submit_btn.disabled = not enabled
	auth_toggle_btn.disabled = not enabled
	auth_submit_btn.text = "PLEASE WAIT..." if not enabled else (
		"CREATE ACCOUNT" if is_register_mode else "SIGN IN"
	)

func _select_role(role: String) -> void:
	selected_practice_role = role
	random_role_btn.texture_normal = TEX_ROLE_RANDOM_ON if role == "random" else TEX_ROLE_RANDOM_OFF
	tagger_role_btn.texture_normal = TEX_ROLE_TAGGER_ON if role == "tagger" else TEX_ROLE_TAGGER_OFF
	runner_role_btn.texture_normal = TEX_ROLE_RUNNER_ON if role == "runner" else TEX_ROLE_RUNNER_OFF

func _process(delta: float) -> void:
	time_passed += delta
	var s = 1.0 + sin(time_passed * 2.5) * 0.02
	title_label.scale = Vector2(s, s)

func _on_play_online_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/3d/lobby_3d.tscn")

func _on_practice_pressed() -> void:
	practice_modal.visible = true
	menu_buttons.visible = false
	title_label.visible = false

func _start_practice(role: String) -> void:
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
	menu_buttons.visible = false
	title_label.visible = false

func _on_quit_pressed() -> void:
	get_tree().quit()

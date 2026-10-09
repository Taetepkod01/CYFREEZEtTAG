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
@onready var quit_btn: Button = $MenuButtons/QuitBtn
@onready var rules_panel: Panel = $RulesPanel
@onready var close_rules_btn: TextureButton = $RulesPanel/CloseBtn

# Practice Modal
@onready var practice_modal: Panel = $PracticeModal
@onready var random_role_btn: TextureButton = $PracticeModal/RoleButtons/RandomRoleBtn
@onready var tagger_role_btn: TextureButton = $PracticeModal/RoleButtons/TaggerRoleBtn
@onready var runner_role_btn: TextureButton = $PracticeModal/RoleButtons/RunnerRoleBtn
@onready var start_practice_btn: TextureButton = $PracticeModal/StartPracticeBtn
@onready var close_practice_btn: TextureButton = $PracticeModal/ClosePracticeBtn

# Firebase Auth Panel
@onready var auth_panel: Panel = $AuthPanel
@onready var auth_title: Label = $AuthPanel/AuthBox/AuthTitle
@onready var email_input: LineEdit = $AuthPanel/AuthBox/EmailInput
@onready var password_input: LineEdit = $AuthPanel/AuthBox/PasswordInput
@onready var auth_submit_btn: Button = $AuthPanel/AuthBox/AuthSubmitBtn
@onready var auth_toggle_btn: Button = $AuthPanel/AuthBox/AuthToggleBtn
@onready var service_status: Label = $ServiceStatus

# Profile Bar Nodes
var profile_bar: PanelContainer = null
var profile_level_lbl: Label = null
var profile_name_lbl: Label = null
var profile_exp_lbl: Label = null
var profile_coins_lbl: Label = null
var profile_account_btn: Button = null
var guest_btn: Button = null

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
		if profile_bar: profile_bar.visible = true
	)
	close_practice_btn.pressed.connect(func():
		practice_modal.visible = false
		menu_buttons.visible = true
		title_label.visible = true
		if profile_bar: profile_bar.visible = true
	)
	
	random_role_btn.pressed.connect(func(): _select_role("random"))
	tagger_role_btn.pressed.connect(func(): _select_role("tagger"))
	runner_role_btn.pressed.connect(func(): _select_role("runner"))
	start_practice_btn.pressed.connect(func(): _start_practice(selected_practice_role))
	
	auth_submit_btn.pressed.connect(_on_auth_submit_pressed)
	auth_toggle_btn.pressed.connect(_on_auth_toggle_pressed)
	
	if FirebaseService:
		FirebaseService.auth_error.connect(_on_firebase_auth_error)
	
	_setup_guest_button()
	_setup_profile_bar()
	_select_role("runner")
	
	if Network:
		Network.auth_succeeded.connect(_on_network_auth_succeeded)
		Network.auth_failed.connect(_on_network_auth_failed)
		Network.profile_updated.connect(func(_u): _update_profile_bar())
		_update_profile_bar()
	
	# If player already logged in previously, allow immediate access
	if FirebaseService and not FirebaseService.current_user.is_empty():
		_show_main_menu()
	elif Network and not Network.current_user.is_empty() and not bool(Network.current_user.get("isGuest", true)):
		_show_main_menu()

# ── Dynamic Guest Play Button ─────────────────────────────────────────────────
func _setup_guest_button() -> void:
	if not auth_panel or not auth_panel.has_node("AuthBox"):
		return
	var auth_box = auth_panel.get_node("AuthBox")
	guest_btn = Button.new()
	guest_btn.name = "GuestBtn"
	guest_btn.text = "⚡ PLAY AS GUEST (QUICK PLAY)"
	guest_btn.custom_minimum_size = Vector2(0, 36)
	guest_btn.flat = true
	guest_btn.modulate = Color(0.4, 0.85, 1.0)
	guest_btn.add_theme_font_size_override("font_size", 11)
	guest_btn.pressed.connect(_on_guest_play_pressed)
	auth_box.add_child(guest_btn)

# ── Top Profile Bar ───────────────────────────────────────────────────────────
func _setup_profile_bar() -> void:
	profile_bar = PanelContainer.new()
	profile_bar.name = "ProfileBar"
	profile_bar.visible = false
	profile_bar.anchors_preset = Control.PRESET_TOP_RIGHT
	profile_bar.anchor_left = 1.0
	profile_bar.anchor_right = 1.0
	profile_bar.offset_left = -440.0
	profile_bar.offset_top = 18.0
	profile_bar.offset_right = -18.0
	profile_bar.offset_bottom = 68.0
	profile_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.09, 0.20, 0.92)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.2, 0.8, 1.0, 0.85)
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0.0, 0.5, 0.9, 0.3)
	sb.shadow_size = 8
	profile_bar.add_theme_stylebox_override("panel", sb)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	profile_bar.add_child(margin)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	margin.add_child(hbox)
	
	profile_level_lbl = Label.new()
	profile_level_lbl.text = "Lv. 1"
	profile_level_lbl.modulate = Color(1.0, 0.85, 0.25)
	profile_level_lbl.add_theme_font_size_override("font_size", 14)
	hbox.add_child(profile_level_lbl)
	
	profile_name_lbl = Label.new()
	profile_name_lbl.text = "Player 1"
	profile_name_lbl.modulate = Color(0.9, 0.95, 1.0)
	profile_name_lbl.add_theme_font_size_override("font_size", 13)
	profile_name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(profile_name_lbl)
	
	profile_exp_lbl = Label.new()
	profile_exp_lbl.text = "EXP: 0/100"
	profile_exp_lbl.modulate = Color(0.4, 0.9, 1.0)
	profile_exp_lbl.add_theme_font_size_override("font_size", 11)
	hbox.add_child(profile_exp_lbl)
	
	profile_coins_lbl = Label.new()
	profile_coins_lbl.text = "🪙 50"
	profile_coins_lbl.modulate = Color(1.0, 0.9, 0.25)
	profile_coins_lbl.add_theme_font_size_override("font_size", 13)
	hbox.add_child(profile_coins_lbl)
	
	profile_account_btn = Button.new()
	profile_account_btn.text = "ACCOUNT"
	profile_account_btn.custom_minimum_size = Vector2(85, 30)
	var btn_sb = StyleBoxFlat.new()
	btn_sb.bg_color = Color(0.08, 0.22, 0.40, 0.95)
	btn_sb.border_width_left = 1
	btn_sb.border_width_top = 1
	btn_sb.border_width_right = 1
	btn_sb.border_width_bottom = 1
	btn_sb.border_color = Color(0.3, 0.85, 1.0, 0.9)
	btn_sb.set_corner_radius_all(6)
	profile_account_btn.add_theme_stylebox_override("normal", btn_sb)
	profile_account_btn.add_theme_font_size_override("font_size", 11)
	profile_account_btn.pressed.connect(_show_auth_panel)
	hbox.add_child(profile_account_btn)
	
	add_child(profile_bar)

func _update_profile_bar() -> void:
	if not profile_bar or not Network:
		return
	var u = Network.current_user
	var lv = int(u.get("level", 1))
	var exp_cur = int(u.get("exp", 0))
	var exp_max = int(u.get("maxExp", 100))
	var coins = int(u.get("coins", 0))
	var d_name = str(u.get("displayName", Network.my_player_name))
	var is_guest = bool(u.get("isGuest", true))
	
	profile_level_lbl.text = "★ Lv. %d" % lv
	profile_name_lbl.text = d_name
	profile_exp_lbl.text = "EXP: %d/%d" % [exp_cur, exp_max]
	profile_coins_lbl.text = "🪙 %d" % coins
	profile_account_btn.text = "GUEST (LOGIN)" if is_guest else "ACCOUNT"

# ── Authentication Flow ───────────────────────────────────────────────────────
func _on_auth_submit_pressed() -> void:
	_set_auth_controls_enabled(false)
	service_status.visible = false
	var email_str = email_input.text.strip_edges()
	var pass_str = password_input.text
	
	if email_str.is_empty() or pass_str.is_empty():
		_show_service_status("Email and password are required.", true)
		_set_auth_controls_enabled(true)
		return
	
	# Attempt Firebase Auth first
	var succeeded = false
	if is_register_mode:
		succeeded = await FirebaseService.sign_up_with_email(email_str, pass_str)
	else:
		succeeded = await FirebaseService.sign_in_with_email(email_str, pass_str)

	if succeeded:
		await _complete_authentication()
	else:
		# Fallback to Server REST Auth (covers local persistence or offline dev)
		if is_register_mode:
			var d_name = email_str.split("@")[0]
			Network.auth_register(email_str, pass_str, d_name)
		else:
			Network.auth_login(email_str, pass_str)
	
	_set_auth_controls_enabled(true)

func _on_guest_play_pressed() -> void:
	if Network:
		var d_name = Network.my_player_name
		if d_name.is_empty() or d_name == "Player 1":
			d_name = "Guest_" + str(randi() % 900 + 100)
		Network.auth_guest(d_name)
	_show_main_menu()
	_update_profile_bar()
	_show_service_status("Playing as Guest (Progress saved locally)", false)

func _complete_authentication() -> void:
	var user: Dictionary = FirebaseService.current_user
	var d_name = str(user.get("display_name", user.get("email", "").get_slice("@", 0)))
	if d_name.is_empty():
		d_name = user.get("email", "Player").get_slice("@", 0)
	
	var existing_profile = await FirebaseService.load_player_profile()
	var cur_level = int(existing_profile.get("level", 1))
	var cur_exp = int(existing_profile.get("exp", 0))
	var cur_max_exp = int(existing_profile.get("max_exp", 100))
	var cur_coins = int(existing_profile.get("coins", 100))
	
	var profile := {
		"email": str(user.get("email", "")),
		"display_name": d_name,
		"level": cur_level,
		"exp": cur_exp,
		"max_exp": cur_max_exp,
		"coins": cur_coins,
		"last_login_at": Time.get_datetime_string_from_system(true)
	}
	if is_register_mode:
		profile["created_at"] = profile["last_login_at"]

	var profile_saved: bool = await FirebaseService.save_player_profile(profile)
	
	if Network:
		Network.current_user["uid"] = str(user.get("uid", ""))
		Network.current_user["email"] = str(user.get("email", ""))
		Network.current_user["displayName"] = d_name
		Network.current_user["level"] = cur_level
		Network.current_user["exp"] = cur_exp
		Network.current_user["maxExp"] = cur_max_exp
		Network.current_user["coins"] = cur_coins
		Network.current_user["isGuest"] = false
		Network.my_player_name = d_name
		Network.save_local_user()
		Network.auth_sync_websocket()
		Network.profile_updated.emit(Network.current_user)
	
	_show_main_menu()
	_update_profile_bar()
	if profile_saved:
		_show_service_status("Signed in as %s (Lv. %d | 🪙 %d)" % [d_name, cur_level, cur_coins], false)
	else:
		_show_service_status("Signed in as %s (Local Mode Active)" % d_name, false)

func _on_network_auth_succeeded(user: Dictionary) -> void:
	_show_main_menu()
	_update_profile_bar()
	_show_service_status("Welcome back, %s!" % user.get("displayName", "Player"), false)

func _on_network_auth_failed(msg: String) -> void:
	_show_service_status(msg, true)

func _show_main_menu() -> void:
	auth_panel.visible = false
	menu_buttons.visible = true
	title_label.visible = true
	if profile_bar:
		profile_bar.visible = true
	quit_btn.text = "LOG OUT" if (Network and not bool(Network.current_user.get("isGuest", true))) else "QUIT"

func _show_auth_panel() -> void:
	auth_panel.visible = true
	menu_buttons.visible = false
	title_label.visible = false
	if profile_bar:
		profile_bar.visible = false
	password_input.clear()
	service_status.visible = false
	is_register_mode = false
	auth_title.text = "PLAYER LOGIN"
	auth_submit_btn.text = "SIGN IN"
	auth_toggle_btn.text = "New player? Create account"
	quit_btn.text = "QUIT"

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
	if guest_btn: guest_btn.disabled = not enabled
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
	if profile_bar: profile_bar.visible = false

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
	if profile_bar: profile_bar.visible = false

func _on_quit_pressed() -> void:
	if FirebaseService and not FirebaseService.current_user.is_empty():
		FirebaseService.sign_out()
		_show_auth_panel()
		return
	if Network and not bool(Network.current_user.get("isGuest", true)):
		Network.current_user = {}
		Network.save_local_user()
		_show_auth_panel()
		return
	get_tree().quit()

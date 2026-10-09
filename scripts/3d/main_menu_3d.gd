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

# Profile Bar & Auth Modal Nodes
var profile_bar: PanelContainer = null
var profile_level_lbl: Label = null
var profile_name_lbl: Label = null
var profile_exp_lbl: Label = null
var profile_coins_lbl: Label = null
var profile_account_btn: Button = null

var auth_modal: Panel = null
var auth_tab_login_btn: Button = null
var auth_tab_register_btn: Button = null
var auth_tab_guest_btn: Button = null
var auth_email_input: LineEdit = null
var auth_pass_input: LineEdit = null
var auth_name_input: LineEdit = null
var auth_email_row: VBoxContainer = null
var auth_pass_row: VBoxContainer = null
var auth_name_row: VBoxContainer = null
var auth_status_lbl: Label = null
var auth_submit_btn: Button = null
var auth_cancel_btn: Button = null
var current_auth_tab: String = "login" # "login", "register", "guest"

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
	
	_select_role("runner")
	
	_setup_profile_bar()
	_setup_auth_modal()
	
	if Network:
		Network.auth_succeeded.connect(_on_auth_succeeded)
		Network.auth_failed.connect(_on_auth_failed)
		Network.profile_updated.connect(func(_u): _update_profile_bar())
		_update_profile_bar()

# ── Top Profile Bar ───────────────────────────────────────────────────────────
func _setup_profile_bar() -> void:
	profile_bar = PanelContainer.new()
	profile_bar.name = "ProfileBar"
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
	profile_account_btn.pressed.connect(_on_open_auth_modal_pressed)
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

# ── Authentication Modal ──────────────────────────────────────────────────────
func _setup_auth_modal() -> void:
	auth_modal = Panel.new()
	auth_modal.name = "AuthModal"
	auth_modal.visible = false
	auth_modal.anchors_preset = Control.PRESET_CENTER
	auth_modal.anchor_left = 0.5
	auth_modal.anchor_top = 0.5
	auth_modal.anchor_right = 0.5
	auth_modal.anchor_bottom = 0.5
	auth_modal.offset_left = -230.0
	auth_modal.offset_top = -225.0
	auth_modal.offset_right = 230.0
	auth_modal.offset_bottom = 225.0
	auth_modal.grow_horizontal = Control.GROW_DIRECTION_BOTH
	auth_modal.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.08, 0.18, 0.98)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.2, 0.8, 1.0, 0.95)
	sb.set_corner_radius_all(16)
	sb.shadow_color = Color(0.0, 0.5, 0.95, 0.35)
	sb.shadow_size = 20
	auth_modal.add_theme_stylebox_override("panel", sb)
	
	var vbox = VBoxContainer.new()
	vbox.anchors_preset = Control.PRESET_FULL_RECT
	vbox.offset_left = 24.0
	vbox.offset_top = 18.0
	vbox.offset_right = -24.0
	vbox.offset_bottom = -18.0
	vbox.add_theme_constant_override("separation", 10)
	auth_modal.add_child(vbox)
	
	var title = Label.new()
	title.text = "CYBER TAG ACCOUNT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate = Color(0.65, 0.92, 1.0)
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)
	
	# Tab switcher
	var tab_bar = HBoxContainer.new()
	tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_bar.add_theme_constant_override("separation", 8)
	vbox.add_child(tab_bar)
	
	auth_tab_login_btn = Button.new()
	auth_tab_login_btn.text = "LOG IN"
	auth_tab_login_btn.custom_minimum_size = Vector2(120, 32)
	auth_tab_login_btn.pressed.connect(func(): _switch_auth_tab("login"))
	tab_bar.add_child(auth_tab_login_btn)
	
	auth_tab_register_btn = Button.new()
	auth_tab_register_btn.text = "REGISTER"
	auth_tab_register_btn.custom_minimum_size = Vector2(120, 32)
	auth_tab_register_btn.pressed.connect(func(): _switch_auth_tab("register"))
	tab_bar.add_child(auth_tab_register_btn)
	
	auth_tab_guest_btn = Button.new()
	auth_tab_guest_btn.text = "GUEST"
	auth_tab_guest_btn.custom_minimum_size = Vector2(120, 32)
	auth_tab_guest_btn.pressed.connect(func(): _switch_auth_tab("guest"))
	tab_bar.add_child(auth_tab_guest_btn)
	
	# Form inputs
	auth_email_row = VBoxContainer.new()
	var email_lbl = Label.new()
	email_lbl.text = "EMAIL ADDRESS:"
	email_lbl.modulate = Color(0.4, 0.85, 1.0)
	email_lbl.add_theme_font_size_override("font_size", 11)
	auth_email_row.add_child(email_lbl)
	auth_email_input = LineEdit.new()
	auth_email_input.placeholder_text = "user@example.com"
	auth_email_row.add_child(auth_email_input)
	vbox.add_child(auth_email_row)
	
	auth_pass_row = VBoxContainer.new()
	var pass_lbl = Label.new()
	pass_lbl.text = "PASSWORD:"
	pass_lbl.modulate = Color(0.4, 0.85, 1.0)
	pass_lbl.add_theme_font_size_override("font_size", 11)
	auth_pass_row.add_child(pass_lbl)
	auth_pass_input = LineEdit.new()
	auth_pass_input.placeholder_text = "••••••••"
	auth_pass_input.secret = true
	auth_pass_row.add_child(auth_pass_input)
	vbox.add_child(auth_pass_row)
	
	auth_name_row = VBoxContainer.new()
	var name_lbl = Label.new()
	name_lbl.text = "DISPLAY NAME:"
	name_lbl.modulate = Color(0.4, 0.85, 1.0)
	name_lbl.add_theme_font_size_override("font_size", 11)
	auth_name_row.add_child(name_lbl)
	auth_name_input = LineEdit.new()
	auth_name_input.placeholder_text = "Nickname (1-16 chars)"
	auth_name_input.max_length = 16
	auth_name_row.add_child(auth_name_input)
	vbox.add_child(auth_name_row)
	
	# Status message
	auth_status_lbl = Label.new()
	auth_status_lbl.text = ""
	auth_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	auth_status_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(auth_status_lbl)
	
	# Buttons
	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 14)
	vbox.add_child(btn_row)
	
	auth_submit_btn = Button.new()
	auth_submit_btn.text = "LOG IN"
	auth_submit_btn.custom_minimum_size = Vector2(170, 38)
	auth_submit_btn.pressed.connect(_on_auth_submit_pressed)
	btn_row.add_child(auth_submit_btn)
	
	auth_cancel_btn = Button.new()
	auth_cancel_btn.text = "CLOSE"
	auth_cancel_btn.custom_minimum_size = Vector2(120, 38)
	auth_cancel_btn.pressed.connect(func():
		auth_modal.visible = false
		menu_buttons.visible = true
		title_label.visible = true
	)
	btn_row.add_child(auth_cancel_btn)
	
	add_child(auth_modal)
	_switch_auth_tab("login")

func _switch_auth_tab(tab: String) -> void:
	current_auth_tab = tab
	auth_status_lbl.text = ""
	
	# Style active tabs
	auth_tab_login_btn.modulate = Color(1.2, 1.2, 1.2) if tab == "login" else Color(0.7, 0.7, 0.7)
	auth_tab_register_btn.modulate = Color(1.2, 1.2, 1.2) if tab == "register" else Color(0.7, 0.7, 0.7)
	auth_tab_guest_btn.modulate = Color(1.2, 1.2, 1.2) if tab == "guest" else Color(0.7, 0.7, 0.7)
	
	match tab:
		"login":
			auth_email_row.visible = true
			auth_pass_row.visible = true
			auth_name_row.visible = false
			auth_submit_btn.text = "LOG IN"
		"register":
			auth_email_row.visible = true
			auth_pass_row.visible = true
			auth_name_row.visible = true
			auth_submit_btn.text = "CREATE ACCOUNT"
		"guest":
			auth_email_row.visible = false
			auth_pass_row.visible = false
			auth_name_row.visible = true
			auth_submit_btn.text = "PLAY AS GUEST"

func _on_open_auth_modal_pressed() -> void:
	auth_modal.visible = true
	menu_buttons.visible = false
	title_label.visible = false
	if Network and Network.current_user:
		auth_name_input.text = Network.current_user.get("displayName", Network.my_player_name)
		if not Network.current_user.get("email", "").is_empty():
			auth_email_input.text = Network.current_user.get("email", "")

func _on_auth_submit_pressed() -> void:
	auth_submit_btn.disabled = true
	auth_status_lbl.text = "Connecting..."
	auth_status_lbl.modulate = Color(0.4, 0.85, 1.0)
	
	match current_auth_tab:
		"login":
			var email = auth_email_input.text.strip_edges()
			var password_str = auth_pass_input.text
			if email.is_empty() or password_str.is_empty():
				auth_status_lbl.text = "Please enter email and password."
				auth_status_lbl.modulate = Color(1.0, 0.4, 0.4)
				auth_submit_btn.disabled = false
				return
			Network.auth_login(email, password_str)
			
		"register":
			var email = auth_email_input.text.strip_edges()
			var password_str = auth_pass_input.text
			var name_str = auth_name_input.text.strip_edges()
			if email.is_empty() or password_str.is_empty():
				auth_status_lbl.text = "Please enter email and password."
				auth_status_lbl.modulate = Color(1.0, 0.4, 0.4)
				auth_submit_btn.disabled = false
				return
			if name_str.is_empty():
				name_str = email.split("@")[0]
			Network.auth_register(email, password_str, name_str)
			
		"guest":
			var name_str = auth_name_input.text.strip_edges()
			if name_str.is_empty():
				name_str = "Guest"
			Network.auth_guest(name_str)

func _on_auth_succeeded(user: Dictionary) -> void:
	auth_submit_btn.disabled = false
	auth_status_lbl.text = "Welcome, %s!" % user.get("displayName", "Player")
	auth_status_lbl.modulate = Color(0.3, 1.0, 0.5)
	_update_profile_bar()
	
	await get_tree().create_timer(0.9).timeout
	if is_instance_valid(auth_modal):
		auth_modal.visible = false
		menu_buttons.visible = true
		title_label.visible = true

func _on_auth_failed(msg: String) -> void:
	auth_submit_btn.disabled = false
	auth_status_lbl.text = msg
	auth_status_lbl.modulate = Color(1.0, 0.35, 0.35)

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

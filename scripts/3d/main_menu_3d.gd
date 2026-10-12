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

# Practice Modal
@onready var practice_modal: Panel = $PracticeModal
@onready var random_role_btn: TextureButton = $PracticeModal/RoleButtons/RandomRoleBtn
@onready var tagger_role_btn: TextureButton = $PracticeModal/RoleButtons/TaggerRoleBtn
@onready var runner_role_btn: TextureButton = $PracticeModal/RoleButtons/RunnerRoleBtn
@onready var start_practice_btn: TextureButton = $PracticeModal/StartPracticeBtn
@onready var close_practice_btn: TextureButton = $PracticeModal/ClosePracticeBtn

var selected_practice_map: String = "SNOW TOWN"

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

# Account Modal Nodes
var account_modal: Panel = null
var account_name_lbl: Label = null
var account_email_lbl: Label = null
var account_stats_lbl: Label = null
var account_sign_out_btn: Button = null
var account_close_btn: Button = null

# Mode Selection Modal Nodes
var mode_select_modal: Panel = null
var freeze_tag_mode_btn: Button = null
var racing_mode_btn: Button = null
var close_mode_select_btn: Button = null

# Falling Snowflake Particle System
const TEX_SNOWFLAKE_PARTICLE = preload("res://assets/ui/menu/snowflake_particle.png")
const MAX_FALLING_SNOWFLAKES: int = 5

# Audio SFX
const AUDIO_BTN_HOVER = preload("res://assets/audio/sfx/btn_hover.mp3")
const AUDIO_BTN_CLICK = preload("res://assets/audio/sfx/btn_click.wav")
var sfx_hover_player: AudioStreamPlayer = null
var sfx_click_player: AudioStreamPlayer = null

@onready var snowflake_container: Control = get_node_or_null("SnowflakeContainer")

var snowflake_spawn_timer: float = 0.0
var next_snowflake_spawn_delay: float = 2.0
var active_snowflakes: Array[Dictionary] = []

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
	
	sfx_hover_player = AudioStreamPlayer.new()
	sfx_hover_player.name = "HoverSFXPlayer"
	sfx_hover_player.stream = AUDIO_BTN_HOVER
	sfx_hover_player.volume_db = -3.0
	add_child(sfx_hover_player)
	
	sfx_click_player = AudioStreamPlayer.new()
	sfx_click_player.name = "ClickSFXPlayer"
	sfx_click_player.stream = AUDIO_BTN_CLICK
	sfx_click_player.volume_db = -2.0
	add_child(sfx_click_player)
	
	if BGMManager:
		BGMManager.play_menu_bgm()
	
	play_online_btn.pressed.connect(_on_play_online_pressed)
	practice_btn.pressed.connect(_on_practice_pressed)
	how_to_play_btn.pressed.connect(_on_how_to_play_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)
	
	for btn in [play_online_btn, practice_btn, how_to_play_btn, quit_btn]:
		btn.pivot_offset = Vector2(155, 41)
		btn.mouse_entered.connect(func():
			_play_hover_sfx()
			var tw = create_tween()
			tw.tween_property(btn, "scale", Vector2(1.04, 1.04), 0.1).set_trans(Tween.TRANS_SINE)
		)
		btn.mouse_exited.connect(func():
			var tw = create_tween()
			tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_SINE)
		)
		btn.pressed.connect(_play_click_sfx)
	
	_connect_button_sfx(close_rules_btn)
	_connect_button_sfx(close_practice_btn)
	_connect_button_sfx(random_role_btn)
	_connect_button_sfx(tagger_role_btn)
	_connect_button_sfx(runner_role_btn)
	_connect_button_sfx(start_practice_btn)
	_connect_button_sfx(auth_submit_btn)
	_connect_button_sfx(auth_toggle_btn)
	
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
	_setup_account_modal()
	_setup_mode_selection_modal()
	_select_role("runner")
	
	if Network:
		Network.auth_succeeded.connect(_on_network_auth_succeeded)
		Network.auth_failed.connect(_on_network_auth_failed)
		Network.profile_updated.connect(func(_u): _update_profile_bar())
		_update_profile_bar()
	
	# If player already logged in previously, or chose to play as guest, allow immediate access
	var is_logged_in_firebase = FirebaseService and not FirebaseService.current_user.is_empty()
	var is_registered_network = Network and not Network.current_user.is_empty() and not bool(Network.current_user.get("isGuest", true))
	var is_guest_chosen = Network and not Network.current_user.is_empty() and bool(Network.current_user.get("has_chosen_guest", false))
	
	# Migrate/Detect existing profiles that already played as guest previously
	if Network and not Network.current_user.is_empty() and not is_logged_in_firebase and not is_registered_network and not is_guest_chosen:
		if int(Network.current_user.get("level", 1)) > 1 \
		or int(Network.current_user.get("exp", 0)) > 0 \
		or int(Network.current_user.get("coins", 50)) != 50 \
		or str(Network.current_user.get("uid", "")).begins_with("guest_"):
			is_guest_chosen = true
			Network.current_user["has_chosen_guest"] = true
			Network.save_local_user()
	
	if is_logged_in_firebase or is_registered_network or is_guest_chosen:
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
	_connect_button_sfx(guest_btn)
	auth_box.add_child(guest_btn)

# ── Audio SFX Helpers ─────────────────────────────────────────────────────────
func _play_hover_sfx() -> void:
	if is_instance_valid(sfx_hover_player) and sfx_hover_player.stream:
		sfx_hover_player.stop()
		sfx_hover_player.play()

func _play_click_sfx() -> void:
	if is_instance_valid(sfx_click_player) and sfx_click_player.stream:
		sfx_click_player.stop()
		sfx_click_player.play()
	if BGMManager and not BGMManager.is_playing():
		BGMManager.play_menu_bgm()

func _connect_hover_sfx(btn: Control) -> void:
	if not btn:
		return
	btn.mouse_entered.connect(_play_hover_sfx)

func _connect_button_sfx(btn: Control) -> void:
	if not btn:
		return
	btn.mouse_entered.connect(_play_hover_sfx)
	if btn is BaseButton:
		btn.pressed.connect(_play_click_sfx)

# ── Top Profile Bar ───────────────────────────────────────────────────────────
func _setup_profile_bar() -> void:
	profile_bar = PanelContainer.new()
	profile_bar.name = "ProfileBar"
	profile_bar.visible = false
	profile_bar.anchors_preset = Control.PRESET_TOP_RIGHT
	profile_bar.anchor_left = 1.0
	profile_bar.anchor_right = 1.0
	profile_bar.offset_left = -470.0
	profile_bar.offset_top = 8.0
	profile_bar.offset_right = -30.0
	profile_bar.offset_bottom = 54.0
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
	profile_account_btn.pressed.connect(_on_profile_account_pressed)
	_connect_button_sfx(profile_account_btn)
	hbox.add_child(profile_account_btn)
	
	add_child(profile_bar)

# ── Account Modal (Sign Out & Close) ──────────────────────────────────────────
func _setup_account_modal() -> void:
	account_modal = Panel.new()
	account_modal.name = "AccountModal"
	account_modal.visible = false
	account_modal.anchors_preset = Control.PRESET_CENTER
	account_modal.anchor_left = 0.5
	account_modal.anchor_top = 0.5
	account_modal.anchor_right = 0.5
	account_modal.anchor_bottom = 0.5
	account_modal.offset_left = -190.0
	account_modal.offset_top = -130.0
	account_modal.offset_right = 190.0
	account_modal.offset_bottom = 130.0
	account_modal.grow_horizontal = Control.GROW_DIRECTION_BOTH
	account_modal.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	var panel_sb = StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.04, 0.09, 0.18, 0.96)
	panel_sb.border_width_left = 2
	panel_sb.border_width_top = 2
	panel_sb.border_width_right = 2
	panel_sb.border_width_bottom = 2
	panel_sb.border_color = Color(0.12, 0.65, 0.95, 0.9)
	panel_sb.set_corner_radius_all(16)
	panel_sb.shadow_color = Color(0, 0.5, 0.95, 0.35)
	panel_sb.shadow_size = 20
	account_modal.add_theme_stylebox_override("panel", panel_sb)
	
	var vbox = VBoxContainer.new()
	vbox.anchors_preset = Control.PRESET_FULL_RECT
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 24.0
	vbox.offset_top = 18.0
	vbox.offset_right = -24.0
	vbox.offset_bottom = -18.0
	vbox.add_theme_constant_override("separation", 10)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	account_modal.add_child(vbox)
	
	var title = Label.new()
	title.text = "ACCOUNT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate = Color(0.65, 0.92, 1.0)
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)
	
	account_name_lbl = Label.new()
	account_name_lbl.text = "Player"
	account_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	account_name_lbl.modulate = Color(1.0, 1.0, 1.0)
	account_name_lbl.add_theme_font_size_override("font_size", 15)
	vbox.add_child(account_name_lbl)
	
	account_email_lbl = Label.new()
	account_email_lbl.text = "player@example.com"
	account_email_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	account_email_lbl.modulate = Color(0.45, 0.85, 1.0)
	account_email_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(account_email_lbl)
	
	account_stats_lbl = Label.new()
	account_stats_lbl.text = "★ Lv. 1   |   🪙 50"
	account_stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	account_stats_lbl.modulate = Color(1.0, 0.85, 0.3)
	account_stats_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(account_stats_lbl)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spacer)
	
	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 14)
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_hbox)
	
	account_sign_out_btn = Button.new()
	account_sign_out_btn.text = "SIGN OUT"
	account_sign_out_btn.custom_minimum_size = Vector2(130, 40)
	var signout_sb = StyleBoxFlat.new()
	signout_sb.bg_color = Color(0.45, 0.12, 0.18, 0.95)
	signout_sb.border_width_left = 1
	signout_sb.border_width_top = 1
	signout_sb.border_width_right = 1
	signout_sb.border_width_bottom = 1
	signout_sb.border_color = Color(1.0, 0.35, 0.45, 0.9)
	signout_sb.set_corner_radius_all(8)
	var signout_hover = signout_sb.duplicate()
	signout_hover.bg_color = Color(0.65, 0.18, 0.25, 1.0)
	account_sign_out_btn.add_theme_stylebox_override("normal", signout_sb)
	account_sign_out_btn.add_theme_stylebox_override("hover", signout_hover)
	account_sign_out_btn.add_theme_stylebox_override("pressed", signout_hover)
	account_sign_out_btn.add_theme_font_size_override("font_size", 12)
	account_sign_out_btn.modulate = Color(1.0, 0.85, 0.85)
	account_sign_out_btn.pressed.connect(_on_account_sign_out_pressed)
	_connect_button_sfx(account_sign_out_btn)
	btn_hbox.add_child(account_sign_out_btn)
	
	account_close_btn = Button.new()
	account_close_btn.text = "CLOSE"
	account_close_btn.custom_minimum_size = Vector2(130, 40)
	var close_sb = StyleBoxFlat.new()
	close_sb.bg_color = Color(0.06, 0.22, 0.42, 0.95)
	close_sb.border_width_left = 1
	close_sb.border_width_top = 1
	close_sb.border_width_right = 1
	close_sb.border_width_bottom = 1
	close_sb.border_color = Color(0.25, 0.75, 1.0, 0.9)
	close_sb.set_corner_radius_all(8)
	var close_hover = close_sb.duplicate()
	close_hover.bg_color = Color(0.10, 0.35, 0.60, 1.0)
	account_close_btn.add_theme_stylebox_override("normal", close_sb)
	account_close_btn.add_theme_stylebox_override("hover", close_hover)
	account_close_btn.add_theme_stylebox_override("pressed", close_hover)
	account_close_btn.add_theme_font_size_override("font_size", 12)
	account_close_btn.modulate = Color(0.85, 0.95, 1.0)
	account_close_btn.pressed.connect(_on_account_close_pressed)
	_connect_button_sfx(account_close_btn)
	btn_hbox.add_child(account_close_btn)
	
	add_child(account_modal)

# ── Mode Selection Modal (FreezeTag & Racing) ─────────────────────────────────
func _setup_mode_selection_modal() -> void:
	mode_select_modal = Panel.new()
	mode_select_modal.name = "ModeSelectModal"
	mode_select_modal.visible = false
	mode_select_modal.anchors_preset = Control.PRESET_FULL_RECT
	mode_select_modal.anchor_left = 0.0
	mode_select_modal.anchor_top = 0.0
	mode_select_modal.anchor_right = 1.0
	mode_select_modal.anchor_bottom = 1.0
	
	var overlay_sb = StyleBoxFlat.new()
	overlay_sb.bg_color = Color(0.02, 0.06, 0.15, 0.90)
	mode_select_modal.add_theme_stylebox_override("panel", overlay_sb)
	
	var center_vbox = VBoxContainer.new()
	center_vbox.anchors_preset = Control.PRESET_CENTER
	center_vbox.anchor_left = 0.5
	center_vbox.anchor_top = 0.5
	center_vbox.anchor_right = 0.5
	center_vbox.anchor_bottom = 0.5
	center_vbox.offset_left = -460.0
	center_vbox.offset_top = -285.0
	center_vbox.offset_right = 460.0
	center_vbox.offset_bottom = 285.0
	center_vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	center_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center_vbox.add_theme_constant_override("separation", 18)
	mode_select_modal.add_child(center_vbox)
	
	# Header
	var title_lbl = Label.new()
	title_lbl.text = "SELECT GAME MODE"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_override("font", preload("res://assets/fonts/Audiowide.ttf"))
	title_lbl.add_theme_font_size_override("font_size", 28)
	title_lbl.modulate = Color(0.92, 0.96, 1.0)
	center_vbox.add_child(title_lbl)
	
	var subtitle_lbl = Label.new()
	subtitle_lbl.text = "CHOOSE YOUR CHALLENGE"
	subtitle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_lbl.add_theme_font_size_override("font_size", 12)
	subtitle_lbl.modulate = Color(0.4, 0.85, 1.0, 0.9)
	center_vbox.add_child(subtitle_lbl)
	
	# 9-slice StyleBox with UI_Flat_Frame02a.png
	var frame_tex = preload("res://assets/ui/mode_selection/UI_Flat_Frame02a.png")
	
	var card_sb_normal = StyleBoxTexture.new()
	card_sb_normal.texture = frame_tex
	card_sb_normal.texture_margin_left = 16.0
	card_sb_normal.texture_margin_top = 16.0
	card_sb_normal.texture_margin_right = 16.0
	card_sb_normal.texture_margin_bottom = 16.0
	card_sb_normal.region_rect = Rect2(0, 0, 96, 64)
	
	var card_sb_hover = card_sb_normal.duplicate()
	card_sb_hover.modulate_color = Color(1.22, 1.22, 1.30)
	
	var card_sb_pressed = card_sb_normal.duplicate()
	card_sb_pressed.modulate_color = Color(0.85, 0.9, 0.95)
	
	# Cards HBox
	var cards_hbox = HBoxContainer.new()
	cards_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_hbox.add_theme_constant_override("separation", 36)
	center_vbox.add_child(cards_hbox)
	
	# ── Left Button: FREEZE TAG ───────────────────────────────────────────────
	freeze_tag_mode_btn = Button.new()
	freeze_tag_mode_btn.name = "FreezeTagBtn"
	freeze_tag_mode_btn.custom_minimum_size = Vector2(360, 360)
	freeze_tag_mode_btn.pivot_offset = Vector2(180, 180)
	freeze_tag_mode_btn.focus_mode = Control.FOCUS_NONE
	freeze_tag_mode_btn.add_theme_stylebox_override("normal", card_sb_normal)
	freeze_tag_mode_btn.add_theme_stylebox_override("hover", card_sb_hover)
	freeze_tag_mode_btn.add_theme_stylebox_override("pressed", card_sb_pressed)
	freeze_tag_mode_btn.add_theme_stylebox_override("focus", card_sb_hover)
	
	var ft_vbox = VBoxContainer.new()
	ft_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ft_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	ft_vbox.add_theme_constant_override("separation", 8)
	ft_vbox.anchors_preset = Control.PRESET_FULL_RECT
	ft_vbox.offset_left = 18.0
	ft_vbox.offset_top = 18.0
	ft_vbox.offset_right = -18.0
	ft_vbox.offset_bottom = -18.0
	freeze_tag_mode_btn.add_child(ft_vbox)
	
	var ft_art = TextureRect.new()
	ft_art.texture = preload("res://assets/ui/mode_selection/mode_freezetag_art.png")
	ft_art.custom_minimum_size = Vector2(320, 185)
	ft_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ft_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ft_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ft_vbox.add_child(ft_art)
	
	var ft_title = Label.new()
	ft_title.text = "FREEZE TAG"
	ft_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ft_title.add_theme_font_override("font", preload("res://assets/fonts/Audiowide.ttf"))
	ft_title.add_theme_font_size_override("font_size", 22)
	ft_title.modulate = Color(1.0, 0.9, 0.35)
	ft_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ft_vbox.add_child(ft_title)
	
	var ft_desc = Label.new()
	ft_desc.text = "❄ Tag, Freeze & Rescue Teammates\nOnline Multiplayer Arena"
	ft_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ft_desc.add_theme_font_size_override("font_size", 12)
	ft_desc.modulate = Color(0.85, 0.95, 1.0, 0.9)
	ft_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ft_vbox.add_child(ft_desc)
	
	var ft_badge = Label.new()
	ft_badge.text = "▶ PLAY FREEZETAG"
	ft_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ft_badge.add_theme_font_size_override("font_size", 13)
	ft_badge.modulate = Color(1.0, 1.0, 1.0)
	var ft_badge_sb = StyleBoxFlat.new()
	ft_badge_sb.bg_color = Color(0.12, 0.40, 0.75, 0.95)
	ft_badge_sb.set_corner_radius_all(6)
	ft_badge_sb.content_margin_top = 4.0
	ft_badge_sb.content_margin_bottom = 4.0
	ft_badge.add_theme_stylebox_override("normal", ft_badge_sb)
	ft_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ft_vbox.add_child(ft_badge)
	
	cards_hbox.add_child(freeze_tag_mode_btn)
	
	# ── Right Button: RACING ──────────────────────────────────────────────────
	racing_mode_btn = Button.new()
	racing_mode_btn.name = "RacingBtn"
	racing_mode_btn.custom_minimum_size = Vector2(360, 360)
	racing_mode_btn.pivot_offset = Vector2(180, 180)
	racing_mode_btn.focus_mode = Control.FOCUS_NONE
	racing_mode_btn.add_theme_stylebox_override("normal", card_sb_normal)
	racing_mode_btn.add_theme_stylebox_override("hover", card_sb_hover)
	racing_mode_btn.add_theme_stylebox_override("pressed", card_sb_pressed)
	racing_mode_btn.add_theme_stylebox_override("focus", card_sb_hover)
	
	var rc_vbox = VBoxContainer.new()
	rc_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rc_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	rc_vbox.add_theme_constant_override("separation", 8)
	rc_vbox.anchors_preset = Control.PRESET_FULL_RECT
	rc_vbox.offset_left = 18.0
	rc_vbox.offset_top = 18.0
	rc_vbox.offset_right = -18.0
	rc_vbox.offset_bottom = -18.0
	racing_mode_btn.add_child(rc_vbox)
	
	var rc_art = TextureRect.new()
	rc_art.texture = preload("res://assets/ui/mode_selection/mode_racing_art.png")
	rc_art.custom_minimum_size = Vector2(320, 185)
	rc_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rc_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rc_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rc_vbox.add_child(rc_art)
	
	var rc_title = Label.new()
	rc_title.text = "RACING"
	rc_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rc_title.add_theme_font_override("font", preload("res://assets/fonts/Audiowide.ttf"))
	rc_title.add_theme_font_size_override("font_size", 22)
	rc_title.modulate = Color(0.2, 1.0, 0.75)
	rc_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rc_vbox.add_child(rc_title)
	
	var rc_desc = Label.new()
	rc_desc.text = "⚡ Dash Through Void Obstacles\nCheckpoints & Finish Line"
	rc_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rc_desc.add_theme_font_size_override("font_size", 12)
	rc_desc.modulate = Color(0.85, 0.95, 1.0, 0.9)
	rc_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rc_vbox.add_child(rc_desc)
	
	var rc_badge = Label.new()
	rc_badge.text = "▶ RACE NOW"
	rc_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rc_badge.add_theme_font_size_override("font_size", 13)
	rc_badge.modulate = Color(1.0, 1.0, 1.0)
	var rc_badge_sb = StyleBoxFlat.new()
	rc_badge_sb.bg_color = Color(0.06, 0.52, 0.48, 0.95)
	rc_badge_sb.set_corner_radius_all(6)
	rc_badge_sb.content_margin_top = 4.0
	rc_badge_sb.content_margin_bottom = 4.0
	rc_badge.add_theme_stylebox_override("normal", rc_badge_sb)
	rc_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rc_vbox.add_child(rc_badge)
	
	cards_hbox.add_child(racing_mode_btn)
	
	# Hover Animations
	for btn in [freeze_tag_mode_btn, racing_mode_btn]:
		btn.mouse_entered.connect(func():
			_play_hover_sfx()
			var tw = create_tween()
			tw.tween_property(btn, "scale", Vector2(1.03, 1.03), 0.12).set_trans(Tween.TRANS_SINE)
		)
		btn.mouse_exited.connect(func():
			var tw = create_tween()
			tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_SINE)
		)
	
	# Bottom Close / Back Button
	close_mode_select_btn = Button.new()
	close_mode_select_btn.text = "← BACK TO MAIN MENU"
	close_mode_select_btn.custom_minimum_size = Vector2(240, 38)
	close_mode_select_btn.flat = true
	close_mode_select_btn.modulate = Color(0.5, 0.85, 1.0)
	close_mode_select_btn.add_theme_font_size_override("font_size", 12)
	close_mode_select_btn.pressed.connect(_on_close_mode_selection_pressed)
	_connect_button_sfx(close_mode_select_btn)
	center_vbox.add_child(close_mode_select_btn)
	
	# Connect Button Events
	freeze_tag_mode_btn.pressed.connect(_on_freeze_tag_selected)
	racing_mode_btn.pressed.connect(_on_racing_selected)
	
	add_child(mode_select_modal)

func _on_profile_account_pressed() -> void:
	var is_logged_in = false
	if FirebaseService and not FirebaseService.current_user.is_empty():
		is_logged_in = true
	elif Network and not bool(Network.current_user.get("isGuest", true)):
		is_logged_in = true
	
	if is_logged_in:
		_show_account_modal()
	else:
		_show_auth_panel()

func _show_account_modal() -> void:
	if not account_modal:
		return
	var u = Network.current_user if Network else {}
	var email = ""
	if FirebaseService and not FirebaseService.current_user.is_empty():
		email = str(FirebaseService.current_user.get("email", ""))
	if email.is_empty():
		email = str(u.get("email", ""))
	
	var d_name = str(u.get("displayName", Network.my_player_name if Network else "Player"))
	var lv = int(u.get("level", 1))
	var exp_cur = int(u.get("exp", 0))
	var exp_max = int(u.get("maxExp", 100))
	var coins = int(u.get("coins", 0))
	
	account_name_lbl.text = d_name
	account_email_lbl.text = email if not email.is_empty() else "Logged in account"
	account_stats_lbl.text = "★ Lv. %d (EXP: %d/%d)   |   🪙 %d" % [lv, exp_cur, exp_max, coins]
	
	account_modal.visible = true

func _on_account_close_pressed() -> void:
	if account_modal:
		account_modal.visible = false

func _on_account_sign_out_pressed() -> void:
	if account_modal:
		account_modal.visible = false
	_perform_sign_out()

func _perform_sign_out() -> void:
	if FirebaseService:
		FirebaseService.sign_out()
	if Network:
		Network.current_user = {
			"uid": "",
			"email": "",
			"displayName": "Player 1",
			"level": 1,
			"exp": 0,
			"maxExp": 100,
			"coins": 50,
			"isGuest": true,
			"has_chosen_guest": false
		}
		Network.my_player_name = "Player 1"
		Network.save_local_user()
		Network.profile_updated.emit(Network.current_user)
	_update_profile_bar()
	_show_auth_panel()
	_show_service_status("Signed out successfully.", false)

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
		var d_name = str(Network.current_user.get("displayName", Network.my_player_name))
		if d_name.is_empty() or d_name == "Player 1":
			d_name = "Guest_" + str(randi() % 900 + 100)
		Network.current_user["has_chosen_guest"] = true
		Network.current_user["isGuest"] = true
		Network.current_user["displayName"] = d_name
		Network.my_player_name = d_name
		Network.save_local_user()
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
		Network.current_user["has_chosen_guest"] = false
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
	if account_modal:
		account_modal.visible = false
	if mode_select_modal:
		mode_select_modal.visible = false
	menu_buttons.visible = true
	title_label.visible = true
	if profile_bar:
		profile_bar.visible = true

func _show_auth_panel() -> void:
	auth_panel.visible = true
	if account_modal:
		account_modal.visible = false
	if mode_select_modal:
		mode_select_modal.visible = false
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
	if guest_btn:
		if Network and bool(Network.current_user.get("has_chosen_guest", false)):
			guest_btn.text = "← BACK TO MENU (CONTINUE AS GUEST)"
		else:
			guest_btn.text = "⚡ PLAY AS GUEST (QUICK PLAY)"

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
	
	_update_snowflakes(delta)

func _update_snowflakes(delta: float) -> void:
	var vp_size = get_viewport_rect().size
	if vp_size.x <= 0 or vp_size.y <= 0:
		vp_size = Vector2(1280, 720)
	
	# Update existing snowflakes
	var i = active_snowflakes.size() - 1
	while i >= 0:
		var flake = active_snowflakes[i]
		var rect: TextureRect = flake.get("node")
		if not is_instance_valid(rect):
			active_snowflakes.remove_at(i)
			i -= 1
			continue
		
		flake["time"] += delta
		flake["pos_y"] += flake["speed_y"] * delta
		var sway = sin(flake["time"] * flake["sway_speed"] + flake["sway_phase"]) * flake["sway_amp"]
		rect.position = Vector2(flake["pos_x"] + sway, flake["pos_y"])
		rect.rotation += flake["rot_speed"] * delta
		
		# Fade in at top, fade out near bottom
		if flake["pos_y"] < 50.0:
			var alpha_in = clampf((flake["pos_y"] + 70.0) / 120.0, 0.0, 1.0)
			rect.modulate.a = flake["base_alpha"] * alpha_in
		elif flake["pos_y"] > vp_size.y - 70.0:
			var alpha_out = clampf((vp_size.y + 70.0 - flake["pos_y"]) / 140.0, 0.0, 1.0)
			rect.modulate.a = flake["base_alpha"] * alpha_out
		else:
			rect.modulate.a = flake["base_alpha"]
		
		# Check if reached bottom of screen
		if flake["pos_y"] > vp_size.y + 75.0:
			rect.queue_free()
			active_snowflakes.remove_at(i)
		i -= 1
	
	# Spawn new snowflake: interval between 3 and 5 seconds, max 5 active
	if active_snowflakes.size() < MAX_FALLING_SNOWFLAKES:
		snowflake_spawn_timer += delta
		if snowflake_spawn_timer >= next_snowflake_spawn_delay:
			snowflake_spawn_timer = 0.0
			next_snowflake_spawn_delay = randf_range(3.0, 5.0)
			_spawn_snowflake(vp_size)

func _spawn_snowflake(vp_size: Vector2) -> void:
	if not snowflake_container or active_snowflakes.size() >= MAX_FALLING_SNOWFLAKES:
		return
	
	var rect = TextureRect.new()
	rect.texture = TEX_SNOWFLAKE_PARTICLE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	var sf_size = randf_range(42.0, 68.0)
	rect.custom_minimum_size = Vector2(sf_size, sf_size)
	rect.size = Vector2(sf_size, sf_size)
	rect.pivot_offset = Vector2(sf_size * 0.5, sf_size * 0.5)
	
	var start_x = randf_range(40.0, vp_size.x - 40.0)
	var start_y = -70.0
	rect.position = Vector2(start_x, start_y)
	
	var base_alpha = randf_range(0.70, 0.95)
	rect.modulate = Color(1.0, 1.0, 1.0, 0.0)
	
	snowflake_container.add_child(rect)
	
	active_snowflakes.append({
		"node": rect,
		"pos_x": start_x,
		"pos_y": start_y,
		"speed_y": randf_range(45.0, 75.0),
		"sway_amp": randf_range(16.0, 36.0),
		"sway_speed": randf_range(1.2, 2.2),
		"sway_phase": randf_range(0.0, TAU),
		"rot_speed": randf_range(-0.35, 0.35),
		"base_alpha": base_alpha,
		"time": 0.0
	})

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if mode_select_modal and mode_select_modal.visible:
			_on_close_mode_selection_pressed()
			get_viewport().set_input_as_handled()
		elif account_modal and account_modal.visible:
			_on_account_close_pressed()
			get_viewport().set_input_as_handled()
		elif rules_panel and rules_panel.visible:
			rules_panel.visible = false
			menu_buttons.visible = true
			title_label.visible = true
			if profile_bar: profile_bar.visible = true
			get_viewport().set_input_as_handled()
		elif practice_modal and practice_modal.visible:
			practice_modal.visible = false
			menu_buttons.visible = true
			title_label.visible = true
			if profile_bar: profile_bar.visible = true
			get_viewport().set_input_as_handled()

func _on_play_online_pressed() -> void:
	_show_mode_selection_modal()

func _show_mode_selection_modal() -> void:
	if not mode_select_modal:
		return
	if account_modal:
		account_modal.visible = false
	if rules_panel:
		rules_panel.visible = false
	if practice_modal:
		practice_modal.visible = false
	if freeze_tag_mode_btn:
		freeze_tag_mode_btn.disabled = false
	if racing_mode_btn:
		racing_mode_btn.disabled = false
	menu_buttons.visible = false
	title_label.visible = false
	if profile_bar:
		profile_bar.visible = false
	mode_select_modal.visible = true

func _on_close_mode_selection_pressed() -> void:
	if mode_select_modal:
		mode_select_modal.visible = false
	menu_buttons.visible = true
	title_label.visible = true
	if profile_bar:
		profile_bar.visible = true

func _on_freeze_tag_selected() -> void:
	_play_click_sfx()
	if freeze_tag_mode_btn:
		freeze_tag_mode_btn.disabled = true
	if Network:
		Network.is_solo_mode = false
		Network.selected_game_mode = "freezetag"
		Network.selected_map = "SPACE STATION"
	await get_tree().create_timer(0.18).timeout
	get_tree().change_scene_to_file("res://scenes/3d/lobby_3d.tscn")

func _on_racing_selected() -> void:
	_play_click_sfx()
	if racing_mode_btn:
		racing_mode_btn.disabled = true
	if Network:
		Network.is_solo_mode = false
		Network.selected_game_mode = "racing"
		Network.selected_practice_role = "runner"
		Network.selected_map = "VOID PARKOUR"
	await get_tree().create_timer(0.18).timeout
	get_tree().change_scene_to_file("res://scenes/3d/lobby_racing_3d.tscn")

func _on_practice_pressed() -> void:
	if account_modal:
		account_modal.visible = false
	practice_modal.visible = true
	menu_buttons.visible = false
	title_label.visible = false
	if profile_bar: profile_bar.visible = false

func _start_practice(role: String) -> void:
	_play_click_sfx()
	start_practice_btn.disabled = true
	random_role_btn.disabled = true
	tagger_role_btn.disabled = true
	runner_role_btn.disabled = true
	
	if Network:
		Network.is_solo_mode = true
		Network.selected_practice_role = role
		Network.selected_map = selected_practice_map
		Network.disconnect_from_server()
	
	await get_tree().create_timer(0.18).timeout
	get_tree().change_scene_to_file("res://scenes/3d/arena_3d.tscn")

func _on_how_to_play_pressed() -> void:
	if account_modal:
		account_modal.visible = false
	rules_panel.visible = true
	menu_buttons.visible = false
	title_label.visible = false
	if profile_bar: profile_bar.visible = false

func _on_quit_pressed() -> void:
	var is_logged_in = false
	if FirebaseService and not FirebaseService.current_user.is_empty():
		is_logged_in = true
	elif Network and not bool(Network.current_user.get("isGuest", true)):
		is_logged_in = true
	
	if is_logged_in:
		_perform_sign_out()
		return
	get_tree().quit()

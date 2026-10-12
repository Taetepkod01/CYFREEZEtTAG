extends Control

signal closed

const FONT_AUDIOWIDE = preload("res://assets/fonts/Audiowide.ttf")
const AUDIO_BTN_HOVER = preload("res://assets/audio/sfx/btn_hover.mp3")
const AUDIO_BTN_CLICK = preload("res://assets/audio/sfx/btn_click.wav")

const TAGGER_CHARACTERS: Array[Dictionary] = [
	{
		"id": "ponpon",
		"name": "PonPon",
		"role": "HUNTER · HIGH SPEED CHASER",
		"class_name": "Hunter",
		"model_path": "res://assets/taggers/ป้อนป้อน.glb",
		"model_scale": Vector3(-1.3, 1.3, -1.3),
		"model_offset": Vector3(0, -0.05, 0),
		"anim_name": "ArmatureAction",
		"avatar_color": Color(0.65, 0.35, 0.16),
		"skill_key": "E",
		"skill_name": "Banana Gun",
		"skill_desc": "Fire a banana peel forward. Runners hit are stunned for 1.5s.",
		"skill_cd": "cooldown 15s",
	},
	{
		"id": "snowman",
		"name": "Snowman",
		"role": "CLASSIC · FROST THROWER",
		"class_name": "Classic",
		"model_path": "res://assets/snowman.glb",
		"model_scale": Vector3(-0.55, 0.55, -0.55),
		"model_offset": Vector3(0, 0, 0),
		"anim_name": "",
		"avatar_color": Color(0.35, 0.75, 1.0),
		"skill_key": "E",
		"skill_name": "Snow Domain",
		"skill_desc": "Deploy a frosty blizzard zone. Slows runners within the area by 10% for 4s.",
		"skill_cd": "cooldown 20s",
	},
	{
		"id": "mafog",
		"name": "Mafog",
		"role": "INTIMIDATOR · SPEED HOWL",
		"class_name": "Intimidator",
		"model_path": "res://assets/taggers/มาฟ้อก.glb",
		"model_scale": Vector3(-1.0, 1.0, -1.0),
		"model_offset": Vector3(0, -0.05, 0),
		"anim_name": "ArmatureAction",
		"avatar_color": Color(0.93, 0.23, 0.23),
		"skill_key": "E",
		"skill_name": "Berry Bomb",
		"skill_desc": "Toss an explosive strawberry. Explodes with red splash, blinding runners within 4m for 2s.",
		"skill_cd": "cooldown 14s",
	},
	{
		"id": "mumu",
		"name": "Mumu",
		"role": "CONTROLLER · ZONE HAZARD",
		"class_name": "Controller",
		"model_path": "res://assets/taggers/มุมุ.glb",
		"model_scale": Vector3(-1.3, 1.3, -1.3),
		"model_offset": Vector3(0, -0.05, 0),
		"anim_name": "ArmatureAction",
		"avatar_color": Color(0.13, 0.71, 0.69),
		"skill_key": "E",
		"skill_name": "Mirror Swap",
		"skill_desc": "Place a mirror shadow decoy. Activate again to swap positions with the shadow.",
		"skill_cd": "cooldown 16s",
	},
	{
		"id": "phoemphoon",
		"name": "PhoemPhoon",
		"role": "TRICKSTER · FROST TITAN",
		"class_name": "Trickster",
		"model_path": "res://assets/taggers/เพิ่มพูน.glb",
		"model_scale": Vector3(-0.55, 0.55, -0.55),
		"model_offset": Vector3(0, -0.05, 0),
		"anim_name": "ArmatureAction",
		"avatar_color": Color(1.0, 0.48, 0.10),
		"skill_key": "E",
		"skill_name": "Bass Drop",
		"skill_desc": "Slam the ground with shockwaves. Runners in radius lose balance and stumble erratically for 1s.",
		"skill_cd": "cooldown 20s",
	},
	{
		"id": "random",
		"name": "Random",
		"role": "ADAPTIVE · MYSTERY TAGGER",
		"class_name": "Random",
		"model_path": "",
		"model_scale": Vector3(1, 1, 1),
		"model_offset": Vector3(0, 0, 0),
		"anim_name": "",
		"avatar_color": Color(1.0, 0.82, 0.25),
		"skill_key": "E",
		"skill_name": "Surprise Pick",
		"skill_desc": "Randomly equips one of the 5 Taggers with their unique skill each match.",
		"skill_cd": "Varies",
	}
]

const RUNNER_CHARACTERS: Array[Dictionary] = [
	{
		"id": "penguin",
		"name": "Penguin",
		"role": "SURVIVOR · CLASSIC RUNNER",
		"class_name": "Survivor",
		"model_path": "res://assets/penguin.glb",
		"model_scale": Vector3(-1.4, 1.4, -1.4),
		"model_offset": Vector3(0, 0, 0),
		"anim_name": "",
		"avatar_color": Color(0.16, 0.56, 0.88),
		"skill_key": "-",
		"skill_name": "Pure Survival",
		"skill_desc": "No special abilities. Outsmart and outrun the taggers to survive.",
		"skill_cd": "Passive",
	}
]

# State
var current_tab: String = "tagger" # "tagger" or "runner"
var selected_char_id: String = "ponpon"
var card_nodes: Dictionary = {} # id -> Dictionary

# SFX Players
var sfx_hover: AudioStreamPlayer = null
var sfx_click: AudioStreamPlayer = null

# SubViewport 3D Nodes
var model_holder: Node3D = null
var preview_viewport: SubViewport = null

# UI References
@onready var tagger_tab_btn: Button = get_node_or_null("HeaderContainer/TabsHBox/TaggerTabBtn")
@onready var runner_tab_btn: Button = get_node_or_null("HeaderContainer/TabsHBox/RunnerTabBtn")
@onready var profile_pill: PanelContainer = get_node_or_null("ProfilePill")
@onready var level_lbl: Label = get_node_or_null("ProfilePill/Margin/HBox/LevelLbl")
@onready var name_lbl: Label = get_node_or_null("ProfilePill/Margin/HBox/NameLbl")
@onready var exp_lbl: Label = get_node_or_null("ProfilePill/Margin/HBox/ExpLbl")
@onready var coins_lbl: Label = get_node_or_null("ProfilePill/Margin/HBox/CoinsLbl")

@onready var char_name_lbl: Label = get_node_or_null("PreviewSection/DetailsVBox/CharNameLbl")
@onready var role_badge_lbl: Label = get_node_or_null("PreviewSection/DetailsVBox/RoleBadge/RoleLabel")
@onready var skill_key_lbl: Label = get_node_or_null("PreviewSection/DetailsVBox/SkillCard/HBox/KeyBox/KeyLbl")
@onready var skill_title_lbl: Label = get_node_or_null("PreviewSection/DetailsVBox/SkillCard/HBox/InfoVBox/SkillTitleLbl")
@onready var skill_desc_lbl: Label = get_node_or_null("PreviewSection/DetailsVBox/SkillCard/HBox/InfoVBox/SkillDescLbl")
@onready var skill_cd_lbl: Label = get_node_or_null("PreviewSection/DetailsVBox/SkillCard/HBox/InfoVBox/SkillCdLbl")

@onready var select_title_lbl: Label = get_node_or_null("SelectionPanel/VBox/HeaderHBox/SelectTitleLbl")
@onready var char_count_lbl: Label = get_node_or_null("SelectionPanel/VBox/HeaderHBox/CountLbl")
@onready var cards_grid: GridContainer = get_node_or_null("SelectionPanel/VBox/Scroll/CardsGrid")
@onready var equip_btn: Button = get_node_or_null("SelectionPanel/VBox/EquipBtn")
@onready var back_btn: Button = get_node_or_null("BackButton")

func _ready() -> void:
	visible = false
	
	sfx_hover = AudioStreamPlayer.new()
	sfx_hover.stream = AUDIO_BTN_HOVER
	sfx_volume_setup(sfx_hover, -4.0)
	add_child(sfx_hover)
	
	sfx_click = AudioStreamPlayer.new()
	sfx_click.stream = AUDIO_BTN_CLICK
	sfx_volume_setup(sfx_click, -2.0)
	add_child(sfx_click)
	
	_setup_3d_preview()
	_connect_events()

func sfx_volume_setup(p: AudioStreamPlayer, vol: float) -> void:
	p.volume_db = vol

func _setup_3d_preview() -> void:
	var vp_container = get_node_or_null("PreviewSection/PreviewPanel/SubViewportContainer")
	if not vp_container:
		return
	
	preview_viewport = vp_container.get_node_or_null("SubViewport")
	if not preview_viewport:
		return
	
	model_holder = preview_viewport.get_node_or_null("ModelHolder")

func _connect_events() -> void:
	if tagger_tab_btn:
		tagger_tab_btn.pressed.connect(func(): _switch_tab("tagger"))
		_connect_sfx(tagger_tab_btn)
	if runner_tab_btn:
		runner_tab_btn.pressed.connect(func(): _switch_tab("runner"))
		_connect_sfx(runner_tab_btn)
	if equip_btn:
		equip_btn.pressed.connect(_on_equip_pressed)
		_connect_sfx(equip_btn)
	if back_btn:
		back_btn.pressed.connect(close)
		_connect_sfx(back_btn)

func _connect_sfx(btn: Control) -> void:
	if not btn: return
	btn.mouse_entered.connect(func():
		if is_instance_valid(sfx_hover): sfx_hover.play()
	)
	if btn is BaseButton:
		btn.pressed.connect(func():
			if is_instance_valid(sfx_click): sfx_click.play()
		)

func open() -> void:
	visible = true
	_update_profile_display()
	_switch_tab("tagger")

func close() -> void:
	visible = false
	closed.emit()

func _process(delta: float) -> void:
	if not visible:
		return
	if is_instance_valid(model_holder):
		model_holder.rotation.y += delta * 0.75

func _get_equipped_id_for_tab(tab: String) -> String:
	var net = get_node_or_null("/root/Network")
	if tab == "tagger":
		if net and not net.selected_tagger_type.is_empty():
			return net.selected_tagger_type
		return "ponpon"
	else:
		if net and not net.selected_runner_type.is_empty():
			return net.selected_runner_type
		return "penguin"

func _switch_tab(tab: String) -> void:
	current_tab = tab
	_update_tab_button_styles()
	
	var char_list = TAGGER_CHARACTERS if current_tab == "tagger" else RUNNER_CHARACTERS
	if select_title_lbl:
		select_title_lbl.text = "SELECT TAGGER" if current_tab == "tagger" else "SELECT RUNNER"
	if char_count_lbl:
		char_count_lbl.text = "%d CHARACTERS" % char_list.size()
	
	var equipped_id = _get_equipped_id_for_tab(current_tab)
	selected_char_id = equipped_id
	
	# Verify selected_char_id exists in this tab
	var found = false
	for c in char_list:
		if c["id"] == selected_char_id:
			found = true
			break
	if not found and not char_list.is_empty():
		selected_char_id = char_list[0]["id"]
	
	_build_cards(char_list)
	_display_character(selected_char_id)

func _update_tab_button_styles() -> void:
	if not tagger_tab_btn or not runner_tab_btn:
		return
	
	var is_tagger = (current_tab == "tagger")
	_apply_tab_style(tagger_tab_btn, is_tagger)
	_apply_tab_style(runner_tab_btn, not is_tagger)

func _apply_tab_style(btn: Button, is_active: bool) -> void:
	var sb = StyleBoxFlat.new()
	sb.set_corner_radius_all(10)
	if is_active:
		sb.bg_color = Color(0.16, 0.56, 0.88, 1.0)
		sb.border_width_left = 3
		sb.border_width_top = 3
		sb.border_width_right = 3
		sb.border_width_bottom = 3
		sb.border_color = Color(1.0, 1.0, 1.0, 1.0)
		sb.shadow_color = Color(0.06, 0.30, 0.59, 1.0)
		sb.shadow_size = 4
		btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	else:
		sb.bg_color = Color(0.06, 0.30, 0.59, 0.55)
		sb.border_width_left = 3
		sb.border_width_top = 3
		sb.border_width_right = 3
		sb.border_width_bottom = 3
		sb.border_color = Color(0.50, 0.72, 0.91, 1.0)
		sb.shadow_size = 0
		btn.add_theme_color_override("font_color", Color(0.81, 0.91, 1.0))
	
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)

func _build_cards(char_list: Array[Dictionary]) -> void:
	if not cards_grid:
		return
	
	for child in cards_grid.get_children():
		child.queue_free()
	card_nodes.clear()
	
	var equipped_id = _get_equipped_id_for_tab(current_tab)
	
	for c_data in char_list:
		var cid = str(c_data["id"])
		var card_btn = Button.new()
		card_btn.custom_minimum_size = Vector2(185, 175)
		card_btn.focus_mode = Control.FOCUS_NONE
		
		var sb_norm = StyleBoxFlat.new()
		sb_norm.set_corner_radius_all(16)
		
		var vbox = VBoxContainer.new()
		vbox.anchors_preset = Control.PRESET_FULL_RECT
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_theme_constant_override("separation", 6)
		card_btn.add_child(vbox)
		
		# Avatar Circle
		var avatar_panel = Panel.new()
		avatar_panel.custom_minimum_size = Vector2(74, 74)
		avatar_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		avatar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var av_sb = StyleBoxFlat.new()
		av_sb.bg_color = c_data.get("avatar_color", Color(0.4, 0.7, 1.0))
		av_sb.set_corner_radius_all(37)
		av_sb.border_width_left = 3
		av_sb.border_width_top = 3
		av_sb.border_width_right = 3
		av_sb.border_width_bottom = 3
		av_sb.border_color = Color(1.0, 1.0, 1.0, 0.9)
		avatar_panel.add_theme_stylebox_override("panel", av_sb)
		
		var av_icon = Label.new()
		av_icon.anchors_preset = Control.PRESET_FULL_RECT
		av_icon.text = str(c_data.get("skill_key", "❄"))
		av_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		av_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		av_icon.add_theme_font_override("font", FONT_AUDIOWIDE)
		av_icon.add_theme_font_size_override("font_size", 22)
		av_icon.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		avatar_panel.add_child(av_icon)
		vbox.add_child(avatar_panel)
		
		# Name Label
		var n_lbl = Label.new()
		n_lbl.text = str(c_data["name"])
		n_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n_lbl.add_theme_font_override("font", FONT_AUDIOWIDE)
		n_lbl.add_theme_font_size_override("font_size", 16)
		n_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		vbox.add_child(n_lbl)
		
		# Class Label
		var cl_lbl = Label.new()
		cl_lbl.text = str(c_data["class_name"])
		cl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl_lbl.add_theme_font_size_override("font_size", 12)
		cl_lbl.add_theme_color_override("font_color", Color(0.84, 0.94, 1.0))
		vbox.add_child(cl_lbl)
		
		# Equipped Badge
		var eq_badge = PanelContainer.new()
		eq_badge.anchors_preset = Control.PRESET_TOP_RIGHT
		eq_badge.anchor_left = 1.0
		eq_badge.anchor_right = 1.0
		eq_badge.offset_left = -78.0
		eq_badge.offset_top = 8.0
		eq_badge.offset_right = -8.0
		eq_badge.offset_bottom = 26.0
		eq_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var badge_sb = StyleBoxFlat.new()
		badge_sb.bg_color = Color(0.18, 0.75, 0.44, 1.0)
		badge_sb.set_corner_radius_all(10)
		eq_badge.add_theme_stylebox_override("panel", badge_sb)
		var b_lbl = Label.new()
		b_lbl.text = "EQUIPPED"
		b_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b_lbl.add_theme_font_size_override("font_size", 9)
		b_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		eq_badge.add_child(b_lbl)
		eq_badge.visible = (cid == equipped_id)
		card_btn.add_child(eq_badge)
		
		card_btn.pressed.connect(func(): _select_character(cid))
		_connect_sfx(card_btn)
		
		cards_grid.add_child(card_btn)
		card_nodes[cid] = {
			"btn": card_btn,
			"sb": sb_norm,
			"equipped_badge": eq_badge
		}
	
	_refresh_card_visuals()

func _refresh_card_visuals() -> void:
	var equipped_id = _get_equipped_id_for_tab(current_tab)
	
	for cid in card_nodes:
		var c = card_nodes[cid]
		var btn: Button = c["btn"]
		var sb: StyleBoxFlat = c["sb"]
		var eq_badge: PanelContainer = c["equipped_badge"]
		var is_selected = (cid == selected_char_id)
		var is_equipped = (cid == equipped_id)
		
		eq_badge.visible = is_equipped
		
		if is_selected:
			sb.bg_color = Color(0.23, 0.63, 0.93, 1.0)
			sb.border_width_left = 4
			sb.border_width_top = 4
			sb.border_width_right = 4
			sb.border_width_bottom = 4
			sb.border_color = Color(1.0, 0.82, 0.25, 1.0)
			sb.shadow_color = Color(1.0, 0.82, 0.25, 0.45)
			sb.shadow_size = 6
		else:
			sb.bg_color = Color(0.15, 0.43, 0.74, 0.45)
			sb.border_width_left = 3
			sb.border_width_top = 3
			sb.border_width_right = 3
			sb.border_width_bottom = 3
			sb.border_color = Color(0.50, 0.72, 0.91, 1.0)
			sb.shadow_size = 0
		
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)

func _select_character(cid: String) -> void:
	selected_char_id = cid
	_refresh_card_visuals()
	_display_character(cid)

func _display_character(cid: String) -> void:
	var char_list = TAGGER_CHARACTERS if current_tab == "tagger" else RUNNER_CHARACTERS
	var data: Dictionary = {}
	for c in char_list:
		if c["id"] == cid:
			data = c
			break
	if data.is_empty() and not char_list.is_empty():
		data = char_list[0]
	
	if char_name_lbl:
		char_name_lbl.text = str(data.get("name", "Character"))
	if role_badge_lbl:
		role_badge_lbl.text = str(data.get("role", "ROLE"))
	if skill_key_lbl:
		skill_key_lbl.text = str(data.get("skill_key", "E"))
	if skill_title_lbl:
		skill_title_lbl.text = str(data.get("skill_name", "Skill"))
	if skill_desc_lbl:
		skill_desc_lbl.text = str(data.get("skill_desc", "Description"))
	if skill_cd_lbl:
		skill_cd_lbl.text = str(data.get("skill_cd", "Cooldown"))
	
	# Update 3D Preview
	_load_preview_model(data)
	
	# Update Equip Button text
	var equipped_id = _get_equipped_id_for_tab(current_tab)
	
	if equip_btn:
		if cid == equipped_id:
			equip_btn.text = "✓ EQUIPPED"
			equip_btn.disabled = true
			equip_btn.modulate = Color(0.8, 0.95, 0.85)
		else:
			equip_btn.text = "EQUIP TAGGER" if current_tab == "tagger" else "EQUIP RUNNER"
			equip_btn.disabled = false
			equip_btn.modulate = Color(1.0, 1.0, 1.0)

func _load_preview_model(data: Dictionary) -> void:
	if not is_instance_valid(model_holder):
		return
	
	for child in model_holder.get_children():
		child.queue_free()
	
	var mpath = str(data.get("model_path", ""))
	if mpath.is_empty():
		# Random: create colorful rotating question box
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(0.8, 0.8, 0.8)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.82, 0.25)
		mat.metallic = 0.5
		mat.roughness = 0.2
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.75, 0.1)
		mat.emission_energy_multiplier = 0.8
		var mi = MeshInstance3D.new()
		mi.mesh = box_mesh
		mi.material_override = mat
		mi.position = Vector3(0, 0.8, 0)
		model_holder.add_child(mi)
		return
	
	if not ResourceLoader.exists(mpath):
		return
	
	var scn = ResourceLoader.load(mpath)
	if not scn or not scn is PackedScene:
		return
	
	var inst = scn.instantiate()
	if not inst:
		return
	
	var m_scale = data.get("model_scale", Vector3(1, 1, 1))
	var m_offset = data.get("model_offset", Vector3(0, 0, 0))
	inst.scale = m_scale
	inst.position = m_offset
	model_holder.add_child(inst)
	
	# Start walk animation if present
	var anim_name = str(data.get("anim_name", ""))
	if not anim_name.is_empty():
		var anim_player: AnimationPlayer = null
		if inst is AnimationPlayer:
			anim_player = inst
		else:
			anim_player = inst.find_child("AnimationPlayer", true, false)
		if is_instance_valid(anim_player) and anim_player.has_animation(anim_name):
			anim_player.play(anim_name)

func _on_equip_pressed() -> void:
	var net = get_node_or_null("/root/Network")
	if current_tab == "tagger":
		if net:
			net.selected_tagger_type = selected_char_id
			net.current_user["taggerType"] = selected_char_id
			net.save_local_user()
	elif current_tab == "runner":
		if net:
			net.selected_runner_type = selected_char_id
			net.current_user["runnerType"] = selected_char_id
			net.save_local_user()
	
	_refresh_card_visuals()
	_display_character(selected_char_id)

func _update_profile_display() -> void:
	var net = get_node_or_null("/root/Network")
	var u = net.current_user if net else {}
	
	var lv = int(u.get("level", 1))
	var d_name = str(u.get("displayName", "Guest"))
	var exp_cur = int(u.get("exp", 0))
	var exp_max = int(u.get("maxExp", 100))
	var coins = int(u.get("coins", 0))
	
	if level_lbl: level_lbl.text = "Lv. %d" % lv
	if name_lbl: name_lbl.text = d_name
	if exp_lbl: exp_lbl.text = "EXP: %d/%d" % [exp_cur, exp_max]
	if coins_lbl: coins_lbl.text = "🪙 %d" % coins

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

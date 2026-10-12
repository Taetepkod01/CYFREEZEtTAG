extends Node

const BGM_MENU_LOBBY = preload("res://assets/audio/bgm/menu_lobby_bgm.mp3")

var bgm_player: AudioStreamPlayer = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "BGMPlayer"
	bgm_player.stream = BGM_MENU_LOBBY
	bgm_player.volume_db = -6.0
	bgm_player.bus = "Master"
	
	if bgm_player.stream is AudioStreamMP3:
		bgm_player.stream.loop = true
	
	add_child(bgm_player)
	play_menu_bgm()

func play_menu_bgm() -> void:
	if not bgm_player:
		return
	if not bgm_player.playing:
		bgm_player.volume_db = -6.0
		bgm_player.play()

func stop_bgm() -> void:
	if bgm_player and bgm_player.playing:
		bgm_player.stop()

func fade_out_bgm(duration: float = 0.8) -> void:
	if not bgm_player or not bgm_player.playing:
		return
	var tween = create_tween()
	tween.tween_property(bgm_player, "volume_db", -40.0, duration)
	tween.finished.connect(func():
		if is_instance_valid(bgm_player):
			bgm_player.stop()
			bgm_player.volume_db = -6.0
	)

func is_playing() -> bool:
	return bgm_player != null and bgm_player.playing

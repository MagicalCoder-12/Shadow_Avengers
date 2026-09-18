extends Node

# Persistent audio player for background music
var background_player: AudioStreamPlayer = AudioStreamPlayer.new()

const BULLET_SFX_COOLDOWN_MS: int = 80
const BULLET_SFX_VOLUME_DB: float = -12.0
const BACKGROUND_MENU_VOLUME_DB: float = -8.0
const BACKGROUND_LEVEL_VOLUME_DB: float = -14.0
const BULLET_BUS_MAX_DB: float = -18.0

# Audio bus indices
var background_bus_idx: int = AudioServer.get_bus_index("Background")
var bullet_bus_idx: int = AudioServer.get_bus_index("Bullet")
var boss_bus_idx: int = AudioServer.get_bus_index("Boss")
var explosion_bus_idx: int = AudioServer.get_bus_index("Explosion")
var video_bus_idx: int = AudioServer.get_bus_index("Video")

# Current background music stream
var current_background_music: AudioStream

# Store original bus volumes for restoration
var _original_bus_volumes: Dictionary = {}
var _last_sfx_play_time_ms_by_bus: Dictionary = {}

# Audio player pool — avoids creating/destroying nodes per SFX.
const SFX_POOL_SIZE: int = 16
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_pool_index: int = 0

func _ready() -> void:
	# Validate bus indices
	if background_bus_idx == -1: push_error("Background bus not found")
	if bullet_bus_idx == -1: push_error("Bullet bus not found")
	if boss_bus_idx == -1: push_error("Boss bus not found")
	if explosion_bus_idx == -1: push_error("Explosion bus not found")
	if video_bus_idx == -1: push_error("Video bus not found")
	
	# Configure background music player
	background_player.bus = "Background"
	add_child(background_player)
	_apply_default_mix_targets()

func play_background_music(stream: AudioStream, force_restart: bool = false) -> void:
	if not stream:
		push_error("No audio stream provided for background music")
		return
	if not is_inside_tree() or not background_player.is_inside_tree():
		# Defer playback until in scene tree
		call_deferred("play_background_music", stream, force_restart)
		return
	if current_background_music == stream and background_player.playing and not force_restart:
		return
	current_background_music = stream
	background_player.stream = stream
	background_player.play()
	AudioServer.set_bus_mute(background_bus_idx, false) # Ensure unmuted

func stop_background_music() -> void:
	background_player.stop()
	current_background_music = null

# Reset all audio state for clean restart
func reset_audio_state() -> void:
	stop_background_music()
	# Stop any remaining scene audio players
	if get_tree() and get_tree().current_scene:
		stop_scene_audio_players(get_tree().current_scene)
	# Reset bus states
	mute_bus("Bullet", false)
	mute_bus("Explosion", false)
	mute_bus("Boss", false)

func play_sound_effect(stream: AudioStream, bus: String) -> void:
	if not stream:
		push_error("No audio stream provided for sound effect")
		return
	if _should_throttle_sound_effect(bus):
		return
	var player := _get_sfx_player()
	player.bus = bus
	player.stream = stream
	player.volume_db = BULLET_SFX_VOLUME_DB if bus == "Bullet" else 0.0
	player.play()

func _should_throttle_sound_effect(bus: String) -> bool:
	if bus != "Bullet":
		return false
	var now_ms: int = Time.get_ticks_msec()
	var last_ms: int = int(_last_sfx_play_time_ms_by_bus.get(bus, -100000))
	if now_ms - last_ms < BULLET_SFX_COOLDOWN_MS:
		return true
	_last_sfx_play_time_ms_by_bus[bus] = now_ms
	return false

func _apply_default_mix_targets() -> void:
	if background_bus_idx != -1:
		# Start from a moderate menu mix instead of boosting BGM to 0 dB.
		AudioServer.set_bus_volume_db(background_bus_idx, BACKGROUND_MENU_VOLUME_DB)
	if bullet_bus_idx != -1:
		var current_bullet_volume: float = AudioServer.get_bus_volume_db(bullet_bus_idx)
		if current_bullet_volume > BULLET_BUS_MAX_DB:
			AudioServer.set_bus_volume_db(bullet_bus_idx, BULLET_BUS_MAX_DB)

func set_gameplay_mix(enabled: bool) -> void:
	if background_bus_idx == -1:
		return
	var target_volume: float = BACKGROUND_LEVEL_VOLUME_DB if enabled else BACKGROUND_MENU_VOLUME_DB
	AudioServer.set_bus_volume_db(background_bus_idx, target_volume)


func mute_audio_buses(mute: bool, exclude_video: bool = false) -> void:
	if background_bus_idx >= 0:
		AudioServer.set_bus_mute(background_bus_idx, mute)
	if bullet_bus_idx >= 0:
		AudioServer.set_bus_mute(bullet_bus_idx, mute)
	if boss_bus_idx >= 0:
		AudioServer.set_bus_mute(boss_bus_idx, mute)
	if explosion_bus_idx >= 0:
		AudioServer.set_bus_mute(explosion_bus_idx, mute)
	if exclude_video and video_bus_idx >= 0:
		AudioServer.set_bus_mute(video_bus_idx, false)

func lower_bus_volumes_except(exclude_buses: Array[String], volume_db: float) -> void:
	_original_bus_volumes = {}
	for bus_idx in AudioServer.bus_count:
		var bus_name = AudioServer.get_bus_name(bus_idx)
		if bus_name not in exclude_buses:
			_original_bus_volumes[bus_name] = AudioServer.get_bus_volume_db(bus_idx)
			AudioServer.set_bus_volume_db(bus_idx, volume_db)

func restore_bus_volumes() -> void:
	for bus_name in _original_bus_volumes:
		var bus_idx = AudioServer.get_bus_index(bus_name)
		if bus_idx != -1:
			AudioServer.set_bus_volume_db(bus_idx, _original_bus_volumes[bus_name])
	_original_bus_volumes.clear()

func stop_scene_audio_players(root: Node) -> void:
	if root:
		# Recursively find and stop all audio players
		var nodes = [root]
		while nodes:
			var node = nodes.pop_front()
			if node is AudioStreamPlayer or node is AudioStreamPlayer2D:
				node.stop()
			nodes.append_array(node.get_children())

func _get_sfx_player() -> AudioStreamPlayer:
	# Lazy-init the pool on first use.
	if _sfx_pool.is_empty():
		_sfx_pool.resize(SFX_POOL_SIZE)
		for i in SFX_POOL_SIZE:
			var p := AudioStreamPlayer.new()
			add_child(p)
			_sfx_pool[i] = p

	# Round-robin through the pool. If the chosen player is still playing,
	# the sound is dropped rather than stacking infinitely.
	var player := _sfx_pool[_sfx_pool_index]
	_sfx_pool_index = (_sfx_pool_index + 1) % SFX_POOL_SIZE
	return player

func mute_bus(bus_name: String, mute: bool) -> void:
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx == -1:
		push_error("Bus %s not found!" % bus_name)
		return
	AudioServer.set_bus_mute(bus_idx, mute)

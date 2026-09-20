extends Node


var gm: Node
var _initialized: bool = false
## Newest scene request that arrived while another transition was still running.
## Empty when nothing is waiting.
var _queued_scene_path: String = ""
## Target of the transition that is currently loading. Used to drop a duplicate
## request (double-tap on the same button) instead of reloading the same scene.
var _in_flight_path: String = ""
const LOADER_SCENE: PackedScene = preload("res://Autoloads/screen_loader.tscn")
const MAP_SCENE: String = "res://Map/map.tscn"
const START_SCREEN_SCENE: String = "res://MainScenes/start_menu.tscn"
const UPGRADE_MENU: String = "res://MainScenes/upgrade_menu.tscn"
const BACKGROUND_MUSIC: AudioStream = preload("res://Assets/Music/Start.ogg")

func _ready() -> void:
	gm = GameManager
	# _process only ticks while a transition is in flight or a request is queued.
	set_process(false)
	# Defer initialization until all autoloads are ready
	call_deferred("initialize")

func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	AudioManager.play_background_music(BACKGROUND_MUSIC, false)

func change_scene(scene_path: String) -> void:
	if not ResourceLoader.exists(scene_path):
		push_error("Scene not found: %s" % scene_path)
		return
	
	# A transition is already running: remember this request instead of dropping
	# it. Dropping was what made a fast double-tap on Start/Play/Back do nothing.
	# A repeat of a target that is already loading or already queued is still
	# ignored, so double-tapping one button cannot reload the same scene twice.
	if is_transitioning() or not _queued_scene_path.is_empty():
		if scene_path != _in_flight_path and scene_path != _queued_scene_path:
			_queued_scene_path = scene_path
		return
	
	_begin_change(scene_path)

## True while a loader screen from an earlier request is still on screen.
func is_transitioning() -> bool:
	var viewport_root: Window = gm.get_tree().root if gm and gm.is_inside_tree() else null
	return viewport_root != null and viewport_root.get_node_or_null("LoaderCanvasLayer") != null

## Starts the queued request once the running loader has finished with it.
## Polling (rather than a loader signal) also covers a loader that errors out and
## frees itself, so a queued request can never be stranded.
func _process(_delta: float) -> void:
	if is_transitioning():
		return
	
	# The previous transition is done.
	_in_flight_path = ""
	if _queued_scene_path.is_empty():
		set_process(false)
		return
	
	var next_scene := _queued_scene_path
	_queued_scene_path = ""
	if not ResourceLoader.exists(next_scene):
		push_error("Queued scene not found: %s" % next_scene)
		return
	_begin_change(next_scene)

func _begin_change(scene_path: String) -> void:
	gm.scene_change_started.emit()
	var viewport_root: Window = gm.get_tree().root
	if viewport_root == null:
		# No tree yet - not reachable in practice, but keep the request alive
		# rather than losing it.
		_queued_scene_path = scene_path
		set_process(true)
		return
	
	# Update stars before transitioning to map scene
	if scene_path == MAP_SCENE:
		_prepare_map_scene()
	
	_in_flight_path = scene_path
	set_process(true)
	var loader: Node = LOADER_SCENE.instantiate()
	loader.name = "LoaderCanvasLayer"
	loader.process_mode = Node.PROCESS_MODE_ALWAYS
	viewport_root.add_child(loader)
	
	# Mute all buses except Background and Master
	for bus in range(AudioServer.bus_count):
		var bus_name = AudioServer.get_bus_name(bus)
		if bus_name != "Background" and bus_name != "Master":
			AudioServer.set_bus_mute(bus, true)
	
	loader.start_load(scene_path)

# Prepare map scene by updating stars visibility
func _prepare_map_scene() -> void:
	# Emit a signal to update stars before transitioning to map scene
	# This ensures stars are properly set before the scene transition
	if gm.has_signal("prepare_map_scene"):
		gm.emit_signal("prepare_map_scene")

func handle_node_added(node: Node) -> void:
	if node is Control and node.name == "LoaderCanvasLayer":
		node.z_index = 4096
	
	if node == gm.get_tree().current_scene:
		var scene_path = node.scene_file_path if node.scene_file_path else ""
		
		if scene_path == START_SCREEN_SCENE or scene_path == MAP_SCENE or scene_path == UPGRADE_MENU:
			AudioManager.play_background_music(BACKGROUND_MUSIC, false)
			AudioManager.set_gameplay_mix(false)
			if AudioManager.background_player:
				AudioManager.background_player.stream.loop = true
				AudioManager.background_player.stream_paused = false
			
			AudioManager.mute_bus("Bullet", true)
			AudioManager.mute_bus("Explosion", true)
			AudioManager.mute_bus("Boss", true)
		else:
			AudioManager.set_gameplay_mix(true)
			if AudioManager.background_player:
				AudioManager.background_player.stream.loop = false
			
			AudioManager.mute_bus("Bullet", false)
			AudioManager.mute_bus("Explosion", false)
			AudioManager.mute_bus("Boss", false)
			

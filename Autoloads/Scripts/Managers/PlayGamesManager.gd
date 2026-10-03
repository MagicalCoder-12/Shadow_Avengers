extends Node
## Project-side wrapper around the GodotPlayGameServices addon (Google Play
## Games Services: sign-in, leaderboards, achievements).
##
## - Android release builds: auto-initializes the plugin, checks sign-in state,
##   submits level scores and unlocks achievements as the game reports them.
## - Everywhere else (editor, desktop, unconfigured IDs): every call is a safe
##   no-op, so gameplay and testing never depend on Play Games.
##
## Play Console setup (one time, by hand):
## 1. Create the game in Play Console, link this app (package
##    com.Aj.ShadowAvenger), create OAuth Android clients (upload + Play
##    signing SHA-1) and publish Games Services.
## 2. Create one leaderboard + the achievements below; paste their IDs into
##    res://data/play_games_ids.json (replace the REPLACE_WITH_* placeholders).
## 3. Enter the numeric Game ID in Project > Export > Android >
##    godot_play_game_services/game_id, then export.

const IDS_PATH: String = "res://data/play_games_ids.json"
const UNCONFIGURED_PREFIX: String = "REPLACE_WITH_"

# Addon client scripts resolve at runtime (not via preload/global class_name)
# so this wrapper - and everything referencing it - compiles even when the
# editor's global script class cache has not rescanned the addon yet.
const SIGN_IN_CLIENT_PATH: String = "res://addons/GodotPlayGameServices/scripts/sign_in/sign_in_client.gd"
const LEADERBOARDS_CLIENT_PATH: String = "res://addons/GodotPlayGameServices/scripts/leaderboards/leaderboards_client.gd"
const ACHIEVEMENTS_CLIENT_PATH: String = "res://addons/GodotPlayGameServices/scripts/achievements/achievements_client.gd"

var available: bool = false
var signed_in: bool = false
var ids: Dictionary = {}

var _sign_in_client: Node = null
var _leaderboards_client: Node = null
var _achievements_client: Node = null
var _warned_unconfigured: bool = false


func _ready() -> void:
	call_deferred("_initialize")


func _initialize() -> void:
	ids = _load_ids()
	if not OS.has_feature("android"):
		return
	if not _has_plugin_autoload():
		return
	var result = GodotPlayGameServices.initialize()
	if int(result) != 0:
		return
	var SignInClientScript: GDScript = load(SIGN_IN_CLIENT_PATH) as GDScript
	var LeaderboardsClientScript: GDScript = load(LEADERBOARDS_CLIENT_PATH) as GDScript
	var AchievementsClientScript: GDScript = load(ACHIEVEMENTS_CLIENT_PATH) as GDScript
	if SignInClientScript == null or LeaderboardsClientScript == null or AchievementsClientScript == null:
		return
	available = true
	_sign_in_client = SignInClientScript.new()
	_leaderboards_client = LeaderboardsClientScript.new()
	_achievements_client = AchievementsClientScript.new()
	add_child(_sign_in_client)
	add_child(_leaderboards_client)
	add_child(_achievements_client)
	_sign_in_client.user_authenticated.connect(_on_user_authenticated)
	_sign_in_client.is_authenticated()


func _has_plugin_autoload() -> bool:
	# The addon registers this singleton when enabled in Project Settings.
	var root: Window = get_tree().root
	return root != null and root.has_node("GodotPlayGameServices")


func _load_ids() -> Dictionary:
	if not FileAccess.file_exists(IDS_PATH):
		return {}
	var file: FileAccess = FileAccess.open(IDS_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _configured_id(key: String) -> String:
	var value := str(ids.get(key, ""))
	if value.is_empty() or value.begins_with(UNCONFIGURED_PREFIX):
		if not _warned_unconfigured and GameManager and GameManager.debug_mode:
			_warned_unconfigured = true
			print("PlayGamesManager: Play Console IDs not configured, Play Games calls are skipped.")
		return ""
	return value


func is_play_games_ready() -> bool:
	return available and signed_in


func sign_in() -> void:
	if not available or _sign_in_client == null:
		return
	_sign_in_client.sign_in()


func _on_user_authenticated(is_authenticated: bool) -> void:
	signed_in = is_authenticated
	if GameManager and GameManager.debug_mode:
		print("PlayGamesManager: signed_in=%s" % str(signed_in))


## Submits a level score to the best-score leaderboard. Play keeps the best.
func submit_level_score(score: int) -> void:
	if not is_play_games_ready():
		return
	var board := _configured_id("leaderboard_best_score")
	if board.is_empty() or score <= 0:
		return
	_leaderboards_client.submit_score(board, score)


## Unlocks one of the achievement IDs from play_games_ids.json, e.g. "boss_5".
func unlock_achievement(key: String) -> void:
	if not is_play_games_ready():
		return
	var achievements: Dictionary = ids.get("achievements", {})
	var achievement_id := str(achievements.get(key, ""))
	if achievement_id.is_empty() or achievement_id.begins_with(UNCONFIGURED_PREFIX):
		return
	_achievements_client.unlock_achievement(achievement_id)


## Opens the Play Games leaderboards UI. No-op unless signed in on Android.
func show_leaderboards() -> void:
	if not is_play_games_ready():
		return
	_leaderboards_client.show_all_leaderboards()


## Opens the Play Games achievements UI. No-op unless signed in on Android.
func show_achievements() -> void:
	if not is_play_games_ready():
		return
	_achievements_client.show_achievements()

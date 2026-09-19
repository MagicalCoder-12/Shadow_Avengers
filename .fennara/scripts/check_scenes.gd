extends SceneTree
## Headless parse validation for the converted scenes.

func _init() -> void:
	var scenes := [
		"res://Bullet/PlBullet/super2.tscn",
		"res://Enemy/bouncer_enemy.tscn",
		"res://Enemy/fast_enemy.tscn",
		"res://Map/map.tscn",
		"res://Powerups/SuperMode.tscn",
		"res://Satellites/Satellite2.tscn",
		"res://Ships/Player_Ship3.tscn",
	]
	var fails := 0
	for s: String in scenes:
		var p: PackedScene = load(s)
		if p == null:
			fails += 1
			print("FAIL ", s)
		else:
			var inst := p.instantiate()
			print("OK   ", s, " (", inst.get_child_count(), " children)")
			inst.free()
	print("RESULT: ", scenes.size() - fails, "/", scenes.size(), " scenes load")
	quit(fails)

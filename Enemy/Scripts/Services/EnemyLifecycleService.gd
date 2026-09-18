extends RefCounted
class_name EnemyLifecycleService

var _enemy: Node = null

func configure(enemy: Node) -> void:
	_enemy = enemy

func disconnect_all_signals() -> void:
	if not _enemy:
		return
	if _enemy.shadow_tween:
		_enemy.shadow_tween.kill()
		_enemy.shadow_tween = null

func initialize_shadow_state() -> void:
	if not _enemy:
		return
	if _enemy.shadow_mode_unlocked and randf() < _enemy.shadow_spawn_probability:
		_enemy._make_shadow_enemy()

func make_shadow_enemy() -> void:
	if not _enemy:
		return
	_enemy.is_shadow_enemy = true
	_enemy.max_health = int(_enemy.max_health * _enemy.shadow_health_multiplier)
	_enemy.damage_amount = int(_enemy.damage_amount * _enemy.shadow_damage_multiplier)
	_enemy.score = int(_enemy.score * _enemy.shadow_score_multiplier)
	if _enemy.sprite and _enemy.sprite.scale.x < 1.0:
		_enemy.sprite.scale = Vector2(1.0, 1.0)
	apply_shadow_visuals()
	_enemy.shadow_state_changed.emit(true)

func apply_shadow_visuals() -> void:
	if not _enemy or not _enemy.is_shadow_enemy:
		return
	if _enemy.sprite and _enemy.sprite.scale.x < 1.0:
		_enemy.sprite.scale = Vector2(1.0, 1.0)
	if _enemy.shadow_texture and _enemy.sprite:
		_enemy.sprite.texture = _enemy.shadow_texture
	else:
		_enemy.modulate = Color(0.4, 0.4, 1.0, 0.8)
		start_shadow_pulse()
	if _enemy.healthbar:
		_enemy.healthbar.modulate = Color(0.5, 0.5, 1.0, 0.8)

func start_shadow_pulse() -> void:
	if not _enemy:
		return
	if _enemy.shadow_tween:
		_enemy.shadow_tween.kill()
	_enemy.shadow_tween = _enemy.create_tween()
	_enemy.shadow_tween.tween_method(Callable(_enemy, "_set_shadow_alpha"), _enemy.shadow_alpha_max, _enemy.shadow_alpha_min, _enemy.shadow_pulse_speed / 2.0)
	_enemy.shadow_tween.tween_method(Callable(_enemy, "_set_shadow_alpha"), _enemy.shadow_alpha_min, _enemy.shadow_alpha_max, _enemy.shadow_pulse_speed / 2.0)
	var finished_callable := Callable(_enemy, "_on_shadow_pulse_finished")
	if not _enemy.shadow_tween.finished.is_connected(finished_callable):
		_enemy.shadow_tween.finished.connect(finished_callable)

func on_shadow_pulse_finished() -> void:
	if not _enemy:
		return
	if _enemy.is_shadow_enemy and not _enemy.shadow_texture and _enemy.is_inside_tree():
		start_shadow_pulse()

func set_shadow_alpha(alpha: float) -> void:
	if not _enemy:
		return
	if _enemy.is_shadow_enemy and not _enemy.shadow_texture:
		_enemy.modulate.a = alpha

func on_shadow_mode_activated() -> void:
	if not _enemy:
		return
	if GameManager.debug_mode:
		print("Shadow mode activated for enemy")
	if not _enemy.is_shadow_enemy:
		_enemy._make_shadow_enemy()
	if _enemy.fire_timer:
		_enemy.fire_timer.wait_time = (1.0 / _enemy.fire_rate) * 0.7
	_enemy.speed = _enemy.original_speed * 1.3
	_enemy.vertical_speed = _enemy.original_vertical_speed * 1.3
	# Avoid synchronized volleys when shadow mode toggles for many enemies.
	_enemy.can_shoot = false
	_enemy.shoot_cooldown = randf_range(0.08, 0.45)
	if _enemy.sprite and _enemy.sprite.scale.x < 1.0:
		_enemy.sprite.scale = Vector2(1.0, 1.0)
	if _enemy.sprite:
		_enemy.sprite.modulate = Color(0.3, 0.3, 1.0, 1.0)

func on_shadow_mode_deactivated() -> void:
	if not _enemy:
		return
	if GameManager.debug_mode:
		print("Shadow mode deactivated for enemy")
	if _enemy.fire_timer:
		_enemy.fire_timer.wait_time = 1.0 / _enemy.fire_rate
	_enemy.speed = _enemy.original_speed
	_enemy.vertical_speed = _enemy.original_vertical_speed
	if _enemy.sprite and _enemy.is_shadow_enemy:
		_enemy.sprite.modulate = Color(0.4, 0.4, 1.0, 0.8)
		if _enemy.shadow_tween:
			_enemy.shadow_tween.kill()
			_enemy.shadow_tween = null

func apply_damage(amount: int) -> void:
	if not _enemy or not _enemy.is_alive:
		return
	var final_amount: int = amount
	if _enemy.shadow_core_shield and _enemy.shadow_core_shield.visible:
		final_amount = int(final_amount * (1.0 - _enemy.shield_damage_reduction))
		show_shield_hit_feedback()
	_enemy.health -= final_amount
	if _enemy.healthbar:
		_enemy.healthbar.value = _enemy.health
	if _enemy.health <= 0:
		_enemy.die()

func show_shield_hit_feedback() -> void:
	if not _enemy:
		return
	if _enemy.shadow_core_shield:
		var tween := _enemy.create_tween()
		tween.tween_property(_enemy.shadow_core_shield, "modulate", Color(1.0, 1.0, 1.0, 0.5), 0.1)
		tween.tween_property(_enemy.shadow_core_shield, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.1)

func die() -> void:
	if not _enemy or not _enemy.is_alive:
		return
	_enemy.is_alive = false
	if _enemy.healthbar:
		_enemy.healthbar.visible = false
	var payload := {
		"enemy_type": _enemy.enemy_type,
		"is_boss": false,
		"base_score": _enemy.score,
		"is_shadow_enemy": _enemy.is_shadow_enemy,
		"shadow_score_multiplier": _enemy.shadow_score_multiplier,
		"global_position": _enemy.global_position
	}
	_enemy.enemy_died.emit(payload)
	disconnect_all_signals()
	play_death_animation()
	_enemy.died.emit()

func play_death_animation() -> void:
	if not _enemy:
		return
	if _enemy.enemy_explosion:
		_enemy.enemy_explosion.visible = true
		_enemy.enemy_explosion.play("explode")
		var finished_callable := Callable(_enemy, "_on_death_animation_finished")
		if not _enemy.enemy_explosion.animation_finished.is_connected(finished_callable):
			_enemy.enemy_explosion.animation_finished.connect(finished_callable)
	if _enemy.explosion_sound:
		_enemy.explosion_sound.play()
	if _enemy.sprite:
		_enemy.sprite.visible = false
	if _enemy.shadow_core_shield:
		_enemy.shadow_core_shield.visible = false
	if _enemy.collision_shape:
		_enemy.collision_shape.set_deferred("disabled", true)

func on_death_animation_finished() -> void:
	if not _enemy:
		return
	_enemy.queue_free()

func on_visible_screen_exited() -> void:
	if not _enemy:
		return
	if _enemy.is_in_entry_phase:
		return
	_enemy.queue_free()

func on_shadow_mode_changed(active: bool) -> void:
	if not _enemy:
		return
	_enemy.is_shadow_mode_active = active
	if active:
		on_shadow_mode_activated()
	else:
		on_shadow_mode_deactivated()

func on_shadow_mode_unlocked_changed(unlocked: bool) -> void:
	if not _enemy:
		return
	_enemy.shadow_mode_unlocked = unlocked

func handle_area_entered(area: Area2D) -> void:
	if not _enemy:
		return
	if area.is_in_group("PlayerBullet"):
		_enemy.damage(_resolve_bullet_damage(area))
		if area.has_method("queue_free"):
			area.queue_free()

func _resolve_bullet_damage(area: Area2D) -> int:
	if area.has_method("get_damage"):
		var reported_damage: Variant = area.call("get_damage")
		if reported_damage is int:
			return max(1, int(reported_damage))
		if reported_damage is float:
			return max(1, int(round(reported_damage)))

	if area is BulletBase:
		return max(1, (area as BulletBase).damage)

	return 1

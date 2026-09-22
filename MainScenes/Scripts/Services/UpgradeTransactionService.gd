extends RefCounted
class_name UpgradeTransactionService

const DEFAULT_SHIP_COSTS := {"crystal_cost": 50, "coin_cost": 250, "void_shard_cost": 100}
const DEFAULT_SATELLITE_COSTS := {"crystal_cost": 30, "coin_cost": 500, "void_shard_cost": 80}

func _get_upgrade_setting(config_loader, key: String, default_value: Variant) -> Variant:
	if is_instance_valid(config_loader) and config_loader.upgrade_settings:
		return config_loader.upgrade_settings.get(key, default_value)
	return default_value

func get_ship_upgrade_costs(config_loader, ship: Dictionary) -> Dictionary:
	if ship.is_empty():
		return DEFAULT_SHIP_COSTS.duplicate(true)

	var upgrade_count: int = int(ship.get("upgrade_count", 0))
	var ascend_count: int = int(ship.get("ascend_count", 0))

	var base_crystal_cost: int = int(_get_upgrade_setting(config_loader, "upgrade_crystal_cost", 50))
	var base_coin_cost: int = int(_get_upgrade_setting(config_loader, "upgrade_coin_cost", 250))
	var ascend_cost: int = int(_get_upgrade_setting(config_loader, "upgrade_ascend_cost", 100))

	var crystal_scaling_factor: float = float(_get_upgrade_setting(config_loader, "crystal_scaling_factor", 1.10))
	var coin_scaling_factor: float = float(_get_upgrade_setting(config_loader, "coin_scaling_factor", 1.25))
	var ascend_scaling_factor: float = float(_get_upgrade_setting(config_loader, "ascend_scaling_factor", 1.05))

	var crystal_cost: float = float(base_crystal_cost) * pow(crystal_scaling_factor, float(upgrade_count - ascend_count))
	var coin_cost: float = float(base_coin_cost) * pow(coin_scaling_factor, float(upgrade_count - ascend_count))
	var void_shard_cost: float = float(ascend_cost) * pow(ascend_scaling_factor, float(ascend_count))

	return {
		"crystal_cost": int(crystal_cost),
		"coin_cost": int(coin_cost),
		"void_shard_cost": int(void_shard_cost)
	}

func get_satellite_upgrade_costs(config_loader, satellite: Dictionary) -> Dictionary:
	if satellite.is_empty():
		return DEFAULT_SATELLITE_COSTS.duplicate(true)

	var upgrade_count: int = int(satellite.get("upgrade_count", 0))
	var ascend_count: int = int(satellite.get("ascend_count", 0))

	var base_crystal_cost: int = int(_get_upgrade_setting(config_loader, "satellite_crystal_cost", 30))
	var base_coin_cost: int = int(_get_upgrade_setting(config_loader, "satellite_coin_cost", 500))
	var ascend_cost: int = int(_get_upgrade_setting(config_loader, "satellite_ascend_cost", 80))

	var crystal_scaling_factor: float = float(_get_upgrade_setting(config_loader, "satellite_crystal_scaling_factor", 1.10))
	var coin_scaling_factor: float = float(_get_upgrade_setting(config_loader, "satellite_coin_scaling_factor", 1.15))
	var ascend_scaling_factor: float = float(_get_upgrade_setting(config_loader, "satellite_ascend_scaling_factor", 1.05))

	var crystal_cost: float = float(base_crystal_cost) * pow(crystal_scaling_factor, float(upgrade_count - ascend_count))
	var coin_cost: float = float(base_coin_cost) * pow(coin_scaling_factor, float(upgrade_count - ascend_count))
	var void_shard_cost: float = float(ascend_cost) * pow(ascend_scaling_factor, float(ascend_count))

	return {
		"crystal_cost": int(crystal_cost),
		"coin_cost": int(coin_cost),
		"void_shard_cost": int(void_shard_cost)
	}

func can_afford(game_manager, cost: int, currency_type: String) -> bool:
	var normalized_cost: int = maxi(0, cost)
	return game_manager != null and game_manager.can_afford(currency_type, normalized_cost)

func deduct_currency(game_manager, amount: int, currency_type: String) -> void:
	if game_manager == null:
		return
	var normalized_amount: int = maxi(0, amount)
	game_manager.deduct_currency(currency_type, normalized_amount)

func save_progress(game_manager) -> void:
	if game_manager and game_manager.save_manager:
		game_manager.save_manager.save_progress()

func try_pay_upgrade_cost(game_manager, costs: Dictionary, currency_type: String) -> Dictionary:
	var cost_key: String = "crystal_cost" if currency_type == "crystals" else "coin_cost"
	var cost: int = int(costs.get(cost_key, 0))
	if not can_afford(game_manager, cost, currency_type):
		return {
			"ok": false,
			"error": "insufficient_funds",
			"currency_type": currency_type,
			"cost": cost
		}
	deduct_currency(game_manager, cost, currency_type)
	return {
		"ok": true,
		"currency_type": currency_type,
		"cost": cost
	}

func try_pay_ascend_cost(game_manager, costs: Dictionary) -> Dictionary:
	var cost: int = int(costs.get("void_shard_cost", 0))
	if not can_afford(game_manager, cost, "void_shards"):
		return {
			"ok": false,
			"error": "insufficient_funds",
			"currency_type": "void_shards",
			"cost": cost
		}
	deduct_currency(game_manager, cost, "void_shards")
	return {
		"ok": true,
		"currency_type": "void_shards",
		"cost": cost
	}

func try_purchase_unlock(game_manager, item: Dictionary, currency_type: String = "crystals") -> Dictionary:
	if item.is_empty():
		return {
			"ok": false,
			"error": "invalid_item"
		}
	if bool(item.get("unlocked", false)):
		return {
			"ok": false,
			"error": "already_unlocked"
		}

	var cost: int = int(item.get("purchase_cost", 0))
	if cost <= 0:
		_mark_purchased(item)
		save_progress(game_manager)
		return {
			"ok": true,
			"was_free": true,
			"currency_type": currency_type,
			"cost": 0
		}

	if not can_afford(game_manager, cost, currency_type):
		return {
			"ok": false,
			"error": "insufficient_funds",
			"currency_type": currency_type,
			"cost": cost
		}

	deduct_currency(game_manager, cost, currency_type)
	_mark_purchased(item)
	save_progress(game_manager)
	return {
		"ok": true,
		"was_free": false,
		"currency_type": currency_type,
		"cost": cost
	}

## Unlocking an item and having bought it are different facts: `unlocked`
## only says it is usable right now, while `purchased` is the durable record
## that crystals were spent on it. The tutorial's satellite-lock migration
## reads `purchased` to decide whether it may re-lock the first satellite for
## the BUY step - without this key it re-locked already-bought satellites
## after a restart and the player lost the purchase.
func _mark_purchased(item: Dictionary) -> void:
	item["unlocked"] = true
	item["purchased"] = true

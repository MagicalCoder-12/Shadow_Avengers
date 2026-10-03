extends RefCounted
class_name WaveMixer

## Runtime wave enrichment: blends shooter and pressure (non-shooter) enemy
## types inside every wave, Chicken Invaders style. A wave keeps its authored
## base type as the majority and gains evenly spread mix-ins: swooping
## FastEnemies / bombing BomberBugs inside shooter formations, and sharpshooters
## inside diver/bomber waves. Mix share and shooter tier scale with the level,
## so late levels (16-20) stay lethal without touching scene files.
##
## Rules:
## - Boss waves, level 0 (tutorial sortie) and waves with hand-authored
##   slot_enemy_types are never touched.
## - Configs are duplicated before enrichment, so shared or inherited scene
##   resources are never mutated (replays and other levels are unaffected).
## - Layouts are deterministic per (level, wave): same seed, same mix.

const FormationEnumsScript = preload("res://EnemyManager/Scripts/formation_enums.gd")

const MIN_MIX_COUNT: int = 5
const SEED_LEVEL_STRIDE: int = 100003
const SEED_WAVE_STRIDE: int = 1013
const SEED_SALT: int = 7


## Fast swoopers and bombers apply pressure without aimed fire.
static func _pressure_types() -> Array:
	return [
		FormationEnumsScript.EnemyType.FAST_ENEMY,
		FormationEnumsScript.EnemyType.BOMBER_BUG,
	]


## Shooter pool unlocks tougher types as levels progress.
static func _shooter_pool(level_num: int) -> Array:
	var pool: Array = [
		FormationEnumsScript.EnemyType.MOB1,
		FormationEnumsScript.EnemyType.MOB2,
		FormationEnumsScript.EnemyType.SLOW_SHOOTER,
	]
	if level_num >= 3:
		pool.append(FormationEnumsScript.EnemyType.MOB3)
	if level_num >= 4:
		pool.append(FormationEnumsScript.EnemyType.BOUNCER_ENEMY)
	if level_num >= 6:
		pool.append(FormationEnumsScript.EnemyType.OBLIVION_TANK)
	if level_num >= 8:
		pool.append(FormationEnumsScript.EnemyType.PHASE_PHANTOM)
		pool.append(FormationEnumsScript.EnemyType.ELITE_ENEMY)
	if level_num >= 11:
		pool.append(FormationEnumsScript.EnemyType.SHADOW_SENTINEL)
	return pool


## Share of slots handed to the complementary role (0.18 early, 0.38 by 20).
static func _mix_fraction(level_num: int) -> float:
	return clampf(0.18 + 0.012 * float(level_num), 0.18, 0.38)


static func enrich_waves(waves: Array[WaveConfig], level_num: int) -> Array[WaveConfig]:
	var out: Array[WaveConfig] = []
	if level_num <= 0:
		out.append_array(waves)
		return out
	for wi in range(waves.size()):
		var wave: WaveConfig = waves[wi]
		if wave == null or wave.is_boss_wave() or not wave.slot_enemy_types.is_empty():
			out.append(wave)
			continue
		var count: int = wave.get_enemy_count()
		if count < MIN_MIX_COUNT:
			out.append(wave)
			continue
		var dup: WaveConfig = wave.duplicate() as WaveConfig
		dup.slot_enemy_types = _build_slots(dup, count, level_num, wi)
		out.append(dup)
	return out


static func _build_slots(wave: WaveConfig, count: int, level_num: int, wave_index: int) -> PackedInt32Array:
	var base: int = int(wave.enemy_type)
	var pressure: Array = _pressure_types()
	var shooters: Array = _shooter_pool(level_num)
	var frac: float = _mix_fraction(level_num)
	var n_mix: int = maxi(1, mini(int(round(float(count) * frac)), int(float(count) * 0.5)))
	var rng := RandomNumberGenerator.new()
	rng.seed = level_num * SEED_LEVEL_STRIDE + wave_index * SEED_WAVE_STRIDE + SEED_SALT
	var slots := PackedInt32Array()
	slots.resize(count)
	for i in range(count):
		slots[i] = base
	var base_is_pressure: bool = pressure.has(base)
	for k in range(n_mix):
		# Even spread so mix-ins never clump on one side of the formation.
		var idx: int = clampi(int(float(k + 0.5) * float(count) / float(n_mix)), 0, count - 1)
		var pick: int = base
		if base_is_pressure:
			pick = _seeded_pick(rng, shooters, base)
		else:
			# Alternate divers and bombers; bombers only join from level 4.
			var pool: Array = pressure if level_num >= 4 else [pressure[0]]
			pick = int(pool[k % pool.size()])
			if pick == base:
				pick = int(pool[(k + 1) % pool.size()])
		slots[idx] = pick
	return slots


static func _seeded_pick(rng: RandomNumberGenerator, pool: Array, avoid: int) -> int:
	if pool.is_empty():
		return avoid
	var options: Array = pool.filter(func(t) -> bool: return int(t) != avoid)
	if options.is_empty():
		return int(pool[0])
	return int(options[rng.randi_range(0, options.size() - 1)])


## One-line debug summary, e.g. "MOB1 +2 mixed (FAST_ENEMY, SLOW_SHOOTER)".
static func describe(wave: WaveConfig) -> String:
	if wave == null:
		return "<null>"
	if wave.is_boss_wave():
		return "Boss"
	var base: int = int(wave.enemy_type)
	var mixed: Dictionary = {}
	for s in wave.slot_enemy_types:
		if int(s) != base:
			mixed[int(s)] = int(mixed.get(int(s), 0)) + 1
	if mixed.is_empty():
		return "%s (single)" % FormationEnumsScript.EnemyType.keys()[base]
	var names: Array = []
	for t in mixed.keys():
		names.append("%s x%d" % [FormationEnumsScript.EnemyType.keys()[int(t)], int(mixed[t])])
	return "%s + mixed (%s)" % [FormationEnumsScript.EnemyType.keys()[base], ", ".join(names)]

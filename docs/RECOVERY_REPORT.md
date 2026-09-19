# Shadow Avenger — Project Recovery Report

**Date:** 2026-09-18
**Godot version:** 4.7.1-stable (project config_version=5, features 4.7)
**Recovery snapshot:** `git stash@{0}` — "PRE-RECOVERY SNAPSHOT before project recovery session"

---

## 1. Original Project State

- Project would launch but **two core autoloads (LevelManager, TutorialManager) failed to instantiate**
  every run, cascading `Nonexistent function ... in base 'Nil'` errors across gameplay.
- Root cause: a half-removed tutorial system. `UI/TutorialOverlay.gd` had been moved to
  `addons/fennara/ai/` (never committed there); a Fennara addon update wiped the folder,
  leaving `UI/TutorialOverlay.tscn` pointing at a non-existent script.
- 861 orphaned asset files (from removed ships/enemies/satellites/prototype systems).
- ~219 unconditional `print()` calls, several debug-only paths enabled by default.
- Runtime baseline (measured, not assumed): menus and map at 60fps vsync; combat cost visible
  in process time; no catastrophic per-frame leak detected in any active system.

## 2. Fixes Applied (all verified at runtime via Fennara)

| # | Fix | Files | Verification |
|---|-----|-------|--------------|
| 1 | Restored deleted `UI/TutorialOverlay.gd` (from git history `f662ca2^`), then reconstructed it against the scene contract | `UI/TutorialOverlay.gd` | autoloads instantiate; 7/7 gameplay checks |
| 2 | Repointed `TutorialOverlay.tscn` script reference from missing addon path to `res://UI/` | `UI/TutorialOverlay.tscn` | 0 script errors on launch |
| 3 | Rebuilt stale global class cache via `--headless --import` | `.godot/` caches | `TutorialOverlay` resolves correctly |
| 4 | Fixed double-negative bounce bug (`velocity.y = --1000.0 * restitution` applied positive velocity) | `Resources/coins.gd` | coins bounce downward correctly |
| 5 | Cached laser SFX `preload` (was allocating a resource wrapper per shot) | `Ships/Scripts/Player.gd` | parse + runtime OK |
| 6 | Removed empty `_physics_process` in WaveManager (physics ticks woke for nothing) | `EnemyManager/Scripts/wave_manager.gd` | 0 errors; physics cost stable/improved |
| 7 | ShakeCam idles until first shake (was writing camera transform every frame forever) | `Camera/ShakeCam.gd` | 0 errors |
| 8 | Disabled debug instant-win by default (`enable_dev_win = false`) | `Autoloads/Scripts/Core/GameManager.gd` | parse OK |
| 9 | Archived 861 verified-orphan assets (no references anywhere: tscn/tres/gd/json/cfg/gdshader/uid/import-dest) | `_archive/orphan_assets/` (reversible) | re-import clean; 7/7 flow checks PASS |
| 10 | Fixed corrupted `.gitignore` (merged line broke ignore rules); ignored Fennara run artifacts | `.gitignore` | git status clean |
| 11 | Removed Windows temp files from Fennara addon bin | `addons/fennara/bin/~*.TMP` | — |

## 3. Performance Baseline (Fennara runtime probes, Godot 4.7.1, desktop)

| Segment | Nodes | FPS (vsync) | Process ms/frame | Physics ms/frame | Draw calls |
|---|---|---|---|---|---|
| start_menu | 24 | 60 | ~1.8–23* | 0.04 | ~15 |
| map | 164 | 60 | ~0.9–24* | 0.05 | 16 |
| level_0 combat | ~300 (peaks 429 during heavy waves) | 60 | ~20–75* | 0.7–1.4 | 49–69 |

\* Desktop-run variance is high (compositor, window focus, background load). Cross-scene
comparisons within a session are reliable; absolute desktop numbers are not. The game's
actual target is mobile (renderer=mobile, AdMob) — **mobile profiling on-device is the
remaining unknown** and the likely place the user's perceived lag lives.

## 4. Reusable Probes (kept in repo)

- `.fennara/scripts/runtime/baseline_probe.gd` — per-scene FPS/process/physics/draw/memory/node census.
- `.fennara/scripts/runtime/gameplay_flow_probe.gd` — drives level_0: load → player spawn →
  tutorial overlay present/dismiss → enemy spawn → 8s combat FPS sample → player alive.
- Run them via the Fennara MCP runtime session (any client), or reproduce the env-var flow.

## 5. Remaining Known Issues / Recommendations

1. **Mobile device profiling** — the lag complaint almost certainly originates on-device.
   The same probes can be embedded in a debug build. Watch: texture VRAM (~125–178MB observed
   on desktop, high for mobile), draw calls during boss waves, CPU particles (CPUParticles2D
   in 14 scenes including Player/Boss/Satellites).
2. **219 unconditional prints** remain in the active codebase. They are event-driven (not
   per-frame), so no measurable desktop impact, but they cost string allocations and I/O on
   mobile. Sweep them behind `GameManager.debug_mode`.
3. **AdMob on desktop** logs errors every launch (plugin is Android-only). Harmless, but a
   `feature_tags` guard or `OS.has_feature("android")` check in AdManager would silence it.
4. **`ShadowModeTutorial.tscn` + `shadow_mode_tutorial.gd`** reference `GameManager` and may
   be dead weight of the newer tutorial generation — verify and archive if unused.
5. Consider `git rm -r --cached _archive` if you want the archive locally but not in the repo;
   it is currently tracked so it is fully restorable.
6. 860 archived files sit in `_archive/orphan_assets/`. After a month of confident gameplay,
   delete permanently (git history retains them regardless).

## 6. Validation Summary (Fennara Godot MCP)

- Startup: 0 script errors after fix #1–#3 (was: 2 broken autoloads + Nil cascade).
- Gameplay flow probe: **7/7 checks PASS** across three consecutive runs (pre/post archive, final).
- Baseline probe: three full runs; node counts and costs consistent; no regression from any fix.
- Full project import: clean (0 errors).

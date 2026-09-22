# Shadow Avenger — Project Recovery Report

**Date:** 2026-09-18 (updated 2026-09-20)
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
| 8 | Disabled debug instant-win by default; later merged into the unified Debug Mode toggle (see `docs/DEBUG_MODE.md`) | `Autoloads/Scripts/Core/GameManager.gd` | parse OK; gate probe 17/17 |
| 9 | Archived 861 verified-orphan assets (no references anywhere: tscn/tres/gd/json/cfg/gdshader/uid/import-dest) | `_archive/orphan_assets/` (reversible) | re-import clean; 7/7 flow checks PASS |
| 10 | Fixed corrupted `.gitignore` (merged line broke ignore rules); ignored Fennara run artifacts | `.gitignore` | git status clean |
| 11 | Removed Windows temp files from Fennara addon bin | `addons/fennara/bin/~*.TMP` | — |
| 12 | Removed a dead `TutorialOverlay` instance baked into `Intern_Menu.tscn` (left over from the old "remove tutorial system" commit); its full-screen `Dimmer` was the topmost hit target over Play/Wheelbutton/Back, silently eating clicks | `MainScenes/Intern_Menu.tscn` | click-target dump + screenshot A/B; all-tutorials probe 14/14 |
| 13 | Wired the shadow-mode tutorial chain to the level-5 unlock (the entry point had no caller) and made the wheel lesson survive both completion routes | `Autoloads/Scripts/Managers/LevelManager.gd`, `TutorialManager.gd` | shadow chain probe 21/21 |
| 14 | Level 0 is recorded as cleared on tutorial completion and Start routes on the live campaign request (`TutorialManager.should_route_to_level_zero()`), so a finished campaign can never re-enter the tutorial level; level 0 also locks itself after the clear | `TutorialManager.gd`, `MainScenes/Scripts/start_menu.gd` | routing probe 20/20 |
| 15 | `SceneManager.change_scene()` now **queues** requests that arrive while a loader is still alive (newest wins, duplicates ignored) instead of silently dropping them — a fast double-tap can no longer lose a navigation | `Autoloads/Scripts/Managers/SceneManager.gd` | queue probe 12/12 |
| 16 | Added `DebugFlags` (build-type gate) and routed every debug surface through it; ungated cheats (Level `_input` dev-win, shop `R`-grant) and 22+ debug prints now gated; release ad config fixed (`is_real=true`, trimmed ad-unit id) | `DebugFlags`, `GameManager`, `AdManager`, `upgrade_menu`, … | gate probe (now 17 checks) |
| 17 | Shop tutorial: reward-reveal spotlight (resource bar, live payout callout) before the upgrade prompt; Satellite 1 forced locked while the campaign is unfinished (save migration in `SaveManager._normalize_loaded_state()`) so the real flow is Buy → Select → Equip | `TutorialManager.gd`, `SaveManager.gd`, `upgrade_menu.gd` | flow probe 49/49 |
| 18 | Relocated 35 misplaced textures from `Autoloads/Scripts/Main_Menu/` to `Assets/UI/Main_Menu/` (git mv, 82 ext_resource refs rewritten across 22 files, zero insertions/deletions, uid-identities preserved) | 22 scenes + `Space.tres` + asset folder | no old-path refs; all textures load; key scenes instantiate clean |

## 3. Performance Baseline (Fennara runtime probes, Godot 4.7.1, desktop)

| Segment | Nodes | FPS (vsync) | Process ms/frame | Physics ms/frame | Draw calls |
|---|---|---|---|---|---|
| start_menu | 24 | 60 | ~1.8–23* | 0.04 | ~15 |
| map | 164 | 60 | ~0.9–24* | 0.05 | 16 |
| level_0 combat | ~300 (peaks 429 during heavy waves) | 60 | ~20–75* | 0.7–1.4 | 49–69 |

\* Desktop-run variance is high (compositor, window focus, background load). Cross-scene
comparisons within a session are reliable; absolute desktop numbers are not. The game's
actual target is mobile (renderer=mobile, AdMob) — on-device numbers now exist in
`docs/MOBILE_PROFILING.md` (CPH2637: level_0 physics ~4.25 ms is the top optimization target).

## 4. Reusable Probes (kept in repo)

- `.fennara/scripts/runtime/baseline_probe.gd` — per-scene FPS/process/physics/draw/memory/node census.
- `.fennara/scripts/runtime/gameplay_flow_probe.gd` — drives level_0: load → player spawn →
  tutorial overlay present/dismiss → enemy spawn → 8s combat FPS sample → player alive.
- `.fennara/scripts/runtime/tutorial_flow_probe.gd` — full shop/spotlight tutorial flow (49 checks).
- `.fennara/scripts/runtime/level0_route_probe.gd` — level-0 one-time routing (20 checks).
- `.fennara/scripts/runtime/scene_queue_probe.gd` — transition queue semantics (12 checks).
- `.fennara/scripts/runtime/debug_gate_probe.gd` — release-simulation gate suite (17 checks).
- `.fennara/scripts/runtime/shadow_tutorial_probe.gd` — level-5 → shadow chain (21 checks).
- Run them via the Fennara MCP runtime session (any client), or reproduce the env-var flow.

## 5. Remaining Known Issues / Recommendations

1. **Mobile physics cost** — level_0 physics is ~4.25 ms on-device vs ~1.44 ms desktop.
   Reduce active rigid bodies / collision pairs during heavy waves (pooling exists; consider
   wider collision layers or area-based culling). See `docs/MOBILE_PROFILING.md`.
2. **VRAM 284 MB in level_0 on-device** — texture compression/import settings review is the
   next lever (ETC2/ASTC-appropriate sizes for mobile).
3. **Start menu process time 33 ms on-device** — worst per-frame CPU in the menu flow;
   likely the animated menu elements. Worth a targeted look before release.
4. **AdMob on desktop** logs errors every launch (plugin is Android-only). Harmless, but a
   `feature_tags` guard or `OS.has_feature("android")` check in AdManager would silence it.
5. **Scene-change UX** — every navigation pays the loader's ~1 s minimum on-screen time even
   when the scene is already in memory; trimming that would make navigation feel instant.
6. Consider `git rm -r --cached _archive` if you want the archive locally but not in the repo;
   it is currently tracked so it is fully restorable.
7. 860 archived files sit in `_archive/orphan_assets/`. After a month of confident gameplay,
   delete permanently (git history retains them regardless).

## 6. Validation Summary (Fennara Godot MCP)

- Startup: 0 script errors after fix #1–#3 (was: 2 broken autoloads + Nil cascade).
- Gameplay flow probe: **7/7 checks PASS** across three consecutive runs (pre/post archive, final).
- Baseline probe: three full runs; node counts and costs consistent; no regression from any fix.
- Full project import: clean (0 errors).
- Post-recovery regression runs (desktop, muted): tutorial flow 49/49, level-0 routing 20/20,
  scene queue 12/12, debug gate 17/17, shadow chain 21/21, all-tutorials 14/14.

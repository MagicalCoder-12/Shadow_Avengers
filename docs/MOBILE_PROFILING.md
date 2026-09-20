# Mobile Profiling — Shadow Avenger

## Setup (one-time, done)

- **Build type is the gate.** `DebugFlags.enabled` is `OS.is_debug_build()` and nothing else:
  cheats, dev-win, debug logging and the profiler are impossible in a release build, even if the
  editor toggles (`debug_mode`, `allow_god_mode`, `enable_dev_win`) were left switched on.
  `debug_mode` is a property whose setter re-checks the gate, so no runtime assignment can
  re-enable debug output in a release binary either.
- **Profiling additionally needs an opt-in**, so a plain debug build stays clean:
  the `profiler` custom feature (`export_presets.cfg` preset.1 "Android Profiler") or
  `SHADOW_PROFILER_FORCE=1` on desktop. Both are ANDed with the debug-build check.
  Export the "Android Profiler" preset as a **Debug** export — profiling a Release export is
  deliberately not possible any more.
- Production preset "Android" (preset.0) exports an AAB with no overlay and no debug output.
- Ads: `addons/AdmobPlugin/export.cfg` sets `is_real=true`, so debug and release builds both
  carry the production AdMob app id (a test app id in a shipping build is a policy problem).
  For ad testing, set `is_real=false` in that file locally — it is gitignored on purpose.
- `addons/AdmobPlugin/export.cfg` supplies the AdMob APPLICATION_ID at export time — without it
  the Google Ads SDK init-provider hard-crashes the app on launch.

## Workflow

See `.github/skills/device-playtest/SKILL.md` for the full verified procedure
(build → TCP-push install → launch via `GodotAppLauncher` → drive taps → pull reports).

Overlay controls (physical px on the CPH2637, 1080×2400):
- PROF toggle: tap (117, 57). Opening the panel auto-dumps the scene UI and logs all button rects.
- Panel buttons (design px, ×0.75 for physical): BASELINE ≈ (139,568), FLOW ≈ (406,568),
  UI DUMP ≈ (292,887), EXIT ≈ (673,887).
- Reports: `user://profiler_reports/*.json` → pull with
  `adb shell run-as com.Aj.ShadowAvenger cat files/profiler_reports/<file>.json`.

## First on-device results (CPH2637, 2026-09-18, Godot 4.7.1 debug build)

Baseline probe (segments, ~10s each):

| Scene | FPS avg | FPS min | process | physics | draws | nodes | VRAM |
|---|---|---|---|---|---|---|---|
| start_menu | 58.0 | 57 | 33.0 ms | 1.35 ms | 29 | 57 | 166 MB |
| map | 58.8 | **7** | 20.5 ms | 0.45 ms | 20 | 197 | 214 MB |
| level_0 | 59.4 | 52 | 20.9 ms | **4.25 ms** | 47 | 362 | 284 MB |

Flow probe (gameplay loop): 5/6 checks passed; combat fps 58.5 avg / 57 min,
341 nodes peak.

Known-good notes:
- `tutorial_overlay_present: FAIL` is a probe-timing artifact (dismiss check passes);
  the overlay works (validated on desktop 7/7).
- The map's `fps_min=7` is a single-frame hiccup during scene load, not sustained jank.

### Findings

1. **Physics cost on-device is ~3× desktop** (4.25 ms vs 1.44 ms desktop at level_0).
   Primary optimization target for mobile: reduce active rigid bodies / collision pairs
   during heavy waves (bullet pooling already exists; consider wider collision layers or
   area-based culling).
2. **VRAM 284 MB in level_0** is high for a mobile title; texture compression/import
   settings review is the next lever (mobile builds should use ETC2/ASTC-appropriate sizes).
3. **Start menu process time 33 ms** is the worst per-frame CPU in the menu flow — likely
   the animated menu elements; worth a targeted look before release.
4. **No crashes, ANRs, or script errors** observed during full gameplay on-device.

## Manual live-stats usage

With the panel open, the overlay shows live scene name, fps (+ cap cycling 60→120→off),
process/physics ms, draw calls/objects, VRAM/static memory, and total node count, updating
4×/second. Use FPS CAP to separate CPU-bound from vsync-bound measurements.

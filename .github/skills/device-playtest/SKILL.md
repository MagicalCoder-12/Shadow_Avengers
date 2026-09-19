---
name: device-playtest
description: Build, deploy, launch, and play-test Shadow Avenger on the user's Android phone over ADB — including on-device profiling via the MobileProfiler overlay, injected-input playthroughs, and logcat bug sweeps. Use whenever the user wants the game pushed to their phone, tested on real hardware, or profiled on-device.
---

# Device Play-Test Skill (Shadow Avenger)

## Environment facts (verified 2026-09-18)

- Godot: `D:/game_setups/Godot_versions/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64.exe`
- ADB: `C:\Users\ajith\AppData\Local\Android\Sdk\platform-tools\adb.exe` (on PATH)
- Phone: Oppo/OnePlus `CPH2637` over **wireless ADB** (`adb connect 192.168.1.12:34803` if disconnected — the port changes per pairing session, ask or check `adb devices`)
- JDK 17: `D:\java_17`; Android SDK: `%LOCALAPPDATA%\Android\Sdk`; debug keystore at `%APPDATA%\Godot\keystores\debug.keystore`
- Package: `com.Aj.ShadowAvenger` (lowercase j). Launcher activity: `com.godot.game.GodotAppLauncher` (exported). `com.godot.game.GodotApp` is NOT exported — `am start` on it fails with Permission Denial.
- A stale **Unity** build `com.AJ.ShadowAvenger` (capital AJ, UnityPlayerActivity) also lives on the phone — never uninstall or launch it.
- Export preset **"Android Profiler"** (preset.1) → `Apks/Shadow Avenger Profiler.apk`, includes the `profiler` custom feature which activates the `MobileProfiler` overlay autoload
- Production preset "Android" (preset.0) → AAB, must never carry the profiler feature

## Standard workflow

1. **Build**: `"GODOT" --headless --path . --export-debug "Android Profiler" "Apks/Shadow Avenger Profiler.apk"` (2–5 min gradle; check `Apks/` mtime). Verify the exe path carefully — `Godot_v4.7.1-stable_win64.exe` is a *directory*; the binary is one level deeper.
2. **Install** (direct `adb install -r` stalls/times out over wireless ADB for the 337MB APK):
   ```bash
   export ANDROID_SERIAL="192.168.1.12:34803" MSYS_NO_PATHCONV=1
   adb push "Apks/Shadow Avenger Profiler.apk" /data/local/tmp/sa_profiler.apk
   adb shell pm install -r /data/local/tmp/sa_profiler.apk
   ```
   `MSYS_NO_PATHCONV=1` is mandatory in Git Bash or `/data/local/tmp` gets rewritten to `C:/Program Files/Git/data/...`.
3. **Launch cleanly**: `adb shell input keyevent KEYCODE_WAKEUP; adb logcat -c; adb shell am start -n com.Aj.ShadowAvenger/com.godot.game.GodotAppLauncher; sleep 12; adb shell pidof com.Aj.ShadowAvenger`
   - If `pidof` is empty, check `adb logcat -d -b crash` and the AndroidRuntime buffer. Historical root cause of launch death: empty AdMob `APPLICATION_ID` in the merged manifest (Google Ads SDK init-provider hard-crash) — fixed via `addons/AdmobPlugin/export.cfg`; the export log must say `Loading export config from file!`.
4. **Watch logs**: `adb logcat -d -s Godot` (game prints, `[PROFILER]` lines) and `adb logcat -d -s AndroidRuntime` (crashes), plus `ANR in` greps in full logcat.
5. **Drive the game**: touch injection via `adb shell input tap <x> <y>` and swipes via `adb shell input swipe <x1> <y1> <x2> <y2> <ms>`. Coordinate space = the phone's physical portrait screen (`adb shell wm size`), NOT the game's 1440×3200 virtual viewport. There is no observable cursor; verify UI state via logcat prints or screenshots (`adb exec-out screencap -p > shot.png`), never by assuming.
6. **Run on-device probes**: tap PROF at physical (117,57) — verified reliable. Opening the panel auto-runs a UI dump AND logs every button's post-layout rect (`[PROFILER] btn <NAME> at (x1,y1)-(x2,y2)` in design px; multiply by 0.75 for physical taps). On this build: BASELINE center ≈ (139,568), FLOW ≈ (406,568), UI DUMP ≈ (292,887), EXIT ≈ (673,887) physical. Probes print per-check lines and a `report:` path to logcat under the godot tag. Volume-key events do NOT reach the app (system consumes them).
7. **Pull reports**: `user://` maps to the app-private dir — `adb shell run-as com.Aj.ShadowAvenger cat files/profiler_reports/<name>.json > local.json` (debug build only). A probe takes 40–90s; the report file appearing is the completion signal.
8. **Cleanup**: `adb shell am force-stop com.Aj.ShadowAvenger`

## Desktop-side Fennara probes (no device)

`.fennara/scripts/runtime/baseline_probe.gd` and `gameplay_flow_probe.gd` run through the
Fennara runtime session (env `FENNARA_RT_SPEC` + command JSON in `.fennara/state/rt-cmds/`).
One probe per app launch — a probe's `close_scene()` quits the app.

## Gotchas learned the hard way

- Godot apps may not start via `adb shell monkey`; use `am start -n` with the explicit activity.
- `mobile_profiler.gd` supports `SHADOW_PROFILER_FORCE=1` env to force-show the overlay on desktop for E2E tests.
- DirAccess on Windows caches directory listings; re-open the dir before re-scanning for new files (this caused a false "no report" in the E2E driver).
- `input tap` while a Godot touch→mouse emulation is active works, but wait ≥300ms between taps; UI buttons in the game are large but targets shift with the stretch/expand aspect mode.
- The phone status bar overlays the top of the screen — taps near y<100 may miss game UI; the PROF button at (117,57) is the exception (verified).
- Inline `CompressedTexture2D.load_path` sub_resources embed `.godot/imported` hashes that change on re-import — they must use stable ext_resource refs instead (7 scenes fixed 2026-09-18).
- UI dump font column reads theme overrides only; labels using `label_settings` show `font=-1` — check the .tscn before assuming small text.

#!/usr/bin/env bash
# Shadow Avenger device play-test helper (run from project root)
set -uo pipefail

GODOT="D:/game_setups/Godot_versions/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64.exe"
PKG="com.Aj.ShadowAvenger"
ACTIVITY="com.Aj.ShadowAvenger/org.godotengine.godot.Godot"
APK="Apks/Shadow Avenger Profiler.apk"
REPORTS="/sdcard/Android/data/com.Aj.ShadowAvenger/files/profiler_reports"

cmd="${1:-help}"
case "$cmd" in
  build)
    "$GODOT" --headless --path . --export-debug "Android Profiler" "$APK" 2>&1 | tail -3
    ls -la "$APK" ;;
  install)
    adb install -r "$APK" ;;
  launch)
    adb logcat -c
    adb shell am start -n "$ACTIVITY"
    sleep 8
    pid=$(adb shell pidof "$PKG" | tr -d '\r')
    if [ -n "$pid" ]; then echo "RUNNING pid=$pid"; else echo "NOT RUNNING — check: adb logcat -d -s Godot AndroidRuntime"; fi ;;
  logs)
    adb logcat -d -s Godot | tail -"${2:-50}" ;;
  crashlogs)
    adb logcat -d -s AndroidRuntime | tail -"${2:-60}" ;;
  anr)
    adb logcat -d | grep -iE "ANR in|Application is not responding" | tail -5 ;;
  tap)
    adb shell input tap "$2" "$3" ;;
  swipe)
    adb shell input swipe "$2" "$3" "$4" "$5" "${6:-300}" ;;
  shot)
    adb exec-out screencap -p > "${2:-shot.png}"
    echo "saved ${2:-shot.png}" ;;
  pullreports)
    mkdir -p .fennara/state/device_reports
    adb pull "$REPORTS" .fennara/state/device_reports/ 2>&1 | tail -2 ;;
  stop)
    adb shell am force-stop "$PKG" ;;
  size)
    adb shell wm size; adb shell wm density ;;
  *)
    echo "usage: .tools/dev_play.sh {build|install|launch|logs|crashlogs|anr|tap x y|swipe x1 y1 x2 y2 [ms]|shot [out.png]|pullreports|stop|size}" ;;
esac

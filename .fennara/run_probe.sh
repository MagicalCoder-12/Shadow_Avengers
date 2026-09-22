#!/usr/bin/env bash
# usage: run_probe.sh <res_probe_path> <done_marker> <logname> [timeout_s]
PROBE="$1"; MARKER="$2"; LOGNAME="${3:-probe}"; TMO="${4:-300}"
GODOT="D:/game_setups/Godot_versions/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64.exe"
P="D:/programs/Godot/shadow-avenger-main"
cd "$P" || exit 1
taskkill //IM Godot_v4.7.1-stable_win64.exe //F >/dev/null 2>&1
sleep 1
rm -f .fennara/state/rt-cmds/*.json
LOG=".fennara/state/rt_${LOGNAME}.log"
FENNARA_RT_SPEC="$P/.fennara/state/rt-spec-bugfix.json" nohup "$GODOT" --path "$P" --audio-driver Dummy > "$LOG" 2>&1 &
sleep 14
BASE="$(basename "$PROBE" .gd)"
printf '{"action":"run_runtime_script","script_run_id":"%s","session_id":"bugfix1","script_path":"res://%s","status_path":"%s/.fennara/state/rt-artifacts/%s_status.json"}\n' "$BASE" "$PROBE" "$P" "$BASE" > ".fennara/state/rt-cmds/cmd_${BASE}.json"
END=$((SECONDS+TMO))
while [ $SECONDS -lt $END ]; do
  if tr -d '\0' < "$LOG" | grep -q "$MARKER"; then break; fi
  sleep 5
done
tr -d '\0' < "$LOG" | grep -E "CHECK |_DONE|SCRIPT ERROR|Parse Error" | head -70

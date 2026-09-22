# Running Shadow Avenger for the Preview tab

This is a Godot 4.7 desktop game -- there is no web dev server or package.json.
The Preview tab shows a **live view of the running game**: the Fennara harness
saves screenshots of the game window while a desktop session is up, and a tiny
local HTTP server (`.freebuff/preview_server.py`, stdlib only, no dependencies)
serves the newest frame with auto-refresh every 2 s.

## Reproduce the artifacts

Nothing to reproduce -- no env files, no lockfile, no build step. The only
inputs are the capture PNGs under `.fennara/state/captures/`, which a running
game session produces on its own.

## Run the server

```
cd D:/programs/Godot/shadow-avenger-main
python .freebuff/preview_server.py 8765
```

- Port: 8765 (checked free). Serve on 127.0.0.1 only.
- Detached (Windows PowerShell), stdout and stderr to DIFFERENT files:

```
powershell -NoProfile -Command "(Start-Process -FilePath 'python.exe' -ArgumentList '.freebuff/preview_server.py','8765' -WorkingDirectory 'D:/programs/Godot/shadow-avenger-main' -RedirectStandardOutput 'D:/programs/Godot/shadow-avenger-main/.freebuff/preview-7d628caf-96f2-4744-b8c5-757daff745c7.log' -RedirectStandardError 'D:/programs/Godot/shadow-avenger-main/.freebuff/preview-7d628caf-96f2-4744-b8c5-757daff745c7.log.err' -WindowStyle Hidden -PassThru).Id"
```

- Health check: `curl -s http://127.0.0.1:8765/latest` should return JSON.
- To watch a live session: launch the game (muted, with the Fennara spec env
  as described in `.fennara/state/rt-spec-*.json` examples). New captures
  appear automatically in the Preview tab every 2 s.

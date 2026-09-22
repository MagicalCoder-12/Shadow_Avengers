# Debug Mode — the single developer toggle

**One toggle controls everything developer-only: `GameManager.debug_mode`.**

God Mode, dev-win, the resource-grant shortcut, level-select overrides and all
verbose debug logging ride this one switch. There is no separate God Mode
switch any more — the old `allow_god_mode` / `enable_dev_win` editor toggles
were removed when the merge happened.

## How the gate works

`debug_mode` is a pass-through of the **build-type gate** (`DebugFlags.enabled`,
which is exactly `OS.is_debug_build()`):

```gdscript
func set_debug_mode(value: bool) -> void:
    debug_mode = value and DebugFlags.enabled
    if not debug_mode and god_mode_enabled:
        set_god_mode_enabled(false, "debug_mode_off")
```

Consequences:

- A **release export** reports `is_debug_build() == false`, so Debug Mode can
  never be enabled there — not by a save file, not by a serialized scene, not
  by runtime code. Everything behind it is equally unreachable.
- **Switching Debug Mode off disarms god mode instantly** (and deactivates
  shadow mode if god mode had enabled it).
- A debug build starts with `debug_mode = false`; turn it on explicitly when
  developing (Inspector on the GameManager autoload, or code).

## What is behind Debug Mode

| Feature | Entry point | Guard |
|---|---|---|
| God Mode (7-tap on the Pause label; 10× damage, 99,999 resources, HUD shadow button) | `pause_menu.gd` | `can_use_god_mode()` → `debug_mode` |
| Dev-win (instant level completion, `W` / `dev_win` action) | `GameManager.dev_win()`, `Level.gd` | `debug_mode` |
| Shop shortcuts (`1-8` select, `U` upgrade, `A` ascend, `R` grant 1M crystals) | `upgrade_menu.gd` `_input` | `DebugFlags.enabled` |
| Level-select debug override (`debug_next_level`) | `Level.gd` | `DebugFlags.enabled` **and** `debug_mode` |
| Verbose debug logging (AdManager, Enemy, HUD, SaveManager, …) | `gm.debug_mode` checks | setter-gated |
| Profiler overlay + Fennara probes | `MobileProfiler` autoload | `DebugFlags.profiling` (see below) |

## Profiling opt-in (read-only, still debug-build-only)

`DebugFlags.profiling` needs `DebugFlags.enabled` **and** one of:

- the `profiler` custom feature (the "Android Profiler" export preset), or
- `SHADOW_PROFILER_FORCE=1` when running from the editor/desktop.

Instrumentation can never grant cheats, and profiling a Release export is
deliberately impossible.

## Verification

The gate suite (`.fennara/scripts/runtime/debug_gate_probe.gd`, 21 checks)
runs in a live desktop session and asserts:

- the toggles legacy setup had (`allow_god_mode`, `enable_dev_win`) are gone;
- with the gate simulating a release build while `debug_mode` is forced on:
  god mode cannot activate, deals no bonus damage, the `R`-grant and the
  `W` dev-win are inert, and the profiler overlay frees itself;
- with the gate on (debug build): god mode activates and deactivates cleanly.

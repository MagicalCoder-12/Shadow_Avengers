extends Node
## Single source of truth for every debug-only subsystem: the profiler overlay,
## runtime probes, god mode, dev-win / easy-win helpers and verbose debug logging.
##
## A debug export reports OS.is_debug_build() == true; a release export reports
## false. Every gate below therefore goes dark in a shipping build even if a
## toggle in the editor (GameManager.debug_mode, allow_god_mode, enable_dev_win)
## was left switched on.
##
## Opting an export in explicitly:
##   * custom feature "debug_tools" enables the full toolkit (cheats included),
##   * custom feature "profiler" enables instrumentation only (overlay/probes),
##     which is what the "Android Profiler" export preset sets.
## The production preset sets neither, so its build is clean.
##
## Usage:
##     if not DebugFlags.enabled:
##         return

## Full toolkit: profiler overlay, probes, god mode, dev-win, resource grants
## and verbose debug logging. True only in a debug build (or an explicit opt-in).
var enabled: bool = false

## Read-only instrumentation (profiler overlay + probes). Never grants cheats,
## so a profiling export of a release build still measures but cannot cheat.
var profiling: bool = false


func _ready() -> void:
	enabled = OS.is_debug_build() or OS.has_feature("debug_tools") \
			or OS.get_environment("SHADOW_DEBUG") == "1"
	profiling = enabled or OS.has_feature("profiler")
	if not enabled:
		set_process(false)
		set_physics_process(false)
	# Disabling the node also stops the profiler overlay from being built in a
	# release build, since it checks `profiling` in its own _ready().


## Guard helper for call sites that want a single line and a breadcrumb.
func block(what: String) -> bool:
	if enabled:
		return false
	push_warning("Debug-only feature blocked in this build: %s" % what)
	return true

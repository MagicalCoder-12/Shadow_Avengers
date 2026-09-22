extends Node
## Single source of truth for every debug-only subsystem: the profiler overlay,
## runtime probes, god mode, dev-win / easy-win helpers and verbose debug logging.
##
## The gate is the BUILD TYPE and nothing else. A debug export reports
## OS.is_debug_build() == true, a release export reports false, so a shipping
## build carries no cheats, no profiler and no debug logging even when a toggle in
## the editor's single Debug Mode toggle (GameManager.debug_mode) was left
## switched on, and even when a stray SHADOW_DEBUG / FENNARA_RT_SPEC environment
## variable happens to exist on the machine that exported it.
##
## Profiling (the on-device overlay + probe scripts) additionally needs an
## explicit opt-in so a plain debug build does not draw a button over the game:
##   * custom feature "profiler" (the "Android Profiler" export preset), or
##   * SHADOW_PROFILER_FORCE=1 when running from the editor.
## Both are ANDed with the debug build check, so neither can reach players.
##
## Usage:
##     if not DebugFlags.enabled:
##         return
##     DebugFlags.debug_print("breadcrumb")

## Full toolkit: profiler overlay, probes, god mode, dev-win, resource grants.
## True only inside a debug build.
var enabled: bool = false

## Read-only instrumentation (profiler overlay + probe scripts). Never grants
## cheats, and is impossible outside a debug build.
var profiling: bool = false


func _ready() -> void:
	enabled = OS.is_debug_build()
	profiling = enabled and (
		OS.has_feature("profiler") or OS.get_environment("SHADOW_PROFILER_FORCE") == "1"
	)
	if not enabled:
		set_process(false)
		set_physics_process(false)


## Prints only from a debug build. Every debug breadcrumb in the game routes
## through here, so a release log stays clean.
func debug_print(message: Variant = "") -> void:
	if enabled:
		print(message)


## Guard helper for call sites that want a single line and a breadcrumb.
func block(what: String) -> bool:
	if enabled:
		return false
	push_warning("Debug-only feature blocked in this build: %s" % what)
	return true

class_name MusicLicenceOverride
extends RefCounted
## The one, named, OFF-BY-DEFAULT way to hear a track whose rights are not yet
## recorded.
##
## ## Why this file exists
##
## `MusicManifest` fails closed: a track plays only when `commercialUse` is
## `"verified"` AND `licenseEvidence` names real evidence. On 2026-09-19 two real
## tracks were delivered by Anny with **no licence evidence supplied**, so their
## rows honestly read `commercialUse: "pending"` / `licenseEvidence: "OWNER TO
## CONFIRM"` -- and the gate therefore refuses to play them. That is the gate
## working, not a bug.
##
## There were only three honest ways out of that, and two of them are forbidden:
##
##   1. Write `"verified"` and invent Suno paperwork.  -- FRAUD. Never.
##   2. Loosen the gate so "pending" plays.            -- Silently ships music we
##                                                        may not own. Never.
##   3. Leave the gate exactly as it is and add a SEPARATE, deliberately-armed
##      preview switch that the owner has to turn on by hand, that is off in
##      every build, and that announces itself loudly when it is on.
##
## This is (3). The gate in `music_manifest.gd` is untouched and still fails
## closed; nothing here can make `is_playable()` return true. What it can do is
## let `AudioDirector` play a track the gate refused **for a licence reason
## only** -- and only after a human deliberately armed it on this one machine.
##
## ## How to arm it (both are per-machine and neither is committed)
##
## Command line, for a single run -- this is what the audio verification uses:
##
##     Godot --headless --path game --script res://tests/smoke_audio_shipping.gd \
##         -- --allow-unverified-music
##
## Or, to keep the preview on while playing on a device, create the marker file:
##
##     user://OWNER_ACKNOWLEDGED_UNVERIFIED_MUSIC
##
## On macOS that is
## `~/Library/Application Support/Godot/app_userdata/Little Days/`; on iPad it is
## the app's Documents directory. Deleting the file disarms it. Nothing in
## `project.godot`, `export_presets.cfg` or any committed file turns it on, so a
## TestFlight or App Store build is silent until the paperwork is real.
##
## ## What arming it does NOT do
##
## It does not touch `commercialUse`. It does not make the track shippable. It
## does not hide itself -- `AudioDirector` pushes a louder warning than an ordinary
## refusal gets and emits `unverified_music_allowed`, and only a test ever silences
## the former (`warn_on_licence_refusal`); the signal always fires. The
## manifest row stays honest, so the day the owner produces evidence the change
## is `"pending"` -> `"verified"` plus the evidence string, and this override
## becomes dead code that can be deleted.
##
## Pure logic and local file I/O. No `Node`, no network.

## The exact command-line switch. Must be passed after `--` so Godot forwards it
## as a user argument.
const CLI_FLAG: String = "--allow-unverified-music"

## The marker file. Its NAME is the documentation: anyone who finds it in a
## user-data directory can tell what it claims without reading this file.
const MARKER_PATH: String = "user://OWNER_ACKNOWLEDGED_UNVERIFIED_MUSIC"

## What `AudioDirector` prints, once, when the override is live. Deliberately
## unmissable: a preview that looks like a shipping build is how unlicensed audio
## reaches a store.
const BANNER: String = (
	"MUSIC LICENCE OVERRIDE IS ARMED. Track '%s' is playing even though its "
	+ "manifest row says commercialUse=\"pending\" / licenseEvidence=\"OWNER TO "
	+ "CONFIRM\". This is an owner-acknowledged local PREVIEW and must never be "
	+ "shipped. Disarm it by removing %s or dropping the %s argument. See "
	+ "docs/ORIGINAL_MUSIC_INTEGRATION.md."
)


## True only when a human armed the override on this machine.
##
## Checked in this order, cheapest first. A `false` here is the default on every
## machine, in every export, and in the test suite.
static func is_armed() -> bool:
	return has_cli_flag() or has_marker_file()


## The `-- --allow-unverified-music` form. USER ARGS ONLY -- everything after the
## `--` separator -- and that restriction is the security boundary, not a detail.
##
## This used to fall back to `OS.get_cmdline_args()` as well, "so it works with a
## stripped export". That was a hole. Godot writes an Android preset's
## `command_line/extra_args` into `assets/_cl_` inside the APK and merges it into
## `get_cmdline_args()` at startup -- and `export_presets.cfg` is a COMMITTED
## file. One line there would have armed unverified music in a DISTRIBUTED build,
## with nothing but a device-side `push_warning` to say so. The shipped APK's
## `_cl_` was checked and holds only harmless engine args, so nothing leaked; the
## route simply should not exist.
##
## Nothing is lost: the documented form is `-- --allow-unverified-music`, which
## is exactly a user arg. A developer previewing on this machine is unaffected.
static func has_cli_flag() -> bool:
	for argument: String in OS.get_cmdline_user_args():
		if argument.strip_edges() == CLI_FLAG:
			return true
	return false


static func has_marker_file() -> bool:
	return FileAccess.file_exists(MARKER_PATH)


## Writes the marker. Only ever called by a human running the documented command;
## no gameplay path calls this. Returns false when the file could not be written,
## which is not an error worth stopping anything for.
static func arm_marker_file(note: String = "") -> bool:
	var file: FileAccess = FileAccess.open(MARKER_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_line("Owner-acknowledged preview of music whose licence is NOT yet verified.")
	file.store_line("Delete this file to silence unverified tracks again.")
	if not note.strip_edges().is_empty():
		file.store_line(note.strip_edges())
	file.close()
	return true


## Removes the marker, disarming the override. Safe when it was never there.
static func disarm_marker_file() -> bool:
	if not has_marker_file():
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(MARKER_PATH)) == OK


## How the override's state should be described in a diagnostics panel or a log.
static func describe() -> String:
	if has_cli_flag():
		return "armed by %s on the command line" % CLI_FLAG
	if has_marker_file():
		return "armed by the marker file %s" % MARKER_PATH
	return "disarmed (unverified music is silent, which is the shipping default)"

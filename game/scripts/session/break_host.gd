extends Node

## Puts the break card (`break_card.gd`) over a running house, holds the room
## while it is up, and gives the room back exactly as it was.
##
## Both house directors (`house_level_director.gd`, `house_freeplay_director.gd`)
## own one of these. THEY decide when it is safe -- after a task is acknowledged
## and before the next starts, after the summary, or when Aliz has been idle for
## a moment -- and call `show()`. This file knows how to hold a house, which is
## `house_hud.gd`'s pause pattern (taps off, character disabled, affordances
## down) written once more in one place rather than a third time in each
## director:
##
##   show()          record taps / character / affordances / narration
##                   -> take them away -> duck the music -> open the card
##   Keep Playing    close -> put every one of them back to what was recorded
##                   -> `PlaySession.keep_playing()` (3-minute snooze)
##   Home            `SaveService.save_profile()` -> `PlaySession.mark_break_taken()`
##                   -> `HouseWorld.leave_to_home()` (or the title scene)
##
## The music is ducked by lowering the `Audio` trim a little and restoring it,
## because the music binder re-decides `set_ducked()` every frame from the
## speech services and would undo a duck asked for any other way. If the trim
## changed under us while the card was up (it cannot -- the Grown-ups panel is
## behind the same card -- but if), the recorded value is left alone.
##
## Nothing here ends the app, drops what Aliz is holding or discards a star.
## `step()` also keeps the clock honest: it is held while the HUD says the world
## is paused (the pause card, the Grown-ups panel) and while a room transition
## is in flight.

const PlaySessionScript := preload("res://scripts/session/play_session.gd")
const BreakCardScript := preload("res://scripts/ui/break_card.gd")

const HOME_SCENE_PATH: String = "res://scenes/main/main.tscn"
## How far the music comes down under the card, in dB. Softly, not off.
const BREAK_DUCK_DB: float = 8.0
const HOLD_MENU: String = "menu"
const HOLD_LOADING: String = "loading"

signal break_shown()
signal kept_playing()
signal went_home()

var _world: Node = null
var _hud: Control = null
var _nav: Node = null
var _character: Node = null
var _transition: Node = null
var _card: Control = null
var _session: Node = null
var _bound: bool = false
var _open: bool = false
var _leaving: bool = false

## What was there before the card, put back on Keep Playing.
var _prior_taps: Variant = null
var _prior_character_disabled: bool = false
var _prior_affordance_enabled: Variant = null
var _prior_narration_covered: Variant = null
var _prior_music_db: Variant = null
var _ducked_music_db: float = 0.0
## Injectable services. Null means "look up by name".
var _save: Object = null
var _audio: Object = null
var _services_injected: bool = false


## -- Wiring ------------------------------------------------------------------------

func bind(world: Node, hud: Control) -> void:
	_world = world
	_hud = hud
	if _world != null:
		_nav = _world.get_node_or_null("NavigationController")
		if _world.has_method("get_character"):
			_character = _world.call("get_character")
		if _world.has_method("get_transition_controller"):
			_transition = _world.call("get_transition_controller")
	_bound = true
	var session: Node = get_session()
	if session != null and _world != null:
		session.call("attach", _world)


## The one play-session clock, made on first use. Null without a tree.
func get_session() -> Node:
	if _session != null and is_instance_valid(_session):
		return _session
	_session = PlaySessionScript.get_or_create(Engine.get_main_loop() as SceneTree)
	return _session


## A test hands in the services it wants watched.
func set_services(save: Object, audio: Object) -> void:
	_save = save
	_audio = audio
	_services_injected = true


func get_card() -> Control:
	return _card


func is_open() -> bool:
	return _open and _card != null and is_instance_valid(_card) and _card.visible


## True once the clock has passed the threshold and nobody has answered yet.
func is_due() -> bool:
	if _open:
		return false
	var session: Node = get_session()
	return session != null and bool(session.call("is_due"))


## Per-frame bookkeeping for the clock: the world's own pauses hold it.
func step(_delta: float) -> void:
	var session: Node = get_session()
	if session == null:
		return
	var menu_open: bool = false
	if _hud != null and is_instance_valid(_hud):
		if _hud.has_method("is_world_paused") and bool(_hud.call("is_world_paused")):
			menu_open = true
		if _hud.has_method("is_grown_ups_open") and bool(_hud.call("is_grown_ups_open")):
			menu_open = true
	session.call("set_held", HOLD_MENU, menu_open)
	var loading: bool = _transition != null and is_instance_valid(_transition) \
			and _transition.has_method("is_transitioning") and bool(_transition.call("is_transitioning"))
	session.call("set_held", HOLD_LOADING, loading)


## -- Show ----------------------------------------------------------------------------

## Opens the card over the room. Returns false when it is already up or there
## is nowhere to mount it.
func show() -> bool:
	if _open or _leaving:
		return false
	var card: Control = _ensure_card()
	if card == null:
		return false
	_open = true
	_hold_world()
	_duck_music(true)
	# On top of everything in the layer, including the HUD's own cards.
	var host: Node = card.get_parent()
	if host != null:
		host.move_child(card, host.get_child_count() - 1)
	card.call("open")
	break_shown.emit()
	return true


func _ensure_card() -> Control:
	if _card != null and is_instance_valid(_card):
		return _card
	var card: Control = BreakCardScript.new()
	card.call("build")
	card.connect("keep_playing_pressed", _on_keep_playing)
	card.connect("home_pressed", _on_home)
	var host: Node = null
	if _world != null and is_instance_valid(_world):
		host = _world.get_node_or_null("UI")
	if host == null:
		host = self
	host.add_child(card)
	_card = card
	return card


## -- Keep Playing ----------------------------------------------------------------------

func _on_keep_playing() -> void:
	if not _open:
		return
	_open = false
	if _card != null and is_instance_valid(_card) and _card.visible:
		_card.call("close")
	_duck_music(false)
	_release_world()
	var session: Node = get_session()
	if session != null:
		session.call("keep_playing")
	kept_playing.emit()


## Keep Playing, as an API (a test, a harness).
func keep_playing() -> void:
	_on_keep_playing()


## -- Home ------------------------------------------------------------------------------

func _on_home() -> void:
	if _leaving:
		return
	_leaving = true
	var save: Object = _save if _services_injected else _autoload("SaveService")
	if save != null and is_instance_valid(save) and save.has_method("save_profile"):
		save.call("save_profile")
	var session: Node = get_session()
	if session != null:
		session.call("mark_break_taken")
	went_home.emit()
	if _world != null and is_instance_valid(_world) and _world.has_method("leave_to_home"):
		# The world saves the location and the profile again and swaps scene.
		_world.call("leave_to_home")
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.get_script() == null and ResourceLoader.exists(HOME_SCENE_PATH):
		tree.call_deferred("change_scene_to_file", HOME_SCENE_PATH)


## Home, as an API.
func go_home() -> void:
	_on_home()


func is_leaving() -> bool:
	return _leaving


## -- Holding the room ------------------------------------------------------------------

func _hold_world() -> void:
	_prior_taps = null
	if _nav != null and is_instance_valid(_nav) and _nav.get("taps_enabled") != null:
		_prior_taps = bool(_nav.get("taps_enabled"))
		_nav.set("taps_enabled", false)
	_prior_character_disabled = false
	if _character != null and is_instance_valid(_character) and _character.has_method("set_disabled"):
		if _character.has_method("get_state_name"):
			_prior_character_disabled = String(_character.call("get_state_name")) == "disabled"
		if not _prior_character_disabled:
			_character.call("set_disabled", true)
	_prior_affordance_enabled = null
	var layer: Control = _affordance_layer()
	if layer != null and layer.has_method("set_enabled"):
		if layer.has_method("is_enabled"):
			_prior_affordance_enabled = bool(layer.call("is_enabled"))
		else:
			_prior_affordance_enabled = true
		layer.call("set_enabled", false)
	_prior_narration_covered = null
	if _hud != null and is_instance_valid(_hud) and _hud.has_method("set_narration_covered"):
		if _hud.has_method("is_narration_covered"):
			_prior_narration_covered = bool(_hud.call("is_narration_covered"))
		else:
			_prior_narration_covered = false
		# Also what keeps the HUD's own refreshes from switching the badges
		# back on under the card.
		_hud.call("set_narration_covered", true)


func _release_world() -> void:
	if _hud != null and is_instance_valid(_hud) and _prior_narration_covered != null \
			and _hud.has_method("set_narration_covered"):
		_hud.call("set_narration_covered", bool(_prior_narration_covered))
	var layer: Control = _affordance_layer()
	if layer != null and _prior_affordance_enabled != null and layer.has_method("set_enabled"):
		layer.call("set_enabled", bool(_prior_affordance_enabled))
	if _character != null and is_instance_valid(_character) and _character.has_method("set_disabled") \
			and not _prior_character_disabled:
		_character.call("set_disabled", false)
	if _nav != null and is_instance_valid(_nav) and _prior_taps != null:
		_nav.set("taps_enabled", bool(_prior_taps))
	_prior_taps = null
	_prior_affordance_enabled = null
	_prior_narration_covered = null


func _affordance_layer() -> Control:
	if _world != null and is_instance_valid(_world) and _world.has_method("get_affordance_layer"):
		var layer: Control = _world.call("get_affordance_layer")
		if layer != null and is_instance_valid(layer):
			return layer
	if _hud != null and is_instance_valid(_hud) and _hud.has_method("get_affordance_layer"):
		return _hud.call("get_affordance_layer")
	return null


## -- Music ------------------------------------------------------------------------------

func _duck_music(down: bool) -> void:
	var audio: Object = _audio if _services_injected else _autoload("Audio")
	if audio == null or not is_instance_valid(audio) \
			or not audio.has_method("get_music_volume_db") or not audio.has_method("set_music_volume_db"):
		return
	if down:
		var before: float = float(audio.call("get_music_volume_db"))
		_prior_music_db = before
		_ducked_music_db = before - BREAK_DUCK_DB
		audio.call("set_music_volume_db", _ducked_music_db)
		return
	if _prior_music_db == null:
		return
	# Still where the duck left it (the trim clamps, so "at or below")? Then it
	# is ours to put back. Anything else was changed by somebody else and stays.
	var now: float = float(audio.call("get_music_volume_db"))
	if now <= float(_prior_music_db) - 0.01:
		audio.call("set_music_volume_db", float(_prior_music_db))
	_prior_music_db = null


func _autoload(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath(autoload_name))

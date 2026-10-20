extends Node
## Small crime registry and simulation-time wanted state. Physics, police and HUD
## report events through this API; the registry knows nothing about their scenes.

signal crime_registered(type: StringName, heat_added: float, position: Vector2)
signal wanted_changed(level: int, heat: float)
signal pursuit_state_changed(state: StringName)

const FIRST_STAR_HEAT: float = 1.0
const SECOND_STAR_HEAT: float = 60.0
const THIRD_STAR_HEAT: float = 140.0
const MAXIMUM_HEAT: float = 240.0

@export var decay_delay: float = 8.0
@export var heat_decay_rate: float = 6.0

var heat: float = 0.0
var wanted_level: int = 0
var state: StringName = &"free"
var last_known_position := Vector2.ZERO

var _catalog: Dictionary = {
	&"pedestrian_hit": {"severity": 45.0, "cooldown": 1.6},
	&"vehicle_collision": {"severity": 15.0, "cooldown": 1.2},
	&"vehicle_theft": {"severity": 65.0, "cooldown": 0.0},
}
var _cooldowns: Dictionary = {}
var _clock: float = 0.0
var _last_crime_time: float = 0.0
var _last_seen_time: float = 0.0
var _next_cleanup_time: float = 5.0
var _visible_to_police: bool = false
var _enabled: bool = true
var _has_focus: bool = true


func _ready() -> void:
	set_physics_process(_enabled and _has_focus)


## New crime types can be registered by future gameplay modules. A minimum of
## one heat point preserves the zero-heat/zero-stars invariant of this version.
func register_crime_type(type: StringName, severity: float, cooldown: float = 0.0) -> bool:
	if type.is_empty() or not is_finite(severity) or severity < FIRST_STAR_HEAT \
		or not is_finite(cooldown) or cooldown < 0.0:
		return false
	_catalog[type] = {"severity": severity, "cooldown": cooldown}
	return true


func register_crime(type: StringName, source: Object = null, subject: Object = null) -> bool:
	if not _enabled or not _has_focus or not _catalog.has(type):
		return false
	var definition: Dictionary = _catalog[type]
	var cooldown: float = float(definition["cooldown"])
	# Cool down a particular victim/vehicle, rather than suppressing crimes
	# against other objects. Persistent contact cannot add heat every frame.
	var subject_id: int = subject.get_instance_id() if is_instance_valid(subject) else 0
	if subject_id == 0 and is_instance_valid(source):
		subject_id = source.get_instance_id()
	var cooldown_key: String = "%s:%d" % [type, subject_id]
	if cooldown > 0.0 and _clock < float(_cooldowns.get(cooldown_key, -INF)):
		return false
	if cooldown > 0.0:
		_cooldowns[cooldown_key] = _clock + cooldown
	_last_crime_time = _clock
	if source is Node2D and is_instance_valid(source):
		var position: Vector2 = (source as Node2D).global_position
		if position.is_finite():
			last_known_position = position
	elif subject is Node2D and is_instance_valid(subject):
		var position: Vector2 = (subject as Node2D).global_position
		if position.is_finite():
			last_known_position = position
	var previous_heat: float = heat
	_set_heat(minf(heat + float(definition["severity"]), MAXIMUM_HEAT))
	_update_state()
	crime_registered.emit(type, heat - previous_heat, last_known_position)
	return true


## A manager may report visibility every few tenths of a second. The most recent
## observation remains valid between reports; unseen reports do not restart the
## grace period, and positions behind cover never update the last known target.
func set_police_observation(visible: bool, position: Vector2) -> void:
	if not _enabled or not _has_focus:
		return
	if visible:
		_last_seen_time = _clock
		if position.is_finite():
			last_known_position = position
	elif _visible_to_police:
		_last_seen_time = _clock
	_visible_to_police = visible
	_update_state()


func _physics_process(delta: float) -> void:
	advance_time(delta)


## Explicit simulation time also supports deterministic tests without sleeps.
func advance_time(delta: float) -> void:
	if not _enabled or not _has_focus or not is_finite(delta) or delta <= 0.0:
		return
	var previous_time: float = _clock
	_clock += delta
	if _clock >= _next_cleanup_time:
		for key: String in _cooldowns.keys():
			if float(_cooldowns[key]) <= _clock:
				_cooldowns.erase(key)
		_next_cleanup_time = _clock + 5.0
	if wanted_level > 0 and not _visible_to_police:
		var grace_end: float = maxf(_last_seen_time, _last_crime_time) + maxf(decay_delay, 0.0)
		# A large frame that crosses the grace boundary decays only its elapsed
		# portion after that boundary, not the entire delta.
		var decay_seconds: float = maxf(_clock - maxf(previous_time, grace_end), 0.0)
		if decay_seconds > 0.0:
			var remaining: float = maxf(heat - maxf(heat_decay_rate, 0.0) * decay_seconds, 0.0)
			_set_heat(0.0 if remaining < FIRST_STAR_HEAT else remaining)
	_update_state()


func _set_heat(value: float) -> void:
	var previous_level: int = wanted_level
	heat = clampf(value, 0.0, MAXIMUM_HEAT)
	if heat >= THIRD_STAR_HEAT:
		wanted_level = 3
	elif heat >= SECOND_STAR_HEAT:
		wanted_level = 2
	elif heat >= FIRST_STAR_HEAT:
		wanted_level = 1
	else:
		wanted_level = 0
	if wanted_level != previous_level:
		wanted_changed.emit(wanted_level, heat)


func _update_state() -> void:
	var next_state: StringName = &"free" if wanted_level == 0 else (&"pursued" if _visible_to_police else &"hidden")
	if next_state != state:
		state = next_state
		pursuit_state_changed.emit(state)


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	set_physics_process(enabled and _has_focus)


func reset() -> void:
	_cooldowns.clear()
	_clock = 0.0
	_last_crime_time = 0.0
	_last_seen_time = 0.0
	_next_cleanup_time = 5.0
	_visible_to_police = false
	last_known_position = Vector2.ZERO
	_set_heat(0.0)
	_update_state()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		_has_focus = false
		set_physics_process(false)
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		_has_focus = true
		set_physics_process(_enabled)

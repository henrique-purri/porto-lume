extends "res://scripts/parked_car.gd"
## Original geometric police livery; light animation is capped to 6.25 Hz.

var _emergency_active: bool = false
var _light_phase: bool = false
var _light_timer: Timer
var _animation_enabled: bool = true


func _ready() -> void:
	body_color = Color("e0e6dc")
	_light_timer = Timer.new()
	_light_timer.name = "LightBarTimer"
	_light_timer.wait_time = 0.16
	add_child(_light_timer)
	_light_timer.timeout.connect(_on_light_tick)
	queue_redraw()


func set_emergency_active(active: bool) -> void:
	if _emergency_active == active:
		return
	_emergency_active = active
	if is_instance_valid(_light_timer):
		if active and _animation_enabled:
			_light_timer.start()
		else:
			_light_timer.stop()
	queue_redraw()


func set_animation_enabled(enabled: bool) -> void:
	_animation_enabled = enabled
	if is_instance_valid(_light_timer):
		if enabled and _emergency_active:
			_light_timer.start()
		else:
			_light_timer.stop()


func _on_light_tick() -> void:
	_light_phase = not _light_phase
	queue_redraw()


func _draw() -> void:
	super._draw()
	var navy := Color("243d58")
	draw_rect(Rect2(-16, -35, 32, 13), navy)
	draw_rect(Rect2(-16, 26, 32, 9), navy)
	draw_line(Vector2(-14, 1), Vector2(14, 1), navy, 9.0)
	draw_rect(Rect2(-13, -5, 26, 6), Color("172d32"))
	var red := Color("ee7867")
	var blue := Color("68b7dc")
	if _emergency_active:
		red = red.lightened(0.4) if _light_phase else red.darkened(0.45)
		blue = blue.darkened(0.45) if _light_phase else blue.lightened(0.4)
	else:
		red = red.darkened(0.3)
		blue = blue.darkened(0.3)
	draw_rect(Rect2(-11, -4, 10, 4), red)
	draw_rect(Rect2(1, -4, 10, 4), blue)
	draw_circle(Vector2(0, 9), 4.1, navy)
	draw_line(Vector2(-2.5, 9), Vector2(2.5, 9), Color("e4d8a3"), 1.5)
	draw_line(Vector2(0, 6.5), Vector2(0, 11.5), Color("e4d8a3"), 1.5)

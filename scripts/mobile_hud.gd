extends CanvasLayer
## The Web shell supplies notch/home-indicator padding with CSS env(safe-area-*
## insets). Browser display coordinates are not reliable native safe-area data.

signal vehicle_action_requested

@export var edge_padding: float = 26.0

@onready var controls: Control = $Controls
@onready var title: Control = $Controls/Title
@onready var compass: Control = $Controls/Compass
@onready var prototype: Label = $Controls/Prototype
@onready var hint: Label = $Controls/Hint
@onready var joystick: Control = $Controls/Joystick
@onready var vehicle_action: Control = $Controls/VehicleAction
@onready var accelerator: Control = $Controls/Accelerator
@onready var brake: Control = $Controls/Brake
@onready var feedback_timer: Timer = $FeedbackTimer

var _driving: bool = false


func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	vehicle_action.activated.connect(_on_vehicle_action)
	feedback_timer.timeout.connect(_restore_hint)
	set_driving(false)
	set_vehicle_action(false, false)
	_layout()


func set_driving(value: bool) -> void:
	if _driving != value:
		reset_controls()
	_driving = value
	accelerator.visible = value
	brake.visible = value
	feedback_timer.stop()
	_restore_hint()


func set_vehicle_action(available: bool, driving: bool) -> void:
	vehicle_action.caption = "SAIR" if driving else "ENTRAR"
	vehicle_action.visible = available


func get_drive_throttle() -> float:
	if not _driving:
		return 0.0
	if brake.is_held():
		return -1.0
	return 1.0 if accelerator.is_held() else 0.0


func get_drive_steering() -> float:
	return joystick.get_direction().x if _driving else 0.0


func reset_controls() -> void:
	joystick.reset()
	vehicle_action.reset()
	accelerator.reset()
	brake.reset()


func show_feedback(message: String) -> void:
	hint.text = message
	feedback_timer.start()


func _restore_hint() -> void:
	hint.text = "Vire ← →" if _driving else "Mova para explorar"


func _on_vehicle_action() -> void:
	reset_controls()
	vehicle_action_requested.emit()


func _on_viewport_size_changed() -> void:
	# Reset any captured touch when rotating or resizing the browser viewport.
	reset_controls()
	_layout.call_deferred()


func _layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var margin := edge_padding
	title.position = Vector2(margin + 3.0, margin)
	compass.position = Vector2(viewport_size.x - margin - 46.0, margin - 1.0)
	prototype.position = Vector2(viewport_size.x - margin - 162.0, margin + 56.0)
	prototype.size = Vector2(162.0, 20.0)
	joystick.position = Vector2(margin, viewport_size.y - margin - 184.0)
	joystick.size = Vector2(184.0, 184.0)
	hint.position = Vector2(margin + 11.0, viewport_size.y - margin - 209.0)
	hint.size = Vector2(340.0, 23.0)

	accelerator.position = Vector2(viewport_size.x - margin - 100.0, viewport_size.y - margin - 100.0)
	accelerator.size = Vector2(100.0, 100.0)
	brake.position = accelerator.position - Vector2(126.0, 0.0)
	brake.size = Vector2(100.0, 100.0)
	vehicle_action.position = Vector2(viewport_size.x - margin - 140.0, viewport_size.y - margin - 216.0)
	vehicle_action.size = Vector2(140.0, 80.0)

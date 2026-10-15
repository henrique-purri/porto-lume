extends CanvasLayer
## The Web shell supplies notch/home-indicator padding with CSS env(safe-area-*
## insets). Browser display coordinates are not reliable native safe-area data.

@export var edge_padding: float = 26.0

@onready var controls: Control = $Controls
@onready var title: Control = $Controls/Title
@onready var compass: Control = $Controls/Compass
@onready var prototype: Label = $Controls/Prototype
@onready var hint: Label = $Controls/Hint
@onready var joystick: Control = $Controls/Joystick


func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_layout()


func _on_viewport_size_changed() -> void:
	# Reset any captured touch when rotating or resizing the browser viewport.
	joystick.reset()
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
	hint.size = Vector2(210.0, 23.0)

extends Node2D
## Composition root: o mundo, jogador e controles não dependem uns dos outros.

@onready var player: CharacterBody2D = $Player
@onready var joystick: Control = $HUD/Controls/Joystick


func _ready() -> void:
	player.set("joystick", joystick)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready():
		player.reset_motion()
		if joystick.has_method("reset"):
			joystick.call("reset")

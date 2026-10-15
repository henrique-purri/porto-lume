extends Node2D
## Composition root: o mundo, jogador e controles não dependem uns dos outros.

@onready var player: CharacterBody2D = $Player
@onready var joystick: Control = $HUD/Controls/Joystick
@onready var vehicle_interaction: Node = $VehicleInteraction


func _ready() -> void:
	player.set("joystick", joystick)
	vehicle_interaction.setup(player, $HUD, $City/Vehicles)
	$PedestrianManager.setup(player, vehicle_interaction, $City/Vehicles)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED] and is_node_ready():
		vehicle_interaction.reset_controls()

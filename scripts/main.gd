extends Node2D
## Composition root: o mundo, jogador e controles não dependem uns dos outros.

@onready var player: CharacterBody2D = $Player
@onready var joystick: Control = $HUD/Controls/Joystick
@onready var vehicle_interaction: Node = $VehicleInteraction


func _ready() -> void:
	player.set("joystick", joystick)
	vehicle_interaction.setup(player, $HUD, $City/Vehicles)
	$TrafficManager.setup(player, vehicle_interaction, $City/Vehicles)
	vehicle_interaction.set_traffic_source($TrafficManager)
	$PoliceManager.setup(player, vehicle_interaction, $TrafficManager, $CrimeSystem)
	$PedestrianManager.setup(player, vehicle_interaction, $City/Vehicles)
	$PedestrianManager.set_traffic_source($TrafficManager)
	$PedestrianManager.set_police_source($PoliceManager)
	$CrimeSystem.wanted_changed.connect(func(_level: int, _heat: float): _sync_wanted_hud())
	$CrimeSystem.pursuit_state_changed.connect(func(_state: StringName): _sync_wanted_hud())
	_sync_wanted_hud()


func _sync_wanted_hud() -> void:
	$HUD.set_wanted_status(int($CrimeSystem.wanted_level), $CrimeSystem.state, float($CrimeSystem.heat))


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED] and is_node_ready():
		vehicle_interaction.reset_controls()

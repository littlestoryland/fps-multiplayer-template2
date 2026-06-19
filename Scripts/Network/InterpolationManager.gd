# InterpolationManager.gd - Smooth movement interpolation for remote players
extends Node
class_name InterpolationManager

class RemotePlayerState:
	var target_position: Vector3
	var current_position: Vector3
	var interpolation_time: float = 0.0
	var interpolation_duration: float = 0.1
	var velocity: Vector3 = Vector3.ZERO
	
	func _init(pos: Vector3) -> void:
		target_position = pos
		current_position = pos

var remote_players: Dictionary = {}  # peer_id -> RemotePlayerState
var interpolation_enabled: bool = true

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_process(interpolation_enabled)

func _process(delta: float) -> void:
	if not interpolation_enabled:
		return
	
	for peer_id in remote_players.keys():
		var state = remote_players[peer_id]
		state.interpolation_time += delta
		
		if state.interpolation_time < state.interpolation_duration:
			var t = state.interpolation_time / state.interpolation_duration
			t = ease(t, -2.0)  # Ease-in-out cubic for smooth motion
			state.current_position = state.current_position.lerp(state.target_position, t)
		else:
			state.current_position = state.target_position
			state.interpolation_time = 0.0

func update_remote_position(peer_id: int, new_position: Vector3, network_latency_ms: float = 50.0) -> void:
	if not remote_players.has(peer_id):
		remote_players[peer_id] = RemotePlayerState.new(new_position)
	else:
		var state = remote_players[peer_id]
		state.target_position = new_position
		state.velocity = (new_position - state.current_position) / 0.1
		
		# Adaptive interpolation duration based on network latency
		state.interpolation_duration = max(0.033, network_latency_ms / 1000.0 * 1.5)
		state.interpolation_time = 0.0

func get_interpolated_position(peer_id: int) -> Vector3:
	if remote_players.has(peer_id):
		return remote_players[peer_id].current_position
	return Vector3.ZERO

func remove_player(peer_id: int) -> void:
	if remote_players.has(peer_id):
		remote_players.erase(peer_id)

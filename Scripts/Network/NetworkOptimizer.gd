# NetworkOptimizer.gd - Centralized network optimization manager
extends Node
class_name NetworkOptimizer

# Bandwidth reduction settings
var enable_bandwidth_optimization: bool = true
var position_sync_interval: float = 0.05  # 50ms between syncs
var rotation_sync_interval: float = 0.033  # ~30fps for rotations
var ammo_sync_interval: float = 0.1  # 100ms for ammo (less critical)
var health_sync_threshold: int = 5  # Only sync if health changes by 5+

# Tracking timers for each sync type
var position_sync_timer: float = 0.0
var rotation_sync_timer: float = 0.0
var ammo_sync_timer: float = 0.0

# Last synced values for delta compression
var last_synced_position: Vector3 = Vector3.ZERO
var last_synced_rotation: Vector3 = Vector3.ZERO
var last_synced_health: int = 200
var last_synced_ammo: Array[int] = [0, 0]

# Distance threshold for position updates (prevents sending tiny movements)
var position_update_threshold: float = 0.1

# Bandwidth stats
var total_packets_sent: int = 0
var packets_skipped: int = 0
var bandwidth_saved_percent: float = 0.0

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_process(enable_bandwidth_optimization)

func _process(delta: float) -> void:
	if not enable_bandwidth_optimization:
		return
	
	position_sync_timer += delta
	rotation_sync_timer += delta
	ammo_sync_timer += delta

func should_sync_position(current_pos: Vector3) -> bool:
	if position_sync_timer < position_sync_interval:
		packets_skipped += 1
		return false
	
	var distance = current_pos.distance_to(last_synced_position)
	if distance < position_update_threshold:
		packets_skipped += 1
		return false
	
	position_sync_timer = 0.0
	last_synced_position = current_pos
	total_packets_sent += 1
	return true

func should_sync_rotation(current_rot: Vector3) -> bool:
	if rotation_sync_timer < rotation_sync_interval:
		return false
	
	rotation_sync_timer = 0.0
	last_synced_rotation = current_rot
	total_packets_sent += 1
	return true

func should_sync_ammo(current_ammo: Array[int]) -> bool:
	if ammo_sync_timer < ammo_sync_interval:
		return false
	
	if current_ammo == last_synced_ammo:
		packets_skipped += 1
		return false
	
	ammo_sync_timer = 0.0
	last_synced_ammo = current_ammo.duplicate()
	total_packets_sent += 1
	return true

func should_sync_health(current_health: int) -> bool:
	var health_diff = abs(current_health - last_synced_health)
	if health_diff < health_sync_threshold:
		packets_skipped += 1
		return false
	
	last_synced_health = current_health
	total_packets_sent += 1
	return true

func calculate_bandwidth_savings() -> void:
	if total_packets_sent == 0:
		bandwidth_saved_percent = 0.0
		return
	
	var total_potential = total_packets_sent + packets_skipped
	bandwidth_saved_percent = (float(packets_skipped) / total_potential) * 100.0

func get_stats() -> Dictionary:
	calculate_bandwidth_savings()
	return {
		"total_packets_sent": total_packets_sent,
		"packets_skipped": packets_skipped,
		"bandwidth_saved_percent": bandwidth_saved_percent
	}

func reset_stats() -> void:
	total_packets_sent = 0
	packets_skipped = 0
	bandwidth_saved_percent = 0.0

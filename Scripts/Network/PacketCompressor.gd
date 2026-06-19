# PacketCompressor.gd - Compress network data to reduce bandwidth
extends Node
class_name PacketCompressor

# Quantization levels for position (reduces from 32-bit float to 16-bit)
const POSITION_QUANTIZE_LEVEL: int = 1000
const ROTATION_QUANTIZE_LEVEL: int = 10000

func compress_position(pos: Vector3) -> PackedInt32Array:
	"""Quantize position to reduce bandwidth. Precision: 0.001 units."""
	return PackedInt32Array([
		int(pos.x * POSITION_QUANTIZE_LEVEL),
		int(pos.y * POSITION_QUANTIZE_LEVEL),
		int(pos.z * POSITION_QUANTIZE_LEVEL)
	])

func decompress_position(data: PackedInt32Array) -> Vector3:
	"""Decompress quantized position."""
	if data.size() < 3:
		return Vector3.ZERO
	return Vector3(
		float(data[0]) / POSITION_QUANTIZE_LEVEL,
		float(data[1]) / POSITION_QUANTIZE_LEVEL,
		float(data[2]) / POSITION_QUANTIZE_LEVEL
	)

func compress_rotation(rot: Vector3) -> PackedInt32Array:
	"""Quantize rotation (Euler angles in radians)."""
	return PackedInt32Array([
		int(rot.x * ROTATION_QUANTIZE_LEVEL),
		int(rot.y * ROTATION_QUANTIZE_LEVEL),
		int(rot.z * ROTATION_QUANTIZE_LEVEL)
	])

func decompress_rotation(data: PackedInt32Array) -> Vector3:
	"""Decompress quantized rotation."""
	if data.size() < 3:
		return Vector3.ZERO
	return Vector3(
		float(data[0]) / ROTATION_QUANTIZE_LEVEL,
		float(data[1]) / ROTATION_QUANTIZE_LEVEL,
		float(data[2]) / ROTATION_QUANTIZE_LEVEL
	)

func delta_encode_ammo(current: Array[int], previous: Array[int]) -> Dictionary:
	"""Only send ammo data if it changed."""
	var delta = {}
	if current.size() != previous.size():
		return {"full": current}
	
	for i in range(current.size()):
		if current[i] != previous[i]:
			delta["slot_%d" % i] = current[i]
	
	return delta if delta.size() > 0 else {}

func compress_state(pos: Vector3, rot: Vector3) -> PackedByteArray:
	"""Combine position and rotation into single compressed packet."""
	var compressed = PackedByteArray()
	var pos_data = compress_position(pos)
	var rot_data = compress_rotation(rot)
	
	for val in pos_data:
		compressed.append_array(var_to_bytes(val))
	for val in rot_data:
		compressed.append_array(var_to_bytes(val))
	
	return compressed

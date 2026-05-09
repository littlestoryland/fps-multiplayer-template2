extends RigidBody3D

@onready var blast_radius = $Area3D
@onready var timer = $Timer

# Preload your explosion effect if you have one (Optional)
# var explosion_fx = preload("res://Effects/Explosion.tscn")

func _ready():
	timer.start()

func _on_timer_timeout():
	# Only the Server calculates damage to prevent cheating
	if multiplayer.is_server():
		explode()

func explode():
	# 1. Damage Loop
	var bodies = blast_radius.get_overlapping_bodies()
	#print("explo det" + str(bodies.size()) + "bodies.")
	for body in bodies:
		#print("checki" + body.name)
		if body.has_method("receive_damage"):
			var space_state = get_world_3d().direct_space_state
			var start_pos = global_position + Vector3(0,0.5,0)
			var target_pos = body.global_position + Vector3(0,1.0,0)
			
			var query = PhysicsRayQueryParameters3D.create(start_pos,target_pos)
			
			query.collision_mask = 1
			
			var result = space_state.intersect_ray(query)
			
			if result and result.collider != body:
				#print("bbw" + result.collider.name)
				continue
			
			# Calculate damage based on distance (Optional polish)
			var dist = global_position.distance_to(body.global_position)
			var dmg = 100 - (dist * 10) # Closer = More ouch
			dmg = clamp(dmg, 10, 100)
			
			#print("dmg pl")
			body.receive_damage.rpc(int(dmg), "Grenade")
	
	# 2. Visuals (Tell everyone to play the boom sound/particle)
	play_effects.rpc()
	
	# 3. Destroy
	$MeshInstance3D.hide()

@rpc("call_local")
func play_effects():
	$Node3D/AnimationPlayer.play("explode")
	#print("BOOM!")


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	queue_free()

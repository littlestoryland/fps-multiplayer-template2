extends CharacterBody3D

# -------------------------------------------------------------------------
# 1. NODES
# -------------------------------------------------------------------------
@onready var camera: Camera3D = $Camera3D
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var raycast: RayCast3D = $Camera3D/RayCast3D
@onready var gun_holder : Node3D = $Camera3D/SubViewport/SubViewport/WeaponCamera/Node3D/Gun
@onready var interact_label: Label = $CanvasLayer/Label
@onready var interact_ray: RayCast3D = $Camera3D/InteractRay
@onready var ammo_label: Label = $CanvasLayer/Label2
@onready var health_bar: ProgressBar = $CanvasLayer/HealthBar
@onready var stamina_bar: ProgressBar = $CanvasLayer/StaminaBar 
@onready var trajectory_line: MeshInstance3D = $TrajectoryLine
@onready var weapon_camera: Camera3D = $Camera3D/SubViewport/SubViewport/WeaponCamera
@onready var mesh_node: MeshInstance3D = $MeshInstance3D
@onready var collision_node: CollisionShape3D = $CollisionShape3D
@onready var head_check_ray: RayCast3D = $HeadCheckRay

# -------------------------------------------------------------------------
# 2. SETTINGS & PRELOADS
# -------------------------------------------------------------------------
const GRENADE_SCENE = preload("res://Scenes/Weapons/grenade.tscn")

@export_group("Gameplay Settings")
@export var health : int = 200
@export var max_stamina : float = 100.0
@export var stamina_regen : float = 15.0
@export var slide_cost : float = 25.0
@export var ads_speed : float = 12.0
@export var infinite_reserves:bool = false
@export var grenade_count: int = 2
@export var medkit_count:int = 1
# This delay is for mobile users only now
@export var auto_run_delay : float = 0.4 
@export var spawns: PackedVector3Array = ([
	Vector3(-18, 0.2, 0), Vector3(18, 0.2, 0), Vector3(-2.8, 0.2, -6),
	Vector3(-17,0,17), Vector3(17,0,17), Vector3(17,0,-17), Vector3(-17,0,-17)
])

@export_group("Recoil Settings")
@export var recoil_kick : float = 0.05 
@export var recoil_snap : float = 10.0 
@export var recoil_recover : float = 6.0 

@export_group("Inventory")
@export var inventory : Array[WeaponData] = [null, null, null]
@export var current_weapon : WeaponData

@export_group("Multiplayer Sync")
@export var playername :String = "":
	set(value):
		playername = value
		if is_node_ready(): update_visuals()
@export var player_color : Color = Color.WHITE:
	set(value):
		player_color = value
		if is_node_ready(): update_visuals()

# -------------------------------------------------------------------------
# 3. VARIABLES
# -------------------------------------------------------------------------
# MOVEMENT
var current_speed = 5.5
const WALK_SPEED = 5.5
const SPRINT_SPEED = 9.0  
const SLIDE_SPEED = 14.0 
const SLIDE_FRICTION = 8.0 
const CROUCH_SPEED = 2.5
const JUMP_VELOCITY = 4.5
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var last_fall_velocity = 0.0 
var stamina : float = 100.0

# TOGGLES & AUTO-RUN
var toggle_sprint : bool = false
var toggle_aim : bool = false
var auto_run : bool = false 
var run_hold_timer : float = 0.0
var is_pc : bool = false # FIX: Detects if using PC

# CROUCH / SLIDE
var standing_height = 2.0
var crouch_height = 1.4      
var default_cam_height = 1.6
var crouch_cam_height = 1.1  
var is_crouched : bool = false
var wants_to_crouch : bool = false

# SLIDING
var is_sliding : bool = false
var slide_direction : Vector3 = Vector3.ZERO
var net_is_sliding : bool = false 

# RECOIL & LOOK
var cam_rot_x : float = 0.0 
var current_recoil_x : float = 0.0
var target_recoil_x : float = 0.0

# INPUT
var sensitivity : float =  0.002 
var controller_sensitivity : float =  0.005
var axis_vector : Vector2
var mouse_captured : bool = true
var synced_rotation_x : float = 0.0 

# WEAPON STATE
var current_gun_node : Node3D = null
var last_fire_time: float = 0.0
var current_slot : int = 0
var is_dead:bool = false
var is_reloading : bool = false
var is_healing : bool = false
var ammo_in_mag : Array[int] = [0,0,0]
var reserve_ammo : Array = [0,0,0]
var throw_force = 20.0 

# AIMING
var current_aim_pos: Vector3 = Vector3(0,0,0)
var current_aim_fov : float = 75.0
var default_pos: Vector3 = Vector3(0,0,0)
var default_fov : float = 75.0
var is_aiming_synced : bool = false

# -------------------------------------------------------------------------
# 4. SETUP
# -------------------------------------------------------------------------
func _enter_tree() -> void:
	set_multiplayer_authority(str(name).to_int())

func _ready() -> void:
	$Camera3D/SubViewport/SubViewport/WeaponCamera/Node3D.position = Vector3(0,0,0)
	default_cam_height = camera.position.y
	stamina = max_stamina
	cam_rot_x = camera.rotation.x
	
	# Detect Platform
	if OS.get_name() in ["Windows", "macOS", "linux", "Web"]:
		is_pc = true
	
	interact_label.text = ""
	interact_label.hide()
	ammo_label.text = ""
	
	if collision_node:
		collision_node.shape = collision_node.shape.duplicate()
		
	var joystick = get_node_or_null("CanvasLayer/Virtual Joystick")
	if joystick and is_pc:
		joystick.process_mode = Node.PROCESS_MODE_DISABLED
		joystick.visible = false
	
	Input.use_accumulated_input = false

	if not is_multiplayer_authority():
		$CanvasLayer.visible = false
	
	var default_gun = load("res://Resources/Weapons/Pistol.tres")
	
	if is_multiplayer_authority():
		inventory[0] = default_gun
		ammo_in_mag[0] = default_gun.clip_size
		reserve_ammo[0] = default_gun.clip_size
		current_weapon = default_gun
		current_slot = 0
		
		player_color = get_parent().selectedcolor
		playername = get_parent().localpn
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		camera.current = true
		if spawns.size() > 0: position = spawns[randi() % spawns.size()]
		
		spawn_gun_visuals(default_gun)
	else:
		if default_gun: spawn_gun_visuals(default_gun)

	health = 200
	update_health_ui()
	update_ammo_ui()
	update_visuals()

# -------------------------------------------------------------------------
# 5. INPUT & PROCESS
# -------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority(): return
	
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * sensitivity)
		cam_rot_x -= event.relative.y * sensitivity
		cam_rot_x = clamp(cam_rot_x, -PI/2, PI/2)
	
	if event is InputEventScreenDrag:
		rotate_y(-event.relative.x * sensitivity)
		cam_rot_x -= event.relative.y * sensitivity
		cam_rot_x = clamp(cam_rot_x, -PI/2, PI/2)

func _process(delta: float) -> void:
	if net_is_sliding and mesh_node:
		mesh_node.rotation_degrees.x = 30 
	elif mesh_node and not net_is_sliding:
		mesh_node.rotation_degrees.x = move_toward(mesh_node.rotation_degrees.x, 0, 100 * delta)

	if not is_multiplayer_authority(): return
	
	target_recoil_x = lerp(target_recoil_x, 0.0, recoil_recover * delta)
	current_recoil_x = lerp(current_recoil_x, target_recoil_x, recoil_snap * delta)
	
	camera.rotation.x = cam_rot_x + current_recoil_x
	weapon_camera.rotation.x = camera.rotation.x

	if interact_ray.is_colliding():
		var object = interact_ray.get_collider()
		var loot_root = null
		if object.has_method("interact"): loot_root = object
		elif object.get_parent() and object.get_parent().has_method("interact"): loot_root = object.get_parent()

		if loot_root:
			var w_name = loot_root.current_weapon_name if "current_weapon_name" in loot_root else "Item"
			interact_label.text = " PRESS F TO PICKUP " + str(w_name)
			interact_label.show()
			if Input.is_action_just_pressed("interact"): loot_root.interact(self)
		else:
			interact_label.hide()
	else:
		interact_label.hide()

	if axis_vector != Vector2.ZERO:
		rotate_y(-axis_vector.x * controller_sensitivity)
		cam_rot_x -= axis_vector.y * controller_sensitivity
		cam_rot_x = clamp(cam_rot_x, -PI/2, PI/2)

	if weapon_camera and is_multiplayer_authority():
		weapon_camera.global_transform = camera.global_transform
		
	if Input.is_action_just_pressed("med"): 
		auto_run = false
		use_medkit.rpc()

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or is_dead: return
	
	if Input.is_action_just_pressed("w1"): equip_slot(0)
	if Input.is_action_just_pressed("w2"): equip_slot(1)
	if Input.is_action_just_pressed("w3"): equip_slot(2)
	
	if Input.is_action_just_pressed("rel"): reload()
	if Input.is_action_just_pressed("respawn"): receive_damage(200, "world")

	if Input.is_action_pressed("throw grenade") and grenade_count > 0:
		auto_run = false
		trajectory_line.show()
		var dir = -camera.global_transform.basis.z + Vector3(0, 0.5, 0)
		update_trajectory(dir.normalized())
	else:
		trajectory_line.hide()
		
	if Input.is_action_just_released("throw grenade"):
		trajectory_line.hide()
		if grenade_count > 0:
			grenade_count -= 1
			pickup_item("grenade", 0) 
			var dir = -camera.global_transform.basis.z + Vector3(0, 0.5, 0)
			request_grenade.rpc_id(1, dir.normalized())
# -------------------------------------------------------------------------
# 6. PHYSICS
# -------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		if abs(camera.rotation.x - synced_rotation_x) > 0.01:
			update_rotation_x.rpc(camera.rotation.x)
			synced_rotation_x = camera.rotation.x
	else:
		camera.rotation.x = lerp(camera.rotation.x, synced_rotation_x, 20 * delta)
		return 

	if is_dead: 
		move_and_slide()
		return

	# 1. SHOOTING
	if current_weapon and current_weapon is WeaponData:
		var attempt_fire = false
		if current_weapon.is_automatic: attempt_fire = Input.is_action_pressed("shoot")
		else: attempt_fire = Input.is_action_just_pressed("shoot")
		
		if attempt_fire:
			auto_run = false 
			if not is_reloading and not is_healing:
				if ammo_in_mag[current_slot] > 0:
					var time_now = Time.get_ticks_msec() / 1000.0
					if time_now - last_fire_time >= current_weapon.fire_rate:
						ammo_in_mag[current_slot] -= 1
						update_ammo_ui()
						shoot.rpc()
						is_healing = false
						last_fire_time = time_now
				else:
					reload()

	# 2. GRAVITY
	if not is_on_floor():
		velocity += get_gravity() * delta
		last_fall_velocity = velocity.y 
	else:
		if last_fall_velocity < -15.0: 
			var damage = abs(last_fall_velocity) * 1.5 
			receive_damage(int(damage), "fall")
		last_fall_velocity = 0.0

	# 3. JUMP
	if Input.is_action_just_pressed("jump") and is_on_floor():
		if is_sliding:
			stop_slide.rpc() 
			velocity.y = JUMP_VELOCITY * 1.2 
		elif is_crouched:
			wants_to_crouch = false
			set_crouch.rpc(false)
			velocity.y = JUMP_VELOCITY
		else:
			velocity.y = JUMP_VELOCITY

	# 4. AIMING
	if Input.is_action_just_pressed("aim"):
		toggle_aim = !toggle_aim
		set_aiming.rpc(toggle_aim)
		is_aiming_synced = toggle_aim

	var target_fov = default_fov
	var target_pos = default_pos
	
	if toggle_aim:
		if anim_player.current_animation != "shoot" and anim_player.current_animation != "RESET":
			anim_player.play("RESET")
		target_fov = current_aim_fov
		target_pos = current_aim_pos
	
	camera.fov = lerp(camera.fov, target_fov, ads_speed * delta)
	weapon_camera.fov = lerp(weapon_camera.fov, target_fov, ads_speed * delta)
	var pivot = $Camera3D/SubViewport/SubViewport/WeaponCamera/Node3D
	pivot.position = pivot.position.lerp(target_pos, ads_speed * delta)

	# 5. MOVEMENT & AUTO-RUN (Platform Specific)
	var input_dir := Input.get_vector("left", "right", "up", "down")
	
	# FIX: Only run Auto-Run logic on Mobile
	if not is_pc:
		# AUTO-RUN TRIGGERS
		if input_dir.y < -0.95:
			run_hold_timer += delta
			if run_hold_timer >= auto_run_delay:
				auto_run = true
				toggle_sprint = true
		else:
			run_hold_timer = 0.0
			# Cancel if pulling back/sideways
			if input_dir.length() > 0.1:
				auto_run = false
				if input_dir.y > -0.5: toggle_sprint = false
	
	# APPLY AUTO-RUN
	if auto_run and input_dir.length() == 0:
		input_dir.y = -1.0
	
	var move_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if is_healing and input_dir != Vector2.ZERO: is_healing = false

	# BUTTON TOGGLE (Works on PC & Mobile)
	if Input.is_action_just_pressed("sprint"):
		toggle_sprint = !toggle_sprint
		if not toggle_sprint: auto_run = false
	
	# Stop logic
	if stamina <= 0:
		toggle_sprint = false
		auto_run = false
	
	# FIX: On PC, stop sprinting instantly if you stop moving
	if is_pc and move_dir.length() == 0:
		toggle_sprint = false

	if not is_sliding and not toggle_sprint:
		stamina = move_toward(stamina, max_stamina, stamina_regen * delta)
	
	# Slide Logic
	if Input.is_action_just_pressed("slide") and is_on_floor() and not is_sliding:
		if current_speed >= SPRINT_SPEED - 0.1 and stamina >= slide_cost:
			stamina -= slide_cost
			start_slide.rpc(move_dir)
	
	if is_sliding:
		current_speed = move_toward(current_speed, 0.0, SLIDE_FRICTION * delta)
		velocity.x = slide_direction.x * current_speed
		velocity.z = slide_direction.z * current_speed
		camera.position.y = lerp(camera.position.y, crouch_cam_height, 10 * delta)
		
		if current_speed < CROUCH_SPEED:
			stop_slide.rpc()
	else:
		if Input.is_action_just_pressed("crouch"): 
			wants_to_crouch = !wants_to_crouch
			if wants_to_crouch: auto_run = false
			
		var head_blocked = head_check_ray.is_colliding()
		var should_crouch = wants_to_crouch or head_blocked
		if should_crouch != is_crouched: set_crouch.rpc(should_crouch)
		
		if is_crouched:
			current_speed = CROUCH_SPEED
			camera.position.y = lerp(camera.position.y, crouch_cam_height, 10 * delta)
		else:
			if toggle_sprint and is_on_floor() and not toggle_aim and input_dir.y < 0 and stamina > 0:
				current_speed = SPRINT_SPEED
				stamina -= 10.0 * delta 
			else:
				current_speed = WALK_SPEED
			
			camera.position.y = lerp(camera.position.y, default_cam_height, 10 * delta)
			
		if move_dir:
			velocity.x = move_dir.x * current_speed
			velocity.z = move_dir.z * current_speed
			if is_on_floor() and anim_player.current_animation != "shoot" and not toggle_aim:
				anim_player.play("move")
		else:
			velocity.x = move_toward(velocity.x, 0, current_speed)
			velocity.z = move_toward(velocity.z, 0, current_speed)
			if is_on_floor() and anim_player.current_animation != "shoot" and not toggle_aim:
				anim_player.play("idle")

		if Input.is_action_just_pressed("back"):
			$Camera3D2.current = true
		if Input.is_action_just_pressed("front"):
			$Camera3D3.current = true
		if Input.is_action_just_pressed("norm"):
			$Camera3D.current = true

	move_and_slide()
	if stamina_bar: stamina_bar.value = stamina

# -------------------------------------------------------------------------
# 7. RPCs & UTILS
# -------------------------------------------------------------------------
@rpc("call_local")
func start_slide(dir: Vector3):
	is_sliding = true
	net_is_sliding = true 
	slide_direction = dir
	current_speed = SLIDE_SPEED
	if collision_node:
		collision_node.shape.height = crouch_height
		collision_node.position.y = crouch_height / 2.0
	if mesh_node:
		var tween = create_tween()
		tween.tween_property(mesh_node, "scale", Vector3(1, 0.7, 1), 0.1)

@rpc("call_local")
func stop_slide():
	is_sliding = false
	net_is_sliding = false
	if collision_node:
		collision_node.shape.height = standing_height
		collision_node.position.y = standing_height / 2.0
	if mesh_node:
		var tween = create_tween()
		tween.tween_property(mesh_node, "scale", Vector3(1, 1, 1), 0.1)
	is_crouched = false
	wants_to_crouch = false

@rpc("call_local")
func shoot() -> void:
	if anim_player:
		anim_player.stop()
		anim_player.play("shoot")
	
	target_recoil_x -= recoil_kick
	
	if current_weapon and current_weapon.shoot_sound:
		var sfx = AudioStreamPlayer3D.new()
		sfx.stream = current_weapon.shoot_sound
		sfx.pitch_scale = randf_range(0.95, 1.05)
		sfx.max_distance = 50
		gun_holder.add_child(sfx)
		sfx.play()
		sfx.finished.connect(sfx.queue_free)
	
	if is_multiplayer_authority():
		if raycast.is_colliding():
			var collider = raycast.get_collider()
			if collider and str(collider).contains("CharacterBody3D"):
				collider.receive_damage.rpc_id(
					collider.get_multiplayer_authority(),
					current_weapon.damage,
					playername
				)

@rpc("call_local")
func sync_health(new_val: int):
	health = new_val
	update_health_ui()

@rpc("any_peer","call_local")
func receive_damage(damage: int, attn: String) -> void:
	if is_dead: return
	health -= damage
	sync_health.rpc(health)
	
	if health <= 0:
		health = 200
		is_dead = true
		wants_to_crouch = false
		is_crouched = false
		stop_slide.rpc()
		set_crouch(false)
		camera.position.y = default_cam_height
		
		if is_multiplayer_authority():
			var drops = []
			for i in range(inventory.size()):
				if inventory[i]:
					drops.append({"path": inventory[i].resource_path, "ammo": ammo_in_mag[i], "is_death": true})
			if drops.size() > 0:
				get_parent().spawn_loot_request(position, drops)
			
			var pistol = load("res://Resources/Weapons/Pistol.tres")
			inventory = [pistol, null, null]
			ammo_in_mag = [pistol.clip_size, 0, 0]
			reserve_ammo = [pistol.clip_size, 0, 0]
			current_weapon = pistol
			current_slot = 0
			sync_weapon_change.rpc("res://Resources/Weapons/Pistol.tres", -1)
			equip_slot(0) 

		self.hide()
		get_parent().add_kill_feed_entry.rpc(attn, playername)
		$CanvasLayer/PauseMenu2.show()
		await get_tree().create_timer(3.0).timeout
		is_dead = false
		$CanvasLayer/PauseMenu2.hide()
		self.show()
		if is_multiplayer_authority():
			position = spawns[randi() % spawns.size()]
			health = 200
			sync_health.rpc(200)

@rpc("call_local")
func set_crouch(crouching: bool):
	if is_sliding: return
	is_crouched = crouching
	var target_height = crouch_height if crouching else standing_height
	var target_y = target_height / 2.0 
	if collision_node:
		collision_node.shape.height = target_height
		collision_node.position.y = target_y
	if mesh_node:
		var target_scale = Vector3(1, 0.7, 1) if crouching else Vector3(1, 1, 1)
		var target_pos = Vector3(0, target_y, 0)
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(mesh_node, "scale", target_scale, 0.1)
		tween.tween_property(mesh_node, "position", target_pos, 0.1)

# -------------------------------------------------------------------------
# 8. WEAPON SYNC & INVENTORY
# -------------------------------------------------------------------------

@rpc("call_local","reliable")
func sync_weapon_change(weapon_path: String, incoming_ammo: int = -1):
	var new_weapon_res = load(weapon_path)
	if not new_weapon_res: return
	
	if is_multiplayer_authority():
		var is_new_pistol = "Pistol" in weapon_path or "pistol" in weapon_path
		var target_slot = 0 if is_new_pistol else -1
		
		if target_slot == -1:
			if inventory[1] == null: target_slot = 1
			elif inventory[2] == null: target_slot = 2
			else: target_slot = current_slot if current_slot != 0 else 1
		
		var current_res = inventory[target_slot]
		if current_res != null and current_res.resource_path == new_weapon_res.resource_path:
			var ammo_to_add = incoming_ammo if incoming_ammo != -1 else new_weapon_res.clip_size
			reserve_ammo[target_slot] += ammo_to_add
			update_ammo_ui()
			return

		if inventory[target_slot] != null:
			var old_res = inventory[target_slot]
			var old_ammo = ammo_in_mag[target_slot]
			var drop_data = [{"path": old_res.resource_path, "ammo": old_ammo, "is_death": false}]
			get_parent().spawn_loot_request(position, drop_data)
		
		inventory[target_slot] = new_weapon_res
		ammo_in_mag[target_slot] = incoming_ammo if incoming_ammo != -1 else new_weapon_res.clip_size
		reserve_ammo[target_slot] = new_weapon_res.clip_size if reserve_ammo[target_slot] == 0 else reserve_ammo[target_slot]
		
		equip_slot(target_slot)
		update_ammo_ui()
	
	spawn_gun_visuals(new_weapon_res)

func equip_slot(index: int):
	if index < 0 or index >= inventory.size(): return
	
	current_slot = index
	
	if inventory[index] == null:
		current_weapon = null
		if current_gun_node: current_gun_node.queue_free()
		update_ammo_ui()
		return
	
	current_weapon = inventory[index]
	spawn_gun_visuals(current_weapon)
	sync_visual_switch.rpc(current_weapon.resource_path)
	update_ammo_ui()
	
	if "aim_position" in current_weapon: 
		current_aim_pos = current_weapon.aim_position
	else: 
		current_aim_pos = default_pos
		
	if "aim_fov" in current_weapon and current_weapon.aim_fov > 0: 
		current_aim_fov = current_weapon.aim_fov
	else: 
		current_aim_fov = default_fov

@rpc("call_local")
func sync_visual_switch(weapon_path: String):
	var res = load(weapon_path)
	spawn_gun_visuals(res)

func spawn_gun_visuals(weapon_res):
	if current_gun_node:
		current_gun_node.queue_free()
		current_gun_node = null
	
	if weapon_res and weapon_res.Weapon_Scene:
		current_gun_node = weapon_res.Weapon_Scene.instantiate()
		
		if is_multiplayer_authority():
			gun_holder.add_child(current_gun_node)
			change_layers_recursive(current_gun_node, 4)
		else:
			camera.add_child(current_gun_node)
			current_gun_node.position = Vector3(0.3, -0.25, -0.5) 
			current_gun_node.rotation = Vector3.ZERO 
			change_layers_recursive(current_gun_node, 1)

func change_layers_recursive(node, layer_number):
	if node is VisualInstance3D:
		node.set_layer_mask_value(1, false)
		node.set_layer_mask_value(2, false)
		node.set_layer_mask_value(4, false)
		node.set_layer_mask_value(layer_number, true)
	for child in node.get_children(): 
		change_layers_recursive(child, layer_number)

# -------------------------------------------------------------------------
# 9. RELOAD, GRENADE & UTILS
# -------------------------------------------------------------------------
func reload():
	if is_reloading or current_weapon == null: return
	var current_mag = ammo_in_mag[current_slot]
	var max_clip = current_weapon.clip_size
	if current_mag >= max_clip: return
	is_reloading = true
	await get_tree().create_timer(current_weapon.reload_time).timeout
	if infinite_reserves:
		ammo_in_mag[current_slot] = max_clip
	else:
		var needed = max_clip - current_mag
		var available = reserve_ammo[current_slot]
		var load_amt = min(needed, available)
		ammo_in_mag[current_slot] += load_amt
		reserve_ammo[current_slot] -= load_amt
	is_reloading = false
	update_ammo_ui()

@rpc("unreliable", "call_remote")
func update_rotation_x(angle: float): 
	synced_rotation_x = angle

@rpc("call_local")
func set_aiming(aiming: bool): 
	is_aiming_synced = aiming

func update_health_ui(): 
	if health_bar: health_bar.value = health

func update_ammo_ui(): 
	if current_weapon and current_weapon is WeaponData: 
		ammo_label.text = str(ammo_in_mag[current_slot]) + ("/ Inf" if infinite_reserves else " / " + str(reserve_ammo[current_slot]))
	else: 
		ammo_label.text = ""

func update_grenade_ui():
	pass

@rpc("any_peer", "call_local")
func request_grenade(dir: Vector3):
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	var sender = get_parent().get_node_or_null(str(sender_id))
	var spawn_pos = Vector3.ZERO
	if sender and sender.has_node("Camera3D"):
		spawn_pos = sender.get_node("Camera3D").global_position
	else:
		spawn_pos = camera.global_position
	sync_grenade_throw.rpc(dir, spawn_pos)

@rpc("call_local")
func sync_grenade_throw(dir: Vector3, spawn_pos: Vector3):
	var nade = GRENADE_SCENE.instantiate()
	get_parent().add_child(nade)
	nade.global_position = spawn_pos + Vector3(0, -0.3, 0)
	if nade is RigidBody3D: 
		nade.apply_impulse(dir * 25.0)

func update_trajectory(dir: Vector3):
	var mesh = trajectory_line.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var pos = camera.to_global(Vector3(0.2,-0.3,0.0))
	var vel = dir * throw_force
	var thickness = 0.1
	var cam_right = camera.global_transform.basis.x.normalized() * thickness
	for i in range(70):
		var delta_t = 0.03
		var new_pos = pos + (vel * delta_t)
		vel.y -= gravity * delta_t
		var space = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(pos, new_pos)
		query.collision_mask = 1 
		query.exclude = [self]
		var collision = space.intersect_ray(query)
		if collision:
			mesh.surface_add_vertex(collision.position - cam_right)
			mesh.surface_add_vertex(collision.position + cam_right)
			break 
		mesh.surface_add_vertex(new_pos - cam_right)
		mesh.surface_add_vertex(new_pos + cam_right)
		pos = new_pos
		if pos.y < -50: break
	mesh.surface_end()

func update_visuals():
	if not is_node_ready(): await ready
	var mesh = get_node_or_null("MeshInstance3D")
	if mesh:
		var material = StandardMaterial3D.new()
		material.albedo_color = player_color
		mesh.set_surface_override_material(0, material)
	var label = $Label3D
	if label:
		label.text = playername if playername != "" else "ID " + str(name)
		label.modulate = player_color

@rpc("any_peer","call_local","reliable")
func set_player_color(new_color: Color, newn : String):
	player_color = new_color
	playername = newn
	if multiplayer.is_server(): 
		sync_color.rpc(new_color, newn)
	update_visuals()

@rpc("any_peer","call_remote","reliable")
func sync_color(c:Color, n:String): 
	player_color = c
	playername = n
	update_visuals()

@rpc("call_local") 
func pickup_item(type:String, amount:int): 
	if type == "medkit": 
		medkit_count += amount
	elif type == "ammo": 
		if current_slot != -1 and current_weapon: 
			reserve_ammo[current_slot] += amount
			update_ammo_ui()
	elif type == "grenade": 
		grenade_count += amount
		update_grenade_ui()

@rpc("call_local") 
func use_medkit():
	if medkit_count <= 0 or health >= 200 or is_healing or is_reloading: return
	is_healing = true
	await get_tree().create_timer(3.0).timeout
	if is_healing == false or is_dead: return
	medkit_count -= 1
	health = min(health + 70, 200)
	sync_health.rpc(health)
	is_healing = false

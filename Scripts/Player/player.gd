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
@onready var weapon_camera: Camera3D = $Camera3D/SubViewport/SubViewport/WeaponCamera
@onready var mesh_node: MeshInstance3D = $MeshInstance3D
@onready var collision_node: CollisionShape3D = $CollisionShape3D
@onready var head_check_ray: RayCast3D = $HeadCheckRay

# -------------------------------------------------------------------------
# 2. SETTINGS & PRELOADS
# -------------------------------------------------------------------------

@export_group("Gameplay Settings")
@export var health : int = 200
@export var infinite_reserves:bool = true
@export var medkit_count:int = 1
@export var spawns: PackedVector3Array = ([
	Vector3(-18, 0.2, 0), Vector3(18, 0.2, 0), Vector3(-2.8, 0.2, -6),
	Vector3(-17,0,17), Vector3(17,0,17), Vector3(17,0,-17), Vector3(-17,0,-17)
])

@export_group("Inventory")
@export var inventory : Array[WeaponData] = [null, null]
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
const JUMP_VELOCITY = 4.5
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var last_fall_velocity = 0.0 
var default_cam_height = 1.6

var cam_rot_x : float = 0.0

# INPUT
var sensitivity : float =  0.002 
var controller_sensitivity : float =  0.005
var axis_vector : Vector2
var mouse_captured : bool = true
var synced_rotation_x : float = 0.0 
var is_pc : bool = false 

# WEAPON STATE
var current_gun_node : Node3D = null
var last_fire_time: float = 0.0
var current_slot : int = 0
var is_dead:bool = false
var is_reloading : bool = false
var is_healing : bool = false
var ammo_in_mag : Array[int] = [0,0]
var reserve_ammo : Array = [0,0]


# -------------------------------------------------------------------------
# 4. SETUP
# -------------------------------------------------------------------------
func _enter_tree() -> void:
	set_multiplayer_authority(str(name).to_int())

func _ready() -> void:
	$Camera3D/SubViewport/SubViewport/WeaponCamera/Node3D.position = Vector3(0,0,0)
	default_cam_height = camera.position.y
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
	if not is_multiplayer_authority(): 
		return
	
	camera.rotation.x = cam_rot_x
	
	if weapon_camera:
		weapon_camera.rotation.x = camera.rotation.x
		weapon_camera.global_transform = camera.global_transform
	
	if axis_vector != Vector2.ZERO:
		rotate_y(-axis_vector.x * controller_sensitivity)
		cam_rot_x -= axis_vector.y * controller_sensitivity
		cam_rot_x = clamp(cam_rot_x, -PI/2, PI/2)
	
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
	
	if Input.is_action_just_pressed("med"): 
		use_medkit.rpc()
	
	if Input.is_action_pressed("shoot") and not is_reloading and not is_healing and not is_dead:
		if current_weapon != null:
			var current_time = Time.get_ticks_msec() / 1000.0
			if current_time - last_fire_time >= current_weapon.fire_rate:
				if ammo_in_mag[current_slot] > 0:
					shoot()
					last_fire_time = current_time
				else:
					reload()

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or is_dead: return
	
	if Input.is_action_just_pressed("w1"): equip_slot(0)
	if Input.is_action_just_pressed("w2"): equip_slot(1)
	if Input.is_action_just_pressed("w3"): equip_slot(2)
	
	if Input.is_action_just_pressed("rel"): reload()
	if Input.is_action_just_pressed("respawn"): receive_damage(200, "world")

# -------------------------------------------------------------------------
# 6. PHYSICS
# -------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	
	if is_dead: 
		return
	
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	
	var input_dir := Input.get_vector("left", "right", "up", "down")
	
	var move_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	current_speed = WALK_SPEED
	
	if move_dir:
		velocity.x = move_dir.x * current_speed
		velocity.z = move_dir.z * current_speed
	else:
		velocity.x = move_toward(velocity.x,0,current_speed)
		velocity.z = move_toward(velocity.z,0,current_speed)
	
	if is_healing and input_dir != Vector2.ZERO: is_healing = false
	move_and_slide()

# -------------------------------------------------------------------------
# 7. RPCs & UTILS
# -------------------------------------------------------------------------
@rpc("call_local")
func shoot() -> void:
	ammo_in_mag[current_slot] -= 1
	update_ammo_ui()
	
	if anim_player:
		anim_player.stop()
		anim_player.play("shoot")
	
	play_shoot_effects.rpc()
	

	if raycast.is_colliding():
		var collider = raycast.get_collider()
		if collider and collider.has_method("receive_damage"):
			collider.receive_damage.rpc_id(collider.get_multiplayer_authority(), current_weapon.damage, multiplayer.get_unique_id())
			

@rpc("call_remote","unreliable")
func play_shoot_effects():
	if current_gun_node and current_gun_node.has_node("AnimationPlayer"):
		var gun_anim = current_gun_node.get_node("AnimationPlayer")
		gun_anim.stop()
		gun_anim.play("shoot")

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

func update_health_ui(): 
	if health_bar: health_bar.value = health

func update_ammo_ui(): 
	if current_weapon and current_weapon is WeaponData: 
		ammo_label.text = str(ammo_in_mag[current_slot]) + ("/ Inf" if infinite_reserves else " / " + str(reserve_ammo[current_slot]))
	else: 
		ammo_label.text = ""

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

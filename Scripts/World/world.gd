extends Node

@onready var main_menu: PanelContainer = $Menu/MainMenu
@onready var options_menu: PanelContainer = $Menu/Options
@onready var pause_menu: PanelContainer = $Menu/PauseMenu
@onready var address_entry: LineEdit = %AddressEntry
@onready var menu_music: AudioStreamPlayer = %MenuMusic
@onready var multiplayer_spawner_2: MultiplayerSpawner = $MultiplayerSpawner2

const Player = preload("res://Scenes/Player/player.tscn")
const PORT = 9999
const LOOT_SCENE = preload("res://Scenes/World/lootbox.tscn")
const EXPLOSION_SCENE = preload("res://Assets/World/explosion.tscn")


var localpn : String = "Player"
var enet_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
var selectedcolor :Color = Color.WHITE
#var ws_peer : WebSocketMultiplayerPeer = WebSocketMultiplayerPeer.new()
var paused: bool = false
var options: bool = false
var controller: bool = false
var is_mobile: bool = OS.has_feature("mobile")
@export var w1: Environment
@export var w2 : Environment
@onready var kill_feed: VBoxContainer = $Menu/KillFeed
@export var grenade_scene : PackedScene

@onready var world_environment: WorldEnvironment = $WorldEnvironment

func _unhandled_input(event: InputEvent) -> void:
	if Input.is_action_pressed("pause") and !main_menu.visible and !options_menu.visible:
		paused = !paused
	if event is InputEventJoypadMotion:
		controller = true
	elif event is InputEventMouseMotion:
		controller = false

func _process(_delta: float) -> void:
	if paused:
		$Menu/Blur.show()
		pause_menu.show()
		
		if !is_mobile and !controller:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			if !is_mobile and !controller and !main_menu.visible:
				Input.mouse_mode =  Input.MOUSE_MODE_CAPTURED

func _on_resume_pressed() -> void:
	if !options:
		$Menu/Blur.hide()
	$Menu/PauseMenu.hide()
	if !controller:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	paused = false
	
func _on_options_pressed() -> void:
	_on_resume_pressed()
	$Menu/Options.show()
	$Menu/Blur.show()
	%Fullscreen.grab_focus()
	if !controller:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	options = true

func _on_back_pressed() -> void:
	if options:
		$Menu/Blur.hide()
		if !controller:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		options = false

func ww():
	if not grenade_scene: return

	var ghost_nade = grenade_scene.instantiate()
	add_child(ghost_nade)
	
	ghost_nade.global_position = Vector3(0,-0.3,0)
	
	ghost_nade.scale = Vector3(0.5,0.5,0.5)
	
	for particle in ghost_nade.find_children("*","GPUParticles3D",true):
		particle.emitting = true
		particle.one_shot = false
		particle.amount = 1
		particle.restart()
	
	for sound in ghost_nade.find_children("*","AudioStreamPlayer3D",true):
		sound.volume_db = -80
		sound.play()
	
	get_tree().create_timer(1.0).timeout.connect(ghost_nade.queue_free)

func _ready() -> void:
	
	warmup_explosions()
	
	ResourceLoader.load_threaded_request("res://Assets/World/explosion.tscn")
	
	#ww()
	
	multiplayer_spawner_2.spawn_function = spawn_loot
	
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		print("ser")
		_on_host_button_pressedded()

func warmup_explosions():
	if not grenade_scene:
		return
	
	var ghost = grenade_scene.instantiate()
	add_child(ghost)
	ghost.global_position = Vector3(0,-100,0)
	
	var explosion = EXPLOSION_SCENE.instantiate()
	add_child(explosion)
	explosion.global_position = Vector3(0,-100,0)
	
	var all_particles = explosion.find_children("*", "GPUparticles3D", true)
	for p in all_particles:
		p.emitting = true
		p.one_shot = true
	
	await get_tree().create_timer(0.5).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	
	ghost.queue_free()
	explosion.queue_free()

func _on_host_button_pressedded():
	enet_peer.create_server(PORT)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_disconnected.connect(remove_player)
	
	#ws_peer.create_server(PORT)
	#multiplayer.multiplayer_peer = ws_peer
	#multiplayer.peer_connected.connect(add_player)
	#multiplayer.peer_disconnected.connect(remove_player)


func _on_host_button_pressed() -> void:
	localpn = %NameEdit.text if %NameEdit.text != "" else "Host"
	selectedcolor = $Menu/MainMenu/MarginContainer/VBoxContainer/ColorPickerButton.color
	main_menu.hide()
	$Menu/DollyCamera.hide()
	$Menu/Blur.hide()
	menu_music.stop()

	enet_peer.create_server(PORT)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_disconnected.connect(remove_player)
	print("serread")

	if options_menu.visible:
		options_menu.hide()

	add_player(multiplayer.get_unique_id())

	upnp_setup()

func _on_join_button_pressed() -> void:
	localpn = %NameEdit.text 
	if localpn == "":
		localpn = "Guest_" + str(randi() % 100)
	selectedcolor = $Menu/MainMenu/MarginContainer/VBoxContainer/ColorPickerButton.color
	main_menu.hide()
	$Menu/Blur.hide()
	menu_music.stop()
	
	var port_to_use = %AddressEntry2.text.to_int()
	if port_to_use == 0:
		port_to_use = PORT
	
	var address = address_entry.text
	
	#if address.begins_with("https://"):
		#address = address.replace("https://", "wss://")
	#elif not address.begins_with("ws://") and not address.begins_with("wss://"):
		#address = "wss://" + address + ":" + str(port_to_use)
	
	#ws_peer.create_client(address)
	
	enet_peer.create_client(address_entry.text, port_to_use)
	if options_menu.visible:
		options_menu.hide()
	
	#multiplayer.multiplayer_peer = ws_peer
	multiplayer.multiplayer_peer = enet_peer
	

func _on_options_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		options_menu.show()
	else:
		options_menu.hide()
		
func _on_music_toggle_toggled(toggled_on: bool) -> void:
	if !toggled_on:
		menu_music.stop()
	else:
		menu_music.play()

func add_player(peer_id: int) -> void:
	var player: Node = Player.instantiate()
	player.name = str(peer_id)
	add_child(player)
	player.set_multiplayer_authority(peer_id)
	
	
	await get_tree().process_frame
	await get_tree().process_frame
	
	if peer_id == multiplayer.get_unique_id():
		#await get_tree().process_frame
		#await get_tree().process_frame
		player.set_player_color.rpc(selectedcolor,localpn)
	
	print("sc",selectedcolor,"top",peer_id)

func remove_player(peer_id: int) -> void:
	var player: Node = get_node_or_null(str(peer_id))
	if player:
		player.queue_free()

func upnp_setup() -> void:
	var upnp: UPNP = UPNP.new()

	upnp.discover()
	upnp.add_port_mapping(PORT)

	var ip: String = upnp.query_external_address()
	if ip == "":
		$Label.text = "Failed to establish upnp connection!"
	else:
		$Label.text = "Success! Join Address: %s" % upnp.query_external_address()


func _on_fps_counter_2_toggled(toggled_on: bool) -> void:
	if toggled_on:
		world_environment.environment = w1
		get_viewport().msaa_3d = Viewport.MSAA_4X
	else:
		world_environment.environment = w2
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED


func _on_color_picker_button_color_changed(color: Color) -> void:
	selectedcolor = color
	print("mm")

@rpc("any_peer","call_local","reliable")
func add_kill_feed_entry(attacker :String, victim:String):
	var label = Label.new()
	label.text = attacker + " Killed " + victim
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = Color.RED
	
	if kill_feed:
		kill_feed.add_child(label)
		await  get_tree().create_timer(4.0).timeout
		if is_instance_valid(label):
			label.queue_free() 


func spawn_loot(data: Dictionary) -> Node:
	var loot = LOOT_SCENE.instantiate()
	loot.position = data["pos"]
	
	# Pass the LIST of weapons
	if data.has("items"):
		loot.contained_weapons = data["items"]
	# Fallback for old code (optional)
	elif data.has("weapon_path"):
		loot.contained_weapons = [data["weapon_path"]]
		
	return loot

@rpc("any_peer","call_local","reliable")
func spawn_loot_request(pos: Vector3, items_list: Array):
	if multiplayer.is_server():
		# Send the list array properly
		multiplayer_spawner_2.spawn({ "pos": pos, "items": items_list })

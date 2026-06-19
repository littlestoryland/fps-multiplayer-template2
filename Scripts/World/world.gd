extends Node

@export var battle_royale_map: PackedScene
@export var one_vs_one_map: PackedScene
@export var ctf_map: PackedScene

var current_map_instance : Node = null

# --- UI References based on your exact Scene Tree ---
@onready var menu_canvas: CanvasLayer = $Menu # The root CanvasLayer
@onready var main_menu_ui: Control = $Menu/Menu # The nested Control node holding Play, Characters, etc.
@onready var lobby_panel: Panel = $Menu/LobbyPanel
@onready var room_list_container: VBoxContainer = $Menu/LobbyPanel/VBoxContainer/ScrollContainer/RoomList
@onready var kill_feed: VBoxContainer = $Menu/KillFeed

# --- Cleaned Up UI References (2-Element Layout) ---
@onready var loading_bar: ProgressBar = $Menu/LoadingPanel/CenterContainer/LoadingBar
@onready var loading_label: Label = $Menu/LoadingPanel/CenterContainer/LoadingBar/LoadingLabel
@onready var loading_panel: Panel = $Menu/LoadingPanel

# --- Core Scene Nodes ---
@onready var menu_music: AudioStreamPlayer = %MenuMusic
@onready var multiplayer_spawner_2: MultiplayerSpawner = $MultiplayerSpawner2
@onready var world_environment: WorldEnvironment = $WorldEnvironment

# --- Preloads and Constants ---
const Player = preload("res://Scenes/Player/player.tscn")
const LOOT_SCENE = preload("res://Scenes/World/lootbox.tscn")

const PORT = 9999
const BROADCAST_PORT = 9998 

# --- Gameplay & System Variables ---
var localpn: String = "Player"
var enet_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
var selectedcolor: Color = Color.WHITE

@export var w1: Environment
@export var w2: Environment
@export var grenade_scene: PackedScene

# --- LAN Discovery Setup ---
var udp_broadcast_peer: PacketPeerUDP = PacketPeerUDP.new()
var udp_listen_peer: PacketPeerUDP = PacketPeerUDP.new()
var is_hosting_lan: bool = false
var is_scanning_lan: bool = false
var broadcast_timer: float = 0.0
var discovered_rooms: Dictionary = {} 

var current_match_map_path: String = ""
var current_game_mode: String = "1v1" 
var upnp_thread: Thread

# --- Lifecycle Hooks ---
func _ready() -> void:
	
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer_spawner_2.spawn_function = spawn_loot
	udp_broadcast_peer.set_broadcast_enabled(true)
	
	_connect_playlist_buttons()
	
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_setup_server_peer()

func _process(delta: float) -> void:
	_handle_lan_discovery(delta)

# --- Wire Up UI Interactions ---
func _connect_playlist_buttons() -> void:
	var primary_play_btn = $Menu/Menu/Play/Button
	if primary_play_btn:
		primary_play_btn.pressed.connect(_on_primary_play_pressed)
		
	$Menu/LobbyPanel/VBoxContainer/OnlineRow1/BattleRoyalBtn.pressed.connect(func(): _select_and_start_mode("BR", false,""))
	$Menu/LobbyPanel/VBoxContainer/OnlineRow1/OneVsOneBtn.pressed.connect(func(): _select_and_start_mode("1v1", false,""))
	$Menu/LobbyPanel/VBoxContainer/CtfBtn.pressed.connect(func(): _select_and_start_mode("CTF", false,""))
	
	$Menu/LobbyPanel/VBoxContainer/OfflineRow1/OfflineOneVsOneBtn.pressed.connect(func(): _select_and_start_mode("1v1", true,""))
	$Menu/LobbyPanel/VBoxContainer/OfflineRow1/FreeForAllBtn.pressed.connect(func(): _select_and_start_mode("BR", true,""))
	
	$Menu/LobbyPanel/VBoxContainer/BackToMenuBtn.pressed.connect(_on_back_to_menu_pressed)

func _on_primary_play_pressed() -> void:
	if main_menu_ui: main_menu_ui.hide()
	if lobby_panel:
		lobby_panel.show()
		_check_and_disable_online_if_no_internet()
		_start_scanning_for_lan_rooms()

func _on_back_to_menu_pressed() -> void:
	_stop_lan_operations()
	if lobby_panel: lobby_panel.hide()
	if main_menu_ui: main_menu_ui.show()

# --- Network Validation Guard ---
func _check_and_disable_online_if_no_internet() -> void:
	var local_ips = IP.get_local_addresses()
	if local_ips.size() <= 1:
		print("No active network adapter detected! Greying out online playlists.")
		$Menu/LobbyPanel/VBoxContainer/OnlineRow1/BattleRoyalBtn.disabled = true
		$Menu/LobbyPanel/VBoxContainer/OnlineRow1/OneVsOneBtn.disabled = true
		$Menu/LobbyPanel/VBoxContainer/CtfBtn.disabled = true
		$Menu/LobbyPanel/VBoxContainer/OnlineHeader.text = "ONLINE MATCHMAKING (OFFLINE)"
	else:
		$Menu/LobbyPanel/VBoxContainer/OnlineRow1/BattleRoyalBtn.disabled = false
		$Menu/LobbyPanel/VBoxContainer/OnlineRow1/OneVsOneBtn.disabled = false
		$Menu/LobbyPanel/VBoxContainer/CtfBtn.disabled = false
		$Menu/LobbyPanel/VBoxContainer/OnlineHeader.text = "ONLINE MATCHMAKING"

# --- Gameplay Routing System ---
func _select_and_start_mode(mode_name: String, is_offline: bool, passed_map_path: String) -> void:
	current_game_mode = mode_name
	localpn = %NameEdit.text if has_node("%NameEdit") and %NameEdit.text != "" else "Soldier"
	
	if has_node("Menu/Menu/Player Panel/MarginContainer/VBoxContainer/ColorPickerButton"):
		selectedcolor = get_node("Menu/Menu/Player Panel/MarginContainer/VBoxContainer/ColorPickerButton").color
	else:
		selectedcolor = Color.WHITE
		
	# 1. Figure out the correct map path
	var final_map_path = passed_map_path
	if final_map_path == "":
		var map_to_load: PackedScene = null
		match current_game_mode:
			"BR": map_to_load = battle_royale_map
			"1v1": map_to_load = one_vs_one_map
			"CTF": map_to_load = ctf_map
		if map_to_load:
			final_map_path = map_to_load.resource_path
			
	if final_map_path == "":
		print("ERROR: No map path provided!")
		return

	# Save the map path globally so incoming clients can request it
	current_match_map_path = final_map_path 

	# 2. SAFE SERVER PEER CHECK
	# Only setup the server peer if we don't have an active network connection open.
	# This prevents kicking your connected friends when transitioning out of the lobby!
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_setup_server_peer()
	
	if not is_offline:
		if typeof(upnp_thread) == TYPE_NIL or not upnp_thread.is_started():
			upnp_thread = Thread.new()
			upnp_thread.start(upnp_setup)
	
	is_hosting_lan = true
	is_scanning_lan = false
	if udp_listen_peer: 
		udp_listen_peer.close()

	# 3. Tell everyone currently sitting in your lobby to load the map
	rpc("sync_map_load_and_start", final_map_path)


# --- CLIENT HANDSHAKE SIGNALS ---

func _on_connected_to_server() -> void:
	print("Client linked up with server successfully! Requesting match state...")
	# Show the lobby or waiting menu so they aren't stuck looking at nothing
	if main_menu_ui: main_menu_ui.hide()
	if lobby_panel: lobby_panel.show() 
	
	# Ask the server: "Hey, what map are we playing right now?"
	rpc_id(1, "request_current_match_state")

func _on_connection_failed() -> void:
	print("Failed to connect to server.")
	if main_menu_ui: main_menu_ui.show()

func _on_server_disconnected() -> void:
	print("Disconnected from server.")
	# Bring the menu back smoothly if the host leaves or drops
	if current_map_instance: current_map_instance.queue_free()
	if main_menu_ui: main_menu_ui.show()
	if lobby_panel: lobby_panel.hide()


@rpc("any_peer", "call_local", "reliable")
func request_current_match_state() -> void:
	if multiplayer.is_server():
		var sender_id = multiplayer.get_remote_sender_id()
		# If a match is already actively running, force this late client to load it!
		if current_match_map_path != "":
			print("Server forcing client ", sender_id, " to sync map: ", current_match_map_path)
			rpc_id(sender_id, "sync_map_load_and_start", current_match_map_path)


# --- MAIN SYNCHRONIZED LOADING SCREEN BLOCK ---

@rpc("call_local", "authority", "reliable")
func sync_map_load_and_start(map_to_load_path: String) -> void:
	if map_to_load_path == "": return
	
	# 1. Cleanly Force UI Overlays
	if loading_panel: loading_panel.show()
	if loading_bar: loading_bar.value = 50.0 # Instant middle visual feedback
	if loading_label: loading_label.text = "LOADING ARENA..."
	
	if main_menu_ui: main_menu_ui.hide()
	if lobby_panel: lobby_panel.hide()
	if menu_music: menu_music.stop()
	
	if has_node("Main menu room"):
		get_node("Main menu room").hide()
		
	await get_tree().process_frame
	
	# 2. Drop the complex thread loop if it's freezing on mobile. 
	# Use standard safe loading to guarantee the file is fetched.
	var map_resource = load(map_to_load_path)
	if not map_resource:
		print("CRITICAL ERROR: Could not load map path: ", map_to_load_path)
		return
		
	# 3. Instantiate securely if it doesn't exist
	if not has_node("CurrentMap"):
		current_map_instance = map_resource.instantiate()
		current_map_instance.name = "CurrentMap"
		add_child(current_map_instance)
	
	if loading_bar: loading_bar.value = 100.0
	await get_tree().create_timer(0.2).timeout 
	
	# 4. Hide all canvas layers to make sure nothing blocks the camera view
	if loading_panel: loading_panel.hide()
	if menu_canvas: menu_canvas.hide()
	
	# 5. Handshake: Let the server spawn the character avatar
	rpc_id(1, "request_player_spawn", multiplayer.get_unique_id())

@rpc("any_peer", "call_local", "reliable")
func request_player_spawn(peer_id: int) -> void:
	if multiplayer.is_server():
		print("Server safely spawning player for peer ID: ", peer_id)
		add_player(peer_id)

# This tells the server to safely add the player now that their map is fully built
# --- Integrated Leave Match System (Smooth Tween Loading) ---

func leave_match_to_menu() -> void:
	if menu_canvas: menu_canvas.show()
	if main_menu_ui: main_menu_ui.hide() 
	
	if loading_panel: loading_panel.show()
	if loading_label: loading_label.text = "DISCONNECTING FROM MATCH..."
	if loading_bar: loading_bar.value = 0
		
	# SMOOTH ANIMATION: Tween from 0 to 30% smoothly over 0.5 seconds
	var load_tween = create_tween()
	load_tween.tween_property(loading_bar, "value", 30.0, 0.5).set_trans(Tween.TRANS_SINE)
	await load_tween.finished
	
	_stop_lan_operations()
	multiplayer.multiplayer_peer = null
	enet_peer = ENetMultiplayerPeer.new() 
	
	if loading_label: loading_label.text = "CLEANING MAP ASSETS..."
	
	# SMOOTH ANIMATION: Tween from 30 to 60%
	load_tween = create_tween()
	load_tween.tween_property(loading_bar, "value", 60.0, 0.5).set_trans(Tween.TRANS_SINE)
	await load_tween.finished
	
	if is_instance_valid(current_map_instance):
		current_map_instance.queue_free()
		current_map_instance = null
		
	for child in get_children():
		if child is CharacterBody3D or child.name.begins_with("loot"):
			child.queue_free()
			
	# CRITICAL FIX: Let Godot process the player deletions before touching cameras
	await get_tree().process_frame
			
	if loading_label: loading_label.text = "RELOADING MAIN MENU..."
	
	# SMOOTH ANIMATION: Tween from 60 to 90%
	load_tween = create_tween()
	load_tween.tween_property(loading_bar, "value", 90.0, 0.5).set_trans(Tween.TRANS_SINE)
	await load_tween.finished
	
	# REBUILD MENU ROOM & FORCE CAMERA
	var menu_room = get_node_or_null("Main menu room")
	if menu_room:
		menu_room.show()
		
		var cam = menu_room.get_node_or_null("DollyCamera")
		if cam:
			cam.show()
			cam.make_current() # Use make_current() to aggressively hijack the viewport

	# SMOOTH ANIMATION: Tween from 90 to 100%
	load_tween = create_tween()
	load_tween.tween_property(loading_bar, "value", 100.0, 0.3).set_trans(Tween.TRANS_SINE)
	await load_tween.finished

	if main_menu_ui: main_menu_ui.show()
	if lobby_panel: lobby_panel.hide()
	if menu_music: menu_music.play()
	
	if loading_panel: loading_panel.hide()

# --- LAN Operations ---
func _handle_lan_discovery(delta: float) -> void:
	if is_hosting_lan:
		broadcast_timer += delta
		if broadcast_timer >= 1.5:
			broadcast_timer = 0.0
			udp_broadcast_peer.set_dest_address("255.255.255.255", BROADCAST_PORT)
			var data = {"name": localpn + "'s Room", "mode": current_game_mode}
			udp_broadcast_peer.put_packet(JSON.stringify(data).to_utf8_buffer())

	if is_scanning_lan:
		while udp_listen_peer.get_available_packet_count() > 0:
			var packet_ip = udp_listen_peer.get_packet_ip()
			var packet_data = udp_listen_peer.get_packet().get_string_from_utf8()
			
			if packet_ip == "127.0.0.1" or packet_ip == "0:0:0:0:0:0:0:1": continue 
			
			var json = JSON.new()
			if json.parse(packet_data) == OK:
				var room_info = json.data
				if not discovered_rooms.has(packet_ip):
					discovered_rooms[packet_ip] = room_info
					_add_discovered_room_to_ui(packet_ip, room_info["name"], room_info["mode"])

func _start_scanning_for_lan_rooms() -> void:
	is_scanning_lan = true
	is_hosting_lan = false
	discovered_rooms.clear()
	
	for child in room_list_container.get_children():
		child.queue_free()
		
	udp_listen_peer.bind(BROADCAST_PORT)

func _add_discovered_room_to_ui(ip: String, room_name: String, mode: String) -> void:
	var btn = Button.new()
	btn.text = "  %s [%s Mode] - TAP TO JOIN" % [room_name.to_upper(), mode.to_upper()]
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 80) 
	btn.add_theme_font_size_override("font_size", 24) 
	
	var back_btn = $Menu/LobbyPanel/VBoxContainer/BackToMenuBtn
	if back_btn:
		var normal_style = back_btn.get_theme_stylebox("normal")
		var hover_style = back_btn.get_theme_stylebox("hover")
		var pressed_style = back_btn.get_theme_stylebox("pressed")
		var font_resource = back_btn.get_theme_font("font")
		
		if normal_style: btn.add_theme_stylebox_override("normal", normal_style)
		if hover_style: btn.add_theme_stylebox_override("hover", hover_style)
		if pressed_style: btn.add_theme_stylebox_override("pressed", pressed_style)
		if font_resource: btn.add_theme_font_override("font", font_resource)
	
	btn.add_theme_color_override("font_color", Color.WHITE)
	
	btn.pressed.connect(func():
		_cleanup_menu_assets()
		_stop_lan_operations()
		enet_peer.create_client(ip, PORT)
		multiplayer.multiplayer_peer = enet_peer
	)
	room_list_container.add_child(btn)

func _stop_lan_operations() -> void:
	is_hosting_lan = false
	is_scanning_lan = false
	udp_listen_peer.close()

func _cleanup_menu_assets() -> void:
	if menu_canvas: menu_canvas.hide() 
	if has_node("Main menu room/DollyCamera"): get_node("Main menu room/DollyCamera").hide() 
	menu_music.stop()

func _setup_server_peer() -> void:
	var max_players: int = 32 
	match current_game_mode:
		"1v1": max_players = 2
		"BR": max_players = 15
		"CTF": max_players = 8 
	
	enet_peer.create_server(PORT, max_players)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_disconnected.connect(remove_player)

# --- Spawning System ---
func add_player(peer_id: int) -> void:
	var player: Node = Player.instantiate()
	player.name = str(peer_id)
	add_child(player)
	player.set_multiplayer_authority(peer_id)
	
	await get_tree().process_frame
	await get_tree().process_frame
	
	if current_map_instance:
		var spawn_position: Vector3 = Vector3.ZERO
		var spawn_basis: Basis = Basis.IDENTITY
		
		if current_game_mode == "1v1":
			if multiplayer.get_unique_id() == peer_id:
				if current_map_instance.has_node("Spawn1"):
					spawn_position = current_map_instance.get_node("Spawn1").global_transform.origin
					spawn_basis = current_map_instance.get_node("Spawn1").global_transform.basis
			else:
				if current_map_instance.has_node("Spawn2"):
					spawn_position = current_map_instance.get_node("Spawn2").global_transform.origin
					spawn_basis = current_map_instance.get_node("Spawn2").global_transform.basis
					
		elif current_game_mode == "CTF":
			var all_players = multiplayer.get_peers()
			all_players.append(multiplayer.get_unique_id())
			all_players.sort()
			var player_index = all_players.find(peer_id)
			
			if player_index % 2 == 0:
				if current_map_instance.has_node("Team1Spawns"):
					var points = current_map_instance.get_node("Team1Spawns").get_children()
					var marker = points[(player_index / 2) % points.size()]
					spawn_position = marker.global_transform.origin
					spawn_basis = marker.global_transform.basis
			else:
				if current_map_instance.has_node("Team2Spawns"):
					var points = current_map_instance.get_node("Team2Spawns").get_children()
					var marker = points[((player_index - 1) / 2) % points.size()]
					spawn_position = marker.global_transform.origin
					spawn_basis = marker.global_transform.basis
					
		else: 
			if current_map_instance.has_node("SpawnPoints"):
				var points = current_map_instance.get_node("SpawnPoints").get_children()
				if points.size() > 0:
					var random_point = points[peer_id % points.size()]
					spawn_position = random_point.global_transform.origin
					spawn_basis = random_point.global_transform.basis
			elif current_map_instance.has_node("Spawn1"):
				spawn_position = current_map_instance.get_node("Spawn1").global_transform.origin
	
		player.global_transform.origin = spawn_position
		player.global_transform.basis = spawn_basis
	
	if peer_id == multiplayer.get_unique_id():
		player.set_player_color.rpc(selectedcolor, localpn)

func remove_player(peer_id: int) -> void:
	var player: Node = get_node_or_null(str(peer_id))
	if player: player.queue_free()

func _on_fps_counter_2_toggled(toggled_on: bool) -> void:
	if toggled_on:
		world_environment.environment = w1
		get_viewport().msaa_3d = Viewport.MSAA_4X
	else:
		world_environment.environment = w2
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED

@rpc("any_peer", "call_local", "reliable")
func add_kill_feed_entry(attacker: String, victim: String):
	var label = Label.new()
	label.text = attacker + " Killed " + victim
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = Color.RED
	if kill_feed:
		kill_feed.add_child(label)
		await get_tree().create_timer(4.0).timeout
		if is_instance_valid(label): label.queue_free()

func spawn_loot(data: Dictionary) -> Node:
	var loot = LOOT_SCENE.instantiate()
	loot.position = data["pos"]
	if data.has("items"): loot.contained_weapons = data["items"]
	return loot

@rpc("any_peer", "call_local", "reliable")
func spawn_loot_request(pos: Vector3, items_list: Array):
	if multiplayer.is_server():
		multiplayer_spawner_2.spawn({ "pos": pos, "items": items_list })

func upnp_setup() -> void:
	var upnp: UPNP = UPNP.new()
	var err = upnp.discover()
	if err == OK:
		upnp.add_port_mapping(PORT)
		print("UPNP Port mapping successful on Port: ", PORT)
	else:
		print("UPNP Discovery failed.")

extends StaticBody3D

@export var editor_weapon_drop: WeaponData 
@export var contained_weapons: Array = [] 
var current_weapon_name: String = "Empty"

@onready var pivot: Node3D = $Pivot
@onready var box_mesh: MeshInstance3D = $Pivot/LootBoxMesh
@onready var weapon_holder: Node3D = $Pivot/WeaponHolder

var active_tween:Tween

func _ready() -> void:
	if editor_weapon_drop:
		contained_weapons.append(editor_weapon_drop.resource_path)
	
	update_visuals()

func update_visuals():
	# 1. Clean up
	for child in weapon_holder.get_children():
		child.queue_free()
	
	# Kill any old animations to reset
	if active_tween:
		active_tween.kill()
	# (Simple way: just create a new unique one below)

	if contained_weapons.size() > 0:
		var entry = contained_weapons[0]
		var is_death_box = false
		
		# --- CHECK TYPE ---
		if typeof(entry) == TYPE_DICTIONARY:
			# Check our new flag "is_death"
			if entry.has("is_death") and entry["is_death"] == true:
				is_death_box = true
			else:
				is_death_box = false
		else:
			# Strings (Editor placed) are always Guns
			is_death_box = false
		
		# --- VISUALS ---
		if is_death_box:
			# SHOW BOX, HIDE GUN, NO SPIN
			box_mesh.show()
			weapon_holder.hide()
			
			# Just static placement (maybe reset rotation)
			pivot.rotation = Vector3.ZERO
			
			var res = load(entry["path"])
			if res: current_weapon_name = "Loot: " + res.name
			
		else:
			# SHOW GUN, HIDE BOX, SPIN!
			box_mesh.hide()
			weapon_holder.show()
			
			# Start Spinning Animation
			active_tween = create_tween().set_loops().set_parallel(true)
			active_tween.tween_property(pivot, "rotation:y", deg_to_rad(360), 4.0).as_relative()
			# Bobbing
			var tween_bob = create_tween().set_loops()
			tween_bob.tween_property(pivot, "position:y", 0.2, 1.0).as_relative().set_trans(Tween.TRANS_SINE)
			tween_bob.tween_property(pivot, "position:y", -0.2, 1.0).as_relative().set_trans(Tween.TRANS_SINE)

			# Load Model
			var path = ""
			if typeof(entry) == TYPE_DICTIONARY: path = entry["path"]
			else: path = str(entry)
			
			var res = load(path)
			if res:
				current_weapon_name = res.name 
				if res.Weapon_Scene:
					var model = res.Weapon_Scene.instantiate()
					weapon_holder.add_child(model)
					model.scale = Vector3(1.5, 1.5, 1.5)
	else:
		queue_free()

func interact(player_node):
	if contained_weapons.size() > 0:
		var entry = contained_weapons[0]
		
		var path_to_give = ""
		
		if typeof(entry) == TYPE_DICTIONARY:
			path_to_give = entry["path"]
		else:
			path_to_give = str(entry)
		
		player_node.equip_weapon.rpc(path_to_give)
		queue_free()
		#contained_weapons.remove_at(0)
		#update_visuals()

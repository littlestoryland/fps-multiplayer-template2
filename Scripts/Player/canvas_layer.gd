extends CanvasLayer

@onready var player: CharacterBody3D = find_player_node() # Gets the player script



func find_player_node() -> CharacterBody3D:
	var current = get_parent()
	while current and not current is CharacterBody3D:
		current= current.get_parent()
	return current

func _ready() -> void:
	# Connect your buttons to these functions in the inspector, 
	# or do it via code right here:
	$ColorRect/CenterContainer/VBoxContainer/HBoxContainer/PanelContainer/VBoxContainer/EquipLightRifle.pressed.connect(_on_light_rifle_selected)
	$ColorRect/CenterContainer/VBoxContainer/HBoxContainer/PanelContainer2/VBoxContainer/EquipAssaultRifle.pressed.connect(_on_assault_rifle_selected)
	$ColorRect/CenterContainer/VBoxContainer/HBoxContainer/PanelContainer3/VBoxContainer/EquipHeavyRifle.pressed.connect(_on_heavy_rifle_selected)
	
	# (Add your third button here for the Heavy Rifle!)

func _on_light_rifle_selected():
	# Pass the Light Rifle resource and the default Pistol resource
	player.confirm_loadout_choice("res://Resources/Weapons/Light Rifle.tres", "res://Resources/Weapons/Pistol.tres")

func _on_assault_rifle_selected():
	# Pass the Assault Rifle resource and the default Pistol resource
	player.confirm_loadout_choice("res://Resources/Weapons/Assault Rifle.tres", "res://Resources/Weapons/Pistol.tres")

func _on_heavy_rifle_selected():
	# Pass the Heavy Rifle resource and the default Pistol resource
	player.confirm_loadout_choice("res://Resources/Weapons/Heavy Rifle.tres", "res://Resources/Weapons/Pistol.tres")

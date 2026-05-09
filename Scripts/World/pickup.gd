extends StaticBody3D

@export_enum("medkit","ammo","grenade") var item_type:String ="medkit"
@export var amount: int = 1
@export var item_name : String = "Medkit"

func interact(player_node):
	player_node.pickup_item.rpc(item_type,amount)
	
	queue_free_network.rpc()

@rpc("call_local")
func queue_free_network():
	queue_free()
	
var current_weapon_name: String:
	get:
		return item_name

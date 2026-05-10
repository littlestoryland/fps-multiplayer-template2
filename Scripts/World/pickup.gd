extends StaticBody3D

@export_enum("medkit","ammo") var item_type:String ="medkit"
@export var amount: int = 1
@export var item_name : String = "Medkit"

func interact(player_node):
	player_node.pickup_item.rpc(item_type,amount)
	destroy_item.rpc_id(1)

@rpc("any_peer","call_local","reliable")
func destroy_item():
	if not multiplayer.is_server():
		return
	
	force_delete_on_clients.rpc(self.name)

@rpc("authority","call_local","reliable")
func force_delete_on_clients(node_name:String):
	if self.name == node_name:
		queue_free()

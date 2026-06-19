extends Resource
class_name WeaponData

@export_group("Stats")
@export var name : String = "Pistol"
@export var damage : int = 45
@export var fire_rate : float = 0.2
@export var is_automatic : bool = false

@export var clip_size: int = 30
@export var reload_time : float = 1.5

@export_group("Visuals")
@export var weapon_icon: Texture2D
@export var Weapon_Scene : PackedScene
@export var shoot_sound : AudioStream

@export_group("Aiming")
@export var aim_position : Vector3 = Vector3(-0.5,0.12,0.0)
@export var aim_fov : float = 50

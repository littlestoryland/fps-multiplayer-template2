extends Panel

@export var FOLLOW_OBJECT : NodePath
@onready var PLAYER = get_node(FOLLOW_OBJECT)

@export var SIZE = 20.0
@export var HEIGHT = 30
@export var ALLOW_ROTATION : bool

@onready var CAMERA = $SubViewportContainer/SubViewport/Camera3D


func _ready():
	CAMERA.size = SIZE


func _physics_process(delta):
	if PLAYER:
		CAMERA.position = Vector3(PLAYER.position.x, HEIGHT, PLAYER.position.z)
		
		if ALLOW_ROTATION:
			CAMERA.rotation.y = PLAYER.rotation.y
			

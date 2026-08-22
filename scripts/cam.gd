extends Camera3D

@onready var aim : Node3D = get_parent().get_parent()
@onready var aim2 : Node3D = aim.get_parent()
@export var sense : float = 0.01
@export var limit : float = PI/2

func _ready() -> void:
	pass

func _physics_process(_delta: float) -> void:
	if projection == PROJECTION_ORTHOGONAL:
		size = position.z

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		var drag = -event.relative * sense
		aim.rotation.x = lerp_angle(aim.rotation.x, clamp(aim.rotation.x + drag.y,-limit,limit),0.5)
		aim2.rotation.y = lerp_angle(aim2.rotation.y, aim2.rotation.y + drag.x, 0.5)

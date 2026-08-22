extends CharacterBody3D
class_name Soul

@onready var ism : StateMachine = $"StateMachine"
@export var controlled : CharacterBody3D

func _physics_process(_delta: float) -> void:
	if controlled and controlled != self:
		set_collision_mask_value(1, false)
		global_transform.origin = controlled.global_transform.origin
	elif controlled == self:
		controlled = null
	elif controlled == null:
		set_collision_mask_value(1,true)

extends CharacterBody3D
class_name Soul

@onready var mesh : MeshInstance3D = $"Soul"
@onready var col : CollisionShape3D = $"CollisionShape3D"
@onready var ism : StateMachine = $"StateMachine"
@export var controlled : CharacterBody3D
@onready var material : ShaderMaterial = mesh.get_active_material(0)

func _physics_process(_delta: float) -> void:
	if controlled and controlled != self:
		set_collision_mask_value(1, false)
		col.disabled = true
		material.set_shader_parameter("force_visible", false)
		global_transform.origin = controlled.global_transform.origin
	elif controlled == self:
		controlled = null
	elif controlled == null:
		set_collision_mask_value(1,true)
		col.disabled = false
		material.set_shader_parameter("force_visible", true)

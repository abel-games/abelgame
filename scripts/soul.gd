extends CharacterBody3D
class_name Soul


@onready var mesh: MeshInstance3D = $"Soul"
@onready var col: CollisionShape3D = $"CollisionShape3D"

@export var controlled: CharacterBody3D
@export var gravity: float = 9.8

@onready var material: ShaderMaterial = mesh.get_active_material(0)
var speed := 0.04
var rotation_speed := 8.0

func _physics_process(delta: float) -> void:
	if controlled and controlled != self:
		_controlled_mode()
	else:
		_normal_mode(delta)


func _controlled_mode() -> void:
	#Transferir velocidad
	speed = controlled.speed
	
	# Transferir movimiento xz
	controlled.velocity.x = velocity.x
	controlled.velocity.z = velocity.z
	
	#Gravedad
	controlled.velocity += get_gravity()
	
	# Transferir rotación
	controlled.rotation = rotation
	
	# Soul no tiene física propia
	velocity = Vector3.ZERO

	# Seguir visualmente al objetivo
	global_transform = controlled.global_transform

	# Display
	set_collision_mask_value(1, false)
	col.disabled = true
	material.set_shader_parameter("force_visible", false)


func _normal_mode(delta: float) -> void:
	# Física normal
	set_collision_mask_value(1, true)
	col.disabled = false
	material.set_shader_parameter("force_visible", true)

	if not is_on_floor():
		velocity.y -= gravity * delta

	move_and_slide()

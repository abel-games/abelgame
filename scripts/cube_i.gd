extends Interactable

@onready var parent_object = get_parent()

@onready var camera: Camera3D = get_viewport().get_camera_3d()

@export var impulse_strength: float = 10.0

func interact(hit: Dictionary) -> void:
	var event_position: Vector3 = hit.position
	var dir: Vector3 = (event_position - camera.global_position).normalized()

	parent_object.apply_force(
		dir * impulse_strength,
		event_position - parent_object.global_position
	)

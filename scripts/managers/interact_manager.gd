@icon("res://interactmanager.svg")
extends Node
class_name InteractManager

@onready var camera = get_viewport().get_camera_3d()
@onready var world3d = get_viewport().find_world_3d().direct_space_state

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			var origin = camera.project_ray_origin(event.position)
			var normal = camera.project_ray_normal(event.position)
			var end = origin + 100.0 * normal
			var queue = PhysicsRayQueryParameters3D.create(origin, end)
			var hit = world3d.intersect_ray(queue)
			if hit.is_empty():
				return
			var collider = hit.collider
			for child in collider.get_children():
				if child is Interactable:
					child.interact(hit)
			#EXPAND Puede expandir o mejorar (ABEL)

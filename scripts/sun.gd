extends DirectionalLight3D

@export var velocity : float = 0.01
var counter : float = 0.0

func _physics_process(delta: float) -> void:
	counter += delta
	if counter >= 1.0:
		rotate_x(velocity * delta)

extends FSMState
class_name Idle

func enter() -> void:
	pass

func exit() -> void:
	pass

func process(delta : float) -> void:
	if Input.get_vector("gm_left","gm_right","gm_down","gm_up") != Vector2.ZERO:
		fsm.change_state("Walk")
	else:
		controlled.velocity.x = move_toward(controlled.velocity.x, 0.0, delta)
		controlled.velocity.z = move_toward(controlled.velocity.z, 0.0, delta)

func physics(_delta : float) -> void:
	pass

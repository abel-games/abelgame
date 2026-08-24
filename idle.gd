extends FSMState
class_name Idle

func enter() -> void:
	pass

func exit() -> void:
	pass

func process(_delta : float) -> void:
	if Input.get_vector("gm_left","gm_right","gm_down","gm_up") != Vector2.ZERO:
		fsm.change_state("Walk")

func physics(_delta : float) -> void:
	pass

extends FSMState

@onready var aim = $"../../../Aim"

func enter() -> void:
	pass

func exit() -> void:
	pass

func process(_delta : float) -> void:
	pass

func physics(delta : float) -> void:
	var mv : Vector2 = Input.get_vector("gm_left","gm_right","gm_up","gm_down")
	if mv == Vector2.ZERO:
		fsm.change_state("Idle")
		return
	var mv3d : Vector3 = Vector3(mv.x, 0.0, mv.y)
	var basis : Basis = aim.global_transform.basis
	var total : Vector3 = basis * mv3d * controlled.speed
	controlled.velocity.x = total.x
	controlled.velocity.z = total.z
	var dir : Vector3 = basis * mv3d
	var bas : Basis = Basis.looking_at(dir, Vector3.UP)
	var quat : Quaternion = bas.get_rotation_quaternion()
	controlled.quaternion = controlled.quaternion.slerp(quat, controlled.rotation_speed * delta)

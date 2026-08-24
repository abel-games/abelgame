extends FSMState

@onready var aim = $"../../../Aim"

func enter() -> void:
	pass

func exit() -> void:
	pass

func process(_delta : float) -> void:
	pass

func physics(delta : float) -> void:
	var mv : Vector2 = Input.get_vector("gm_right","left","gm_down","gm_up")
	var mv3d : Vector3 = Vector3(mv.x, 0.0, mv.y)
	var basis : Basis = aim.transform.basis
	controlled.velocity = mv3d * controlled.speed * delta * basis

extends OmniLight3D

@onready var sun : DirectionalLight3D = $"../../../Sun"

func _process(_delta: float) -> void:
	var foward = -sun.global_basis.z
	var dot = foward.dot(Vector3.UP)
	if dot >= 0.0:
		visible = true
	else:
		visible = false

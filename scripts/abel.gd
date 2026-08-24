extends CharacterBody3D
class_name Abel

enum SoulMode {
	NORMAL,
	ALERT,
	ANALYSIS
}

var soul_mesh : MeshInstance3D
@export var soul: Soul
@onready var front: ColorRect = $"../../CanvasLayer/Front"
@onready var mesh: MeshInstance3D = $"Mesh"
@onready var mesh2: MeshInstance3D = $"Mesh/Eyes"
@onready var aim: Node3D = $"../Aim"
@export var mode: SoulMode = SoulMode.NORMAL

var speed := 160.0
var JUMP_VELOCITY := 12.0
const MASS := 2.0
var ROTATION_SPEED := 0.1

var old_mode: int = SoulMode.NORMAL

func _ready() -> void:
	soul_mesh = soul.get_child(0)

func _state_machine_do() -> void:
	pass

func _physics_process(_delta: float) -> void:
	_state_machine_do()
	_display(old_mode,mode)
	move_and_slide()
	old_mode = mode
func _display(old, new) -> void:
	if old == new:
		return
	
	var matsoul : ShaderMaterial = soul_mesh.mesh.surface_get_material(0)
	var mat : ShaderMaterial = mesh.mesh.surface_get_material(0)
	var mat2 : ShaderMaterial = mesh2.mesh.surface_get_material(0)
	
	var outline_mat : ShaderMaterial = mesh.material_overlay
	var outline_mat2 : ShaderMaterial = mesh2.material_overlay
	
	var target_soul := 0.0
	var target_albedo := 0.0
	var target_light := 0.0
	var target_outline := Vector3.ZERO
	var target_rect := 0.0

	match new:
		SoulMode.NORMAL:
			target_soul = 0.0
			target_albedo = 0.0
			target_light = 0.0
			target_outline = Vector3(0.0, 0.0, 0.0)
			target_rect = 0.0

		SoulMode.ALERT:
			target_soul = 1.0
			target_albedo = 1.0
			target_light = 1.0
			target_outline = Vector3(1.0, 0.0, 0.0)
			target_rect = 0.1

		SoulMode.ANALYSIS:
			target_soul = 1.0
			target_albedo = 0.0
			target_light = -1.0
			target_outline = Vector3(1.0, 1.0, 1.0) * 2.0
			target_rect = 0.75


	var tween := create_tween()


	# Material principal
	var current_albedo: float = mat.get_shader_parameter("shader_lerp")
	var current_light: float = mat.get_shader_parameter("light_mode")
	#Material del Rect
	var current_rect: float = front.color.a
	#Material del Soul
	var current_soul: float = matsoul.get_shader_parameter("a")
	
	tween.parallel().tween_method(func(value):
		matsoul.set_shader_parameter("a",value)
		, current_soul, target_soul, 1.0)
	
	tween.parallel().tween_method(func(value):
		mat.set_shader_parameter("shader_lerp", value),
		current_albedo,
		target_albedo,
		1.0
	)

	tween.parallel().tween_method(func(value):
		mat.set_shader_parameter("light_mode", value),
		current_light,
		target_light,
		1.0
	)


	# Material ojos
	current_albedo = mat2.get_shader_parameter("shader_lerp")
	current_light = mat2.get_shader_parameter("light_mode")

	tween.parallel().tween_method(func(value):
		mat2.set_shader_parameter("shader_lerp", value),
		current_albedo,
		target_albedo,
		1.0
	)

	tween.parallel().tween_method(func(value):
		mat2.set_shader_parameter("light_mode", value),
		current_light,
		target_light,
		1.0
	)


	# Outline cuerpo
	var current_outline: Vector3 = outline_mat.get_shader_parameter("outline_color")

	tween.parallel().tween_method(func(value):
		outline_mat.set_shader_parameter("outline_color", value),
		current_outline,
		target_outline,
		1.0
	)


	# Outline ojos
	current_outline = outline_mat2.get_shader_parameter("outline_color")

	tween.parallel().tween_method(func(value):
		outline_mat2.set_shader_parameter("outline_color", value),
		current_outline,
		target_outline,
		1.0
	)
	#ColorRect Cambio
	tween.parallel().tween_method(func(value):
		front.color.a = value
		,current_rect, target_rect, 1.0)

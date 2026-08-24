extends Node
class_name StateMachine


var states : Dictionary[String, FSMState] = {}
@export var actual : FSMState

func _ready() -> void:
	actual.enter()
	for child in get_children():
		var child_name : String = child.name
		if child is FSMState:
			states[child_name] = child
			child.fsm = self
			child.controlled = owner

func _process(delta: float) -> void:
	actual.process(delta)

func _physics_process(delta: float) -> void:
	actual.physics(delta)

func change_state(new_state : String) -> void:
	var new : FSMState = states[new_state]
	actual.exit()
	actual = new
	actual.enter()

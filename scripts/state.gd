@abstract class_name FSMState
extends Node

var fsm : StateMachine
var controlled : Node

@abstract func enter() -> void

@abstract func exit() -> void

@abstract func process(delta : float) -> void

@abstract func physics(delta : float) -> void

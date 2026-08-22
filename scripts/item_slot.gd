extends Control
class_name ItemSlot

@onready var normal : TextureRect = $"False"
@onready var pressed : TextureRect = $"True"
var on : bool
signal change(this : Node, state : bool)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			on = not on
			normal.visible = on
			pressed.visible = not on
			change.emit(self, on)

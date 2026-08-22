extends LineEdit


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			grab_focus()

func _exited() -> void:
	release_focus()
	clear()

func _ready() -> void:
	focus_exited.connect(Callable(self,"_exited"))

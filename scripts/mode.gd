extends Button

@onready var player : Abel = $"../../../World3D/Abel"

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			player.mode = player.SoulMode.ANALYSIS if player.mode == player.SoulMode.NORMAL else player.SoulMode.NORMAL

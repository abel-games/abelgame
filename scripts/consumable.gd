extends Item
class_name Consumable


func action_on() -> void:
	queue_free()

func _process(_delta: float) -> void:
	_update_item()

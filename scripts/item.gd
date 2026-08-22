@abstract class_name Item
extends RigidBody3D

@export var itemdata: ItemData
@export var max_cantity : int = 64:
	set(value):
		if value >= 1:
			max_cantity = value
		else:
			max_cantity = 1
	get:
		return max_cantity
@export var cantity : int = 64:
	set(value):
		if value >= 0 and value < max_cantity:
			cantity = value
		else:
			cantity = clampi(cantity, 0, max_cantity)
	get:
		return cantity

@abstract func action_on() -> void
func use_action() -> void:
	if not itemdata.unusable and not itemdata.blocked:
		action_on()

func set_data(key : String, val : Variant) -> void:
	if key in itemdata:
		itemdata[key] = val

func get_data(key : String) -> Variant:
	return itemdata.get(key)

func _update_item() -> void:
	if itemdata.durability <= 0 and not itemdata.unbreakable:
		queue_free()

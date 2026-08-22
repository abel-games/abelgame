@icon("res://itemdata_icon.svg")
extends Resource
class_name ItemData

enum ItemType {
	GENERAL,
	FOOD,
	WEAPON,
	POWERFUL
}

@export var id : StringName = "gm:none"
@export var name : String = "None"
@export_group("Display")
@export var color_name : Color
@export var type : ItemType = ItemType.GENERAL
@export_group("Physics")
@export var durability : int = 1000
@export var max_durability : int = 1000
@export_group("Flags")
@export var unbreakable : bool
@export var unusable : bool
@export var blocked : bool
@export var undropable : bool
@export var effects : Array

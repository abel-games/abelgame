extends HBoxContainer
@onready var nd : Array[Node] = get_children()

var selitem : ItemSlot = null
var items : Array[ItemSlot] = []

func _change_item(this : ItemSlot, state : bool) -> void:
	this.normal.visible = false
	this.pressed.visible = true
	this.on = true
	for item in items:
		if item != this:
			item.normal.visible = true
			item.pressed.visible = false
			item.on = false
	if not state:
		if this == selitem:
			this.normal.visible = true
			this.pressed.visible = false
			this.on = false
			selitem = null
		return
	if state:
		this.normal.visible = false
		this.pressed.visible = true
		this.on = true
		selitem = this

func _ready() -> void:
	for item in nd:
		if item is ItemSlot:
			items.append(item)
	for item in items:
		item.connect("change", _change_item)

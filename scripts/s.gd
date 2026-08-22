extends MeshInstance3D

@onready var h : HTTPRequest = $HTTPRequest

func _ready() -> void:
	var error = h.request("https://significado.com/wp-content/uploads/planicie.jpg")
	if error != OK:
		push_error("chale no funciona")


@warning_ignore("unused_parameter")
func _on_http_request_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("no hay nada tmr")
	var img := Image.new()
	var error := img.load_jpg_from_buffer(body)
	if error != OK:
		push_error("ni es jpg")
		return
	var it := ImageTexture.create_from_image(img)
	var mt := StandardMaterial3D.new()
	mt.albedo_texture = it
	mesh.surface_set_material(0,mt)
	
	
#a

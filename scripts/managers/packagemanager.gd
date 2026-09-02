@icon("res://assets/icon/packagemanager.svg")
extends Node
class_name PackageManager

@export var console_manager : ConsoleManager
@export var packages : Array[NodePath] = []


@onready var hr: HTTPRequest = $HR

@export var package_url: Dictionary = {
	"foo": "https://raw.githubusercontent.com/huamancabanillasabelmoises3-ctrl/abconsolefoo/main/package.json"
}

func _ready() -> void:
	var pdata = {
		"cm" : console_manager,
		"rfm" : console_manager.route_file_manager
	}
	for package in packages:
		var node := get_node(package)
		if node:
			(node as PackedPackage).give_data(pdata)

func output(value: Variant) -> void:
	console_manager.console_output(str(value))

func get_url_package(pkg: String) -> String:
	var url = package_url.get(pkg)

	if url == null:
		return ""

	return str(url)

func search_package(pkg : String) -> Variant:
	var data = await _fetch_package(pkg)
	if not data:
		output("[ERROR] No se pudo buscar el paquete")
		return
	_display_package(data)
	return data

func _fetch_package(pkg: String) -> Variant:
	var url := get_url_package(pkg)

	if url.is_empty():
		output("[ERROR] Package not found: " + pkg)
		return null

	var error := hr.request(url)

	if error != OK:
		output("[ERROR] Could not connect to package.")
		return null

	var response = await hr.request_completed

	var result: int = response[0]
	var response_code: int = response[1]
	var body: PackedByteArray = response[3]

	if result != HTTPRequest.RESULT_SUCCESS:
		output("[ERROR] Connection error.")
		return null

	if response_code < 200 or response_code >= 300:
		output("[ERROR] HTTP " + str(response_code))
		return null

	var data = JSON.parse_string(body.get_string_from_utf8())

	if data == null or not data is Dictionary:
		output("[ERROR] Invalid package.json.")
		return null

	return data

func _display_package(data: Dictionary):
	output("")
	output("========== PACKAGE ==========")

	if data.has("name"):
		output("Package Name : " + str(data["name"]))

	if data.has("version"):
		output("Version      : " + str(data["version"]))

	if data.has("description"):
		output("Description  : " + str(data["description"]))

	if data.has("author"):
		output("Author       : " + str(data["author"]))

	output("==============================")

	return data

func test_save_package() -> void:
	var dir := "user://packages/foo"

	var error := DirAccess.make_dir_recursive_absolute(dir)

	if error != OK:
		output("No se pudo crear la carpeta: " + dir)
		return

	var file := FileAccess.open(
		dir + "/dontdelete.txt",
		FileAccess.WRITE
	)

	if file == null:
		output("No se pudo crear dontdelete.txt")
		return

	file.store_string(
		"Archivo de prueba este txt se genera para comprobar que el sistema de guardado funciona PORFAVOR no elimine esto en ejecución si no quieres que tu juego crashee o trate de reiniciar pensando que el sistema fallo"
	)

	file.close()

	output("Paquete guardado correctamente en: " + dir)



func _handle_search_result(
	result: int,
	response_code: int,
	body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		output("No se pudo obtener el paquete. Error de conexión.")
		return

	if response_code < 200 or response_code >= 300:
		output("El servidor respondió con HTTP " + str(response_code))
		return

	var text := body.get_string_from_utf8()
	var data = JSON.parse_string(text)

	if data == null:
		output("El package.json no contiene JSON válido.")
		return

	if not data is Dictionary:
		output("El package.json debe contener un objeto JSON.")
		return

	output(data)

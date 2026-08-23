@icon("res://assets/routefilemanager.svg")
extends Node
class_name RouteFileManager


@export var console_manager: ConsoleManager
@export var extensions: Array[String] = [
	"tscn",
	"scn",
	"png",
	"jpg",
	"jpeg",
	"svg",
	"tres",
	"res",
	"mp3",
	"ogg",
	"wav"
]

## Nodo utilizado como Home (~).
@export var home: Node

## Representación lógica de la ruta actual.
## Puede representar un NodePath, res://, user:// o ~.
@onready var logical_route: String = "~"


## Devuelve el nodo utilizado como Home.
func get_home() -> Variant:
	if home != null:
		return home

	return self


## Devuelve la representación física de la ruta actual.
func get_physical_route() -> String:
	var parts := logical_route.split("/")
	var physical_parts: Array[String] = []

	for part in parts:
		if part == "~":
			physical_parts.append(str(get_home().get_path()))
		else:
			physical_parts.append(part)

	return "/".join(physical_parts)


## Devuelve el objeto correspondiente a la ruta actual.
func get_actual_route() -> Variant:
	return resolve_route(logical_route, get_home())


## Carga un archivo, recurso o nodo a partir de una ruta.
func execute_load(args: Array) -> Variant:
	if args.is_empty():
		output("[ERROR] Se requiere mínimo 1 argumento: load [RUTA]")
		return null

	var reference := str(args[0]).strip_edges()

	if reference.is_empty():
		output("[ERROR] La ruta no puede estar vacía")
		return null

	var route = resolve_route(reference, null)

	if route == null:
		output("[ERROR] Ruta no encontrada: " + reference)
		return null

	if route is Node:
		return route

	if route is String:
		return _load_file(route)

	return route


## Carga el contenido de un archivo según su extensión.
func _load_file(path: String) -> Variant:
	if DirAccess.dir_exists_absolute(path):
		output("[ERROR] La ruta es un directorio: " + path)
		return null

	if not FileAccess.file_exists(path):
		output("[ERROR] Archivo no encontrado: " + path)
		return null

	var extension := path.get_extension().to_lower()

	if extension in extensions:
		var resource := load(path)

		if resource == null:
			output(
				"[ERROR] No se pudo cargar el recurso: "
				+ path
			)
			return null

		return resource

	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		output(
			"[ERROR] No se pudo abrir el archivo: "
			+ path
		)
		return null

	var text := file.get_as_text()
	file.close()

	return text


## Cambia la ruta actual.
## Admite:
## ~                  → Home
## ..                 → directorio/nodo padre
## /root/...          → NodePath absoluto
## res://...          → filesystem
## user://...         → filesystem
## nombre             → ruta relativa al contexto actual
func execute_cd(args: Array) -> Variant:
	if args.is_empty():
		return get_actual_route()

	var reference := str(args[0]).strip_edges()

	if reference.is_empty():
		return get_actual_route()

	# Volver al Home.
	if reference == "~":
		logical_route = "~"
		return get_home()

	var current = get_actual_route()

	# Navegación para Nodes.
	if current is Node:
		var current_node: Node = current

		if reference == "..":
			var parent := current_node.get_parent()

			if parent == null:
				return current_node

			if parent == get_home():
				logical_route = "~"
			else:
				logical_route = str(parent.get_path())

			return parent

		var target: Node = current_node.get_node_or_null(reference)

		if target != null:
			logical_route = str(target.get_path())
			return target

	# Navegación para filesystem.
	if current is String:
		var current_path := str(current)

		if reference == "..":
			var parent_path := current_path.get_base_dir()

			# Evitamos subir fuera de res:// o user://.
			if (
				current_path.begins_with("res://")
				and parent_path == "res:/"
			):
				parent_path = "res://"

			if (
				current_path.begins_with("user://")
				and parent_path == "user:/"
			):
				parent_path = "user://"

			logical_route = parent_path
			return parent_path

		var filesystem_target := current_path.path_join(reference)
		filesystem_target = filesystem_target.simplify_path()

		if _is_filesystem_path(filesystem_target):
			if DirAccess.dir_exists_absolute(filesystem_target):
				logical_route = filesystem_target
				return filesystem_target

			output(
				"[ERROR] No es un directorio: "
				+ filesystem_target
			)
			return null

	# Intentar resolver una ruta absoluta.
	var resolved = resolve_route(reference, null)

	if resolved == null:
		output("[ERROR] Ruta no encontrada: " + reference)
		return null

	# cd solo acepta destinos navegables.
	if resolved is Node:
		logical_route = str(resolved.get_path())
		return resolved

	if resolved is String:
		if not DirAccess.dir_exists_absolute(resolved):
			output("[ERROR] No es un directorio: " + reference)
			return null

		logical_route = resolved
		return resolved

	output("[ERROR] La referencia no es navegable")
	return null


## Lista el contenido de la ruta actual o de una ruta especificada.
func execute_ls(args: Array) -> Variant:
	var target: Variant

	if args.is_empty():
		target = get_actual_route()
	else:
		target = resolve_route(str(args[0]), null)

	if target == null:
		output("[ERROR] Ruta no encontrada")
		return null

	# Listar hijos de un Node.
	if target is Node:
		var node: Node = target
		var children: Array = node.get_children()

		for child in children:
			output(str(child.name))

		return children

	# Listar archivos/directorios.
	if target is String:
		var path := str(target)

		if not DirAccess.dir_exists_absolute(path):
			output("[ERROR] No es un directorio: " + path)
			return null

		var directory := DirAccess.open(path)

		if directory == null:
			output("[ERROR] No se pudo abrir: " + path)
			return null

		var entries: Array[String] = []

		directory.list_dir_begin()

		while true:
			var entry := directory.get_next()

			if entry.is_empty():
				break

			if directory.current_is_dir():
				entries.append(entry + "/")
			else:
				entries.append(entry)

		directory.list_dir_end()

		for entry in entries:
			output(entry)

		return entries

	output("[ERROR] La ruta no puede ser listada")
	return null


## Devuelve la ruta textual actual.
##
## Opciones:
## -L, --logical  → devuelve la ruta lógica. Es la opción por defecto.
## -P, --physical → devuelve la ruta física.
func execute_pwd(args: Array) -> Variant:
	var use_physical := false

	if not args.is_empty():
		var option := str(args[0]).strip_edges()

		match option:
			"-L", "--logical":
				use_physical = false

			"-P", "--physical":
				use_physical = true

			_:
				output("[ERROR] Opción desconocida: " + option)
				return null

	if use_physical:
		var physical_route := get_physical_route()

		if physical_route.is_empty():
			output("[ERROR] No se pudo resolver la ruta física")
			return null

		output(physical_route)
		return physical_route

	output(logical_route)
	return logical_route


## Envía texto al canal de salida.
## Más adelante puede convertirse en una señal conectada a ConsoleManager.
func output(text: String) -> void:
	console_manager.console_output(text)


## Resuelve una referencia sin ejecutarla ni cargarla.
## Devuelve un Node o una ruta de filesystem.
func resolve_route(
	reference: String,
	fallback: Variant = null
) -> Variant:
	var route := reference.strip_edges()

	if route.is_empty():
		return fallback

	# Home.
	if route == "~":
		return get_home()

	# Intentar resolver un NodePath.
	var node := get_node_or_null(NodePath(route))

	if node != null:
		return node

	# Intentar resolver un archivo o directorio.
	if _is_filesystem_path(route):
		return route

	return fallback


## Comprueba si la ruta pertenece al filesystem del juego.
func _is_filesystem_path(path: String) -> bool:
	if not (
		path.begins_with("res://")
		or path.begins_with("user://")
	):
		return false

	return (
		FileAccess.file_exists(path)
		or DirAccess.dir_exists_absolute(path)
	)

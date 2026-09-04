@icon("res://assets/icon/consolemanager.svg")
extends Node
class_name ConsoleManager

#region Definiciones

## Clase para gestionar una consola con comandos y control del motor.
## Se recomienda usar execute() y conectar output para obtener resultados.
signal output(out: String)


## RouteFileManager encargado de resolver rutas externas a ConsoleManager.
## Debe exponer una función resolve_reference(text: String) -> Variant.
@export var route_file_manager: RouteFileManager


## Variables internas de la consola.
@export var variables: Dictionary = {}

## Funciones definidas directamente en CAB mediante `func`.
var functions: Dictionary = {}

## Variables locales de llamadas `fcall`. Cada entrada sobrescribe temporalmente
## variables globales con el mismo nombre, pero las variables globales siguen
## disponibles como fallback.
var variable_scopes: Array[Dictionary] = []


## Último resultado válido producido por un comando.
## Se puede utilizar mediante @.
var last_value: Variant = null


## Contexto temporal utilizado por `at`.
## No representa una ruta permanente.
var context_stack: Array[Variant] = []

## Buffer persistente para comandos multilinea.
## Si el usuario deja un bloque { abierto, la entrada se conserva
## hasta que el parser detecte que el EOF de la estructura fue resuelto.
var command_buffer: String = ""
var command_buffer_active: bool = false

## Buffer para estructuras que pueden continuar con elsif/elif/else.
var structure_buffer: String = ""
var structure_buffer_active: bool = false

## Límite de seguridad para evitar que un CAB defectuoso bloquee el hilo principal.
@export_range(1, 1000000, 1) var max_loop_iterations: int = 10000


@export var package_manager: PackageManager


class TCommandCall:
	var t_name: String
	var t_args: Array

	func _init(
		_t_name: String = "",
		_t_args: Array = []
	) -> void:
		t_name = _t_name
		t_args = _t_args


## Bloque de comandos delimitado por { } .
## Se analiza sin ejecutarlo y se ejecuta cuando el comando padre lo solicite.
class TCommandBlock:
	var t_commands: Array = []
	var t_source: String = ""

	func _init(
		_t_commands: Array = [],
		_t_source: String = ""
	) -> void:
		t_commands = _t_commands
		t_source = _t_source


## Función definida por el usuario en CAB.
## `fcall` ejecuta directamente el TCommandBlock asociado.
class TFunction:
	var t_name: String
	var t_parameters: Array[String]
	var t_block: TCommandBlock

	func _init(
		_t_name: String = "",
		_t_parameters: Array[String] = [],
		_t_block: TCommandBlock = null
	) -> void:
		t_name = _t_name
		t_parameters = _t_parameters
		t_block = _t_block


## Cláusula opcional de una estructura encadenable.
## Es reutilizable para if/elsif/else y futuras construcciones como while/else.
class TStructureClause:
	var t_name: String
	var t_args: Array
	var t_block: Variant

	func _init(
		_t_name: String = "",
		_t_args: Array = [],
		_t_block: Variant = null
	) -> void:
		t_name = _t_name
		t_args = _t_args
		t_block = _t_block


## Valor que se resuelve durante la ejecución, no durante el parseo.
## Esto evita que expresiones y variables queden congeladas al construir un bloque.
class TDeferredValue:
	var t_text: String
	var t_expression: bool

	func _init(
		_t_text: String = "",
		_t_expression: bool = false
	) -> void:
		t_text = _t_text
		t_expression = _t_expression


class NoResult:
	pass


class ConsoleContext:
	var t_last: Variant
	var t_current: Variant
	var t_variables: Dictionary

	func _init(
		_t_last: Variant,
		_t_current: Variant,
		_t_variables: Dictionary
	) -> void:
		t_last = _t_last
		t_current = _t_current
		t_variables = _t_variables


enum OutputType {
	LOG,
	DEBUG,
	WARNING,
	ERROR,
	FATAL
}

#endregion

#region Variables
func _push_variable_scope(t_scope: Dictionary) -> void:
	variable_scopes.append(t_scope)


func _pop_variable_scope() -> bool:
	if variable_scopes.is_empty():
		return false
	variable_scopes.pop_back()
	return true


func _has_variable(t_name: String) -> bool:
	for t_index in range(variable_scopes.size() - 1, -1, -1):
		if variable_scopes[t_index].has(t_name):
			return true
	return variables.has(t_name)


func _get_variable(t_name: String) -> Variant:
	for t_index in range(variable_scopes.size() - 1, -1, -1):
		if variable_scopes[t_index].has(t_name):
			return variable_scopes[t_index][t_name]

	if variables.has(t_name):
		return variables[t_name]

	return NoResult.new()


func _set_variable(t_name: String, t_value: Variant) -> void:
	if not variable_scopes.is_empty() and variable_scopes.back().has(t_name):
		variable_scopes.back()[t_name] = t_value
		return

	variables[t_name] = t_value
#endregion

#region output
func console_output(
	t_value: Variant,
	type: OutputType = OutputType.LOG
) -> void:
	var message = str(t_value)

	var color = Color.WHITE

	match type:
		OutputType.DEBUG:
			color = Color("#CCCCCC")

		OutputType.WARNING:
			color = Color("#FFEE00")

		OutputType.ERROR:
			color = Color("#EE0000")

		OutputType.FATAL:
			color = Color("#FF00FF")

		OutputType.LOG:
			color = Color.WHITE

	var formatted = "[color=%s]%s[/color]" % [
		color.to_html(),
		message
	]

	output.emit(formatted)


## Emite información de depuración solamente cuando variables["debug"] sea true.
## Esto permite depurar parser, AST y ejecución sin llenar la consola normalmente.
func debug_output(t_value: Variant) -> void:
	if bool(_get_variable("debug") if _has_variable("debug") else false):
		console_output(t_value, OutputType.DEBUG)
#endregion

#region Contexto

func _current_context() -> Variant:
	# El contexto impuesto por "at" SIEMPRE tiene prioridad.
	if not context_stack.is_empty():
		return context_stack.back()

	# Sin contexto explícito, utilizar la ruta actual.
	if route_file_manager != null:
		var route = route_file_manager.get_actual_route()

		if route != null:
			return route

	# Último fallback: ConsoleManager.
	return self

func _push_context(t_value: Variant) -> void:
	context_stack.append(t_value)


func _pop_context() -> bool:
	if context_stack.is_empty():
		return false

	context_stack.pop_back()
	return true


func _strip_surrounding_quotes(t_text: String) -> String:
	t_text = t_text.strip_edges()

	if (
		t_text.begins_with("\"")
		and t_text.ends_with("\"")
		and t_text.length() >= 2
	):
		return t_text.substr(1, t_text.length() - 2)

	return t_text


## Elimina solamente el par exterior de llaves.
## Ejemplo: { hola qué tal } -> hola qué tal
## No elimina llaves internas: {{hola}} -> {hola}
func _strip_braces(t_text: String) -> String:
	t_text = t_text.strip_edges()

	if (
		t_text.length() >= 2
		and t_text.begins_with("{")
		and t_text.ends_with("}")
	):
		t_text = t_text.substr(1, t_text.length() - 2)
		return t_text.strip_edges()

	return t_text

#endregion

#region Auxiliares

func _process_wr_text(t_text: String) -> String:
	var t_result = _strip_braces(t_text)

	# Permite escribir saltos de línea con \n	# sin perder los saltos reales que ya existan dentro del bloque.
	return t_result.replace("\\n", "\n")


func _is_brace_block(t_text: String) -> bool:
	t_text = t_text.strip_edges()
	return (
		t_text.length() >= 2
		and t_text.begins_with("{")
		and t_text.ends_with("}")
	)


func _has_property(
	t_object: Object,
	t_property_name: String
) -> bool:
	for t_property in t_object.get_property_list():
		if (
			t_property.has("name")
			and str(t_property["name"]) == t_property_name
		):
			return true

	return false


func _get_member(
	t_container: Variant,
	t_member: String
) -> Variant:
	if t_member == "self":
		return t_container

	if t_container is Dictionary:
		var t_dict: Dictionary = t_container

		if not t_dict.has(t_member):
			return NoResult.new()

		return t_dict[t_member]

	if t_container is Array:
		if not t_member.is_valid_int():
			return NoResult.new()

		var t_index = int(t_member)
		var t_array: Array = t_container

		if t_index < 0 or t_index >= t_array.size():
			return NoResult.new()

		return t_array[t_index]

	if t_container is Object:
		var t_object: Object = t_container

		if not _has_property(t_object, t_member):
			return NoResult.new()

		return t_object.get(t_member)

	return NoResult.new()


func _set_member(
	t_container: Variant,
	t_member: String,
	t_value: Variant
) -> bool:
	if t_container is Dictionary:
		var t_dict: Dictionary = t_container
		t_dict[t_member] = t_value
		return true

	if t_container is Array:
		if not t_member.is_valid_int():
			return false

		var t_index = int(t_member)
		var t_array: Array = t_container

		if t_index < 0 or t_index >= t_array.size():
			return false

		t_array[t_index] = t_value
		return true

	if t_container is Object:
		var t_object: Object = t_container

		if not _has_property(t_object, t_member):
			return false

		t_object.set(t_member, t_value)
		return true

	return false

func _resolve_property_chain(
	t_base: Variant,
	t_chain: String
) -> Variant:
	var t_current: Variant = t_base

	for t_part in t_chain.split(":"):
		t_part = t_part.strip_edges()

		if t_part.is_empty():
			continue

		if t_part == "@":
			t_current = last_value
			continue

		if t_part == "self":
			t_current = t_base
			continue

		t_current = _get_member(t_current, t_part)

		if t_current is NoResult:
			return t_current

	return t_current

func _resolve_property_parent(
	t_base: Variant,
	t_chain: String
) -> Dictionary:
	var t_parts = t_chain.split(":")

	if t_parts.is_empty():
		return {"t_error": true}

	var t_current: Variant = t_base

	for t_index in range(t_parts.size() - 1):
		var t_part = t_parts[t_index].strip_edges()

		if t_part.is_empty():
			continue

		if t_part == "@":
			t_current = last_value
			continue

		if t_part == "self":
			t_current = t_base
			continue

		t_current = _get_member(t_current, t_part)

		if t_current is NoResult:
			return {"t_error": true}

	return {
		"t_parent": t_current,
		"t_leaf": t_parts[t_parts.size() - 1].strip_edges()
	}


func _resolve_reference(t_text: String) -> Variant:
	t_text = _strip_surrounding_quotes(t_text)

	if t_text == "self":
		return _current_context()

	if _has_variable(t_text):
		return _get_variable(t_text)

	if t_text == "@":
		return last_value

	if route_file_manager != null:
		if route_file_manager.has_method("resolve_reference"):
			var t_resolved = route_file_manager.call(
				"resolve_reference",
				t_text
			)

			if t_resolved != null:
				return t_resolved

		if route_file_manager.has_method("resolve"):
			var t_resolved = route_file_manager.call(
				"resolve",
				t_text
			)

			if t_resolved != null:
				return t_resolved

	if t_text.find(":") != -1:
		var t_chained = _resolve_property_chain(
			_current_context(),
			t_text
		)

		if not (t_chained is NoResult):
			return t_chained

	return null


func _looks_like_expression(t_text: String) -> bool:
	t_text = t_text.strip_edges()

	if t_text.is_empty():
		return false

	if t_text.begins_with("\"") and t_text.ends_with("\""):
		return false

	if t_text in ["null", "true", "false", "@"]:
		return false

	for t_character in [
		"+", "-", "*", "/", "%",
		"(", ")", ".", ",", "[", "]", "{", "}",
		"<", ">", "=", "!", "&", "|"
	]:
		if t_text.find(t_character) != -1:
			return true

	for t_operator in [" in ", " not ", " and ", " or "]:
		if t_operator in t_text:
			return true

	return false


const EXPRESSION_LAST_NAME := "__cab_last_value"


func preprocess_expression(t_text: String) -> String:
	# Sustituye @ solamente fuera de cadenas.
	# Así `"@"` permanece literalmente `"@"`.
	var t_result := ""
	var t_quote := false
	var t_escaped := false

	for t_character in t_text:
		if t_escaped:
			t_result += t_character
			t_escaped = false
			continue

		if t_character == "\\":
			t_result += t_character
			t_escaped = true
			continue

		if t_character == "\"":
			t_quote = not t_quote
			t_result += t_character
			continue

		if not t_quote and t_character == "@":
			t_result += EXPRESSION_LAST_NAME
		else:
			t_result += t_character

	return t_result


func _get_expression_inputs() -> Dictionary:
	var t_names := PackedStringArray()
	var t_values: Array = []

	var t_merged_variables: Dictionary = {}
	for t_name in variables:
		t_merged_variables[str(t_name)] = variables[t_name]

	for t_scope in variable_scopes:
		for t_name in t_scope:
			t_merged_variables[str(t_name)] = t_scope[t_name]

	for t_name in t_merged_variables:
		var t_name_string: String = str(t_name)
		if t_name_string == EXPRESSION_LAST_NAME:
			continue
		t_names.append(t_name_string)
		t_values.append(t_merged_variables[t_name])

	# `@` usa siempre este binding reservado, incluso si el usuario
	# tiene una variable llamada `last`.
	t_names.append(EXPRESSION_LAST_NAME)
	t_values.append(last_value)

	return {
		"names": t_names,
		"values": t_values
	}


func evaluate_expression(t_text: String) -> Variant:
	var t_expression = Expression.new()
	var t_parsed_text = preprocess_expression(t_text)
	var t_inputs = _get_expression_inputs()

	var t_error = t_expression.parse(
		t_parsed_text,
		t_inputs["names"]
	)

	if t_error != OK:
		console_output("[ERROR] Expresión inválida: %s" % t_expression.get_error_text(), OutputType.ERROR)
		return NoResult.new()

	var t_context = ConsoleContext.new(
		last_value,
		_current_context(),
		variables
	)

	var t_result = t_expression.execute(
		t_inputs["values"],
		t_context
	)

	if t_expression.has_execute_failed():
		console_output("[ERROR] Falló la ejecución de la expresión: %s" % t_expression.get_error_text(), OutputType.ERROR)
		return NoResult.new()

	return t_result

#endregion

#region Parser y expresiones

func evaluate_raw_expression(t_text: String) -> Variant:
	var t_expression = Expression.new()
	var t_inputs = _get_expression_inputs()

	var t_error = t_expression.parse(
		t_text,
		t_inputs["names"]
	)

	if t_error != OK:
		console_output("[ERROR] Expresión inválida: %s" % t_expression.get_error_text(), OutputType.ERROR)
		return NoResult.new()

	var t_result = t_expression.execute(
		t_inputs["values"],
		ConsoleContext.new(
			last_value,
			_current_context(),
			variables
		)
	)

	if t_expression.has_execute_failed():
		console_output("[ERROR] Falló la ejecución de la expresión: %s" % t_expression.get_error_text(), OutputType.ERROR)
		return NoResult.new()

	return t_result


func parse_value(t_value: String) -> Variant:
	t_value = t_value.strip_edges()

	# Los valores dinámicos NO se evalúan aquí.
	# Se guardan para resolverlos justo antes de ejecutar el comando.
	if t_value == "@":
		return TDeferredValue.new("@", false)

	if (
		t_value.begins_with("\"")
		and t_value.ends_with("\"")
	):
		return t_value.substr(
			1,
			t_value.length() - 2
		)

	if t_value == "null":
		return null

	if t_value == "true":
		return true

	if t_value == "false":
		return false

	if t_value.is_valid_int():
		return int(t_value)

	if t_value.is_valid_float():
		return float(t_value)

	if _looks_like_expression(t_value):
		return TDeferredValue.new(t_value, true)

	# Los identificadores simples también deben ser diferidos.
	# Así `log i` dentro de un repeat ve el valor actual de i.
	return TDeferredValue.new(t_value, false)


func _resolve_runtime_value(t_value: Variant) -> Variant:
	if t_value is TDeferredValue:
		var t_deferred: TDeferredValue = t_value

		if t_deferred.t_expression:
			return evaluate_expression(t_deferred.t_text)

		if t_deferred.t_text == "@":
			return last_value

		if _has_variable(t_deferred.t_text):
			return _get_variable(t_deferred.t_text)

		# Si no existe como variable, conserva el texto original.
		return t_deferred.t_text

	if t_value is Array:
		var t_array: Array = t_value
		var t_resolved_array: Array = []

		for t_item in t_array:
			t_resolved_array.append(_resolve_runtime_value(t_item))

		return t_resolved_array

	if t_value is Dictionary:
		var t_dict: Dictionary = t_value
		var t_resolved_dict: Dictionary = {}

		for t_key in t_dict:
			t_resolved_dict[t_key] = _resolve_runtime_value(t_dict[t_key])

		return t_resolved_dict

	# Los comandos y bloques son estructuras del AST y no se resuelven aquí.
	return t_value


func _parse_argument(
	t_tokens: PackedStringArray,
	t_index: int,
	t_end: int,
	t_raw: bool
) -> Dictionary:
	if t_index >= t_end:
		return {
			"value": NoResult.new(),
			"next_index": t_index
		}

	if t_raw:
		var t_raw_value: String = t_tokens[t_index]
		debug_output(
			"_parse_argument: RAW -> %s" % t_raw_value
		)
		return {
			"value": t_raw_value,
			"next_index": t_index + 1
		}

	var t_token = t_tokens[t_index]

	if t_token in commands:
		return _parse_command_call(
			t_tokens,
			t_index,
			t_end
		)

	return {
		"value": parse_value(t_token),
		"next_index": t_index + 1
	}

#endregion

#region Structured Command Parsing

func _has_structure_metadata(t_command_data: Dictionary) -> bool:
	return t_command_data.has("structure")


## Parsea una parte fija de una estructura usando metadata.
## `block_args` / `call_args` usan Dictionary como conjunto de posiciones.
func _parse_structured_part(
	t_tokens: PackedStringArray,
	t_index: int,
	t_end: int,
	t_data: Dictionary
) -> Dictionary:
	var t_args_count: int = int(t_data.get("args", 0))
	var t_raw: Dictionary = t_data.get("raw", {})
	var t_call_args: Dictionary = t_data.get("call_args", {})
	var t_block_args: Dictionary = t_data.get("block_args", {})
	var t_text_args: Dictionary = t_data.get("text_args", {})

	var t_args: Array = []
	var t_current_index = t_index

	for t_argument_index in range(t_args_count):
		if t_current_index >= t_end:
			return {
				"ok": false,
				"args": t_args,
				"next_index": t_current_index
			}

		if t_argument_index in t_call_args:
			var t_nested_result = _parse_nested_command(
				t_tokens,
				t_current_index,
				t_end
			)

			if t_nested_result["value"] is NoResult:
				return {
					"ok": false,
					"args": t_args,
					"next_index": t_current_index
				}

			t_args.append(t_nested_result["value"])
			t_current_index = t_nested_result["next_index"]
			continue

		if t_argument_index in t_block_args:
			var t_block_token = t_tokens[t_current_index]

			if not _is_brace_block(t_block_token):
				return {
					"ok": false,
					"args": t_args,
					"next_index": t_current_index
				}

			var t_block = _parse_block_token(t_block_token)
			if t_block is NoResult:
				return {
					"ok": false,
					"args": t_args,
					"next_index": t_current_index
				}

			t_args.append(t_block)
			t_current_index += 1
			continue

		var t_is_raw = t_argument_index in t_raw
		var t_parsed = _parse_argument(
			t_tokens,
			t_current_index,
			t_end,
			t_is_raw
		)

		if t_parsed["value"] is NoResult:
			return {
				"ok": false,
				"args": t_args,
				"next_index": t_current_index
			}

		var t_value: Variant = t_parsed["value"]
		if t_argument_index in t_text_args and t_value is String:
			t_value = _process_wr_text(t_value)

		t_args.append(t_value)
		t_current_index = t_parsed["next_index"]

	return {
		"ok": true,
		"args": t_args,
		"next_index": t_current_index
	}


## Ensambla una estructura completa y consume sus continuaciones.
## La estructura resultante sigue siendo un TCommandCall; sus continuaciones
## son TStructureClause y por tanto no son comandos independientes.
func _parse_structured_command_call(
	t_tokens: PackedStringArray,
	t_index: int,
	t_end: int,
	t_command_name: String,
	t_command_data: Dictionary
) -> Dictionary:
	var t_structure: Dictionary = t_command_data["structure"]
	var t_head_data: Dictionary = t_structure.get("head", {})

	var t_head = _parse_structured_part(
		t_tokens,
		t_index + 1,
		t_end,
		t_head_data
	)

	if not t_head["ok"]:
		return {
			"value": NoResult.new(),
			"next_index": t_head["next_index"]
		}

	var t_call = TCommandCall.new(t_command_name)
	for t_argument in t_head["args"]:
		t_call.t_args.append(t_argument)

	var t_current_index: int = t_head["next_index"]
	var t_continuations: Dictionary = t_structure.get("continuations", {})
	var t_seen_terminal = false

	while t_current_index < t_end:
		var t_keyword = str(t_tokens[t_current_index])

		if not t_continuations.has(t_keyword):
			break

		if t_seen_terminal:
			return {
				"value": NoResult.new(),
				"next_index": t_current_index
			}

		var t_clause_data: Dictionary = t_continuations[t_keyword]
		var t_clause = _parse_structured_part(
			t_tokens,
			t_current_index + 1,
			t_end,
			t_clause_data
		)

		if not t_clause["ok"]:
			return {
				"value": NoResult.new(),
				"next_index": t_clause["next_index"]
			}

		var t_clause_args: Array = t_clause["args"]
		var t_block_index = int(t_clause_data.get("block_index", -1))
		var t_clause_block: Variant = null
		var t_condition_args: Array = []

		for t_clause_index in range(t_clause_args.size()):
			if t_clause_index == t_block_index:
				t_clause_block = t_clause_args[t_clause_index]
			else:
				t_condition_args.append(t_clause_args[t_clause_index])

		t_call.t_args.append(
			TStructureClause.new(
				t_keyword,
				t_condition_args,
				t_clause_block
			)
		)

		t_current_index = t_clause["next_index"]
		t_seen_terminal = bool(t_clause_data.get("terminal", false))

	return {
		"value": t_call,
		"next_index": t_current_index
	}

#endregion

#region ready
func _ready() -> void:
	var tree: SceneTree = get_tree()
	variables["tree"] = tree
	if not variables.has("debug"):
		variables["debug"] = false
#endregion

#region Parser
#region Command Call Parsing

func _parse_command_call(
	t_tokens: PackedStringArray,
	t_index: int,
	t_end: int
) -> Dictionary:
	if t_index >= t_end:
		debug_output("[PARSE COMMAND] EOF: no hay token en index=%d" % t_index)
		return {
			"value": NoResult.new(),
			"next_index": t_index
		}

	var t_token: String = str(t_tokens[t_index])
	debug_output("[PARSE COMMAND] Inicio: %s" % str(t_tokens))

	if not t_token in commands:
		return {
			"value": NoResult.new(),
			"next_index": t_index
		}

	var t_command_data: Dictionary = commands[t_token]

	if t_token == "func":
		return _parse_function_definition(t_tokens, t_index, t_end)

	if _has_structure_metadata(t_command_data):
		return _parse_structured_command_call(
			t_tokens,
			t_index,
			t_end,
			t_token,
			t_command_data
		)

	var t_amount: int = t_command_data["args"]
	var t_raw: Dictionary = t_command_data.get("raw", {})
	var t_call_args: Dictionary = t_command_data.get("call_args", {})
	var t_block_args: Dictionary = t_command_data.get("block_args", {})
	var t_text_args: Dictionary = t_command_data.get("text_args", {})
	var t_call = TCommandCall.new(t_token)

	if t_amount == -1:
		@warning_ignore("confusable_local_declaration")
		var t_current_index = t_index + 1

		while t_current_index < t_end:
			var t_argument_position = t_current_index - t_index - 1

			if t_argument_position in t_call_args:
				var t_nested_result = _parse_nested_command(
					t_tokens,
					t_current_index,
					t_end
				)

				if t_nested_result["value"] is NoResult:
					return {
						"value": NoResult.new(),
						"next_index": t_end
					}

				t_call.t_args.append(t_nested_result["value"])
				t_current_index = t_nested_result["next_index"]
				continue

			if t_argument_position in t_block_args:
				var t_block_token = t_tokens[t_current_index]
				if not _is_brace_block(t_block_token):
					return {
						"value": NoResult.new(),
						"next_index": t_end
					}

				var t_block = _parse_block_token(t_block_token)
				if t_block is NoResult:
					return {
						"value": NoResult.new(),
						"next_index": t_end
					}

				t_call.t_args.append(t_block)
				t_current_index += 1
				continue

			var t_is_raw = t_argument_position in t_raw
			var t_parsed = _parse_argument(
				t_tokens,
				t_current_index,
				t_end,
				t_is_raw
			)

			if t_parsed["value"] is NoResult:
				return {
					"value": NoResult.new(),
					"next_index": t_end
				}

			var t_value: Variant = t_parsed["value"]
			if t_argument_position in t_text_args and t_value is String:
				t_value = _process_wr_text(t_value)

			t_call.t_args.append(t_value)
			t_current_index = t_parsed["next_index"]

		return {
			"value": t_call,
			"next_index": t_current_index
		}

	var t_current_index = t_index + 1

	for t_argument_index in range(t_amount):
		if t_current_index >= t_end:
			break

		if t_argument_index in t_call_args:
			var t_nested_result = _parse_nested_command(
				t_tokens,
				t_current_index,
				t_end
			)

			if t_nested_result["value"] is NoResult:
				break

			t_call.t_args.append(t_nested_result["value"])
			t_current_index = t_nested_result["next_index"]
			continue

		if t_argument_index in t_block_args:
			var t_block_token = t_tokens[t_current_index]
			if not _is_brace_block(t_block_token):
				break

			var t_block = _parse_block_token(t_block_token)
			if t_block is NoResult:
				break

			t_call.t_args.append(t_block)
			t_current_index += 1
			continue

		var t_is_raw = t_argument_index in t_raw
		var t_parsed = _parse_argument(
			t_tokens,
			t_current_index,
			t_end,
			t_is_raw
		)

		if t_parsed["value"] is NoResult:
			break

		var t_parsed_value: Variant = t_parsed["value"]
		if t_argument_index in t_text_args and t_parsed_value is String:
			t_parsed_value = _process_wr_text(t_parsed_value)

		t_call.t_args.append(t_parsed_value)
		t_current_index = t_parsed["next_index"]

	return {
		"value": t_call,
		"next_index": t_current_index
	}


func _parse_function_definition(
	t_tokens: PackedStringArray,
	t_index: int,
	t_end: int
) -> Dictionary:
	debug_output("[PARSE FUNC] Inicio: tokens=%s" % str(t_tokens))

	# La sintaxis permite tanto:
	# func nombre { ... }
	# como:
	# func nombre parametro1 parametro2 { ... }
	if t_end - t_index < 3:
		console_output(
			"[CAB PARSE ERROR] Uso: func [name] [parametros...] { ... }",
			OutputType.ERROR
		)
		return {"value": NoResult.new(), "next_index": t_end}

	var t_name: String = str(t_tokens[t_index + 1]).strip_edges()
	if t_name.is_empty() or not t_name.is_valid_identifier():
		console_output(
			"[CAB PARSE ERROR] Nombre de función inválido: %s" % t_name,
			OutputType.ERROR
		)
		return {"value": NoResult.new(), "next_index": t_end}

	var t_block_token: String = str(t_tokens[t_end - 1])
	if not _is_brace_block(t_block_token):
		console_output(
			"[CAB PARSE ERROR] func requiere un bloque final: { ... }",
			OutputType.ERROR
		)
		return {"value": NoResult.new(), "next_index": t_end}

	var t_parameters: Array[String] = []
	for t_parameter_index in range(t_index + 2, t_end - 1):
		var t_parameter: String = str(t_tokens[t_parameter_index]).strip_edges()
		if t_parameter.is_empty() or not t_parameter.is_valid_identifier():
			console_output(
				"[CAB PARSE ERROR] Parámetro inválido en func %s: %s" % [t_name, t_parameter],
				OutputType.ERROR
			)
			return {"value": NoResult.new(), "next_index": t_end}
		if t_parameter in t_parameters:
			console_output(
				"[CAB PARSE ERROR] Parámetro duplicado en func %s: %s" % [t_name, t_parameter],
				OutputType.ERROR
			)
			return {"value": NoResult.new(), "next_index": t_end}
		t_parameters.append(t_parameter)

	var t_block: Variant = _parse_block_token(t_block_token)
	if t_block is NoResult:
		console_output("[CAB PARSE ERROR] No se pudo parsear el cuerpo de func %s" % t_name, OutputType.ERROR)
		return {"value": NoResult.new(), "next_index": t_end}

	debug_output(
		"[PARSE FUNC] OK: name=%s params=%s body_commands=%d" % [
			t_name,
			str(t_parameters),
			t_block.t_commands.size()
		]
	)

	return {
		"value": TCommandCall.new("func", [t_name, t_parameters, t_block]),
		"next_index": t_end
	}

func _parse_nested_command(
	t_tokens: PackedStringArray,
	t_index: int,
	t_end: int
) -> Dictionary:
	if t_index >= t_end:
		return {
			"value": NoResult.new(),
			"next_index": t_index
		}

	var t_token = t_tokens[t_index]

	if _is_brace_block(t_token):
		debug_output(
			"_parse_nested_command: %s reconocido como bloque" % t_token
		)
		return {
			"value": _parse_block_token(t_token),
			"next_index": t_index + 1
		}

	return _parse_command_call(
		t_tokens,
		t_index,
		t_end
	)

#endregion

#endregion

#region execute_call
func _execute_call(t_call: TCommandCall) -> Variant:
	debug_output("[CALL] Inicio: %s args=%d" % [str(t_call.t_name) if t_call != null else "<null>", t_call.t_args.size() if t_call != null else 0])
	if t_call == null:
		return NoResult.new()

	if not commands.has(t_call.t_name):
		return NoResult.new()

	var t_command_data: Dictionary = commands[
		t_call.t_name
	]

	var t_function: Callable = t_command_data["func"]
	if not t_function.is_valid():
		console_output("[ERROR] Comando sin función ejecutable: %s" % t_call.t_name, OutputType.ERROR)
		return NoResult.new()

	var t_expected_args: int = int(t_command_data.get("args", -1))
	if t_expected_args >= 0 and t_call.t_args.size() != t_expected_args:
		console_output("[ERROR] '%s' recibió %d argumentos; se esperaban %d" % [t_call.t_name, t_call.t_args.size(), t_expected_args], OutputType.ERROR)
		return NoResult.new()

	var t_runtime_args: Array = []

	var t_text_args: Dictionary = t_command_data.get("text_args", {})
	var t_lazy_args: Dictionary = t_command_data.get("lazy_args", {})

	for t_argument_index in range(t_call.t_args.size()):
		var t_argument = t_call.t_args[t_argument_index]
		debug_output(
			"_execute_call: %s arg[%d] tipo=%s valor=%s" % [
				t_call.t_name,
				t_argument_index,
				str(typeof(t_argument)),
				str(t_argument)
			]
		)

		# Los bloques y llamadas anidadas ya son AST y deben permanecer intactos.
		# Si por cualquier ruta un AST llega a un argumento textual, recuperamos
		# el texto fuente en lugar de dejar escapar la instancia RefCounted.
		if t_argument_index in t_text_args:
			if t_argument is TCommandBlock:
				t_runtime_args.append(t_argument.t_source)
				continue
			if t_argument is TDeferredValue:
				t_runtime_args.append(t_argument.t_text)
				continue

		# Lazy arguments must remain deferred until the command itself resolves them.
		# `while` uses this for its condition because it must be evaluated every iteration.
		if t_argument_index in t_lazy_args:
			t_runtime_args.append(t_argument)
			continue

		if t_argument is TCommandCall or t_argument is TCommandBlock:
			t_runtime_args.append(t_argument)
		else:
			t_runtime_args.append(
				_resolve_runtime_value(t_argument)
			)

	var t_result = await t_function.call(
		t_runtime_args
	)

	if not (t_result is NoResult):
		last_value = t_result

	debug_output("[CALL] Fin: %s -> %s" % [t_call.t_name, str(t_result)])
	return t_result
#endregion

#region Command Blocks
#region Block Parsing

func _parse_block_token(t_block_token: String) -> Variant:
	debug_output("[BLOCK PARSE] Inicio")
	var t_content: String = _strip_braces(t_block_token)
	t_content = _normalize_source(t_content)
	debug_output(
		"_parse_block_token: creando TCommandBlock para %s" % t_block_token
	)
	var t_block = TCommandBlock.new([], t_block_token)

	var t_commands = _split_complete_commands(t_content)

	for t_text in t_commands:
		var t_line = t_text.strip_edges()
		if t_line.is_empty():
			continue

		var t_tokens = tokenize(t_line)
		if t_tokens.is_empty():
			continue

		var t_parsed = _parse_command_call(
			t_tokens,
			0,
			t_tokens.size()
		)

		if t_parsed["value"] is NoResult:
			return NoResult.new()

		if t_parsed["next_index"] != t_tokens.size():
			return NoResult.new()

		if t_parsed["value"] is TCommandCall:
			t_block.t_commands.append(t_parsed["value"])
		else:
			return NoResult.new()

	return t_block



#endregion

#region Block Execution

func _execute_block(t_block: TCommandBlock) -> Variant:
	var t_final_result: Variant = NoResult.new()

	for t_command in t_block.t_commands:
		var t_result = await _execute_call(t_command)

		if not (t_result is NoResult):
			t_final_result = t_result

	return t_final_result


#endregion
#endregion

#region Command Splitting

func _get_structure_continuation_names() -> Dictionary:
	var t_names: Dictionary = {}

	for t_command_name in commands:
		var t_command_data: Dictionary = commands[t_command_name]
		if not _has_structure_metadata(t_command_data):
			continue

		var t_structure: Dictionary = t_command_data["structure"]
		var t_continuations: Dictionary = t_structure.get(
			"continuations",
			{}
		)

		for t_keyword in t_continuations:
			t_names[str(t_keyword)] = true

	return t_names


func _starts_structure_continuation(t_text: String) -> bool:
	var t_tokens = tokenize(t_text.strip_edges())
	if t_tokens.is_empty():
		return false

	var t_keyword = str(t_tokens[0])
	return t_keyword in _get_structure_continuation_names()


func _command_can_have_structure_continuation(t_text: String) -> bool:
	var t_tokens = tokenize(t_text.strip_edges())
	if t_tokens.is_empty():
		return false

	var t_command_name = str(t_tokens[0])
	if not commands.has(t_command_name):
		return false

	return _has_structure_metadata(commands[t_command_name])


## Divide comandos completos a nivel superior y vuelve a unir las
## continuaciones estructurales aunque estén en otra línea.
func _split_complete_commands(t_text: String) -> Array[String]:
	var t_raw_result: Array[String] = []
	var t_start = 0
	var t_braces = 0
	var t_quote = false
	var t_escaped = false

	for t_index in range(t_text.length()):
		var t_character = t_text[t_index]

		if t_escaped:
			t_escaped = false
			continue

		if t_character == "\\":
			t_escaped = true
			continue

		if t_character == "\"":
			t_quote = not t_quote
			continue

		if t_quote:
			continue

		match t_character:
			"{":
				t_braces += 1
			"}":
				t_braces = maxi(0, t_braces - 1)
			"\n":
				if t_braces == 0:
					var t_command = t_text.substr(
						t_start,
						t_index - t_start
					)
					if not t_command.strip_edges().is_empty():
						t_raw_result.append(t_command)
					t_start = t_index + 1

	var t_tail = t_text.substr(t_start)
	if not t_tail.strip_edges().is_empty():
		t_raw_result.append(t_tail)

	var t_result: Array[String] = []

	for t_command in t_raw_result:
		var t_text_command = t_command.strip_edges()
		if t_text_command.is_empty():
			continue

		if (
				not t_result.is_empty()
				and _starts_structure_continuation(t_text_command)
				and _command_can_have_structure_continuation(
					t_result[t_result.size() - 1]
				)
		):
			t_result[t_result.size() - 1] += " " + t_text_command
			continue

		t_result.append(t_text_command)

	return t_result


## Detecta si la entrada todavía está esperando el cierre de un bloque.


#endregion

#region que es esta wea
func _has_unclosed_structure(t_text: String) -> bool:
	var t_stack: Array[String] = []
	var t_quote: bool = false
	var t_escaped: bool = false

	for t_character in t_text:
		if t_escaped:
			t_escaped = false
			continue

		if t_character == "\\" and t_quote:
			t_escaped = true
			continue

		if t_character == '"':
			t_quote = not t_quote
			continue

		if t_quote:
			continue

		match t_character:
			"{", "(", "[":
				t_stack.append(t_character)
			"}", ")", "]":
				if t_stack.is_empty():
					console_output("[CAB ERROR] Cierre '%s' sin apertura" % t_character, OutputType.ERROR)
					return true
				var t_open: String = str(t_stack.back())
				var t_expected: String = {
					"{": "}",
					"(": ")",
					"[": "]"
				}.get(t_open, "")
				if t_character != t_expected:
					console_output(
						"[CAB ERROR] Cierre '%s' no corresponde a '%s'" % [t_character, t_open],
						OutputType.ERROR
					)
					return true
				t_stack.pop_back()

	if t_escaped:
		console_output("[CAB EOF ERROR] Escape incompleto al final de la entrada", OutputType.ERROR)
		return true

	if t_quote:
		console_output("[CAB EOF ERROR] Comillas sin cerrar al final de la entrada", OutputType.ERROR)
		return true

	if not t_stack.is_empty():
		console_output(
			"[CAB EOF ERROR] Falta cerrar '%s' al final de la entrada" % str(t_stack.back()),
			OutputType.ERROR
		)
		return true

	return false


func _has_unclosed_block(t_text: String) -> bool:
	var t_braces = 0
	var t_quote = false
	var t_escaped = false

	for t_character in t_text:
		if t_escaped:
			t_escaped = false
			continue

		if t_character == "\\":
			t_escaped = true
			continue

		if t_character == "\"":
			t_quote = not t_quote
			continue

		if t_quote:
			continue

		if t_character == "{":
			t_braces += 1
		elif t_character == "}":
			t_braces -= 1

		if t_braces < 0:
			return false

	return t_braces > 0
#endregion

#region Execution Entry Points

## Ejecuta CAB usando las tres etapas públicas:
## String -> lex() -> parse_ast() -> execute_ast().
##
## `execute()` es la entrada principal para la consola interactiva.
## Flujo explícito disponible: lex() -> parse_ast() -> execute_ast().
## Para archivos CAB completos se recomienda separar estas etapas y evitar
## los buffers interactivos de execute().
func _flush_structure_buffer() -> void:
	if structure_buffer.is_empty():
		structure_buffer_active = false
		return

	var t_pending := structure_buffer
	structure_buffer = ""
	structure_buffer_active = false

	var t_ast = parse_ast(lex(t_pending))
	if t_ast is NoResult:
		return

	var t_result = await execute_ast(t_ast)
	if not (t_result is NoResult):
		last_value = t_result


func _input_starts_structure_continuation(t_command: String) -> bool:
	var t_commands = _split_complete_commands(t_command)
	if t_commands.is_empty():
		return false

	return _starts_structure_continuation(t_commands[0])


func _has_potential_structure_continuation(
	t_tokens: PackedStringArray
) -> bool:
	if t_tokens.is_empty():
		return false

	var t_command_name = str(t_tokens[0])
	if not commands.has(t_command_name):
		return false

	var t_command_data: Dictionary = commands[t_command_name]
	if not _has_structure_metadata(t_command_data):
		return false

	var t_structure: Dictionary = t_command_data["structure"]
	var t_head: Dictionary = t_structure.get("head", {})
	var t_head_args: int = int(t_head.get("args", 0))
	var t_continuations: Dictionary = t_structure.get(
		"continuations",
		{}
	)

	if t_continuations.is_empty():
		return false

	# Las posiciones que siguen al head son las cláusulas ya presentes
	# en esta entrada. Si existe una cláusula terminal (por ejemplo else),
	# ya no hay nada que esperar.
	var t_first_clause_index = 1 + t_head_args
	for t_index in range(
		t_first_clause_index,
		t_tokens.size()
	):
		var t_keyword = str(t_tokens[t_index])
		if not t_continuations.has(t_keyword):
			continue

		var t_clause_data: Dictionary = t_continuations[t_keyword]
		if bool(t_clause_data.get("terminal", false)):
			return false

	return true


func execute(t_command: String) -> int:
	debug_output("[EXECUTE] Entrada: %s" % t_command)
	t_command = t_command.replace("\r\n", "\n").replace("\r", "\n")

	# Si había una estructura completa pendiente, una nueva entrada que no
	# empiece por una continuación significa que aquella estructura terminó.
	if structure_buffer_active and not structure_buffer.is_empty():
		if _input_starts_structure_continuation(t_command):
			t_command = structure_buffer + " " + t_command
			structure_buffer = ""
			structure_buffer_active = false
		else:
			await _flush_structure_buffer()

	var t_normalized := _normalize_source(t_command)

	if not command_buffer.is_empty():
		command_buffer += "\n"

	command_buffer += t_normalized

	var t_commands := _split_complete_commands(command_buffer)
	command_buffer = ""
	command_buffer_active = false

	var t_complete_texts: Array[String] = []

	for t_index in range(t_commands.size()):
		var t_command_text: String = t_commands[t_index]
		var t_text := t_command_text.strip_edges()
		if t_text.is_empty():
			continue

		if _has_unclosed_block(t_text):
			command_buffer = t_text
			command_buffer_active = true
			continue

		t_complete_texts.append(t_text)

	debug_output("[EXECUTE] Pasando a LEX. complete_texts=%d" % t_complete_texts.size())
	var t_lexed: Array = lex("\n".join(t_complete_texts))
	debug_output("[EXECUTE] Pasando a PARSE. token_lists=%d" % t_lexed.size())
	var t_ast: Variant = parse_ast(t_lexed)

	if t_ast is NoResult:
		return 0

	# Una estructura sin cláusula terminal puede necesitar la siguiente línea
	# en la consola interactiva. No aplica al parser de archivos: parse_ast()
	# siempre devuelve el AST completo disponible.
	if t_complete_texts.size() > 0 and t_lexed.size() > 0:
		var t_last_text := t_complete_texts[t_complete_texts.size() - 1]
		var t_last_tokens: PackedStringArray = t_lexed[t_lexed.size() - 1]
		if (
				_command_can_have_structure_continuation(t_last_text)
				and _has_potential_structure_continuation(t_last_tokens)
		):
			# Separa el último comando del AST ejecutable; así no se ejecuta
			# hasta que llegue elsif/else o una nueva entrada cierre la estructura.
			if t_ast is TCommandBlock and t_ast.t_commands.size() > 0:
				t_ast.t_commands.pop_back()
				structure_buffer = t_last_text
				structure_buffer_active = true
			
				if t_ast.t_commands.is_empty():
					return 0

	if t_ast is TCommandBlock and t_ast.t_commands.is_empty():
		return 0

	debug_output("[EXECUTE] Pasando a EXECUTE_AST")
	await execute_ast(t_ast)
	debug_output("[EXECUTE] Fin")
	return 0


func _normalize_source(t_command: String) -> String:
	debug_output("[NORMALIZE] Inicio. caracteres=%d" % t_command.length())

	var t_normalized: String = ""
	var t_quote: bool = false
	var t_escaped: bool = false
	var t_comment: bool = false
	var t_braces: int = 0
	var t_parentheses: int = 0
	var t_brackets: int = 0

	for t_character in t_command:
		if t_comment:
			if t_character == "\n":
				t_comment = false
				t_normalized += "\n"
				debug_output("[NORMALIZE] Fin de comentario")
			continue

		if t_escaped:
			t_normalized += t_character
			t_escaped = false
			continue

		if t_character == "\\" and t_quote:
			t_normalized += t_character
			t_escaped = true
			continue

		if t_character == '"':
			t_quote = not t_quote
			t_normalized += t_character
			continue

		if not t_quote and t_character == "#":
			t_comment = true
			debug_output("[NORMALIZE] '#' detectado: inicio de comentario")
			continue

		if not t_quote:
			if t_character == "{":
				t_braces += 1
			elif t_character == "}":
				t_braces -= 1
			elif t_character == "(":
				t_parentheses += 1
			elif t_character == ")":
				t_parentheses -= 1
			elif t_character == "[":
				t_brackets += 1
			elif t_character == "]":
				t_brackets -= 1
			elif (
				t_character == ";"
				and t_braces == 0
				and t_parentheses == 0
				and t_brackets == 0
			):
				t_normalized += "\n"
				continue

		t_normalized += t_character

	if t_comment:
		debug_output("[NORMALIZE] EOF alcanzado dentro de comentario; es válido")

	if t_quote:
		console_output("[CAB EOF ERROR] Cadena sin cerrar al final del archivo/entrada", OutputType.ERROR)
		debug_output("[NORMALIZE] EOF ERROR: comillas abiertas")
		return ""

	if t_escaped:
		console_output("[CAB EOF ERROR] Escape '\\\\' incompleto al final de la entrada", OutputType.ERROR)
		debug_output("[NORMALIZE] EOF ERROR: escape incompleto")
		return ""

	if t_braces < 0:
		console_output("[CAB ERROR] '}' inesperado: no existe un bloque abierto", OutputType.ERROR)
		return ""
	if t_parentheses < 0:
		console_output("[CAB ERROR] ')' inesperado: no existe '(' abierto", OutputType.ERROR)
		return ""
	if t_brackets < 0:
		console_output("[CAB ERROR] ']' inesperado: no existe '[' abierto", OutputType.ERROR)
		return ""

	debug_output(
		"[NORMALIZE] Fin. braces=%d parentheses=%d brackets=%d" % [
			t_braces,
			t_parentheses,
			t_brackets
		]
	)
	return t_normalized

func lex(t_text: String) -> Array:
	debug_output("[LEX] Inicio. source_length=%d" % t_text.length())

	var t_normalized: String = _normalize_source(t_text)
	if t_text.length() > 0 and t_normalized.is_empty():
		debug_output("[LEX] Normalización devolvió vacío; se aborta el lexing")
		return []

	var t_commands: Array[String]
	if t_normalized.is_empty():
		t_commands = []
	else:
		t_commands = _split_complete_commands(t_normalized)

	debug_output("[LEX] Comandos detectados=%d" % t_commands.size())

	var t_result: Array = []
	var t_command_index: int = 0

	for t_command_text in t_commands:
		t_command_index += 1
		var t_text_command: String = t_command_text.strip_edges()
		debug_output("[LEX] Comando #%d: %s" % [t_command_index, t_text_command])

		if t_text_command.is_empty():
			continue

		if _has_unclosed_structure(t_text_command):
			console_output(
				"[CAB EOF ERROR] Estructura sin cerrar en el comando #%d" % t_command_index,
				OutputType.ERROR
			)
			return []

		var t_tokens: PackedStringArray = tokenize(t_text_command)
		if t_tokens.is_empty():
			debug_output("[LEX] Comando #%d produjo 0 tokens" % t_command_index)
			continue

		debug_output("[LEX] Tokens #%d: %s" % [t_command_index, str(t_tokens)])
		t_result.append(t_tokens)

	debug_output("[LEX] Fin. token_lists=%d" % t_result.size())
	return t_result

func parse_ast(t_lexed: Array) -> Variant:
	debug_output("[PARSE] Inicio. listas_de_tokens=%d" % t_lexed.size())
	var t_block: TCommandBlock = TCommandBlock.new()

	for t_tokens_value in t_lexed:
		if not t_tokens_value is PackedStringArray:
			console_output("[ERROR] parse_ast recibió una lista de tokens inválida", OutputType.ERROR)
			return NoResult.new()

		var t_tokens: PackedStringArray = t_tokens_value
		if t_tokens.is_empty():
			continue

		var t_parsed = _parse_command_ast(t_tokens, 0)
		if t_parsed is NoResult:
			debug_output("[PARSE] ERROR: comando no pudo convertirse a AST")
			return NoResult.new()

		if not t_parsed is TCommandCall:
			return NoResult.new()

		t_block.t_commands.append(t_parsed)
		debug_output("[PARSE] AST command=%s" % t_parsed.t_name)

	debug_output("[PARSE] Fin. comandos=%d" % t_block.t_commands.size())
	return t_block


## Parsea un único comando a AST, sin ejecutarlo.
func _parse_command_ast(
	t_tokens: PackedStringArray,
	t_index: int = 0
) -> Variant:
	if t_index < 0 or t_index >= t_tokens.size():
		return NoResult.new()

	var t_parsed := _parse_command_call(
		t_tokens,
		t_index,
		t_tokens.size()
	)

	if t_parsed["value"] is NoResult:
		return NoResult.new()

	var t_call = t_parsed["value"]
	if not t_call is TCommandCall:
		var t_unknown := str(t_tokens[t_index])
		console_output(
			"[ERROR] Comando desconocido: %s" % t_unknown,
			OutputType.ERROR
		)
		return NoResult.new()

	if t_parsed["next_index"] != t_tokens.size():
		console_output(
			"[ERROR] Argumentos sobrantes después de '%s'" % t_call.t_name,
			OutputType.ERROR
		)
		return NoResult.new()

	return t_call


## Ejecuta un AST ya construido. No hace lexing ni parsing.
func execute_ast(t_ast: Variant) -> Variant:
	if t_ast is TCommandBlock:
		return await _execute_block(t_ast)
	if t_ast is TCommandCall:
		return await _execute_call(t_ast)

	console_output("[ERROR] execute_ast recibió un AST inválido", OutputType.ERROR)
	return NoResult.new()


## Compatibilidad con la API anterior. Ahora parsea, no ejecuta.
func parse_command(
	t_tokens: PackedStringArray,
	t_index: int = 0
) -> Variant:
	return _parse_command_ast(t_tokens, t_index)


## Compatibilidad: parse_text() ahora es simplemente lex() + parse_ast().
func parse_text(t_text: String) -> Variant:
	if _has_unclosed_block(t_text):
		console_output("[ERROR] El texto CAB contiene un bloque sin cerrar", OutputType.ERROR)
		return NoResult.new()

	return parse_ast(lex(t_text))


## Compatibilidad: ejecuta un AST ya construido.
func execute_call_block(t_value: Variant) -> Variant:
	return await execute_ast(t_value)

#endregion

#region AST Serialization

const CABC_MAGIC := "CABC"
const CABC_VERSION := 1


## Convierte el AST en una estructura compuesta únicamente por Variants básicos.
## Eso permite usar store_var() sin serializar instancias de clases internas.
func _ast_encode(t_value: Variant) -> Variant:
	if t_value is TCommandCall:
		var t_call: TCommandCall = t_value
		var t_args: Array = []
		for t_argument in t_call.t_args:
			t_args.append(_ast_encode(t_argument))
		return {
			"type": "call",
			"name": t_call.t_name,
			"args": t_args
		}

	if t_value is TCommandBlock:
		var t_block: TCommandBlock = t_value
		var t_commands: Array = []
		for t_command in t_block.t_commands:
			t_commands.append(_ast_encode(t_command))
		return {
			"type": "block",
			"source": t_block.t_source,
			"commands": t_commands
		}

	if t_value is TStructureClause:
		var t_clause: TStructureClause = t_value
		var t_clause_args: Array = []
		for t_argument in t_clause.t_args:
			t_clause_args.append(_ast_encode(t_argument))
		return {
			"type": "structure_clause",
			"name": t_clause.t_name,
			"args": t_clause_args,
			"block": _ast_encode(t_clause.t_block)
		}

	if t_value is TDeferredValue:
		var t_deferred: TDeferredValue = t_value
		return {
			"type": "deferred",
			"text": t_deferred.t_text,
			"expression": t_deferred.t_expression
		}

	if t_value is Array:
		var t_array: Array = []
		for t_item in t_value:
			t_array.append(_ast_encode(t_item))
		return t_array

	if t_value is Dictionary:
		var t_dictionary: Dictionary = {}
		for t_key in t_value:
			t_dictionary[t_key] = _ast_encode(t_value[t_key])
		return t_dictionary

	return t_value


## Reconstruye las clases del AST a partir de la representación serializable.
func _ast_decode(t_value: Variant) -> Variant:
	if t_value is Array:
		var t_array: Array = []
		for t_item in t_value:
			t_array.append(_ast_decode(t_item))
		return t_array

	if not t_value is Dictionary:
		return t_value

	var t_dictionary: Dictionary = t_value
	var t_type := str(t_dictionary.get("type", ""))

	match t_type:
		"call":
			var t_call := TCommandCall.new(
				str(t_dictionary.get("name", ""))
			)
			var t_args_value = t_dictionary.get("args", [])
			if not t_args_value is Array:
				return NoResult.new()
			for t_argument in t_args_value:
				t_call.t_args.append(_ast_decode(t_argument))
			return t_call

		"block":
			var t_block := TCommandBlock.new(
				[],
				str(t_dictionary.get("source", ""))
			)
			var t_commands_value = t_dictionary.get("commands", [])
			if not t_commands_value is Array:
				return NoResult.new()
			for t_command in t_commands_value:
				var t_decoded = _ast_decode(t_command)
				if not t_decoded is TCommandCall:
					return NoResult.new()
				t_block.t_commands.append(t_decoded)
			return t_block

		"structure_clause":
			var t_clause_args_value = t_dictionary.get("args", [])
			if not t_clause_args_value is Array:
				return NoResult.new()
			var t_clause := TStructureClause.new(
				str(t_dictionary.get("name", "")),
				[],
				_ast_decode(t_dictionary.get("block", null))
			)
			for t_argument in t_clause_args_value:
				t_clause.t_args.append(_ast_decode(t_argument))
			return t_clause

		"deferred":
			return TDeferredValue.new(
				str(t_dictionary.get("text", "")),
				bool(t_dictionary.get("expression", false))
			)

	return t_dictionary


## Guarda un AST en un archivo .cabc.
## El archivo contiene solo Variants serializables, no objetos ejecutables.
func store_ast(t_ast: Variant, t_path: String) -> bool:
	if not t_path.to_lower().ends_with(".cabc"):
		console_output("[ERROR] store_ast requiere una ruta con extensión .cabc", OutputType.ERROR)
		return false

	if not (t_ast is TCommandBlock or t_ast is TCommandCall):
		console_output("[ERROR] store_ast recibió un AST inválido", OutputType.ERROR)
		return false

	var t_file := FileAccess.open(t_path, FileAccess.WRITE)
	if t_file == null:
		console_output("[ERROR] No se pudo abrir .cabc para escritura: %s" % t_path, OutputType.ERROR)
		return false

	var t_data := {
		"magic": CABC_MAGIC,
		"version": CABC_VERSION,
		"ast": _ast_encode(t_ast)
	}

	var t_ok := t_file.store_var(t_data)
	t_file.close()

	if not t_ok:
		console_output("[ERROR] No se pudo guardar el AST: %s" % t_path, OutputType.ERROR)
	return t_ok


## Carga un .cabc y reconstruye su AST.
func load_ast(t_path: String) -> Variant:
	if not t_path.to_lower().ends_with(".cabc"):
		console_output("[ERROR] load_ast requiere una ruta con extensión .cabc", OutputType.ERROR)
		return NoResult.new()

	if not FileAccess.file_exists(t_path):
		console_output("[ERROR] No existe el archivo .cabc: %s" % t_path, OutputType.ERROR)
		return NoResult.new()

	var t_file := FileAccess.open(t_path, FileAccess.READ)
	if t_file == null:
		console_output("[ERROR] No se pudo abrir .cabc: %s" % t_path, OutputType.ERROR)
		return NoResult.new()

	var t_data = t_file.get_var(false)
	var t_read_error: Error = t_file.get_error()
	t_file.close()

	if t_read_error != OK:
		console_output("[ERROR] No se pudo leer el .cabc: %s" % t_path, OutputType.ERROR)
		return NoResult.new()

	if not t_data is Dictionary:
		console_output("[ERROR] .cabc no contiene un contenedor válido", OutputType.ERROR)
		return NoResult.new()

	if str(t_data.get("magic", "")) != CABC_MAGIC:
		console_output("[ERROR] Archivo .cabc inválido", OutputType.ERROR)
		return NoResult.new()

	if int(t_data.get("version", -1)) != CABC_VERSION:
		console_output("[ERROR] Versión de .cabc no compatible: %s" % t_data.get("version"), OutputType.ERROR)
		return NoResult.new()

	return _ast_decode(t_data.get("ast", null))

#endregion
#region flujo de variables

func cmd_vget(t_args: Array) -> Variant:
	if t_args.size() != 1:
		console_output(
			"Uso: vget [name]",
			OutputType.ERROR
		)
		return NoResult.new()

	var t_name = str(t_args[0])

	if not _has_variable(t_name):
		console_output(
			"Variable no encontrada: " + t_name,
			OutputType.ERROR
		)
		return NoResult.new()

	return _get_variable(t_name)


func cmd_vset(t_args: Array) -> Variant:
	if t_args.size() != 2:
		console_output(
			"Uso: vset [name] [value]",
			OutputType.ERROR
		)
		return NoResult.new()

	var t_name = str(t_args[0])
	var t_value: Variant = t_args[1]

	_set_variable(t_name, t_value)

	return NoResult.new()

#endregion

#region log y new
func cmd_log(t_args: Array) -> Variant:
	if not t_args.is_empty():
		console_output(
			t_args[0],
			OutputType.LOG
		)

	return NoResult.new()

func cmd_new(t_args: Array) -> Variant:
	if t_args.is_empty():
		console_output(
			"Uso: new [CLASS]",
			OutputType.ERROR
		)
		return NoResult.new()

	var type_name = str(t_args[0]).strip_edges()

	if not ClassDB.class_exists(type_name):
		console_output(
			"[ERROR] Clase no encontrada: " + type_name,
			OutputType.ERROR
		)
		return NoResult.new()

	if not ClassDB.can_instantiate(type_name):
		console_output(
			"[ERROR] La clase no puede ser instanciada: " + type_name,
			OutputType.ERROR
		)
		return NoResult.new()

	return ClassDB.instantiate(type_name)

#endregion

#region get y set
func cmd_get(t_args: Array) -> Variant:
	var t_target: Variant
	var t_property: String

	if t_args.size() == 1:
		t_target = _current_context()
		t_property = str(t_args[0])

	elif t_args.size() == 2:
		t_target = _resolve_reference(
			str(t_args[0])
		)
		t_property = str(t_args[1])

	else:
		console_output(
			"Uso: get [route] [value]",
			OutputType.ERROR
		)
		return NoResult.new()

	if t_target == null or t_target is NoResult:
		console_output(
			"Referencia inválida",
			OutputType.ERROR
		)
		return NoResult.new()

	var t_result = _resolve_property_chain(
		t_target,
		t_property
	)

	if t_result is NoResult:
		console_output(
			"Propiedad no encontrada: " + t_property,
			OutputType.ERROR
		)
		return NoResult.new()

	return t_result


func cmd_set(t_args: Array) -> Variant:
	var t_target: Variant
	var t_property: String
	var t_value: Variant

	if t_args.size() == 2:
		t_target = _current_context()
		t_property = str(t_args[0])
		t_value = t_args[1]

	elif t_args.size() == 3:
		t_target = _resolve_reference(
			str(t_args[0])
		)
		t_property = str(t_args[1])
		t_value = t_args[2]

	else:
		console_output(
			"Uso: set [route] [value] [data]",
			OutputType.ERROR
		)
		return NoResult.new()

	if t_target == null or t_target is NoResult:
		console_output(
			"Referencia inválida",
			OutputType.ERROR
		)
		return NoResult.new()

	var t_endpoint = _resolve_property_parent(
		t_target,
		t_property
	)

	if t_endpoint.has("t_error"):
		console_output(
			"Propiedad no encontrada: " + t_property,
			OutputType.ERROR
		)
		return NoResult.new()

	var t_parent: Variant = t_endpoint["t_parent"]
	var t_leaf = str(t_endpoint["t_leaf"])

	if not _set_member(
		t_parent,
		t_leaf,
		t_value
	):
		console_output(
			"No se pudo asignar: " + t_property,
			OutputType.ERROR
		)
		return NoResult.new()

	return NoResult.new()

#endregion

#region call y emit

func cmd_call(t_args: Array) -> Variant:
	if t_args.is_empty():
		console_output(
			"Uso: call [route] [method] [parameters]",
			OutputType.ERROR
		)
		return NoResult.new()

	# El contexto siempre tiene prioridad.
	var t_target: Variant = _current_context()
	var t_method_index = 0

	# Si el primer argumento no es un método del contexto,
	# se interpreta como objeto/ruta.
	if t_args.size() >= 2:
		var t_first = str(t_args[0])

		if (
			t_target is Object
			and t_target.has_method(t_first)
		):
			t_method_index = 0
		else:
			var t_resolved = _resolve_reference(t_first)

			if (
				t_resolved != null
				and t_resolved is Object
			):
				t_target = t_resolved
				t_method_index = 1

	if (
		t_target == null
		or not t_target is Object
	):
		console_output(
			"Referencia inválida",
			OutputType.ERROR
		)
		return NoResult.new()

	var t_method = str(
		t_args[t_method_index]
	)

	if not t_target.has_method(t_method):
		console_output(
			"Método no encontrado: " + t_method,
			OutputType.ERROR
		)
		return NoResult.new()

	var t_parameters: Array = []

	for t_index in range(
		t_method_index + 1,
		t_args.size()
	):
		var t_parameter = t_args[t_index]

		# Solo la forma abreviada:
		#
		# call metodo parametro
		#
		# resuelve el primer parámetro.
		if (
			t_method_index == 0
			and t_index == 1
			and t_parameter is String
		):
			var t_resolved_parameter = _resolve_reference(
				t_parameter
			)

			if t_resolved_parameter != null:
				t_parameter = t_resolved_parameter

		t_parameters.append(t_parameter)

	return t_target.callv(
		t_method,
		t_parameters
	)

func cmd_emit(t_args: Array) -> Variant:
	if t_args.is_empty():
		console_output(
			"Uso: emit [route] [signal] [parameters]",
			OutputType.ERROR
		)
		return NoResult.new()

	var t_target: Variant = _current_context()
	var t_signal_index = 0

	if t_args.size() >= 2:
		var t_first = str(t_args[0])

		if (
			t_target is Object
			and t_target.has_signal(t_first)
		):
			t_signal_index = 0
		else:
			var t_resolved = _resolve_reference(
				t_first
			)

			if (
				t_resolved != null
				and t_resolved is Object
			):
				t_target = t_resolved
				t_signal_index = 1

	if (
		t_target == null
		or not t_target is Object
	):
		console_output(
			"Referencia inválida",
			OutputType.ERROR
		)
		return NoResult.new()

	var t_signal_name = str(
		t_args[t_signal_index]
	)

	if not t_target.has_signal(t_signal_name):
		console_output(
			"Señal no encontrada: " + t_signal_name,
			OutputType.ERROR
		)
		return NoResult.new()

	var t_parameters: Array = []

	for t_index in range(
		t_signal_index + 1,
		t_args.size()
	):
		t_parameters.append(
			t_args[t_index]
		)

	t_target.callv(
		"emit_signal",
		[t_signal_name] + t_parameters
	)

	return NoResult.new()

#endregion

#region rfm 1
func cmd_load(t_args: Array) -> Variant:
	if route_file_manager == null:
		console_output("[ERROR] RouteFileManager no está configurado", OutputType.ERROR)
		return NoResult.new()
	return route_file_manager.execute_load(t_args)


func cmd_cd(args: Array) -> Variant:
	if route_file_manager == null:
		console_output("[ERROR] RouteFileManager no está configurado", OutputType.ERROR)
		return NoResult.new()
	return route_file_manager.execute_cd(args)


func cmd_ls(args: Array) -> Variant:
	if route_file_manager == null:
		console_output("[ERROR] RouteFileManager no está configurado", OutputType.ERROR)
		return NoResult.new()
	return route_file_manager.execute_ls(args)


func cmd_pwd(args: Array) -> Variant:
	if route_file_manager == null:
		console_output("[ERROR] RouteFileManager no está configurado", OutputType.ERROR)
		return NoResult.new()
	return route_file_manager.execute_pwd(args)

#endregion

#region El Gran pkg
func cmd_pkg(t_args: Array) -> Variant:
	var error: Error = Error.ERR_BUG

	if package_manager == null:
		console_output("[ERROR] PackageManager no está configurado", OutputType.ERROR)
		return NoResult.new()

	if t_args.size() < 1:
		console_output(
			"Parámetros insuficientes. Use pkg [OPERACIÓN] [PARAMETROS...]",
			OutputType.ERROR
		)

		error = Error.ERR_PARAMETER_RANGE_ERROR
		return error

	var op: String = str(t_args[0])

	match op:
		"search":
			if t_args.size() < 2:
				console_output(
					"Uso: pkg search [PAQUETE]",
					OutputType.ERROR
				)
				return Error.ERR_PARAMETER_RANGE_ERROR

			return await package_manager.search_package(
				str(t_args[1])
			)

		_:
			console_output(
				"Operación de paquete desconocida: " + op,
				OutputType.ERROR
			)

			return error
#endregion

#region rfm 2
func cmd_rd(t_args: Array) -> Variant:
	if route_file_manager == null:
		console_output("[ERROR] RouteFileManager no está configurado", OutputType.ERROR)
		return NoResult.new()

	var result = route_file_manager.execute_rd(t_args)
	if result == null or result is NoResult:
		console_output("[ERROR] No se pudo leer archivo", OutputType.ERROR)
		return NoResult.new()
	return result

func cmd_mkdir(t_args: Array) -> Variant:
	if route_file_manager == null:
		console_output("[ERROR] RouteFileManager no está configurado", OutputType.ERROR)
		return NoResult.new()
	return route_file_manager.execute_mkdir(t_args)

func cmd_wr(t_args: Array) -> Variant:
	var t_runtime_args: Array = t_args.duplicate()
	if t_runtime_args.size() > 1:
		var t_text: String = str(t_runtime_args[1]).strip_edges()
		if t_text.begins_with("{") and t_text.ends_with("}"):
			t_runtime_args[1] = t_text.substr(1, t_text.length() - 2)
	if route_file_manager == null:
		console_output("[ERROR] RouteFileManager no está configurado", OutputType.ERROR)
		return NoResult.new()
	return route_file_manager.execute_wr(t_runtime_args)

func cmd_dl(t_args: Array) -> Variant:
	if route_file_manager == null:
		console_output("[ERROR] RouteFileManager no está configurado", OutputType.ERROR)
		return NoResult.new()
	return route_file_manager.execute_dl(t_args)

#endregion

#region funciones CAB
func cmd_func(t_args: Array) -> Variant:
	if t_args.size() != 3:
		console_output(
			"Uso: func [name] [parameters...] { ... }",
			OutputType.ERROR
		)
		return NoResult.new()

	var t_name: String = str(t_args[0])
	var t_parameters_value: Variant = t_args[1]
	var t_block: Variant = t_args[2]

	if not t_parameters_value is Array or not t_block is TCommandBlock:
		console_output("Definición de función inválida", OutputType.ERROR)
		return NoResult.new()

	var t_parameters: Array[String] = []
	for t_parameter_value in t_parameters_value:
		t_parameters.append(str(t_parameter_value))

	functions[t_name] = TFunction.new(
		t_name,
		t_parameters,
		t_block
	)

	return NoResult.new()


func cmd_fcall(t_args: Array) -> Variant:
	if t_args.is_empty():
		console_output(
			"Uso: fcall [name] [arguments...]",
			OutputType.ERROR
		)
		return NoResult.new()

	var t_name: String = str(t_args[0])
	if not functions.has(t_name):
		console_output(
			"Función no encontrada: " + t_name,
			OutputType.ERROR
		)
		return NoResult.new()

	var t_function_value: Variant = functions[t_name]
	if not t_function_value is TFunction:
		console_output(
			"Definición inválida para la función: " + t_name,
			OutputType.ERROR
		)
		return NoResult.new()

	var t_function: TFunction = t_function_value
	var t_argument_count: int = t_args.size() - 1
	if t_argument_count != t_function.t_parameters.size():
		console_output(
			"'%s' recibió %d argumentos; se esperaban %d" % [
				t_name,
				t_argument_count,
				t_function.t_parameters.size()
			],
			OutputType.ERROR
		)
		return NoResult.new()

	var t_scope: Dictionary = {}
	for t_index in range(t_function.t_parameters.size()):
		t_scope[t_function.t_parameters[t_index]] = t_args[t_index + 1]

	_push_variable_scope(t_scope)
	var t_result: Variant = await _execute_block(t_function.t_block)
	_pop_variable_scope()

	return t_result
#endregion

#region bloques_de_codigo

#region contexto comando
func cmd_at(t_args: Array) -> Variant:
	if t_args.size() != 2:
		console_output(
			"Uso: at [reference] [command]",
			OutputType.ERROR
		)
		return NoResult.new()

	var t_target: Variant = t_args[0]
	var t_nested = t_args[1]

	if t_target is String:
		t_target = _resolve_reference(t_target)

	if (
		t_target == null
		or t_target is NoResult
	):
		console_output(
			"Referencia inválida",
			OutputType.ERROR
		)
		return NoResult.new()

	if not (t_nested is TCommandCall or t_nested is TCommandBlock):
		console_output(
			"Se esperaba un comando o bloque",
			OutputType.ERROR
		)
		return NoResult.new()

	_push_context(t_target)

	var t_result: Variant
	if t_nested is TCommandBlock:
		t_result = await _execute_block(t_nested)
	else:
		t_result = await _execute_call(t_nested)

	_pop_context()

	return t_result
#endregion

#region repetidores

func cmd_while(t_args: Array) -> Variant:
	if t_args.size() != 2:
		console_output(
			"[FATAL] No se pudo ejecutar. Use: while [CONDICION] [COMANDO]",
			OutputType.FATAL
		)
		return NoResult.new()

	var t_condition = t_args[0]
	var t_command = t_args[1]
	var t_last: Variant = NoResult.new()
	var t_iterations := 0

	if not (t_command is TCommandCall or t_command is TCommandBlock):
		console_output("[ERROR] while esperaba un comando o un bloque", OutputType.ERROR)
		return NoResult.new()

	while true:
		var t_evaluated = _resolve_runtime_value(t_condition)

		if t_evaluated is NoResult:
			console_output("[ERROR] No se pudo evaluar la condición del while", OutputType.ERROR)
			return NoResult.new()

		if t_evaluated is TCommandCall or t_evaluated is TCommandBlock:
			console_output("[ERROR] La condición de while no puede ser un comando o bloque", OutputType.ERROR)
			return NoResult.new()

		if not bool(t_evaluated):
			break

		t_iterations += 1
		if t_iterations > max_loop_iterations:
			console_output("[ERROR] while superó el límite de %d iteraciones" % max_loop_iterations, OutputType.ERROR)
			return NoResult.new()

		if t_command is TCommandBlock:
			t_last = await _execute_block(t_command)
		else:
			t_last = await _execute_call(t_command)

		await get_tree().process_frame

	return t_last

func cmd_repeat(t_args: Array) -> Variant:
	if t_args.size() != 2:
		console_output(
			"Uso: repeat [amount] [command]",
			OutputType.ERROR
		)
		return NoResult.new()

	var t_amount: Variant = t_args[0]
	var t_nested = t_args[1]

	if not t_amount is int:
		console_output(
			"La cantidad debe ser un entero",
			OutputType.ERROR
		)
		return NoResult.new()

	if t_amount < 0:
		console_output(
			"La cantidad no puede ser negativa",
			OutputType.ERROR
		)
		return NoResult.new()

	if not (t_nested is TCommandCall or t_nested is TCommandBlock):
		console_output(
			"Se esperaba un comando o bloque",
			OutputType.ERROR
		)
		return NoResult.new()

	var t_final_result: Variant = NoResult.new()

	if t_amount > max_loop_iterations:
		console_output("[ERROR] repeat supera el límite de %d iteraciones" % max_loop_iterations, OutputType.ERROR)
		return NoResult.new()

	for _t_i in range(t_amount):
		var t_result: Variant
		if t_nested is TCommandBlock:
			t_result = await _execute_block(t_nested)
		else:
			t_result = await _execute_call(t_nested)

		if not (t_result is NoResult):
			t_final_result = t_result

		await get_tree().process_frame

	return t_final_result
#endregion
#endregion

#region Control de flujo

func _execute_block_result(t_block: Variant) -> Variant:
	if t_block is TCommandBlock:
		return await _execute_block(t_block)

	if t_block is TCommandCall:
		return await _execute_call(t_block)

	return NoResult.new()


func cmd_if(t_args: Array) -> Variant:
	if t_args.size() < 2:
		console_output(
			"Uso: if [CONDICION] [BLOQUE]",
			OutputType.ERROR
		)
		return NoResult.new()

	var t_condition = _resolve_runtime_value(t_args[0])
	if t_condition is NoResult:
		console_output(
			"No se pudo evaluar la condición del if",
			OutputType.ERROR
		)
		return NoResult.new()

	if t_condition is TCommandCall or t_condition is TCommandBlock:
		console_output(
			"[ERROR] La condición de if no puede ser un comando o bloque",
			OutputType.ERROR
		)
		return NoResult.new()

	if bool(t_condition):
		return await _execute_block_result(t_args[1])

	for t_index in range(2, t_args.size()):
		var t_clause = t_args[t_index]

		if not t_clause is TStructureClause:
			continue

		if t_clause.t_name == "else":
			return await _execute_block_result(t_clause.t_block)

		if (
				t_clause.t_name == "elsif"
				or t_clause.t_name == "elif"
		):
			if t_clause.t_args.is_empty():
				continue

			var t_clause_condition = _resolve_runtime_value(
				t_clause.t_args[0]
			)

			if t_clause_condition is NoResult:
				console_output(
					"No se pudo evaluar la condición de %s" % t_clause.t_name,
					OutputType.ERROR
				)
				return NoResult.new()

			if t_clause_condition is TCommandCall or t_clause_condition is TCommandBlock:
				console_output(
					"[ERROR] La condición de %s no puede ser un comando o bloque" % t_clause.t_name,
					OutputType.ERROR
				)
				return NoResult.new()

			if bool(t_clause_condition):
				return await _execute_block_result(
					t_clause.t_block
				)

	return NoResult.new()

#endregion

# ---------------------------------------------------------
# TU DICCIONARIO `commands` VA AQUÍ SIN CAMBIARLO.
# ---------------------------------------------------------

var commands = {
	"func": {
		"func": cmd_func,
		"args": 3,
		"lazy_args": {0: true, 1: true}
	},
	"fcall": {
		"func": cmd_fcall,
		"args": -1,
		"raw": {0: true},
		"lazy_args": {0: true}
	},
	"log": {
		"func": cmd_log,
		"args": 1,
	},
	"cd": {
		"func": cmd_cd,
		"args": 1,
		"raw": {0: true}
	},
	"pwd": {
		"func": cmd_pwd,
		"args": 0,
		"raw": {0: true}
	},
	"rd": {
		"func": cmd_rd,
		"args": 2,
		"raw": {0: true, 1: true}
	},
	"wr": {
		"func": cmd_wr,
		"args": 2,
		"raw": {0: true},
		"text_args": {1: true}
	},
	"dl": {
		"func": cmd_dl,
		"args": 1,
		"raw": {0: true}
	},
	"mkdir": {
		"func": cmd_mkdir,
		"args": 2,
		"raw": {0: true}
	},
	"ls": {
		"func": cmd_ls,
		"args": 0
	},
	"get": {
		"func": cmd_get,
		"args": -1,
		"raw": {0: true, 1: true}
	},
	"pkg": {
		"func": cmd_pkg,
		"args": -1,
		"raw": {0: true}
	},
	"set": {
		"func": cmd_set,
		"args": -1,
		"raw": {0: true, 1: true}
	},
	"call": {
		"func": cmd_call,
		"args": -1,
		"raw": {0: true, 1: true}
	},
	"emit": {
		"func": cmd_emit,
		"args": -1,
		"raw": {0: true, 1: true}
	},
	"vget": {
		"func": cmd_vget,
		"args": 1,
		"raw": {0: true}
	},
	"vset": {
		"func": cmd_vset,
		"args": 2,
		"raw": {0: true}
	},
	"load": {
		"func": cmd_load,
		"args": 1,
		"raw": {0: true}
	},
	"while": {
		"func": cmd_while,
		"args": 2,
		"call_args": {1: true},
		"block_args": {1: true},
		"lazy_args": {0: true}
	},
	"new": {
		"func": cmd_new,
		"args": 1,
		"raw": {0: true}
	},
	"at": {
		"func": cmd_at,
		"args": 2,
		"raw": {},
		"call_args": {1: true},
		"block_args": {1: true}
	},
	"repeat": {
		"func": cmd_repeat,
		"args": 2,
		"raw": {},
		"call_args": {1: true},
		"block_args": {1: true}
	},
	"if": {
		"func": cmd_if,
		"args": -1,
		"structure": {
			"head": {
				"args": 2,
				"block_args": {1: true}
			},
			"continuations": {
				"elsif": {
					"args": 2,
					"block_args": {1: true},
					"block_index": 1
				},
				"elif": {
					"args": 2,
					"block_args": {1: true},
					"block_index": 1
				},
				"else": {
					"args": 1,
					"block_args": {0: true},
					"block_index": 0,
					"terminal": true
				}
			}
		}
	}
}


func tokenize(t_text: String) -> PackedStringArray:
	debug_output("[TOKENIZE] Inicio: %s" % t_text)

	var t_tokens: PackedStringArray = PackedStringArray()
	var t_current: String = ""
	var t_quote: bool = false
	var t_escaped: bool = false
	var t_parentheses: int = 0
	var t_brackets: int = 0
	var t_braces: int = 0
	var t_comment: bool = false

	for t_character in t_text:
		if t_comment:
			if t_character == "\n":
				t_comment = false
				debug_output("[TOKENIZE] Fin de comentario")
			continue

		if t_escaped:
			t_current += t_character
			t_escaped = false
			continue

		if t_character == "\\" and t_quote:
			t_current += t_character
			t_escaped = true
			continue

		if t_character == '"':
			t_quote = not t_quote
			t_current += t_character
			continue

		if not t_quote and t_character == "#":
			t_comment = true
			if not t_current.is_empty():
				t_tokens.append(t_current)
				t_current = ""
			debug_output("[TOKENIZE] '#' detectado: ignorando resto de línea")
			continue

		if not t_quote:
			match t_character:
				"(":
					t_parentheses += 1
				")":
					t_parentheses -= 1
				"[":
					t_brackets += 1
				"]":
					t_brackets -= 1
				"{":
					t_braces += 1
				"}":
					t_braces -= 1

			if t_character == " " or t_character == "\t" or t_character == "\n":
				if (
					t_parentheses == 0
					and t_brackets == 0
					and t_braces == 0
				):
					if not t_current.is_empty():
						t_tokens.append(t_current)
						t_current = ""
					continue

		t_current += t_character

	if t_comment:
		debug_output("[TOKENIZE] EOF dentro de comentario: válido")

	if t_escaped:
		console_output("[CAB EOF ERROR] Escape incompleto en tokenize()", OutputType.ERROR)
		return PackedStringArray()

	if t_quote:
		console_output("[CAB EOF ERROR] Cadena sin cerrar en tokenize()", OutputType.ERROR)
		return PackedStringArray()

	if t_parentheses < 0:
		console_output("[CAB ERROR] ')' inesperado en tokenize()", OutputType.ERROR)
		return PackedStringArray()
	if t_brackets < 0:
		console_output("[CAB ERROR] ']' inesperado en tokenize()", OutputType.ERROR)
		return PackedStringArray()
	if t_braces < 0:
		console_output("[CAB ERROR] '}' inesperado en tokenize()", OutputType.ERROR)
		return PackedStringArray()

	if t_parentheses > 0:
		console_output("[CAB EOF ERROR] '(' sin cerrar en tokenize()", OutputType.ERROR)
		return PackedStringArray()
	if t_brackets > 0:
		console_output("[CAB EOF ERROR] '[' sin cerrar en tokenize()", OutputType.ERROR)
		return PackedStringArray()
	if t_braces > 0:
		console_output("[CAB EOF ERROR] '{' sin cerrar en tokenize()", OutputType.ERROR)
		return PackedStringArray()

	if not t_current.is_empty():
		t_tokens.append(t_current)

	debug_output("[TOKENIZE] Fin. tokens=%d -> %s" % [t_tokens.size(), str(t_tokens)])
	return t_tokens

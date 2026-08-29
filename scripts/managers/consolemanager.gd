@icon("res://assets/icon/consolemanager.svg")
extends Node
class_name ConsoleManager


## Clase para gestionar una consola con comandos y control del motor.
## Se recomienda usar execute() y conectar output para obtener resultados.
signal output(out: String)


## RouteFileManager encargado de resolver rutas externas a ConsoleManager.
## Debe exponer una función resolve_reference(text: String) -> Variant.
@export var route_file_manager: RouteFileManager


## Variables internas de la consola.
@export var variables: Dictionary = {}


## Último resultado válido producido por un comando.
## Se puede utilizar mediante @.
var last_value: Variant = null


## Contexto temporal utilizado por `at`.
## No representa una ruta permanente.
var context_stack: Array[Variant] = []


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


func console_output(
	t_value: Variant,
	type: OutputType = OutputType.LOG
) -> void:
	var message := str(t_value)

	var color := Color.WHITE

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

	var formatted := "[color=%s]%s[/color]" % [
		color.to_html(),
		message
	]

	output.emit(formatted)


func _current_context() -> Variant:
	if context_stack.is_empty():
		return self

	return context_stack.back()


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

		var t_index := int(t_member)
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

		var t_index := int(t_member)
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
	var t_parts := t_chain.split(":")

	if t_parts.is_empty():
		return {"t_error": true}

	var t_current: Variant = t_base

	for t_index in range(t_parts.size() - 1):
		var t_part := t_parts[t_index].strip_edges()

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

	if variables.has(t_text):
		return variables[t_text]

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
	if t_text.is_empty():
		return false

	if t_text.begins_with("\"") and t_text.ends_with("\""):
		return false

	if (
		t_text == "null"
		or t_text == "true"
		or t_text == "false"
	):
		return false

	if t_text == "@":
		return false

	for t_character in [
		"+",
		"-",
		"*",
		"/",
		"%",
		"(",
		")",
		".",
		",",
		"[",
		"]",
		"{",
		"}"
	]:
		if t_text.find(t_character) != -1:
			return true

	return false


func preprocess_expression(t_text: String) -> String:
	return t_text.replace("@", "last")


func evaluate_expression(t_text: String) -> Variant:
	var t_expression := Expression.new()
	var t_parsed_text := preprocess_expression(t_text)

	var t_error := t_expression.parse(t_parsed_text)

	if t_error != OK:
		return NoResult.new()

	var t_context := ConsoleContext.new(
		last_value,
		_current_context(),
		variables
	)

	var t_result = t_expression.execute([], t_context)

	if t_expression.has_execute_failed():
		return NoResult.new()

	return t_result


func evaluate_raw_expression(t_text: String) -> Variant:
	var t_expression := Expression.new()

	var t_error := t_expression.parse(t_text)

	if t_error != OK:
		return NoResult.new()

	var t_result = t_expression.execute(
		[],
		ConsoleContext.new(
			last_value,
			_current_context(),
			variables
		)
	)

	if t_expression.has_execute_failed():
		return NoResult.new()

	return t_result


func parse_value(t_value: String) -> Variant:
	t_value = t_value.strip_edges()

	if t_value == "@":
		return last_value

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

	if variables.has(t_value):
		return variables[t_value]

	if t_value.is_valid_int():
		return int(t_value)

	if t_value.is_valid_float():
		return float(t_value)

	if _looks_like_expression(t_value):
		var t_expression_result = evaluate_expression(t_value)

		if not (t_expression_result is NoResult):
			return t_expression_result

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
		return {
			"value": t_tokens[t_index],
			"next_index": t_index + 1
		}

	var t_token := t_tokens[t_index]

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


func _ready() -> void:
	var tree: SceneTree = get_tree()
	variables["tree"] = tree


func _parse_command_call(
	t_tokens: PackedStringArray,
	t_index: int,
	t_end: int
) -> Dictionary:
	if t_index >= t_end:
		return {
			"value": NoResult.new(),
			"next_index": t_index
		}

	var t_token := t_tokens[t_index]

	if not t_token in commands:
		return {
			"value": parse_value(t_token),
			"next_index": t_index + 1
		}

	var t_command_data: Dictionary = commands[t_token]
	var t_amount: int = t_command_data["args"]
	var t_raw: Array = t_command_data.get("raw", [])

	var t_call := TCommandCall.new(t_token)

	if t_token == "at":
		if t_index + 2 >= t_end:
			return {
				"value": NoResult.new(),
				"next_index": t_end
			}

		var t_reference = parse_value(
			t_tokens[t_index + 1]
		)

		var t_nested := _parse_command_call(
			t_tokens,
			t_index + 2,
			t_end
		)

		if t_nested["value"] is NoResult:
			return {
				"value": NoResult.new(),
				"next_index": t_end
			}

		t_call.t_args = [
			t_reference,
			t_nested["value"]
		]

		return {
			"value": t_call,
			"next_index": t_nested["next_index"]
		}

	if t_token == "repeat":
		if t_index + 2 >= t_end:
			return {
				"value": NoResult.new(),
				"next_index": t_end
			}

		var t_amount_result = parse_value(
			t_tokens[t_index + 1]
		)

		var t_nested_repeat := _parse_command_call(
			t_tokens,
			t_index + 2,
			t_end
		)

		if t_nested_repeat["value"] is NoResult:
			return {
				"value": NoResult.new(),
				"next_index": t_end
			}

		t_call.t_args = [
			t_amount_result,
			t_nested_repeat["value"]
		]

		return {
			"value": t_call,
			"next_index": t_nested_repeat["next_index"]
		}

	if t_amount == -1:
		for t_argument_index in range(
			t_index + 1,
			t_end
		):
			var t_argument_position := (
				t_argument_index - t_index - 1
			)

			if t_argument_position in t_raw:
				t_call.t_args.append(
					t_tokens[t_argument_index]
				)
			else:
				t_call.t_args.append(
					parse_value(
						t_tokens[t_argument_index]
					)
				)

		return {
			"value": t_call,
			"next_index": t_end
		}

	var t_current_index := t_index + 1

	for t_argument_index in range(t_amount):
		if t_current_index >= t_end:
			break

		var t_is_raw := t_argument_index in t_raw

		var t_parsed := _parse_argument(
			t_tokens,
			t_current_index,
			t_end,
			t_is_raw
		)

		if t_parsed["value"] is NoResult:
			break

		t_call.t_args.append(
			t_parsed["value"]
		)

		t_current_index = t_parsed["next_index"]

	return {
		"value": t_call,
		"next_index": t_current_index
	}


func _execute_call(t_call: TCommandCall) -> Variant:
	if t_call == null:
		return NoResult.new()

	if not commands.has(t_call.t_name):
		return NoResult.new()

	var t_command_data: Dictionary = commands[
		t_call.t_name
	]

	var t_function: Callable = t_command_data["func"]

	var t_result = await t_function.call(
		t_call.t_args
	)

	if not (t_result is NoResult):
		last_value = t_result

	return t_result


func parse_command(
	t_tokens: PackedStringArray,
	t_index := 0
) -> Variant:
	var t_parsed := _parse_command_call(
		t_tokens,
		t_index,
		t_tokens.size()
	)

	if t_parsed["value"] is NoResult:
		return NoResult.new()

	var t_call = t_parsed["value"]

	if not t_call is TCommandCall:
		return t_call

	return await _execute_call(t_call)


func cmd_vget(t_args: Array) -> Variant:
	if t_args.size() != 1:
		console_output(
			"Uso: vget [name]",
			OutputType.ERROR
		)
		return NoResult.new()

	var t_name := str(t_args[0])

	if not variables.has(t_name):
		console_output(
			"Variable no encontrada: " + t_name,
			OutputType.ERROR
		)
		return NoResult.new()

	return variables[t_name]


func cmd_vset(t_args: Array) -> Variant:
	if t_args.size() != 2:
		console_output(
			"Uso: vset [name] [value]",
			OutputType.ERROR
		)
		return NoResult.new()

	var t_name := str(t_args[0])
	var t_value: Variant = t_args[1]

	variables[t_name] = t_value

	return NoResult.new()


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
			"Uso: new [expression]",
			OutputType.ERROR
		)
		return NoResult.new()

	var t_expression := " ".join(t_args)

	var t_result = evaluate_raw_expression(
		t_expression
	)

	if not (t_result is NoResult):
		return t_result

	var t_type_name := str(t_args[0])

	if ClassDB.class_exists(t_type_name):
		if not ClassDB.can_instantiate(t_type_name):
			console_output(
				"La clase no puede ser instanciada: "
				+ t_type_name,
				OutputType.ERROR
			)
			return NoResult.new()

		return ClassDB.instantiate(t_type_name)

	console_output(
		"No se pudo crear: " + t_expression,
		OutputType.ERROR
	)

	return NoResult.new()


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

	var t_endpoint := _resolve_property_parent(
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
	var t_leaf := str(t_endpoint["t_leaf"])

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


func cmd_call(t_args: Array) -> Variant:
	if t_args.is_empty():
		console_output(
			"Uso: call [route] [method] [parameters]",
			OutputType.ERROR
		)
		return NoResult.new()

	var t_target: Variant = _current_context()
	var t_method_index := 0

	if t_args.size() >= 2:
		var t_first := str(t_args[0])

		if (
			t_target is Object
			and t_target.has_method(t_first)
		):
			t_method_index = 0
		else:
			var t_resolved = _resolve_reference(
				t_first
			)

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

	var t_method := str(
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
		t_parameters.append(
			t_args[t_index]
		)

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
	var t_signal_index := 0

	if t_args.size() >= 2:
		var t_first := str(t_args[0])

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

	var t_signal_name := str(
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


func cmd_load(t_args: Array) -> Variant:
	return route_file_manager.execute_load(t_args)


func cmd_cd(args: Array) -> Variant:
	return route_file_manager.execute_cd(args)


func cmd_ls(args: Array) -> Variant:
	return route_file_manager.execute_ls(args)


func cmd_pwd(args: Array) -> Variant:
	return route_file_manager.execute_pwd(args)


func cmd_pkg(t_args: Array) -> Variant:
	var error: Error = Error.ERR_BUG

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

func cmd_rd(t_args: Array) -> Variant:
	var result = route_file_manager.execute_rd(t_args)
	if not result:
		console_output("[ERROR] No se pudo leer archivo", OutputType.ERROR)
		return
	return result

func cmd_wr(t_args : Array) -> Variant:
	var result = route_file_manager.execute_wr(t_args)
	if not result:
		console_output("[ERROR] No se pudo leer archivo", OutputType.FATAL)
		return
	return result

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

	if not t_nested is TCommandCall:
		console_output(
			"Se esperaba un comando",
			OutputType.ERROR
		)
		return NoResult.new()

	_push_context(t_target)

	var t_result = await _execute_call(t_nested)

	_pop_context()

	return t_result


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

	if not t_nested is TCommandCall:
		console_output(
			"Se esperaba un comando",
			OutputType.ERROR
		)
		return NoResult.new()

	var t_final_result: Variant = NoResult.new()

	for _t_i in range(t_amount):
		var t_result = await _execute_call(t_nested)

		if not (t_result is NoResult):
			t_final_result = t_result

	return t_final_result


# ---------------------------------------------------------
# TU DICCIONARIO `commands` VA AQUÍ SIN CAMBIARLO.
# ---------------------------------------------------------

var commands := {
	"log": {
		"func": cmd_log,
		"args": 1,
	},
	"cd" : {
		"func" : cmd_cd,
		"args" : 1,
		"raw" : [0]
	},
	"pwd" : {
		"func": cmd_pwd,
		"args": 1,
		"raw": [0]
	},
	"rd" : {
		"func" : cmd_rd,
		"args" : 2,
		"raw" : [2]
	},
	"wr": {
		"func" : cmd_wr,
		"args" : 3,
		"raw" : [2]
	},
	"ls" : {
		"func" : cmd_ls,
		"args" : 0
	},
	"get": {
		"func": cmd_get,
		"args": 2,
		"raw": [0]
	},
	"pkg" : {
		"func" : cmd_pkg,
		"args" : -1,
		"raw" : []
	},
	"set": {
		"func": cmd_set,
		"args": 3,
		"raw": [0]
	},
	"call": {
		"func": cmd_call,
		"args": -1,
		"raw": [0, 1]
	},
	"emit": {
		"func": cmd_emit,
		"args": -1,
		"raw": [0, 1]
	},
	"vget": {
		"func": cmd_vget,
		"args": 1,
		"raw": [0]
	},
	"vset": {
		"func": cmd_vset,
		"args": 2,
		"raw": [0]
	},
	"load": {
		"func": cmd_load,
		"args": 1
	},
	"new": {
		"func": cmd_new,
		"args": -1
	},
	"at": {
		"func": cmd_at,
		"args": 2,
		"raw": []
	},
	"repeat": {
		"func": cmd_repeat,
		"args": 2,
		"raw": []
	}
}


func tokenize(t_text: String) -> PackedStringArray:
	var t_tokens := PackedStringArray()

	var t_current := ""
	var t_quote := false
	var t_parentheses := 0
	var t_brackets := 0
	var t_braces := 0

	for t_character in t_text:
		match t_character:
			"\"":
				t_quote = not t_quote
				t_current += t_character

			"(":
				t_parentheses += 1
				t_current += t_character

			")":
				t_parentheses -= 1
				t_current += t_character

			"[":
				t_brackets += 1
				t_current += t_character

			"]":
				t_brackets -= 1
				t_current += t_character

			"{":
				t_braces += 1
				t_current += t_character

			"}":
				t_braces -= 1
				t_current += t_character

			" ":
				if (
					not t_quote
					and t_parentheses == 0
					and t_brackets == 0
					and t_braces == 0
				):
					if not t_current.is_empty():
						t_tokens.append(t_current)
						t_current = ""
				else:
					t_current += t_character

			_:
				t_current += t_character

	if not t_current.is_empty():
		t_tokens.append(t_current)

	return t_tokens


func execute(t_command: String) -> int:
	t_command = t_command.replace(";", "\n")

	var t_command_lines := t_command.split("\n")

	if t_command_lines.is_empty():
		return 1

	for t_line in t_command_lines:
		var t_text := t_line.strip_edges()

		if t_text.is_empty():
			continue

		var t_tokens := tokenize(t_text)

		if t_tokens.is_empty():
			continue

		var t_result = await parse_command(t_tokens)

		if not (t_result is NoResult):
			last_value = t_result

	return 0

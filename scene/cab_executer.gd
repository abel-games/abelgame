extends PackedPackage
class_name CABExecuter


var data: Dictionary

const MAX_DEPTH: int = 32
const MAX_FILE_SIZE: int = 4 * 1024 * 1024
const DEFAULT_PHASE: String = "execute"

var _execution_stack: Array[String] = []


func give_data(t_data: Dictionary) -> void:
	data = t_data

	var t_cm: ConsoleManager = data.get("cm") as ConsoleManager

	if t_cm == null:
		return

	var t_commands: Dictionary = t_cm.commands as Dictionary

	t_commands["cab"] = {
		"func": cmd_cab,
		"args": -1,
		"raw": {
			0: true,
			1: true
		}
	}

	_debug(t_cm, "CABExecuter registrado correctamente.")


func cmd_cab(t_args: Array) -> Variant:
	var t_cm: ConsoleManager = data.get("cm") as ConsoleManager

	_debug(t_cm, "----------------------------------------")
	_debug(t_cm, "CAB command iniciado.")
	_debug(t_cm, "Argumentos: %s" % str(t_args))

	if t_args.is_empty() or t_args.size() > 2:
		return _cab_error(
			"Uso: cab [archivo.cab|archivo.cabc] [lex|parse|compile|execute]"
		)

	var t_target: String = str(t_args[0]).strip_edges()
	var t_phase: String = DEFAULT_PHASE

	if t_args.size() == 2:
		t_phase = str(t_args[1]).strip_edges().to_lower()

	_debug(t_cm, "Target recibido: '%s'" % t_target)
	_debug(t_cm, "Fase solicitada: '%s'" % t_phase)

	if t_target.is_empty():
		return _cab_error("La ruta de CAB está vacía")

	if ".." in t_target:
		return _cab_error("No se permiten rutas con '..'")

	var t_lower_target: String = t_target.to_lower()

	var t_is_cab: bool = t_lower_target.ends_with(".cab")
	var t_is_cabc: bool = t_lower_target.ends_with(".cabc")

	_debug(t_cm, "Es .cab: %s" % str(t_is_cab))
	_debug(t_cm, "Es .cabc: %s" % str(t_is_cabc))

	if not t_is_cab and not t_is_cabc:
		return _cab_error(
			"CAB solo admite archivos .cab o .cabc"
		)

	if t_is_cabc and t_phase != "execute":
		return _cab_error(
			"Un .cabc solo puede ejecutarse; usa \'cab archivo.cab compile\' para generarlo"
		)

	if t_phase not in ["lex", "parse", "compile", "execute"]:
		return _cab_error(
			"Fase desconocida: %s" % t_phase
		)

	var t_rfm: RouteFileManager = data.get("rfm") as RouteFileManager

	if t_cm == null or t_rfm == null:
		return _cab_error(
			"CABExecuter no recibió ConsoleManager o RouteFileManager"
		)

	var t_base_path: String = t_rfm.get_physical_route()

	_debug(t_cm, "Ruta física actual: '%s'" % t_base_path)

	if t_base_path.is_empty():
		return _cab_error(
			"No se pudo obtener la ruta física actual"
		)

	var t_path: String = t_base_path.path_join(t_target).simplify_path()

	_debug(t_cm, "Ruta física final: '%s'" % t_path)

	if _execution_stack.has(t_path):
		return _cab_error(
			"Ejecución recursiva/cíclica detectada: %s" % t_path
		)

	if _execution_stack.size() >= MAX_DEPTH:
		return _cab_error(
			"Se alcanzó la profundidad máxima de ejecución (%d)"
			% MAX_DEPTH
		)

	if not FileAccess.file_exists(t_path):
		return _cab_error(
			"Archivo CAB no encontrado: %s" % t_path
		)

	var t_file: FileAccess = FileAccess.open(
		t_path,
		FileAccess.READ
	)

	if t_file == null:
		return _cab_error(
			"No se pudo abrir: %s" % t_path
		)

	var t_file_size: int = t_file.get_length()

	_debug(
		t_cm,
		"Tamaño del archivo: %d bytes" % t_file_size
	)

	if t_file_size > MAX_FILE_SIZE:
		t_file.close()

		return _cab_error(
			"El archivo supera el límite de %d bytes"
			% MAX_FILE_SIZE
		)

	_execution_stack.append(t_path)

	_debug(
		t_cm,
		"Stack PUSH -> profundidad: %d"
		% _execution_stack.size()
	)

	var t_result: Variant

	if t_is_cab:
		var t_text: String = t_file.get_as_text()

		t_file.close()

		_debug(
			t_cm,
			"Archivo .cab leído. Caracteres: %d"
			% t_text.length()
		)

		t_result = await _execute_cab_source(
			t_cm,
			t_text,
			t_path,
			t_phase
		)

	else:
		t_file.close()

		_debug(
			t_cm,
			"Archivo .cabc detectado. Cargando AST..."
		)

		t_result = await _execute_cabc(
			t_cm,
			t_path
		)

	if not _execution_stack.is_empty():
		_execution_stack.pop_back()

	_debug(
		t_cm,
		"Stack POP -> profundidad: %d"
		% _execution_stack.size()
	)

	_debug(
		t_cm,
		"CAB finalizado. Resultado: %s"
		% str(t_result)
	)

	_debug(t_cm, "----------------------------------------")

	return t_result


func _execute_cab_source(
	t_cm: ConsoleManager,
	t_text: String,
	t_source_path: String,
	t_phase: String
) -> Variant:

	_debug(
		t_cm,
		"Entrando a fase '%s' -> %s"
		% [t_phase, t_source_path]
	)

	match t_phase:

		"lex":
			_debug(t_cm, "Ejecutando LEX...")

			var t_lexed: Variant = t_cm.lex(t_text)

			_debug(
				t_cm,
				"LEX terminado. Resultado: %s"
				% str(t_lexed)
			)

			return t_lexed


		"parse":
			_debug(t_cm, "Ejecutando LEX para PARSE...")

			var t_lexed: Variant = t_cm.lex(t_text)

			_debug(
				t_cm,
				"Tokens obtenidos: %s"
				% str(t_lexed)
			)

			if t_lexed.is_empty() and not t_text.strip_edges().is_empty():
				_cab_error(
					"El lexer no produjo tokens aunque el archivo contiene texto."
				)

				return ConsoleManager.NoResult.new()

			_debug(t_cm, "Ejecutando PARSE...")

			var t_ast: Variant = t_cm.parse_ast(t_lexed)

			_debug(
				t_cm,
				"AST generado: %s"
				% str(t_ast)
			)

			return t_ast


		"compile":
			_debug(t_cm, "Ejecutando COMPILACIÓN...")

			var t_lexed: Variant = t_cm.lex(t_text)

			_debug(
				t_cm,
				"LEX para compile terminado."
			)

			if t_lexed.is_empty() and not t_text.strip_edges().is_empty():
				_cab_error(
					"El lexer no produjo tokens durante compile."
				)

				return ConsoleManager.NoResult.new()

			var t_ast: Variant = t_cm.parse_ast(t_lexed)

			if t_ast is ConsoleManager.NoResult:
				_cab_error(
					"parse_ast() devolvió NoResult durante compile."
				)

				return t_ast

			_debug(
				t_cm,
				"AST válido. Guardando .cabc..."
			)

			var t_cabc_path: String = t_source_path

			if t_cabc_path.to_lower().ends_with(".cab"):
				t_cabc_path = (
					t_cabc_path.left(
						t_cabc_path.length() - 4
					)
					+ ".cabc"
				)

			_debug(
				t_cm,
				"Ruta de salida: %s"
				% t_cabc_path
			)

			var t_stored: bool = t_cm.store_ast(
				t_ast,
				t_cabc_path
			)

			if not t_stored:
				return _cab_error(
					"No se pudo guardar el archivo .cabc"
				)

			_debug(
				t_cm,
				"Compilación completada correctamente."
			)

			return t_cabc_path


		"execute":
			_debug(t_cm, "Ejecutando archivo CAB...")

			var t_lexed: Variant = t_cm.lex(t_text)

			_debug(
				t_cm,
				"LEX terminado."
			)

			if t_lexed.is_empty() and not t_text.strip_edges().is_empty():
				return _cab_error(
					"El lexer no produjo tokens durante execute."
				)

			var t_ast: Variant = t_cm.parse_ast(t_lexed)

			_debug(
				t_cm,
				"PARSE terminado. AST: %s"
				% str(t_ast)
			)

			if t_ast is ConsoleManager.NoResult:
				return _cab_error(
					"parse_ast() devolvió NoResult durante execute."
				)

			_debug(
				t_cm,
				"Ejecutando AST..."
			)

			var t_result: Variant = await t_cm.execute_ast(t_ast)

			_debug(
				t_cm,
				"execute_ast() terminó. Resultado: %s"
				% str(t_result)
			)

			return t_result


	return _cab_error(
		"Fase no implementada: %s" % t_phase
	)


func _execute_cabc(
	t_cm: ConsoleManager,
	t_path: String
) -> Variant:

	_debug(
		t_cm,
		"Cargando AST compilado: %s"
		% t_path
	)

	var t_ast: Variant = t_cm.load_ast(t_path)

	if t_ast is ConsoleManager.NoResult:
		return _cab_error(
			"load_ast() devolvió NoResult."
		)

	_debug(
		t_cm,
		"AST cargado correctamente."
	)

	_debug(
		t_cm,
		"Ejecutando AST compilado..."
	)

	var t_result: Variant = await t_cm.execute_ast(t_ast)

	_debug(
		t_cm,
		"AST compilado ejecutado. Resultado: %s"
		% str(t_result)
	)

	return t_result


func _debug(
	t_cm: ConsoleManager,
	t_message: String
) -> void:

	if t_cm == null:
		return

	if not "variables" in t_cm:
		return

	var t_variables: Dictionary = t_cm.variables

	if not t_variables.has("debug"):
		return

	if not bool(t_variables.get("debug")):
		return

	t_cm.console_output(
		"[CAB DEBUG] %s" % t_message,
		ConsoleManager.OutputType.DEBUG
	)


func _cab_error(t_message: String) -> Variant:

	var t_cm: ConsoleManager = data.get("cm") as ConsoleManager

	if t_cm != null:
		t_cm.console_output(
			"[CAB ERROR] %s" % t_message,
			ConsoleManager.OutputType.ERROR
		)

	return ConsoleManager.NoResult.new()

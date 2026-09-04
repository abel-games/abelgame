extends PackedPackage
class_name CABExecuter

var data: Dictionary

const MAX_DEPTH := 32
const MAX_FILE_SIZE := 4 * 1024 * 1024
const DEFAULT_PHASE := "execute"

var _execution_stack: Array[String] = []


func give_data(t_data: Dictionary) -> void:
	data = t_data

	var t_cm: ConsoleManager = data.get("cm") as ConsoleManager
	if t_cm == null:
		return

	(t_cm.commands as Dictionary)["cab"] = {
		"func": cmd_cab,
		"args": -1,
		"raw": {0: true, 1: true}
	}


func cmd_cab(t_args: Array) -> Variant:
	if t_args.is_empty() or t_args.size() > 2:
		return _cab_error("Uso: cab [archivo.cab|archivo.cabc] [lex|parse|compile|execute]")

	var t_target := str(t_args[0]).strip_edges()
	var t_phase := DEFAULT_PHASE

	if t_args.size() == 2:
		t_phase = str(t_args[1]).strip_edges().to_lower()

	if t_target.is_empty():
		return _cab_error("La ruta de CAB está vacía")

	if ".." in t_target:
		return _cab_error("No se permiten rutas con '..'")

	var t_is_cab := t_target.to_lower().ends_with(".cab")
	var t_is_cabc := t_target.to_lower().ends_with(".cabc")

	if not t_is_cab and not t_is_cabc:
		return _cab_error("CAB solo admite archivos .cab o .cabc")

	if t_is_cabc and t_phase != "execute":
		return _cab_error("Un .cabc solo puede ejecutarse; usa 'cab archivo.cab compile' para generarlo")

	if t_phase not in ["lex", "parse", "compile", "execute"]:
		return _cab_error("Fase desconocida: %s" % t_phase)

	var t_cm: ConsoleManager = data.get("cm") as ConsoleManager
	var t_rfm: RouteFileManager = data.get("rfm") as RouteFileManager

	if t_cm == null or t_rfm == null:
		return _cab_error("CABExecuter no recibió ConsoleManager o RouteFileManager")

	var t_base_path := t_rfm.get_physical_route()
	if t_base_path.is_empty():
		return _cab_error("No se pudo obtener la ruta física actual")

	var t_path := t_base_path.path_join(t_target).simplify_path()

	if _execution_stack.has(t_path):
		return _cab_error("Ejecución recursiva/cíclica detectada: %s" % t_path)

	if _execution_stack.size() >= MAX_DEPTH:
		return _cab_error("Se alcanzó la profundidad máxima de ejecución (%d)" % MAX_DEPTH)

	if not FileAccess.file_exists(t_path):
		return _cab_error("Archivo CAB no encontrado: %s" % t_path)

	var t_file := FileAccess.open(t_path, FileAccess.READ)
	if t_file == null:
		return _cab_error("No se pudo abrir: %s" % t_path)

	if t_file.get_length() > MAX_FILE_SIZE:
		t_file.close()
		return _cab_error("El archivo supera el límite de %d bytes" % MAX_FILE_SIZE)

	var t_result: Variant

	_execution_stack.append(t_path)

	if t_is_cab:
		var t_text := t_file.get_as_text()
		t_file.close()
		t_result = await _execute_cab_source(
			t_cm,
			t_text,
			t_path,
			t_phase
		)
	else:
		# Un .cabc se consume como AST serializado.
		t_file.close()
		t_result = await _execute_cabc(
			t_cm,
			t_path
		)

	_execution_stack.pop_back()
	return t_result


func _execute_cab_source(
	t_cm: ConsoleManager,
	t_text: String,
	t_source_path: String,
	t_phase: String
) -> Variant:
	match t_phase:
		"lex":
			return t_cm.lex(t_text)

		"parse":
			var t_lexed = t_cm.lex(t_text)
			if t_lexed.is_empty() and not t_text.strip_edges().is_empty():
				return ConsoleManager.NoResult.new()
			return t_cm.parse_ast(t_lexed)

		"compile":
			var t_lexed = t_cm.lex(t_text)
			if t_lexed.is_empty() and not t_text.strip_edges().is_empty():
				return ConsoleManager.NoResult.new()

			var t_ast = t_cm.parse_ast(t_lexed)
			if t_ast is ConsoleManager.NoResult:
				return t_ast

			var t_cabc_path := t_source_path
			if t_cabc_path.to_lower().ends_with(".cab"):
				t_cabc_path = t_cabc_path.left(t_cabc_path.length() - 4) + ".cabc"

			if not t_cm.store_ast(t_ast, t_cabc_path):
				return ConsoleManager.NoResult.new()

			return t_cabc_path

		"execute":
			var t_lexed = t_cm.lex(t_text)
			if t_lexed.is_empty() and not t_text.strip_edges().is_empty():
				return ConsoleManager.NoResult.new()

			var t_ast = t_cm.parse_ast(t_lexed)
			if t_ast is ConsoleManager.NoResult:
				return t_ast

			return await t_cm.execute_ast(t_ast)

	return ConsoleManager.NoResult.new()


func _execute_cabc(
	t_cm: ConsoleManager,
	t_path: String
) -> Variant:
	var t_ast = t_cm.load_ast(t_path)
	if t_ast is ConsoleManager.NoResult:
		return t_ast

	return await t_cm.execute_ast(t_ast)


func _cab_error(t_message: String) -> Variant:
	var t_cm: ConsoleManager = data.get("cm") as ConsoleManager
	if t_cm != null:
		t_cm.console_output("[ERROR] %s" % t_message, ConsoleManager.OutputType.ERROR)

	return ConsoleManager.NoResult.new()

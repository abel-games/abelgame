extends PackedPackage
class_name CABExecuter

var data: Dictionary

const MAX_DEPTH := 32
const MAX_FILE_SIZE := 4 * 1024 * 1024

var _execution_stack: Array[String] = []


func give_data(t_data: Dictionary) -> void:
	data = t_data

	var t_cm = data["cm"]

	(t_cm.commands as Dictionary)["cab"] = {
		"func": cmd_cab,
		"args": 1,
		"raw": {0: true}
	}


func cmd_cab(t_args: Array) -> Variant:
	var t_cm = data["cm"]
	var t_rfm = data["rfm"]

	if t_args.size() != 1:
		t_cm.console_output(
			"[FATAL] Parámetros insuficientes. Use: cab [ARCHIVO.cab]",
			t_cm.OutputType.FATAL
		)
		return t_cm.NoResult.new()

	var t_target := str(t_args[0]).strip_edges()

	if t_target.is_empty():
		t_cm.console_output(
			"[ERROR] Se especificó un archivo vacío",
			t_cm.OutputType.ERROR
		)
		return t_cm.NoResult.new()

	if not t_target.to_lower().ends_with(".cab"):
		t_cm.console_output(
			"[ERROR] El archivo debe tener extensión .cab",
			t_cm.OutputType.ERROR
		)
		return t_cm.NoResult.new()

	# Evitar rutas absolutas y traversal.
	if t_target.contains(".."):
		t_cm.console_output(
			"[ERROR] Ruta CAB no permitida",
			t_cm.OutputType.ERROR
		)
		return t_cm.NoResult.new()

	var t_base_path: String = t_rfm.get_physical_route()
	var t_path := t_base_path.path_join(t_target).simplify_path()

	# Evitar ciclos de ejecución.
	if t_path in _execution_stack:
		t_cm.console_output(
			"[ERROR] Dependencia CAB circular detectada: %s"
			% t_path,
			t_cm.OutputType.ERROR
		)
		return t_cm.NoResult.new()

	# Evitar una profundidad excesiva.
	if _execution_stack.size() >= MAX_DEPTH:
		t_cm.console_output(
			"[ERROR] Profundidad máxima de CAB alcanzada: %d"
			% MAX_DEPTH,
			t_cm.OutputType.ERROR
		)
		return t_cm.NoResult.new()

	if not FileAccess.file_exists(t_path):
		t_cm.console_output(
			"[ERROR] No existe el archivo CAB: %s"
			% t_target,
			t_cm.OutputType.ERROR
		)
		return t_cm.NoResult.new()

	var t_file := FileAccess.open(t_path, FileAccess.READ)

	if t_file == null:
		t_cm.console_output(
			"[ERROR] No se pudo abrir '%s'. Código: %s"
			% [t_target, FileAccess.get_open_error()],
			t_cm.OutputType.ERROR
		)
		return t_cm.NoResult.new()

	if t_file.get_length() > MAX_FILE_SIZE:
		t_file.close()

		@warning_ignore("integer_division")
		t_cm.console_output(
			"[ERROR] El CAB supera el tamaño máximo permitido (%d MB)"
			% (MAX_FILE_SIZE / 1024 / 1024),
			t_cm.OutputType.ERROR
		)
		return t_cm.NoResult.new()

	var t_text := t_file.get_as_text()
	t_file.close()

	_execution_stack.append(t_path)

	# CAB de texto:
	# texto → parser → AST → ejecución.
	var t_ast = t_cm.parse_command(t_text)

	var t_result: Variant = await t_cm.execute_call_block(t_ast)

	_execution_stack.pop_back()

	return t_result

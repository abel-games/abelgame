extends RichTextLabel

@onready var console : ConsoleManager = $"../../../ConsoleManager"
@onready var entry : LineEdit = $"../ConsoleEntry"

func _on_console_entry_text_submitted(new_text: String) -> void:
	entry.clear()
	entry.release_focus()
	console.execute(new_text)
	


func _on_console_manager_output(out: String) -> void:
	append_text(out + "\n")


func _on_console_entry_text_change_rejected(_rejected_substring: String) -> void:
	entry.clear()
	entry.release_focus()

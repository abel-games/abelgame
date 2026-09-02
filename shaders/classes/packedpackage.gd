class_name PackedPackage
extends Node

@export var pkg_name: String = ""
@export_multiline var pkg_description: String = """
Empty Description Text
"""
@export var version: Version = Version.new()
@export var doc: Dictionary = {}
@export var metadata: Dictionary = {}

@warning_ignore("unused_parameter")
func give_data(t_data: Dictionary) -> void:
	pass

func define_package(
	tname: String = "",
	tscript: String = "",
	tversion: Version = Version.new(),
	tdescription: String = "",
	tdoc: Dictionary = {},
	tmetadata: Dictionary = {}
) -> void:
	pkg_name = tname
	version = tversion
	pkg_description = tdescription
	doc = tdoc
	metadata = tmetadata

	if tscript != "":
		var s := GDScript.new()
		s.source_code = tscript
		set_script(s)

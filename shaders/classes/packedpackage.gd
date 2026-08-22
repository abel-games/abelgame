class_name PackedPackage
extends Resource

@export var name : String = ""
@export var description : String = """
Empty Description Text
"""
@export var version : Version = Version.new()
@export var doc : Dictionary = {}
@export var metadata : Dictionary = {}

func _init(tname : String = "", tscript : String = "", tversion : Version = Version.new(), tdescription : String = "", tdoc : Dictionary = {}, tmetadata : Dictionary = {}):
	name = tname
	var s := GDScript.new()
	s.source_code = tscript
	set_script(s)
	version = tversion
	description = tdescription
	doc = tdoc
	metadata = tmetadata

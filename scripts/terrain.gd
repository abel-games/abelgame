extends MeshInstance3D

@export var noise: FastNoiseLite
@export var noise_scale: float = 64.0
@export var height: float = 30.0


func _ready() -> void:
	if noise == null:
		push_error("FastNoiseLite no asignado en el inspector")
		return

	if mesh == null:
		push_error("Mesh no asignado")
		return

	_convert_mesh_if_needed()
	_deform_mesh()


func _convert_mesh_if_needed() -> void:
	if mesh is ArrayMesh:
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.create_from(mesh, 0)
	st.generate_normals()

	var array_mesh := ArrayMesh.new()
	st.commit(array_mesh)

	mesh = array_mesh


func get_height_at(x: float, z: float) -> float:
	var n := noise.get_noise_2d(
		x / noise_scale,
		z / noise_scale
	)

	return (n + 1.0) * 0.5 * height


func _deform_mesh() -> void:
	var array_mesh := mesh as ArrayMesh

	var mdt := MeshDataTool.new()
	mdt.create_from_surface(array_mesh, 0)

	for i in range(mdt.get_vertex_count()):
		var v := mdt.get_vertex(i)
		v.y = get_height_at(v.x, v.z)
		mdt.set_vertex(i, v)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for f in range(mdt.get_face_count()):
		for j in range(3):
			var vi := mdt.get_face_vertex(f, j)
			st.add_vertex(mdt.get_vertex(vi))

	st.generate_normals()

	var new_mesh := ArrayMesh.new()
	st.commit(new_mesh)
	mesh = new_mesh

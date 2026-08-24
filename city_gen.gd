extends MeshInstance3D

var vertices : PackedVector3Array = PackedVector3Array()

@onready var col : CollisionShape3D = $"../C"

func create_collision():
	col.shape = mesh.create_trimesh_shape()

func generate_plain(x, y, sx, sy) -> PackedVector3Array:
	var vs := PackedVector3Array()
	var offset := Vector3((x+1) * sx / 2.0, 0.0,(y+1) * sy / 2.0)

	for i in range(x + 1):
		for j in range(y + 1):
			vs.append(Vector3(i * sx, 0.0, j * sy) - offset)

	return vs


func generate_triangles(x, y) -> PackedInt32Array:
	var tris := PackedInt32Array()

	for i in range(x):
		for j in range(y):
			var a = i * (y + 1) + j
			var b = a + 1
			var c = a + (y + 1)
			var d = c + 1

			# Mirando hacia +Y
			tris.append(c)
			tris.append(b)
			tris.append(a)

			tris.append(c)
			tris.append(d)
			tris.append(b)

	return tris


func generate_normals(vertex_count : int) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(vertex_count)

	for i in range(vertex_count):
		normals[i] = Vector3.UP

	return normals


func create_mesh():
	var size_x = 10
	var size_y = 10

	var vs = generate_plain(size_x, size_y, 2.0, 2.0)
	var tris = generate_triangles(size_x, size_y)
	var normals = generate_normals(vs.size())

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	arrays[Mesh.ARRAY_VERTEX] = vs
	arrays[Mesh.ARRAY_INDEX] = tris
	arrays[Mesh.ARRAY_NORMAL] = normals

	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES,
		arrays
	)

	mesh = array_mesh
	create_collision()


func _ready() -> void:
	create_mesh()

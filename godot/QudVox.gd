# Voxel wall blocks from the Qud asset store: tools/wall2vox.py writes one
# <store>/walls/<name>.json per wall family (a 16x16x10 grid as z-layers of
# 16-character rows, '.' air and '1' main / '2' detail / '3' core), reached
# here through res://qud/walls/. One ArrayMesh per (family, variant), built
# once and shared by every block on the track: only faces between a solid
# voxel and air are emitted, coloured per material with vertex colours.
#
# Grid axes: x east, y north (row 0 of a layer is the SOUTH face, the front),
# z up. In the scene a block is centred on its footprint, base at y = 0.
class_name QudVox
extends RefCounted

const ROOT := "res://qud/walls/"
const MAIN := 1
const DETAIL := 2
const CORE := 3

static var _meshes := {}
static var _index := {}
static var _index_loaded := false

# (dx, dy, dz) per face, the four corners of that face (unit voxel), and its normal.
const FACES := [
	[Vector3i(1, 0, 0), [Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)]],
	[Vector3i(-1, 0, 0), [Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)]],
	[Vector3i(0, 1, 0), [Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)]],
	[Vector3i(0, -1, 0), [Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 0)]],
	[Vector3i(0, 0, 1), [Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)]],
	[Vector3i(0, 0, -1), [Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 0)]],
]


static func _load_index() -> void:
	if _index_loaded:
		return
	_index_loaded = true
	var path := ROOT + "index.json"
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
	if d is Dictionary:
		_index = d


# The model name for a family stem ("wall_brick"): the Walls folder's set wins when
# two folders ship the same stem (wall2vox names those "<Folder>_<stem>").
static func model_name(stem: String) -> String:
	_load_index()
	if _index.has(stem):
		return stem
	var best := ""
	for name in _index:
		var fam := String(_index[name].get("family", ""))
		if fam.ends_with("/" + stem):
			if best == "" or fam.begins_with("Walls/"):
				best = String(name)
	return best


static func available(stem: String) -> bool:
	return model_name(stem) != ""


# One shared mesh per model file, or null when the store has none.
static func mesh(stem: String, variant := "") -> ArrayMesh:
	var name := model_name(stem)
	if name == "":
		return null
	var key := name + variant
	if _meshes.has(key):
		return _meshes[key]
	var path := ROOT + name + variant + ".json"
	var m: ArrayMesh = null
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
		if d is Dictionary and d.has("layers"):
			m = build(d)
	elif variant != "":
		m = mesh(stem)      # no isolated variant: the run model stands in
	_meshes[key] = m
	return m


static func build(d: Dictionary) -> ArrayMesh:
	var layers: Array = d["layers"]
	var H := layers.size()
	var D: int = layers[0].size()
	var W: int = String(layers[0][0]).length()
	var cols: Dictionary = d.get("colours", {})
	var main := _rgb(cols.get("main_rgb", [177, 201, 195]))
	var detail := _rgb(cols.get("detail_rgb", [255, 255, 255]))
	var palette := {MAIN: main, DETAIL: detail, CORE: main.darkened(0.45)}
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := 0
	for z in H:
		for y in D:
			var row := String(layers[z][y])
			for x in W:
				var m := _mat(row[x])
				if m == 0:
					continue
				st.set_color(palette[m])
				for f in FACES:
					var n: Vector3i = f[0]
					if _solid(layers, x + n.x, y + n.y, z + n.z, W, D, H):
						continue
					# grid -> local: x east, z up, y north = -Z; centred on the footprint
					var base := Vector3(x - W * 0.5, z, (D * 0.5 - 1) - y)
					st.set_normal(Vector3(n.x, n.z, -n.y))
					var c: Array = f[1]
					var v := []
					for k in 4:
						var q: Vector3 = c[k]
						v.append(base + Vector3(q.x, q.z, 1.0 - q.y))
					st.add_vertex(v[0]); st.add_vertex(v[1]); st.add_vertex(v[2])
					st.add_vertex(v[0]); st.add_vertex(v[2]); st.add_vertex(v[3])
					faces += 1
	var mesh := st.commit()
	mesh.set_meta("faces", faces)
	mesh.set_meta("size", Vector3i(W, D, H))
	return mesh


static func material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true      # the palette is sRGB; Godot assumes linear otherwise
	mat.roughness = 0.95
	mat.metallic_specular = 0.05
	return mat


# A block instance: `px_per_voxel` world px per voxel (Track.U metres per px).
static func block(stem: String, variant: String, px_per_voxel: float, unit: float) -> MeshInstance3D:
	var m := mesh(stem, variant)
	if m == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material()
	mi.scale = Vector3.ONE * px_per_voxel * unit
	return mi


static func _solid(layers: Array, x: int, y: int, z: int, W: int, D: int, H: int) -> bool:
	if x < 0 or y < 0 or z < 0 or x >= W or y >= D or z >= H:
		return false
	return _mat(String(layers[z][y])[x]) != 0


static func _mat(ch: String) -> int:
	match ch:
		"1": return MAIN
		"2": return DETAIL
		"3": return CORE
	return 0


static func _rgb(a) -> Color:
	if a is Array and a.size() >= 3:
		return Color8(int(a[0]), int(a[1]), int(a[2]))
	return Color.WHITE

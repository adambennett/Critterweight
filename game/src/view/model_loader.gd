class_name ModelLoader
## Runtime glTF loading for content packages (mods) that ship their own creature/prop models.
## Uses Godot's GLTFDocument (data only: meshes, skins, materials, textures — never scripts).
## Results are cached per path for the session.

static var _cache := {}


static func load_gltf_scene(path: String) -> PackedScene:
	if _cache.has(path):
		return _cache[path]
	if not FileAccess.file_exists(path):
		push_warning("ModelLoader: missing %s" % path)
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_warning("ModelLoader: failed to parse %s (%s)" % [path, error_string(err)])
		return null
	var root := doc.generate_scene(state)
	if root == null:
		return null
	var ps := PackedScene.new()
	_set_owner_recursive(root, root)
	ps.pack(root)
	root.free()
	_cache[path] = ps
	return ps


static func _set_owner_recursive(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		_set_owner_recursive(c, owner)

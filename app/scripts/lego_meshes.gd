class_name LegoMeshes
extends RefCounted

const STUD := 0.40
const AXLE_Y := 1.08 # Radio exacto de wheel_43.glb para que la llanta toque Y = 0

static var _scene_cache := {}


static func create_piece_visual(kind: String) -> Dictionary:
    var root := Node3D.new()
    var spin_pivot := Node3D.new()
    root.add_child(spin_pivot)

    match kind:
        "motor":
            var model := _instantiate_glb("res://assets/parts/ev3_motor_large.glb")
            if model != null:
                # En 95658.dat el cubo rojo esta en (0,0,0) con eje en X -> rotar -90 Y lo alinea con Z
                model.rotation.y = -PI * 0.5
                root.add_child(model)
                var hub := _find_node_by_prefix(model, "MotorHub")
                if hub != null:
                    hub.owner = null
                    hub.get_parent().remove_child(hub)
                    hub.rotation.y = -PI * 0.5
                    spin_pivot.add_child(hub)
            else:
                _fallback_box(root, Vector3(STUD * 4.0, STUD * 2.0, STUD * 2.0), Color(0.8, 0.2, 0.2))
        "brick":
            var model := _instantiate_glb("res://assets/parts/ev3_brick.glb")
            if model != null:
                # Ladrillo EV3 horizontal; base y=-1.80 -> apoyado encima de AXLE_Y
                model.position.y = 0.72
                root.add_child(model)
            else:
                _fallback_box(root, Vector3(STUD * 9.0, STUD * 5.0, STUD * 13.5), Color(0.85, 0.85, 0.88))
        "sensor":
            var model := _instantiate_glb("res://assets/parts/ev3_color_sensor.glb")
            if model != null:
                # Rotar +90 en X para que el lente apunte hacia abajo (-Y) leyendo la pista
                model.rotation.x = PI * 0.5
                model.position = Vector3(0.0, 0.40, -0.60)
                root.add_child(model)
            else:
                _fallback_box(root, Vector3(STUD * 3.0, STUD * 4.0, STUD * 3.0), Color(0.85, 0.2, 0.2))
        "beam":
            var model := _instantiate_glb("res://assets/parts/beam_7.glb")
            if model != null:
                model.rotation.y = PI * 0.5
                root.add_child(model)
            else:
                _fallback_box(root, Vector3(STUD * 7.0, STUD, STUD), Color(0.4, 0.44, 0.48))
        "beam_11":
            var model := _instantiate_glb("res://assets/parts/beam_11.glb")
            if model != null:
                model.rotation.y = PI * 0.5
                root.add_child(model)
            else:
                _fallback_box(root, Vector3(STUD * 11.0, STUD, STUD), Color(0.65, 0.68, 0.72))
        "axle":
            var model := _instantiate_glb("res://assets/parts/axle_5.glb")
            if model != null:
                model.rotation.y = PI * 0.5
                spin_pivot.add_child(model)
            else:
                _fallback_box(spin_pivot, Vector3(0.16, 0.16, STUD * 5.0), Color(0.18, 0.2, 0.24))
        "gear_24":
            var model := _instantiate_glb("res://assets/parts/gear_24.glb")
            if model != null:
                spin_pivot.add_child(model)
            else:
                _fallback_box(spin_pivot, Vector3(STUD * 3.0, STUD * 3.0, 0.38), Color(0.65, 0.68, 0.72))
        "gear_8":
            var model := _instantiate_glb("res://assets/parts/gear_8.glb")
            if model != null:
                spin_pivot.add_child(model)
            else:
                _fallback_box(spin_pivot, Vector3(STUD, STUD, 0.40), Color(0.35, 0.38, 0.42))
        "wheel":
            var model := _instantiate_glb("res://assets/parts/wheel_43.glb")
            if model != null:
                spin_pivot.add_child(model)
            else:
                _fallback_box(spin_pivot, Vector3(STUD * 5.4, STUD * 5.4, 1.08), Color(0.15, 0.16, 0.18))

    return {"root": root, "spin_pivot": spin_pivot}


static func _instantiate_glb(res_path: String) -> Node3D:
    if _scene_cache.has(res_path):
        var cached: PackedScene = _scene_cache[res_path]
        return cached.instantiate() as Node3D

    if ResourceLoader.exists(res_path):
        var res := ResourceLoader.load(res_path)
        if res is PackedScene:
            _scene_cache[res_path] = res
            return (res as PackedScene).instantiate() as Node3D

    var abs_path := ProjectSettings.globalize_path(res_path)
    if FileAccess.file_exists(abs_path):
        var gltf := GLTFDocument.new()
        var state := GLTFState.new()
        if gltf.append_from_file(abs_path, state) == OK:
            var scene := gltf.generate_scene(state)
            if scene is Node3D:
                return scene as Node3D

    return null


static func _find_node_by_prefix(node: Node, prefix: String) -> Node3D:
    if node.name.begins_with(prefix) and node is Node3D:
        return node as Node3D
    for c in node.get_children():
        var found := _find_node_by_prefix(c, prefix)
        if found != null:
            return found
    return null


static func _fallback_box(parent: Node3D, sz: Vector3, col: Color) -> void:
    var mi := MeshInstance3D.new()
    var b := BoxMesh.new()
    b.size = sz
    mi.mesh = b
    var m := StandardMaterial3D.new()
    m.albedo_color = col
    mi.material_override = m
    parent.add_child(mi)


static func set_ghost_tint(node: Node, color: Color) -> void:
    var mat := StandardMaterial3D.new()
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.albedo_color = color
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    _apply_material_recursive(node, mat)


static func _apply_material_recursive(node: Node, mat: Material) -> void:
    if node is MeshInstance3D:
        (node as MeshInstance3D).material_override = mat
    for child in node.get_children():
        _apply_material_recursive(child, mat)
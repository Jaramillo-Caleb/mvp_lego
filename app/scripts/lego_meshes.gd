class_name LegoMeshes
extends RefCounted

const STUD := 0.40
const AXLE_Y := 0.60
const GEAR_MODULE := STUD * 0.125


static func create_piece_visual(kind: String) -> Dictionary:
    var root := Node3D.new()
    var spin_pivot := Node3D.new()
    root.add_child(spin_pivot)

    match kind:
        "motor":
            _build_ev3_motor(root, spin_pivot)
        "beam":
            _build_technic_beam_with_holes(root, 7)
        "axle":
            _build_axle(spin_pivot, 5)
        "gear_24":
            _build_gear(spin_pivot, 24, Color(0.63, 0.66, 0.70), Color(0.22, 0.25, 0.29))
        "gear_8":
            _build_gear(spin_pivot, 8, Color(0.36, 0.38, 0.41), Color(0.95, 0.62, 0.14))
        "wheel":
            _build_wheel(spin_pivot)

    return {"root": root, "spin_pivot": spin_pivot}


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


static func _mat(color: Color, roughness := 0.55) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = roughness
    return m


static func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = size
    mi.mesh = box
    mi.material_override = mat
    mi.position = pos
    mi.rotation = rot
    parent.add_child(mi)
    return mi


static func _add_cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, rot := Vector3.ZERO, segs := 20) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    var cyl := CylinderMesh.new()
    cyl.top_radius = radius
    cyl.bottom_radius = radius
    cyl.height = height
    cyl.radial_segments = segs
    mi.mesh = cyl
    mi.material_override = mat
    mi.position = pos
    mi.rotation = rot
    parent.add_child(mi)
    return mi


# Agrega un quad con winding horario garantizado en Godot 4 respecto a la normal exterior
static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
    var v0 := a
    var v1 := b
    var v2 := c
    var v3 := d
    if (v1 - v0).cross(v2 - v0).dot(normal) > 0.0:
        v1 = d
        v3 = b
    st.set_normal(normal)
    st.add_vertex(v0)
    st.set_normal(normal)
    st.add_vertex(v1)
    st.set_normal(normal)
    st.add_vertex(v2)

    st.set_normal(normal)
    st.add_vertex(v0)
    st.set_normal(normal)
    st.add_vertex(v2)
    st.set_normal(normal)
    st.add_vertex(v3)


static func _build_ring_mesh(r_inner: float, r_outer: float, depth: float, segs: int) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var hz := depth * 0.5

    for i in range(segs):
        var a0 := TAU * float(i) / float(segs)
        var a1 := TAU * float(i + 1) / float(segs)
        var c0 := cos(a0)
        var s0 := sin(a0)
        var c1 := cos(a1)
        var s1 := sin(a1)

        var in0 := Vector2(c0 * r_inner, s0 * r_inner)
        var in1 := Vector2(c1 * r_inner, s1 * r_inner)
        var out0 := Vector2(c0 * r_outer, s0 * r_outer)
        var out1 := Vector2(c1 * r_outer, s1 * r_outer)

        _add_quad(
            st,
            Vector3(in0.x, in0.y, hz), Vector3(out0.x, out0.y, hz),
            Vector3(out1.x, out1.y, hz), Vector3(in1.x, in1.y, hz),
            Vector3.BACK
        )
        _add_quad(
            st,
            Vector3(in1.x, in1.y, -hz), Vector3(out1.x, out1.y, -hz),
            Vector3(out0.x, out0.y, -hz), Vector3(in0.x, in0.y, -hz),
            Vector3.FORWARD
        )

        var amid := (a0 + a1) * 0.5
        var n_out := Vector3(cos(amid), sin(amid), 0.0)
        _add_quad(
            st,
            Vector3(out0.x, out0.y, -hz), Vector3(out1.x, out1.y, -hz),
            Vector3(out1.x, out1.y, hz), Vector3(out0.x, out0.y, hz),
            n_out
        )
        _add_quad(
            st,
            Vector3(in1.x, in1.y, -hz), Vector3(in0.x, in0.y, -hz),
            Vector3(in0.x, in0.y, hz), Vector3(in1.x, in1.y, hz),
            -n_out
        )

    return st.commit()


static func _build_technic_beam_with_holes(root: Node3D, holes: int) -> void:
    var beam_gray := _mat(Color(0.42, 0.46, 0.50), 0.48)
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    var hw := STUD * 0.5
    var hh := STUD * 0.46
    var hz := STUD * 0.425
    var r_hole := STUD * 0.24
    var sub := 4
    var half_idx := float(holes - 1) * 0.5

    # 4 bordes exactos en sentido antihorario: Derecha (+X), Arriba (+Y), Izquierda (-X), Abajo (-Y)
    var corners := [
        Vector2(hw, -hh),
        Vector2(hw, hh),
        Vector2(-hw, hh),
        Vector2(-hw, -hh),
    ]
    var edge_normals := [
        Vector3.RIGHT,
        Vector3.UP,
        Vector3.LEFT,
        Vector3.DOWN,
    ]

    for idx in range(holes):
        var cx := (float(idx) - half_idx) * STUD
        var center := Vector2(cx, 0.0)

        for e in range(4):
            var p_start: Vector2 = corners[e]
            var p_end: Vector2 = corners[(e + 1) % 4]
            var n_edge: Vector3 = edge_normals[e]

            for s in range(sub):
                var t0 := float(s) / float(sub)
                var t1 := float(s + 1) / float(sub)
                var lo0 := p_start.lerp(p_end, t0)
                var lo1 := p_start.lerp(p_end, t1)

                var out0 := center + lo0
                var out1 := center + lo1
                var in0 := center + lo0.normalized() * r_hole
                var in1 := center + lo1.normalized() * r_hole

                # Cara frontal (+Z) y cara trasera (-Z)
                _add_quad(
                    st,
                    Vector3(in0.x, in0.y, hz), Vector3(out0.x, out0.y, hz),
                    Vector3(out1.x, out1.y, hz), Vector3(in1.x, in1.y, hz),
                    Vector3.BACK
                )
                _add_quad(
                    st,
                    Vector3(in1.x, in1.y, -hz), Vector3(out1.x, out1.y, -hz),
                    Vector3(out0.x, out0.y, -hz), Vector3(in0.x, in0.y, -hz),
                    Vector3.FORWARD
                )

                # Pared cilindrica interior del hueco
                var n_in := Vector3(-((in0 + in1) * 0.5 - center).normalized().x, -((in0 + in1) * 0.5 - center).normalized().y, 0.0)
                _add_quad(
                    st,
                    Vector3(in1.x, in1.y, -hz), Vector3(in0.x, in0.y, -hz),
                    Vector3(in0.x, in0.y, hz), Vector3(in1.x, in1.y, hz),
                    n_in
                )

                # Paredes exteriores: arriba y abajo en todas las celdas, derecha en la ultima, izquierda en la primera
                var emit_outer := (e == 1 or e == 3) or (e == 0 and idx == holes - 1) or (e == 2 and idx == 0)
                if emit_outer:
                    _add_quad(
                        st,
                        Vector3(out0.x, out0.y, -hz), Vector3(out1.x, out1.y, -hz),
                        Vector3(out1.x, out1.y, hz), Vector3(out0.x, out0.y, hz),
                        n_edge
                    )

    var mi := MeshInstance3D.new()
    mi.mesh = st.commit()
    mi.material_override = beam_gray
    root.add_child(mi)


static func _build_ev3_motor(root: Node3D, spin_pivot: Node3D) -> void:
    var body_gray := _mat(Color(0.84, 0.85, 0.87), 0.45)
    var dark_gray := _mat(Color(0.24, 0.26, 0.29), 0.55)
    var ev3_red := _mat(Color(0.78, 0.14, 0.16), 0.42)

    _add_box(root, Vector3(STUD * 2.4, STUD * 2.2, STUD * 3.6), Vector3(0.0, -STUD * 0.25, -STUD * 2.5), body_gray)
    _add_box(root, Vector3(STUD * 2.2, STUD * 1.8, STUD * 0.45), Vector3(0.0, -STUD * 0.25, -STUD * 4.45), dark_gray)
    _add_box(root, Vector3(STUD * 2.3, STUD * 2.7, STUD * 1.35), Vector3(0.0, -STUD * 0.05, -STUD * 0.72), body_gray)
    _add_cyl(root, STUD * 0.92, STUD * 0.55, Vector3(0.0, 0.0, -STUD * 0.20), ev3_red, Vector3(PI * 0.5, 0.0, 0.0), 24)

    _add_cyl(spin_pivot, STUD * 0.58, STUD * 0.24, Vector3(0.0, 0.0, STUD * 0.10), ev3_red, Vector3(PI * 0.5, 0.0, 0.0), 20)
    _add_box(spin_pivot, Vector3(STUD * 0.72, STUD * 0.14, STUD * 0.28), Vector3(0.0, 0.0, STUD * 0.12), dark_gray)
    _add_box(spin_pivot, Vector3(STUD * 0.14, STUD * 0.72, STUD * 0.28), Vector3(0.0, 0.0, STUD * 0.12), dark_gray)


static func _build_axle(spin_pivot: Node3D, studs_length: int) -> void:
    var axle_dark := _mat(Color(0.16, 0.17, 0.20), 0.45)
    var tip_mark := _mat(Color(0.85, 0.65, 0.15), 0.45)

    var len_m := float(studs_length) * STUD - 0.04
    var arm_w := STUD * 0.16
    var arm_h := STUD * 0.44

    _add_box(spin_pivot, Vector3(arm_h, arm_w, len_m), Vector3.ZERO, axle_dark)
    _add_box(spin_pivot, Vector3(arm_w, arm_h, len_m), Vector3.ZERO, axle_dark)
    _add_box(spin_pivot, Vector3(arm_h * 1.1, arm_w * 0.9, STUD * 0.25), Vector3.ZERO, tip_mark)


static func _build_gear(spin_pivot: Node3D, teeth: int, gear_color: Color, accent_color: Color) -> void:
    var gear_mat := _mat(gear_color, 0.45)
    var accent_mat := _mat(accent_color, 0.45)

    var pitch_r := (GEAR_MODULE * float(teeth)) * 0.5
    var body_r := maxf(STUD * 0.28, pitch_r - GEAR_MODULE * 0.95)
    var thick := STUD * 0.52

    if teeth >= 16:
        var outer_ring := MeshInstance3D.new()
        outer_ring.mesh = _build_ring_mesh(body_r * 0.70, body_r, thick, 32)
        outer_ring.material_override = gear_mat
        spin_pivot.add_child(outer_ring)

        var hub_ring := MeshInstance3D.new()
        hub_ring.mesh = _build_ring_mesh(STUD * 0.20, body_r * 0.36, thick, 16)
        hub_ring.material_override = gear_mat
        spin_pivot.add_child(hub_ring)

        var spoke_len := (body_r * 0.73) - (body_r * 0.33)
        var spoke_mid := (body_r * 0.73 + body_r * 0.33) * 0.5
        for q in range(4):
            var a := float(q) * PI * 0.5
            _add_box(
                spin_pivot,
                Vector3(spoke_len, STUD * 0.22, thick * 0.94),
                Vector3(cos(a) * spoke_mid, sin(a) * spoke_mid, 0.0),
                accent_mat if q == 0 else gear_mat,
                Vector3(0.0, 0.0, a)
            )
    else:
        var small_ring := MeshInstance3D.new()
        small_ring.mesh = _build_ring_mesh(STUD * 0.18, body_r, thick, 16)
        small_ring.material_override = gear_mat
        spin_pivot.add_child(small_ring)

        _add_box(
            spin_pivot,
            Vector3(body_r * 0.60, STUD * 0.11, thick + 0.02),
            Vector3(body_r * 0.45, 0.0, 0.0),
            accent_mat
        )

    var tooth_box := BoxMesh.new()
    tooth_box.size = Vector3(GEAR_MODULE * 1.85, GEAR_MODULE * 1.30, thick * 0.92)
    var tooth_r := pitch_r - GEAR_MODULE * 0.05

    for i in range(teeth):
        var angle := TAU * float(i) / float(teeth)
        var t := MeshInstance3D.new()
        t.mesh = tooth_box
        t.material_override = gear_mat
        t.position = Vector3(cos(angle) * tooth_r, sin(angle) * tooth_r, 0.0)
        t.rotation.z = angle
        spin_pivot.add_child(t)


static func _build_wheel(spin_pivot: Node3D) -> void:
    var tire_mat := _mat(Color(0.11, 0.12, 0.14), 0.85)
    var rim_mat := _mat(Color(0.92, 0.74, 0.12), 0.40)
    var hub_mat := _mat(Color(0.20, 0.22, 0.25), 0.60)
    var mark_mat := _mat(Color(0.85, 0.18, 0.16), 0.40)

    var tire_r := STUD * 1.40
    var rim_r := STUD * 0.90
    var width := STUD * 1.10

    _add_cyl(spin_pivot, tire_r, width, Vector3.ZERO, tire_mat, Vector3(PI * 0.5, 0.0, 0.0), 28)
    _add_cyl(spin_pivot, rim_r, width + 0.02, Vector3.ZERO, rim_mat, Vector3(PI * 0.5, 0.0, 0.0), 24)

    _add_box(spin_pivot, Vector3(STUD * 0.44, STUD * 0.15, width + 0.04), Vector3.ZERO, hub_mat)
    _add_box(spin_pivot, Vector3(STUD * 0.15, STUD * 0.44, width + 0.04), Vector3.ZERO, hub_mat)

    for i in range(6):
        var a := TAU * float(i) / 6.0
        _add_cyl(
            spin_pivot,
            STUD * 0.12,
            width + 0.03,
            Vector3(cos(a) * STUD * 0.56, sin(a) * STUD * 0.56, 0.0),
            mark_mat if i == 0 else hub_mat,
            Vector3(PI * 0.5, 0.0, 0.0),
            10
        )
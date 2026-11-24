extends Node3D

const LegoMeshesScript := preload("res://scripts/lego_meshes.gd")

const STUD := LegoMeshesScript.STUD
const AXLE_Y := LegoMeshesScript.AXLE_Y
const GRID_HALF_EXTENT := 12

const PIECE_SPECS := {
    "motor": {"label": "Motor EV3", "color": Color(0.80, 0.22, 0.22)},
    "beam": {"label": "Viga Technic 1x7", "color": Color(0.45, 0.48, 0.54)},
    "axle": {"label": "Eje 5L", "color": Color(0.25, 0.28, 0.34)},
    "gear_24": {"label": "Engranaje 24T", "color": Color(0.65, 0.68, 0.72)},
    "gear_8": {"label": "Engranaje 8T", "color": Color(0.95, 0.62, 0.16)},
    "wheel": {"label": "Rueda Technic", "color": Color(0.90, 0.74, 0.16)},
}

@onready var sim: OpenSimNode = $OpenSim
@onready var camera: Camera3D = $Camera3D
@onready var pieces_root: Node3D = $PiecesRoot
@onready var hud: CanvasLayer = $HUD

# Camara orbital 360 grados
var _cam_target := Vector3(0.4, 0.35, 0.2)
var _cam_yaw := 0.55
var _cam_pitch := 0.48
var _cam_dist := 6.8
var _rmb_down := false
var _mmb_down := false
var _rmb_drag_dist := 0.0

# Editor, seleccion multiple (marquee) y arrastre de grupo
var _tool := "select"
var _rot_step := 0
var _hover_grid := Vector2i.ZERO
var _hover_valid := false
var _hover_on_table := false
var _ghost_group := [] # Array of { "id": String, "node": Node3D, "offset": Vector2i, "rot": int, "kind": String }
var _selected_ids: Array[String] = []
var _selection_boxes_root: Node3D

var _drag_anchor_id := ""
var _drag_start_mouse := Vector2.ZERO
var _is_dragging_group := false
var _drag_orig := {} # id -> { "grid": Vector2i, "rot_step": int }

var _is_marquee := false
var _marquee_start := Vector2.ZERO
var _marquee_end := Vector2.ZERO
var _marquee_panel: Panel

# Piezas colocadas
var _pieces := {}
var _next_id := 1

# Controles HUD
var _tool_buttons := {}
var _status_label: Label
var _hint_label: Label
var _selection_label: Label
var _telemetry_label: Label
var _rpm_spinbox: SpinBox
var _sim_button: Button
var _stop_button: Button
var _reverse_button: Button
var _delete_button: Button
var _metrics_label: Label
var _metrics_timer := 0.0


func _ready() -> void:
    _setup_environment()
    _build_workplane()
    _selection_boxes_root = Node3D.new()
    add_child(_selection_boxes_root)
    _build_hud()
    _update_camera_transform()

    sim.set_strict_mode(false)
    _load_example_train()


func _process(delta: float) -> void:
    if sim != null and sim.is_running() and sim.is_mechanism_valid():
        for id in _pieces.keys():
            var p: Dictionary = _pieces[id]
            if not sim.is_component_connected(id):
                continue
            var rpm := sim.get_component_rpm(id)
            if absf(rpm) > 0.0001:
                var omega := rpm * TAU / 60.0
                var pivot: Node3D = p["spin_pivot"]
                pivot.rotate_z(omega * delta)

    _metrics_timer += delta
    if _metrics_timer >= 0.30:
        _metrics_timer = 0.0
        _update_metrics()


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed:
            var focused := get_viewport().gui_get_focus_owner()
            if focused != null:
                focused.release_focus()

        if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
            _cam_dist = maxf(2.2, _cam_dist - 0.55)
            _update_camera_transform()
        elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
            _cam_dist = minf(16.0, _cam_dist + 0.55)
            _update_camera_transform()
        elif mb.button_index == MOUSE_BUTTON_RIGHT:
            if mb.pressed:
                _rmb_down = true
                _rmb_drag_dist = 0.0
            else:
                var was_click := _rmb_drag_dist < 5.0
                _rmb_down = false
                if was_click:
                    if _is_dragging_group:
                        _cancel_group_drag()
                    elif _is_marquee:
                        _cancel_marquee()
                    elif _tool != "select":
                        _set_tool("select")
        elif mb.button_index == MOUSE_BUTTON_MIDDLE:
            _mmb_down = mb.pressed
        elif mb.button_index == MOUSE_BUTTON_LEFT:
            if sim.is_running():
                return
            if mb.pressed:
                if _tool == "select":
                    var hit_id := _pick_piece_under_mouse(mb.position)
                    if hit_id != "":
                        if Input.is_key_pressed(KEY_SHIFT):
                            if hit_id in _selected_ids:
                                _selected_ids.erase(hit_id)
                            else:
                                _selected_ids.append(hit_id)
                            _update_selection_visuals()
                            _refresh_ui()
                        else:
                            if not (hit_id in _selected_ids):
                                _selected_ids = [hit_id]
                                _update_selection_visuals()
                                _refresh_ui()
                            _drag_anchor_id = hit_id
                            _drag_start_mouse = mb.position
                    else:
                        if not Input.is_key_pressed(KEY_SHIFT):
                            _selected_ids.clear()
                            _update_selection_visuals()
                            _refresh_ui()
                        _is_marquee = true
                        _marquee_start = mb.position
                        _marquee_end = mb.position
                        _update_marquee_panel()
                elif _hover_on_table and _hover_valid:
                    _place_piece(_tool, _hover_grid, _rot_step)
            else:
                if _is_dragging_group:
                    _finish_group_drag()
                elif _is_marquee:
                    _finish_marquee(Input.is_key_pressed(KEY_SHIFT))
                _drag_anchor_id = ""

    elif event is InputEventMouseMotion:
        var mm := event as InputEventMouseMotion
        if _rmb_down or _mmb_down:
            _rmb_drag_dist += mm.relative.length()
            var scale := _cam_dist * 0.0015
            if _mmb_down or Input.is_key_pressed(KEY_SPACE):
                _cam_target -= camera.global_transform.basis.x * mm.relative.x * scale
                _cam_target += camera.global_transform.basis.y * mm.relative.y * scale
                _update_camera_transform()
            elif Input.is_key_pressed(KEY_SHIFT):
                var right := camera.global_transform.basis.x
                var forward := Vector3(right.z, 0.0, -right.x).normalized()
                _cam_target -= right * mm.relative.x * scale
                _cam_target += forward * mm.relative.y * scale
                _update_camera_transform()
            else:
                _cam_yaw -= mm.relative.x * 0.008
                _cam_pitch = clampf(_cam_pitch + mm.relative.y * 0.008, -1.45, 1.45)
                _update_camera_transform()
        elif not sim.is_running():
            if _is_marquee:
                _marquee_end = mm.position
                _update_marquee_panel()
            elif _drag_anchor_id != "" and not _is_dragging_group:
                if mm.position.distance_to(_drag_start_mouse) > 6.0:
                    _begin_group_drag(_drag_anchor_id, mm.position)
            elif _is_dragging_group:
                _update_group_ghost_under_mouse(mm.position)
            elif _tool != "select":
                _update_single_ghost_under_mouse(mm.position)

    elif event is InputEventKey and event.pressed and not event.echo:
        var ke := event as InputEventKey
        if ke.keycode == KEY_R and not sim.is_running():
            _rotate_tool()
        elif ke.keycode == KEY_ESCAPE:
            if _is_dragging_group:
                _cancel_group_drag()
            elif _is_marquee:
                _cancel_marquee()
            else:
                _set_tool("select")
        elif (ke.keycode == KEY_DELETE or ke.keycode == KEY_BACKSPACE) and not sim.is_running():
            if not _is_dragging_group and not _is_marquee:
                _delete_selected_pieces()


func _setup_environment() -> void:
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.13, 0.15, 0.18)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.55, 0.58, 0.62)
    env.ambient_light_energy = 0.85

    var world_env := WorldEnvironment.new()
    world_env.environment = env
    add_child(world_env)


func _build_workplane() -> void:
    var im := ImmediateMesh.new()
    var grid_mat := StandardMaterial3D.new()
    grid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    grid_mat.albedo_color = Color(0.34, 0.40, 0.48, 0.85)
    grid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

    im.surface_begin(Mesh.PRIMITIVE_LINES, grid_mat)
    var half := (float(GRID_HALF_EXTENT) + 0.5) * STUD
    for i in range(-GRID_HALF_EXTENT, GRID_HALF_EXTENT + 2):
        var c := (float(i) - 0.5) * STUD
        im.surface_add_vertex(Vector3(c, 0.0, -half))
        im.surface_add_vertex(Vector3(c, 0.0, half))
        im.surface_add_vertex(Vector3(-half, 0.0, c))
        im.surface_add_vertex(Vector3(half, 0.0, c))
    im.surface_end()

    var grid_mi := MeshInstance3D.new()
    grid_mi.mesh = im
    add_child(grid_mi)

    var axes := ImmediateMesh.new()
    var ax_mat := StandardMaterial3D.new()
    ax_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    ax_mat.vertex_color_use_as_albedo = true
    axes.surface_begin(Mesh.PRIMITIVE_LINES, ax_mat)
    axes.surface_set_color(Color(0.85, 0.30, 0.30))
    axes.surface_add_vertex(Vector3(0.0, 0.005, 0.0))
    axes.surface_add_vertex(Vector3(STUD * 2.0, 0.005, 0.0))
    axes.surface_set_color(Color(0.30, 0.55, 0.95))
    axes.surface_add_vertex(Vector3(0.0, 0.005, 0.0))
    axes.surface_add_vertex(Vector3(0.0, 0.005, STUD * 2.0))
    axes.surface_end()

    var ax_mi := MeshInstance3D.new()
    ax_mi.mesh = axes
    add_child(ax_mi)


func _update_camera_transform() -> void:
    var offset := Vector3(
        _cam_dist * cos(_cam_pitch) * sin(_cam_yaw),
        _cam_dist * sin(_cam_pitch),
        _cam_dist * cos(_cam_pitch) * cos(_cam_yaw)
    )
    camera.position = _cam_target + offset
    camera.look_at(_cam_target, Vector3.UP)


func _build_hud() -> void:
    # Cuadro azul de seleccion multiple (overlay que no bloquea clics)
    _marquee_panel = Panel.new()
    _marquee_panel.visible = false
    _marquee_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.24, 0.65, 1.0, 0.16)
    sb.border_color = Color(0.35, 0.80, 1.0, 0.90)
    sb.set_border_width_all(2)
    _marquee_panel.add_theme_stylebox_override("panel", sb)
    hud.add_child(_marquee_panel)

    var top_panel := PanelContainer.new()
    top_panel.anchor_right = 1.0
    top_panel.offset_left = 12
    top_panel.offset_top = 12
    top_panel.offset_right = -12
    top_panel.offset_bottom = 66
    hud.add_child(top_panel)

    var top_margin := MarginContainer.new()
    top_margin.add_theme_constant_override("margin_left", 12)
    top_margin.add_theme_constant_override("margin_right", 12)
    top_margin.add_theme_constant_override("margin_top", 8)
    top_margin.add_theme_constant_override("margin_bottom", 8)
    top_panel.add_child(top_margin)

    var top_row := HBoxContainer.new()
    top_row.add_theme_constant_override("separation", 10)
    top_margin.add_child(top_row)

    var app_title := Label.new()
    app_title.text = "mvp_lego Studio (EV3 / Technic)"
    app_title.add_theme_font_size_override("font_size", 16)
    top_row.add_child(app_title)

    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top_row.add_child(spacer)

    var rpm_lbl := Label.new()
    rpm_lbl.text = "Motor (RPM):"
    top_row.add_child(rpm_lbl)

    _rpm_spinbox = SpinBox.new()
    _rpm_spinbox.min_value = -300.0
    _rpm_spinbox.max_value = 300.0
    _rpm_spinbox.step = 10.0
    _rpm_spinbox.value = 60.0
    _rpm_spinbox.custom_minimum_size = Vector2(96, 0)
    _rpm_spinbox.value_changed.connect(_on_rpm_changed)
    top_row.add_child(_rpm_spinbox)

    _sim_button = Button.new()
    _sim_button.text = "Simular"
    _sim_button.focus_mode = Control.FOCUS_NONE
    _sim_button.pressed.connect(_on_simulate_pressed)
    top_row.add_child(_sim_button)

    _stop_button = Button.new()
    _stop_button.text = "Detener / Construir"
    _stop_button.focus_mode = Control.FOCUS_NONE
    _stop_button.pressed.connect(_on_stop_pressed)
    top_row.add_child(_stop_button)

    _reverse_button = Button.new()
    _reverse_button.text = "Invertir giro"
    _reverse_button.focus_mode = Control.FOCUS_NONE
    _reverse_button.pressed.connect(_on_reverse_pressed)
    top_row.add_child(_reverse_button)

    var left_panel := PanelContainer.new()
    left_panel.offset_left = 12
    left_panel.offset_top = 78
    left_panel.offset_right = 264
    left_panel.offset_bottom = 635
    hud.add_child(left_panel)

    var left_margin := MarginContainer.new()
    left_margin.add_theme_constant_override("margin_left", 10)
    left_margin.add_theme_constant_override("margin_right", 10)
    left_margin.add_theme_constant_override("margin_top", 10)
    left_margin.add_theme_constant_override("margin_bottom", 10)
    left_panel.add_child(left_margin)

    var left_vbox := VBoxContainer.new()
    left_vbox.add_theme_constant_override("separation", 6)
    left_margin.add_child(left_vbox)

    var pal_title := Label.new()
    pal_title.text = "Piezas LEGO esenciales"
    pal_title.add_theme_font_size_override("font_size", 14)
    left_vbox.add_child(pal_title)

    var sel_btn := Button.new()
    sel_btn.text = "Seleccionar / Mover (Esc)"
    sel_btn.toggle_mode = true
    sel_btn.focus_mode = Control.FOCUS_NONE
    sel_btn.pressed.connect(func(): _set_tool("select"))
    left_vbox.add_child(sel_btn)
    _tool_buttons["select"] = sel_btn

    for key in ["motor", "beam", "axle", "gear_24", "gear_8", "wheel"]:
        var b := Button.new()
        b.text = "+ " + PIECE_SPECS[key]["label"]
        b.toggle_mode = true
        b.focus_mode = Control.FOCUS_NONE
        b.pressed.connect(func(): _set_tool(key))
        left_vbox.add_child(b)
        _tool_buttons[key] = b

    left_vbox.add_child(HSeparator.new())

    var rot_btn := Button.new()
    rot_btn.text = "Rotar 90° (R)"
    rot_btn.focus_mode = Control.FOCUS_NONE
    rot_btn.pressed.connect(_rotate_tool)
    left_vbox.add_child(rot_btn)

    _delete_button = Button.new()
    _delete_button.text = "Borrar seleccion (Supr)"
    _delete_button.focus_mode = Control.FOCUS_NONE
    _delete_button.pressed.connect(_delete_selected_pieces)
    left_vbox.add_child(_delete_button)

    left_vbox.add_child(HSeparator.new())

    var example_btn := Button.new()
    example_btn.text = "Cargar tren ejemplo"
    example_btn.focus_mode = Control.FOCUS_NONE
    example_btn.pressed.connect(_load_example_train)
    left_vbox.add_child(example_btn)

    var clear_btn := Button.new()
    clear_btn.text = "Limpiar mesa"
    clear_btn.focus_mode = Control.FOCUS_NONE
    clear_btn.pressed.connect(_clear_all_pieces)
    left_vbox.add_child(clear_btn)

    var help_lbl := Label.new()
    help_lbl.text = "Camara: Der.=Orbita 360° | Espacio+Der.=Mover ejes | Rueda=Zoom\nSeleccion: Cuadro en vacio | Arrastra para mover | R=Rotar"
    help_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    help_lbl.add_theme_font_size_override("font_size", 11)
    help_lbl.modulate = Color(0.75, 0.80, 0.86)
    left_vbox.add_child(help_lbl)

    var right_panel := PanelContainer.new()
    right_panel.anchor_left = 1.0
    right_panel.anchor_right = 1.0
    right_panel.offset_left = -335
    right_panel.offset_top = 78
    right_panel.offset_right = -12
    right_panel.offset_bottom = 445
    hud.add_child(right_panel)

    var right_margin := MarginContainer.new()
    right_margin.add_theme_constant_override("margin_left", 12)
    right_margin.add_theme_constant_override("margin_right", 12)
    right_margin.add_theme_constant_override("margin_top", 10)
    right_margin.add_theme_constant_override("margin_bottom", 10)
    right_panel.add_child(right_margin)

    var right_vbox := VBoxContainer.new()
    right_vbox.add_theme_constant_override("separation", 8)
    right_margin.add_child(right_vbox)

    var insp_title := Label.new()
    insp_title.text = "Estado y Cinematica (C++)"
    insp_title.add_theme_font_size_override("font_size", 14)
    right_vbox.add_child(insp_title)

    _status_label = Label.new()
    _status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    right_vbox.add_child(_status_label)

    _hint_label = Label.new()
    _hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _hint_label.modulate = Color(0.80, 0.86, 0.94)
    _hint_label.add_theme_font_size_override("font_size", 12)
    right_vbox.add_child(_hint_label)

    right_vbox.add_child(HSeparator.new())

    _selection_label = Label.new()
    _selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    right_vbox.add_child(_selection_label)

    right_vbox.add_child(HSeparator.new())

    _telemetry_label = Label.new()
    _telemetry_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _telemetry_label.add_theme_font_size_override("font_size", 12)
    right_vbox.add_child(_telemetry_label)

    _metrics_label = Label.new()
    _metrics_label.add_theme_font_size_override("font_size", 11)
    _metrics_label.modulate = Color(0.70, 0.76, 0.82)
    right_vbox.add_child(_metrics_label)

    _set_tool("select")


func _set_tool(tool_name: String) -> void:
    if _is_dragging_group:
        _cancel_group_drag()
    if _is_marquee:
        _cancel_marquee()

    _tool = tool_name
    for key in _tool_buttons.keys():
        (_tool_buttons[key] as Button).set_pressed_no_signal(key == tool_name)

    _clear_ghosts()

    if _tool != "select" and not sim.is_running():
        _selected_ids.clear()
        _update_selection_visuals()
        var vis := LegoMeshesScript.create_piece_visual(_tool)
        var node: Node3D = vis["root"]
        node.visible = false
        LegoMeshesScript.set_ghost_tint(node, Color(0.25, 0.92, 0.45, 0.45))
        add_child(node)
        _ghost_group.append({"id": "", "node": node, "offset": Vector2i.ZERO, "rot": _rot_step, "kind": _tool})

    _refresh_ui()


func _clear_ghosts() -> void:
    for g in _ghost_group:
        if g["node"] != null:
            (g["node"] as Node3D).queue_free()
    _ghost_group.clear()


func _update_marquee_panel() -> void:
    if not _is_marquee:
        _marquee_panel.visible = false
        return
    var rect := Rect2(_marquee_start, _marquee_end - _marquee_start).abs()
    _marquee_panel.position = rect.position
    _marquee_panel.size = rect.size
    _marquee_panel.visible = true


func _cancel_marquee() -> void:
    _is_marquee = false
    _update_marquee_panel()


func _finish_marquee(additive: bool) -> void:
    var rect := Rect2(_marquee_start, _marquee_end - _marquee_start).abs()
    _is_marquee = false
    _update_marquee_panel()

    if rect.size.x < 4.0 and rect.size.y < 4.0:
        return

    if not additive:
        _selected_ids.clear()

    for id in _pieces.keys():
        var p: Dictionary = _pieces[id]
        var box := _piece_aabb(p["kind"], p["grid"], int(p["rot_step"]))
        if _aabb_intersects_screen_rect(box, rect):
            if not (id in _selected_ids):
                _selected_ids.append(id)

    _update_selection_visuals()
    _refresh_ui()


func _aabb_intersects_screen_rect(box: AABB, screen_rect: Rect2) -> bool:
    var min_p := Vector2(INF, INF)
    var max_p := Vector2(-INF, -INF)
    var any_in_front := false

    for i in range(8):
        var corner := box.get_endpoint(i)
        if camera.is_position_behind(corner):
            continue
        any_in_front = true
        var sp := camera.unproject_position(corner)
        min_p.x = minf(min_p.x, sp.x)
        min_p.y = minf(min_p.y, sp.y)
        max_p.x = maxf(max_p.x, sp.x)
        max_p.y = maxf(max_p.y, sp.y)

    if not any_in_front:
        return false

    var box_2d := Rect2(min_p, max_p - min_p)
    return screen_rect.intersects(box_2d)


func _begin_group_drag(anchor_id: String, mouse_pos: Vector2) -> void:
    if not _pieces.has(anchor_id):
        return
    _is_dragging_group = true
    _drag_orig.clear()
    _clear_ghosts()
    _clear_selection_visuals()

    var anchor_grid: Vector2i = _pieces[anchor_id]["grid"]
    for id in _selected_ids:
        if not _pieces.has(id):
            continue
        var p: Dictionary = _pieces[id]
        _drag_orig[id] = {"grid": p["grid"], "rot_step": int(p["rot_step"])}
        (p["node"] as Node3D).visible = false

        var vis := LegoMeshesScript.create_piece_visual(p["kind"])
        var ghost: Node3D = vis["root"]
        ghost.visible = false
        add_child(ghost)
        _ghost_group.append({
            "id": id,
            "node": ghost,
            "offset": (p["grid"] as Vector2i) - anchor_grid,
            "rot": int(p["rot_step"]),
            "kind": p["kind"],
        })

    _update_group_ghost_under_mouse(mouse_pos)


func _finish_group_drag() -> void:
    _is_dragging_group = false
    _clear_ghosts()

    for id in _drag_orig.keys():
        if _pieces.has(id):
            (_pieces[id]["node"] as Node3D).visible = true

    if _hover_on_table and _hover_valid:
        var anchor_orig: Vector2i = _drag_orig[_drag_anchor_id]["grid"]
        var delta := _hover_grid - anchor_orig
        for id in _drag_orig.keys():
            if not _pieces.has(id):
                continue
            var p: Dictionary = _pieces[id]
            var new_grid: Vector2i = (_drag_orig[id]["grid"] as Vector2i) + delta
            p["grid"] = new_grid
            (p["node"] as Node3D).position = _grid_to_world(new_grid)
        _hint_label.text = "Movidas %d pieza(s)." % _drag_orig.size()
    else:
        for id in _drag_orig.keys():
            if not _pieces.has(id):
                continue
            var p: Dictionary = _pieces[id]
            var orig_grid: Vector2i = _drag_orig[id]["grid"]
            var orig_rot: int = int(_drag_orig[id]["rot_step"])
            p["grid"] = orig_grid
            p["rot_step"] = orig_rot
            (p["node"] as Node3D).position = _grid_to_world(orig_grid)
            (p["node"] as Node3D).rotation.y = float(orig_rot) * PI * 0.5
        _hint_label.text = "Movimiento cancelado (espacio ocupado o fuera de la mesa)."

    _drag_orig.clear()
    _drag_anchor_id = ""
    _rebuild_kinematic_graph()
    _update_selection_visuals()
    _refresh_ui()


func _cancel_group_drag() -> void:
    if not _is_dragging_group:
        return
    _is_dragging_group = false
    _clear_ghosts()

    for id in _drag_orig.keys():
        if _pieces.has(id):
            var p: Dictionary = _pieces[id]
            var node := p["node"] as Node3D
            node.visible = true
            p["grid"] = _drag_orig[id]["grid"]
            p["rot_step"] = _drag_orig[id]["rot_step"]
            node.position = _grid_to_world(p["grid"])
            node.rotation.y = float(p["rot_step"]) * PI * 0.5

    _drag_orig.clear()
    _drag_anchor_id = ""
    _update_selection_visuals()
    _refresh_ui()


func _rotate_tool() -> void:
    if _is_dragging_group:
        return
    _rot_step = (_rot_step + 1) % 4
    if _tool != "select" and _ghost_group.size() == 1:
        var g: Dictionary = _ghost_group[0]
        g["rot"] = _rot_step
        (g["node"] as Node3D).rotation.y = float(_rot_step) * PI * 0.5
        _validate_single_ghost()
    elif _selected_ids.size() == 1 and _pieces.has(_selected_ids[0]):
        var id := _selected_ids[0]
        var p: Dictionary = _pieces[id]
        var next_rot := (int(p["rot_step"]) + 1) % 4
        var check := _check_placement_valid(p["kind"], p["grid"], next_rot, [id])
        if check["ok"]:
            p["rot_step"] = next_rot
            (p["node"] as Node3D).rotation.y = float(next_rot) * PI * 0.5
            _rebuild_kinematic_graph()
            _update_selection_visuals()
            _refresh_ui()
        else:
            _hint_label.text = check["reason"]


func _grid_to_world(grid: Vector2i) -> Vector3:
    return Vector3(float(grid.x) * STUD, AXLE_Y, float(grid.y) * STUD)


func _mouse_to_grid(mouse_pos: Vector2) -> Dictionary:
    var ray_origin := camera.project_ray_origin(mouse_pos)
    var ray_dir := camera.project_ray_normal(mouse_pos)
    var plane := Plane(Vector3.UP, AXLE_Y)
    var hit = plane.intersects_ray(ray_origin, ray_dir)
    if hit == null:
        return {"on_table": false, "grid": Vector2i.ZERO}
    var pos: Vector3 = hit
    var gx := roundi(pos.x / STUD)
    var gz := roundi(pos.z / STUD)
    var on_table := absi(gx) <= GRID_HALF_EXTENT and absi(gz) <= GRID_HALF_EXTENT
    return {"on_table": on_table, "grid": Vector2i(gx, gz)}


func _update_single_ghost_under_mouse(mouse_pos: Vector2) -> void:
    if _ghost_group.is_empty():
        return
    var g: Dictionary = _ghost_group[0]
    var res := _mouse_to_grid(mouse_pos)
    _hover_on_table = res["on_table"]
    _hover_grid = res["grid"]
    var node: Node3D = g["node"]
    node.visible = _hover_on_table
    if not _hover_on_table:
        _hint_label.text = "Mueve el mouse sobre la mesa de trabajo."
        return
    node.position = _grid_to_world(_hover_grid)
    node.rotation.y = float(_rot_step) * PI * 0.5
    _validate_single_ghost()


func _validate_single_ghost() -> void:
    var check := _check_placement_valid(_tool, _hover_grid, _rot_step, [])
    _hover_valid = check["ok"]
    var reason: String = check["reason"]

    if _hover_valid and (_tool == "gear_24" or _tool == "gear_8"):
        var my_teeth := 24 if _tool == "gear_24" else 8
        var my_axis := _piece_axis(_rot_step)
        for id in _pieces.keys():
            var p: Dictionary = _pieces[id]
            if p["kind"] == "gear_24" or p["kind"] == "gear_8":
                var other_axis := _piece_axis(int(p["rot_step"]))
                if my_axis == other_axis and _will_gears_mesh(_hover_grid, my_teeth, p["grid"], int(p["teeth"]), my_axis):
                    reason = "Engrana con %s en (%d, %d)." % [id, _hover_grid.x, _hover_grid.y]
                    break

    var col := Color(0.25, 0.92, 0.45, 0.45) if _hover_valid else Color(0.95, 0.25, 0.25, 0.50)
    LegoMeshesScript.set_ghost_tint(_ghost_group[0]["node"], col)
    _hint_label.text = reason


func _update_group_ghost_under_mouse(mouse_pos: Vector2) -> void:
    var res := _mouse_to_grid(mouse_pos)
    _hover_on_table = res["on_table"]
    _hover_grid = res["grid"]

    if not _hover_on_table:
        for g in _ghost_group:
            (g["node"] as Node3D).visible = false
        _hover_valid = false
        _hint_label.text = "Mueve el mouse sobre la mesa de trabajo."
        return

    var ignore_ids: Array[String] = []
    for g in _ghost_group:
        ignore_ids.append(g["id"])

    _hover_valid = true
    var reason := "Soltar para mover %d pieza(s) a (%d, %d)." % [_ghost_group.size(), _hover_grid.x, _hover_grid.y]

    for g in _ghost_group:
        var target_grid := _hover_grid + (g["offset"] as Vector2i)
        var node: Node3D = g["node"]
        node.visible = true
        node.position = _grid_to_world(target_grid)
        node.rotation.y = float(g["rot"]) * PI * 0.5

        if absi(target_grid.x) > GRID_HALF_EXTENT or absi(target_grid.y) > GRID_HALF_EXTENT:
            _hover_valid = false
            reason = "Una pieza del grupo sale de la mesa."
        elif _hover_valid:
            var chk := _check_placement_valid(g["kind"], target_grid, int(g["rot"]), ignore_ids)
            if not chk["ok"]:
                _hover_valid = false
                reason = chk["reason"]

    var col := Color(0.25, 0.92, 0.45, 0.45) if _hover_valid else Color(0.95, 0.25, 0.25, 0.50)
    for g in _ghost_group:
        LegoMeshesScript.set_ghost_tint(g["node"], col)
    _hint_label.text = reason


func _piece_axis(rot_step: int) -> String:
    return "Z" if (rot_step % 2 == 0) else "X"


func _check_placement_valid(kind: String, grid: Vector2i, rot_step: int, ignore_ids: Array) -> Dictionary:
    if kind == "motor":
        for id in _pieces.keys():
            if not (id in ignore_ids) and _pieces[id]["kind"] == "motor":
                return {"ok": false, "reason": "MVP admite 1 Motor EV3 a la vez."}

    var my_aabb := _piece_aabb(kind, grid, rot_step)
    var my_axis := _piece_axis(rot_step)
    var my_teeth := 24 if kind == "gear_24" else (8 if kind == "gear_8" else 0)

    for id in _pieces.keys():
        if id in ignore_ids:
            continue
        var other: Dictionary = _pieces[id]
        var okind: String = other["kind"]
        var ogrid: Vector2i = other["grid"]
        var orot: int = int(other["rot_step"])
        var oaxis := _piece_axis(orot)
        var oaabb := _piece_aabb(okind, ogrid, orot)

        if kind == "axle" and okind == "axle":
            for c in _axle_cells(grid, rot_step):
                if c in _axle_cells(ogrid, orot):
                    return {"ok": false, "reason": "Choca con eje %s." % id}
            continue

        if (kind == "axle" and okind == "beam") or (kind == "beam" and okind == "axle"):
            var beam_g := ogrid if kind == "axle" else grid
            var beam_r := orot if kind == "axle" else rot_step
            var axle_g := grid if kind == "axle" else ogrid
            var axle_r := rot_step if kind == "axle" else orot
            var beam_span_axis := "X" if _piece_axis(beam_r) == "Z" else "Z"
            var axle_axis := _piece_axis(axle_r)
            if beam_span_axis == axle_axis:
                for c in _axle_cells(axle_g, axle_r):
                    if c in _beam_cells(beam_g, beam_r):
                        return {"ok": false, "reason": "El eje no puede ir paralelo dentro de %s." % id}
            continue

        if (kind == "axle" and (okind == "gear_24" or okind == "gear_8" or okind == "wheel")) or \
           ((kind == "gear_24" or kind == "gear_8" or kind == "wheel") and okind == "axle"):
            var axle_g := grid if kind == "axle" else ogrid
            var axle_r := rot_step if kind == "axle" else orot
            var part_g := ogrid if kind == "axle" else grid
            var part_r := orot if kind == "axle" else rot_step
            if _piece_axis(axle_r) == _piece_axis(part_r) and (part_g in _axle_cells(axle_g, axle_r)):
                continue
            if _aabbs_overlap(my_aabb, oaabb):
                return {"ok": false, "reason": "Colisiona lateralmente con %s." % id}
            continue

        if (kind == "axle" and okind == "motor") or (kind == "motor" and okind == "axle"):
            var motor_g := ogrid if kind == "axle" else grid
            var motor_r := orot if kind == "axle" else rot_step
            var axle_g := grid if kind == "axle" else ogrid
            var axle_r := rot_step if kind == "axle" else orot
            var motor_body := _motor_body_aabb(motor_g, motor_r)
            var axle_box := _piece_aabb("axle", axle_g, axle_r)
            if _aabbs_overlap(motor_body, axle_box):
                return {"ok": false, "reason": "El eje choca con la carcasa del motor."}
            if _piece_axis(motor_r) != _piece_axis(axle_r) and _aabbs_overlap(my_aabb, oaabb):
                return {"ok": false, "reason": "El eje cruza el frontal del motor."}
            continue

        if (kind == "gear_24" or kind == "gear_8") and (okind == "gear_24" or okind == "gear_8"):
            var oteeth := int(other["teeth"])
            if my_axis == oaxis:
                var same_slice := (grid.y == ogrid.y) if my_axis == "Z" else (grid.x == ogrid.x)
                if same_slice:
                    var d_studs := absf(float(grid.x - ogrid.x)) if my_axis == "Z" else absf(float(grid.y - ogrid.y))
                    var min_studs := float(my_teeth + oteeth) / 16.0 - 0.05
                    if d_studs < min_studs:
                        return {"ok": false, "reason": "Se superpone con engranaje %s." % id}
                    continue
            if _aabbs_overlap(my_aabb, oaabb):
                return {"ok": false, "reason": "Colisiona con engranaje %s." % id}
            continue

        if _aabbs_overlap(my_aabb, oaabb):
            return {"ok": false, "reason": "Espacio ocupado por %s." % id}

    return {"ok": true, "reason": "Valido en (%d, %d)." % [grid.x, grid.y]}


func _aabbs_overlap(a: AABB, b: AABB) -> bool:
    var eps := 0.04
    var sa := AABB(a.position + Vector3.ONE * eps, (a.size - Vector3.ONE * (eps * 2.0)).max(Vector3.ONE * 0.01))
    var sb := AABB(b.position + Vector3.ONE * eps, (b.size - Vector3.ONE * (eps * 2.0)).max(Vector3.ONE * 0.01))
    return sa.intersects(sb)


func _motor_body_aabb(grid: Vector2i, rot_step: int) -> AABB:
    var hub := _grid_to_world(grid)
    var fwd := _motor_forward(rot_step)
    var fwd3 := Vector3(float(fwd.x), 0.0, float(fwd.y))
    var center := hub - fwd3 * (STUD * 2.55)
    var along_z := (rot_step % 2 == 0)
    var size := Vector3(STUD * 2.35, STUD * 2.4, STUD * 4.1) if along_z else Vector3(STUD * 4.1, STUD * 2.4, STUD * 2.35)
    return AABB(center - size * 0.5, size)


func _piece_aabb(kind: String, grid: Vector2i, rot_step: int) -> AABB:
    var along_z := (rot_step % 2 == 0)
    var center := _grid_to_world(grid)
    var size := Vector3.ONE * STUD
    match kind:
        "motor":
            var fwd := _motor_forward(rot_step)
            center -= Vector3(float(fwd.x), 0.0, float(fwd.y)) * (STUD * 2.15)
            size = Vector3(STUD * 2.35, STUD * 2.4, STUD * 4.7) if along_z else Vector3(STUD * 4.7, STUD * 2.4, STUD * 2.35)
        "beam":
            size = Vector3(STUD * 6.95, STUD * 0.90, STUD * 0.84) if along_z else Vector3(STUD * 0.84, STUD * 0.90, STUD * 6.95)
        "axle":
            size = Vector3(STUD * 0.44, STUD * 0.44, STUD * 4.90) if along_z else Vector3(STUD * 4.90, STUD * 0.44, STUD * 0.44)
        "gear_24":
            size = Vector3(STUD * 3.10, STUD * 3.10, STUD * 0.52) if along_z else Vector3(STUD * 0.52, STUD * 3.10, STUD * 3.10)
        "gear_8":
            size = Vector3(STUD * 1.15, STUD * 1.15, STUD * 0.52) if along_z else Vector3(STUD * 0.52, STUD * 1.15, STUD * 1.15)
        "wheel":
            size = Vector3(STUD * 2.80, STUD * 2.80, STUD * 1.10) if along_z else Vector3(STUD * 1.10, STUD * 2.80, STUD * 2.80)
    return AABB(center - size * 0.5, size)


func _beam_cells(grid: Vector2i, rot_step: int) -> Array[Vector2i]:
    var cells: Array[Vector2i] = []
    var span_dir := Vector2i(1, 0) if (_piece_axis(rot_step) == "Z") else Vector2i(0, 1)
    for k in range(-3, 4):
        cells.append(grid + span_dir * k)
    return cells


func _place_piece(kind: String, grid: Vector2i, rot_step: int, custom_id := "") -> String:
    var id := custom_id
    if id == "":
        id = "%s_%d" % [kind, _next_id]
        _next_id += 1

    var vis := LegoMeshesScript.create_piece_visual(kind)
    var node: Node3D = vis["root"]
    node.position = _grid_to_world(grid)
    node.rotation.y = float(rot_step) * PI * 0.5
    pieces_root.add_child(node)

    var teeth := 0
    if kind == "gear_24":
        teeth = 24
    elif kind == "gear_8":
        teeth = 8

    _pieces[id] = {
        "id": id,
        "kind": kind,
        "grid": grid,
        "rot_step": rot_step,
        "teeth": teeth,
        "node": node,
        "spin_pivot": vis["spin_pivot"],
    }

    _rebuild_kinematic_graph()
    _refresh_ui()
    return id


func _pick_piece_under_mouse(mouse_pos: Vector2) -> String:
    var ray_origin := camera.project_ray_origin(mouse_pos)
    var ray_dir := camera.project_ray_normal(mouse_pos)

    var best_id := ""
    var best_dist := INF

    for id in _pieces.keys():
        var p: Dictionary = _pieces[id]
        var box := _piece_aabb(p["kind"], p["grid"], int(p["rot_step"]))
        var hit = box.intersects_ray(ray_origin, ray_dir)
        if hit != null:
            var d := ray_origin.distance_to(hit)
            if d < best_dist:
                best_dist = d
                best_id = id

    return best_id


func _clear_selection_visuals() -> void:
    for child in _selection_boxes_root.get_children():
        child.queue_free()


func _update_selection_visuals() -> void:
    _clear_selection_visuals()
    if _selected_ids.is_empty():
        return

    var mat := StandardMaterial3D.new()
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.albedo_color = Color(0.25, 0.78, 1.0, 0.24)
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

    var unit_box := BoxMesh.new()
    unit_box.size = Vector3.ONE

    for id in _selected_ids:
        if not _pieces.has(id):
            continue
        var p: Dictionary = _pieces[id]
        var aabb := _piece_aabb(p["kind"], p["grid"], int(p["rot_step"]))
        var mi := MeshInstance3D.new()
        mi.mesh = unit_box
        mi.material_override = mat
        mi.position = aabb.position + aabb.size * 0.5
        mi.scale = aabb.size * 1.04
        _selection_boxes_root.add_child(mi)


func _delete_selected_pieces() -> void:
    if _selected_ids.is_empty():
        return
    for id in _selected_ids:
        if _pieces.has(id):
            (_pieces[id]["node"] as Node3D).queue_free()
            _pieces.erase(id)
    _selected_ids.clear()
    _update_selection_visuals()
    _rebuild_kinematic_graph()
    _refresh_ui()


func _clear_all_pieces() -> void:
    sim.stop()
    for id in _pieces.keys():
        (_pieces[id]["node"] as Node3D).queue_free()
    _pieces.clear()
    _selected_ids.clear()
    _next_id = 1
    _update_selection_visuals()
    _rebuild_kinematic_graph()
    _refresh_ui()


func _load_example_train() -> void:
    _clear_all_pieces()
    _place_piece("motor", Vector2i(0, -1), 0, "motor_ev3")
    _place_piece("beam", Vector2i(1, 0), 0, "beam_soporte")
    _place_piece("axle", Vector2i(0, 1), 0, "eje_entrada")
    _place_piece("gear_24", Vector2i(0, 1), 0, "gear24_conductor")
    _place_piece("axle", Vector2i(2, 1), 0, "eje_salida")
    _place_piece("gear_8", Vector2i(2, 1), 0, "gear8_conducido")
    _place_piece("wheel", Vector2i(2, 2), 0, "rueda_salida")
    _set_tool("select")
    _hint_label.text = "Tren de ejemplo cargado. Arrastra en vacio para seleccion multiple o pulsa Simular."
    _refresh_ui()


func _motor_forward(rot_step: int) -> Vector2i:
    match rot_step % 4:
        0: return Vector2i(0, 1)
        1: return Vector2i(1, 0)
        2: return Vector2i(0, -1)
        _: return Vector2i(-1, 0)


func _axle_cells(grid: Vector2i, rot_step: int) -> Array[Vector2i]:
    var cells: Array[Vector2i] = []
    var dir := Vector2i(0, 1) if (_piece_axis(rot_step) == "Z") else Vector2i(1, 0)
    for k in range(-2, 3):
        cells.append(grid + dir * k)
    return cells


func _will_gears_mesh(g1: Vector2i, teeth1: int, g2: Vector2i, teeth2: int, axis: String) -> bool:
    var expected_studs := (teeth1 + teeth2) / 16
    if axis == "Z":
        return g1.y == g2.y and absi(g1.x - g2.x) == expected_studs
    return g1.x == g2.x and absi(g1.y - g2.y) == expected_studs


func _rebuild_kinematic_graph() -> void:
    sim.clear_mechanism()

    for id in _pieces.keys():
        var p: Dictionary = _pieces[id]
        match p["kind"]:
            "motor":
                sim.add_motor(id)
            "axle":
                sim.add_shaft(id)
            "gear_24":
                sim.add_gear(id, 24)
            "gear_8":
                sim.add_gear(id, 8)
            "wheel":
                sim.add_wheel(id)

    var ids := _pieces.keys()
    for i in range(ids.size()):
        for j in range(i + 1, ids.size()):
            var a: Dictionary = _pieces[ids[i]]
            var b: Dictionary = _pieces[ids[j]]
            var ka: String = a["kind"]
            var kb: String = b["kind"]
            if ka == "beam" or kb == "beam":
                continue

            var axis_a := _piece_axis(int(a["rot_step"]))
            var axis_b := _piece_axis(int(b["rot_step"]))
            if axis_a != axis_b:
                continue

            if _are_coaxial(a, b):
                sim.connect_coaxial(a["id"], b["id"])

            if (ka == "gear_24" or ka == "gear_8") and (kb == "gear_24" or kb == "gear_8"):
                if _will_gears_mesh(a["grid"], int(a["teeth"]), b["grid"], int(b["teeth"]), axis_a):
                    sim.connect_external_gears(a["id"], b["id"])

    _align_meshed_gear_phases()


func _are_coaxial(a: Dictionary, b: Dictionary) -> bool:
    var cells_a := _rotational_cells(a)
    var cells_b := _rotational_cells(b)
    for ca in cells_a:
        if ca in cells_b:
            if a["kind"] == "axle" or b["kind"] == "axle" or a["kind"] == "motor" or b["kind"] == "motor":
                return true
    return false


func _rotational_cells(p: Dictionary) -> Array[Vector2i]:
    var kind: String = p["kind"]
    var grid: Vector2i = p["grid"]
    var rot_step: int = int(p["rot_step"])
    if kind == "axle":
        return _axle_cells(grid, rot_step)
    if kind == "motor":
        return [grid, grid + _motor_forward(rot_step)]
    return [grid]


func _align_meshed_gear_phases() -> void:
    for id in _pieces.keys():
        var p: Dictionary = _pieces[id]
        if p["kind"] == "gear_8":
            (p["spin_pivot"] as Node3D).rotation.z = PI / 8.0
        elif p["kind"] == "gear_24" or p["kind"] == "wheel" or p["kind"] == "axle" or p["kind"] == "motor":
            (p["spin_pivot"] as Node3D).rotation.z = 0.0


func _on_simulate_pressed() -> void:
    _set_tool("select")
    _rebuild_kinematic_graph()
    sim.start()
    _refresh_ui()


func _on_stop_pressed() -> void:
    sim.stop()
    _refresh_ui()


func _on_reverse_pressed() -> void:
    sim.reverse_direction()
    _refresh_ui()


func _on_rpm_changed(val: float) -> void:
    sim.set_target_rpm(val)
    _refresh_ui()


func _dir_text(rpm: float) -> String:
    if rpm > 0.0001:
        return "Antihorario (+)"
    if rpm < -0.0001:
        return "Horario (-)"
    return "Detenido"


func _refresh_ui() -> void:
    if sim == null:
        return

    _rpm_spinbox.set_value_no_signal(sim.get_target_rpm())

    var running := sim.is_running()
    var valid := sim.is_mechanism_valid()
    var disconnected := sim.get_disconnected_components()

    if not valid:
        _status_label.text = "No listo: %s" % sim.get_status_message()
        _status_label.modulate = Color(1.0, 0.42, 0.42)
    elif running and disconnected.size() > 0:
        _status_label.text = "Simulando | Sueltas sin motor: %s" % ", ".join(disconnected)
        _status_label.modulate = Color(0.98, 0.78, 0.28)
    elif running:
        _status_label.text = "Simulando (Mecanismo completo conectado)"
        _status_label.modulate = Color(0.35, 0.92, 0.45)
    elif disconnected.size() > 0:
        _status_label.text = "Modo Construir | Piezas sueltas: %s" % ", ".join(disconnected)
        _status_label.modulate = Color(0.95, 0.80, 0.35)
    else:
        _status_label.text = "Modo Construir | Mecanismo listo"
        _status_label.modulate = Color(0.65, 0.86, 1.0)

    if _selected_ids.size() == 1 and _pieces.has(_selected_ids[0]):
        var sid := _selected_ids[0]
        var sp: Dictionary = _pieces[sid]
        var info := "Seleccionado: %s (%s)\nPosicion: (%d, %d)" % [
            sp["id"], PIECE_SPECS[sp["kind"]]["label"], sp["grid"].x, sp["grid"].y
        ]
        if sp["kind"] != "beam":
            if sim.is_component_connected(sid):
                var rpm := sim.get_component_rpm(sid)
                info += "\nEstado: Conectada | %+.1f RPM (%s)" % [rpm, _dir_text(rpm)]
            else:
                info += "\nEstado: Sin conexion al motor (0 RPM)"
        else:
            info += "\nRol: Pieza estructural (soporte)"
        _selection_label.text = info
    elif _selected_ids.size() > 1:
        _selection_label.text = "Seleccionadas: %d piezas\nArrastra cualquiera para mover el grupo o pulsa Supr para borrar." % _selected_ids.size()
    else:
        _selection_label.text = "Seleccion: Ninguna\n(Clic o arrastra cuadro en vacio)"

    var lines := PackedStringArray()
    lines.append("Lecturas del nucleo C++:")
    for id in _pieces.keys():
        var p: Dictionary = _pieces[id]
        if p["kind"] == "beam":
            continue
        if sim.is_component_connected(id):
            var r := sim.get_component_rpm(id)
            lines.append("• %s: %+.1f RPM" % [id, r])
        else:
            lines.append("• %s: desconectada" % id)
    _telemetry_label.text = "\n".join(lines)

    _sim_button.disabled = running or not valid
    _stop_button.disabled = not running
    _reverse_button.disabled = not valid
    _delete_button.disabled = running or _selected_ids.is_empty()
    _update_metrics()


func _update_metrics() -> void:
    var mem_mb := float(OS.get_static_memory_usage()) / (1024.0 * 1024.0)
    _metrics_label.text = "FPS: %d | Mem estatica: %.1f MB" % [
        Engine.get_frames_per_second(),
        mem_mb
    ]
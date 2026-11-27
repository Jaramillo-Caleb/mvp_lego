class_name TrackArena
extends Node3D

const ARENA_SIZE := 40.0
const TEX_RES := 1024

var _track_image: Image
var _track_texture: ImageTexture
var _floor_body: StaticBody3D
var _sensor_spot: MeshInstance3D


func _ready() -> void:
    _generate_track_image()
    _build_floor_and_walls()
    _build_sensor_spot()


func _generate_track_image() -> void:
    _track_image = Image.create(TEX_RES, TEX_RES, false, Image.FORMAT_RGBA8)
    _track_image.fill(Color(0.93, 0.94, 0.96, 1.0))

    # Cuadricula sutil de referencia cada 2 m para apreciar el avance
    var grid_px := int(2.0 / ARENA_SIZE * float(TEX_RES))
    var grid_col := Color(0.84, 0.87, 0.91, 1.0)
    for x in range(TEX_RES):
        if x % grid_px == 0:
            for y in range(TEX_RES):
                _track_image.set_pixel(x, y, grid_col)
    for y in range(TEX_RES):
        if y % grid_px == 0:
            for x in range(TEX_RES):
                _track_image.set_pixel(x, y, grid_col)

    # Pista cerrada negra: recta superior (z=+8) + curva + chicane suave en S + curva
    var pts := _build_track_points()
    var line_radius_m := 0.30
    var r_px := maxi(2, int(line_radius_m / ARENA_SIZE * float(TEX_RES)))
    var black := Color(0.06, 0.07, 0.08, 1.0)

    for i in range(pts.size()):
        var p0 := pts[i]
        var p1 := pts[(i + 1) % pts.size()]
        var steps := maxi(1, int(p0.distance_to(p1) * 16.0))
        for s in range(steps + 1):
            var p := p0.lerp(p1, float(s) / float(steps))
            var cx := int(((p.x + ARENA_SIZE * 0.5) / ARENA_SIZE) * float(TEX_RES - 1))
            var cy := int(((p.y + ARENA_SIZE * 0.5) / ARENA_SIZE) * float(TEX_RES - 1))
            _paint_disc(cx, cy, r_px, black)

    _track_texture = ImageTexture.create_from_image(_track_image)


func _build_track_points() -> Array[Vector2]:
    var pts: Array[Vector2] = []
    # Recta superior z = +8.0 desde x = -7 hasta +7
    for i in range(28):
        pts.append(Vector2(lerpf(-7.0, 7.0, float(i) / 28.0), 8.0))
    # Curva derecha hacia z = -8.0 (radio 8 m, suave)
    for i in range(40):
        var a := lerpf(PI * 0.5, -PI * 0.5, float(i) / 40.0)
        pts.append(Vector2(7.0 + 7.5 * cos(a), 8.0 * sin(a)))
    # Recta inferior con suave curva en S (z = -8.0 + 1.6 * sin)
    for i in range(36):
        var t := float(i) / 36.0
        var x := lerpf(7.0, -7.0, t)
        var z := -8.0 + 1.8 * sin(t * TAU)
        pts.append(Vector2(x, z))
    # Curva izquierda regresando a z = +8.0
    for i in range(40):
        var a := lerpf(-PI * 0.5, -PI * 1.5, float(i) / 40.0)
        pts.append(Vector2(-7.0 + 7.5 * cos(a), 8.0 * sin(a)))
    return pts


func _paint_disc(cx: int, cy: int, r: int, col: Color) -> void:
    var r2 := r * r
    for dy in range(-r, r + 1):
        var py := cy + dy
        if py < 0 or py >= TEX_RES:
            continue
        for dx in range(-r, r + 1):
            var px := cx + dx
            if px < 0 or px >= TEX_RES:
                continue
            if dx * dx + dy * dy <= r2:
                _track_image.set_pixel(px, py, col)


func _build_floor_and_walls() -> void:
    _floor_body = StaticBody3D.new()
    var zero_fric := PhysicsMaterial.new()
    zero_fric.friction = 0.0
    zero_fric.bounce = 0.0
    _floor_body.physics_material_override = zero_fric
    add_child(_floor_body)

    var floor_col := CollisionShape3D.new()
    var floor_box := BoxShape3D.new()
    floor_box.size = Vector3(ARENA_SIZE, 0.4, ARENA_SIZE)
    floor_col.shape = floor_box
    floor_col.position = Vector3(0.0, -0.2, 0.0)
    _floor_body.add_child(floor_col)

    var floor_mesh := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(ARENA_SIZE, ARENA_SIZE)
    floor_mesh.mesh = plane
    var mat := StandardMaterial3D.new()
    mat.albedo_texture = _track_texture
    mat.roughness = 0.85
    floor_mesh.material_override = mat
    add_child(floor_mesh)

    # Muros suaves perimetrales para no caer al vacio
    var wall_mat := StandardMaterial3D.new()
    wall_mat.albedo_color = Color(0.24, 0.28, 0.34)
    var half := ARENA_SIZE * 0.5
    var specs := [
        [Vector3(0.0, 0.4, -half), Vector3(ARENA_SIZE, 0.8, 0.5)],
        [Vector3(0.0, 0.4, half), Vector3(ARENA_SIZE, 0.8, 0.5)],
        [Vector3(-half, 0.4, 0.0), Vector3(0.5, 0.8, ARENA_SIZE)],
        [Vector3(half, 0.4, 0.0), Vector3(0.5, 0.8, ARENA_SIZE)],
    ]
    for s in specs:
        var wc := CollisionShape3D.new()
        var wb := BoxShape3D.new()
        wb.size = s[1]
        wc.shape = wb
        wc.position = s[0]
        _floor_body.add_child(wc)

        var wm := MeshInstance3D.new()
        var bm := BoxMesh.new()
        bm.size = s[1]
        wm.mesh = bm
        wm.position = s[0]
        wm.material_override = wall_mat
        add_child(wm)


func _build_sensor_spot() -> void:
    _sensor_spot = MeshInstance3D.new()
    var cyl := CylinderMesh.new()
    cyl.top_radius = 0.18
    cyl.bottom_radius = 0.18
    cyl.height = 0.02
    _sensor_spot.mesh = cyl
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.albedo_color = Color(1.0, 0.2, 0.2)
    _sensor_spot.material_override = m
    _sensor_spot.visible = false
    add_child(_sensor_spot)


func update_sensor_spot(world_pos: Vector3, active: bool, light_pct: float) -> void:
    _sensor_spot.visible = active
    if active:
        _sensor_spot.position = Vector3(world_pos.x, 0.015, world_pos.z)
        var m := _sensor_spot.material_override as StandardMaterial3D
        m.albedo_color = Color(0.15, 0.95, 0.35) if light_pct < 45.0 else Color(1.0, 0.25, 0.20)


func sample_light_intensity(world_pos: Vector3) -> float:
    if _track_image == null:
        return 100.0
    var u := clampf((world_pos.x + ARENA_SIZE * 0.5) / ARENA_SIZE, 0.0, 0.999)
    var v := clampf((world_pos.z + ARENA_SIZE * 0.5) / ARENA_SIZE, 0.0, 0.999)
    var cx := int(u * float(TEX_RES - 1))
    var cy := int(v * float(TEX_RES - 1))

    # Promedio 3x3 pixeles (simula el haz de luz del Sensor EV3)
    var total := 0.0
    var count := 0
    for dy in range(-1, 2):
        var py := clampi(cy + dy, 0, TEX_RES - 1)
        for dx in range(-1, 2):
            var px := clampi(cx + dx, 0, TEX_RES - 1)
            var c := _track_image.get_pixel(px, py)
            total += (c.r + c.g + c.b) / 3.0
            count += 1
    return (total / float(count)) * 100.0
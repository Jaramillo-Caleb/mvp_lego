extends SceneTree

var _failures := 0

func _check(cond: bool, msg: String) -> void:
    if cond:
        print("[PASS] ", msg)
    else:
        push_error("[FAIL] " + msg)
        _failures += 1

func _check_near(actual: float, expected: float, msg: String) -> void:
    _check(absf(actual - expected) <= 1e-6, "%s (expected=%s actual=%s)" % [msg, expected, actual])

func _init() -> void:
    _check(ClassDB.class_exists("OpenSimNode"), "OpenSimNode registered in ClassDB")
    if not ClassDB.class_exists("OpenSimNode"):
        quit(1)
        return

    var sim = ClassDB.instantiate("OpenSimNode")
    _check(sim != null, "OpenSimNode instantiated")
    _check(sim.is_mechanism_valid(), "Default mechanism is valid")
    _check(not sim.is_running(), "Starts stopped")

    _check(sim.set_target_rpm(60.0), "Set target RPM to +60")
    _check(sim.start(), "Start succeeds")
    _check_near(sim.get_input_rpm(), 60.0, "24T gear at +60 RPM")
    _check_near(sim.get_output_rpm(), -180.0, "8T gear at -180 RPM")

    _check(sim.reverse_direction(), "Reverse succeeds")
    _check_near(sim.get_input_rpm(), -60.0, "Reversed 24T gear at -60 RPM")
    _check_near(sim.get_output_rpm(), 180.0, "Reversed 8T gear at +180 RPM")

    sim.stop()
    _check_near(sim.get_output_rpm(), 0.0, "Output RPM returns to 0 on stop")

    # Studio partial mode + Wheel check
    sim.set_strict_mode(false)
    sim.clear_mechanism()
    _check(sim.add_motor("m1"), "Add motor in Studio mode")
    _check(sim.add_shaft("a1"), "Add shaft 1")
    _check(sim.add_gear("g24", 24), "Add 24T gear")
    _check(sim.add_gear("g8", 8), "Add 8T gear")
    _check(sim.add_shaft("a2"), "Add shaft 2")
    _check(sim.add_wheel("w_out"), "Add driven wheel")
    _check(sim.add_wheel("w_loose"), "Add loose wheel")

    _check(sim.connect_coaxial("m1", "a1"), "Connect m1-a1")
    _check(sim.connect_coaxial("a1", "g24"), "Connect a1-g24")
    _check(sim.connect_external_gears("g24", "g8"), "Mesh g24-g8")
    _check(sim.connect_coaxial("g8", "a2"), "Connect g8-a2")
    _check(sim.connect_coaxial("a2", "w_out"), "Connect a2-w_out")

    sim.set_target_rpm(60.0)
    _check(sim.start(), "Start Studio mechanism")
    _check(sim.is_component_connected("w_out"), "Driven wheel is connected")
    _check_near(sim.get_component_rpm("w_out"), -180.0, "Driven wheel spins at -180 RPM")
    _check(not sim.is_component_connected("w_loose"), "Loose wheel reported disconnected")
    _check(sim.get_disconnected_components().size() == 1, "Disconnected list size is 1")

    _check(not sim.add_gear("bad_gear", 0), "Zero-tooth gear rejected from GDScript")
    _check(sim.get_error_code() != 0, "Error code reported for invalid gear")

    sim.free()

    if _failures == 0:
        print("GODOT GDEXTENSION SMOKE TEST PASSED")
        quit(0)
    else:
        print("GODOT GDEXTENSION SMOKE TEST FAILED: ", _failures)
        quit(1)
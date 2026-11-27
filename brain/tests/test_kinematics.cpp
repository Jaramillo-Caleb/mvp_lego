#include "opensim/Simulation.hpp"

#include <cmath>
#include <iostream>
#include <string>

namespace {

int g_failures = 0;

void check_true(bool condition, const std::string& label) {
    if (!condition) {
        std::cerr << "[FAIL] " << label << "\n";
        ++g_failures;
    } else {
        std::cout << "[PASS] " << label << "\n";
    }
}

void check_near(double actual, double expected, const std::string& label) {
    const bool ok = std::abs(actual - expected) <= 1e-9;
    if (!ok) {
        std::cerr << "[FAIL] " << label
                  << " (expected " << expected << ", got " << actual << ")\n";
        ++g_failures;
    } else {
        std::cout << "[PASS] " << label << "\n";
    }
}

void test_default_24t_to_8t_forward_reverse_and_stop() {
    opensim::Simulation sim;

    check_true(sim.is_mechanism_valid(), "1.1 Default MVP mechanism is valid");
    check_true(!sim.is_running(), "1.2 Simulation starts in Stopped state");
    check_near(sim.input_rpm(), 0.0, "1.3 Input RPM is 0 when stopped");
    check_near(sim.output_rpm(), 0.0, "1.4 Output RPM is 0 when stopped");

    const auto start_res = sim.start();
    check_true(start_res.ok, "1.5 Start succeeds");
    check_true(sim.is_running(), "1.6 State is Running");
    check_near(sim.input_rpm(), 60.0, "1.7 24T input is +60 RPM");
    check_near(sim.output_rpm(), -180.0, "1.8 8T output is -180 RPM");
    check_near(sim.component_ratio("gear_8").value_or(0.0), -3.0, "1.9 Gear 8T ratio is -3.0");

    const auto rev_res = sim.reverse_direction();
    check_true(rev_res.ok, "2.1 Reverse succeeds");
    check_near(sim.input_rpm(), -60.0, "2.2 Reversed 24T input is -60 RPM");
    check_near(sim.output_rpm(), 180.0, "2.3 Reversed 8T output is +180 RPM");

    sim.stop();
    check_true(!sim.is_running(), "3.1 Stop sets state to Stopped");
    check_true(sim.is_mechanism_valid(), "3.2 Topology remains valid after Stop");
    check_near(sim.input_rpm(), 0.0, "3.3 Input RPM returns to 0 after Stop");
    check_near(sim.output_rpm(), 0.0, "3.4 Output RPM returns to 0 after Stop");
    check_true(!std::signbit(sim.output_rpm()), "3.5 Output zero is not negative zero (-0.0)");

    sim.start();
    check_near(sim.output_rpm(), 180.0, "3.6 Restarting preserves reversed speed (+180 RPM)");
}

void test_invalid_gear_teeth_rejected() {
    opensim::ConnectionGraph graph;

    const auto zero_teeth = graph.add_component(opensim::Component::make_gear("g0", 0));
    check_true(!zero_teeth.ok && zero_teeth.error == opensim::ErrorCode::InvalidArgument,
               "4.1 Zero gear teeth rejected");

    const auto neg_teeth = graph.add_component(opensim::Component::make_gear("g_neg", -8));
    check_true(!neg_teeth.ok && neg_teeth.error == opensim::ErrorCode::InvalidArgument,
               "4.2 Negative gear teeth rejected");
}

void test_unknown_and_incompatible_connections_rejected() {
    opensim::ConnectionGraph graph;
    graph.add_component(opensim::Component::make_motor("motor"));
    graph.add_component(opensim::Component::make_shaft("shaft"));
    graph.add_component(opensim::Component::make_gear("g24", 24));
    graph.add_component(opensim::Component::make_wheel("wheel"));

    const auto unknown = graph.connect({
        "motor", opensim::PortKind::RotationalAxis,
        "does_not_exist", opensim::PortKind::RotationalAxis,
        opensim::ConnectionKind::Coaxial});
    check_true(!unknown.ok && unknown.error == opensim::ErrorCode::UnknownComponent,
               "5.1 Unknown component ID rejected");

    const auto self_conn = graph.connect({
        "motor", opensim::PortKind::RotationalAxis,
        "motor", opensim::PortKind::RotationalAxis,
        opensim::ConnectionKind::Coaxial});
    check_true(!self_conn.ok && self_conn.error == opensim::ErrorCode::SelfConnection,
               "5.2 Self connection rejected");

    const auto incompatible_port = graph.connect({
        "motor", opensim::PortKind::RotationalAxis,
        "g24", opensim::PortKind::GearTeeth,
        opensim::ConnectionKind::Coaxial});
    check_true(!incompatible_port.ok && incompatible_port.error == opensim::ErrorCode::IncompatiblePorts,
               "5.3 Mismatched ports on Coaxial rejected");

    const auto incompatible_mesh = graph.connect({
        "shaft", opensim::PortKind::GearTeeth,
        "g24", opensim::PortKind::GearTeeth,
        opensim::ConnectionKind::ExternalGearMesh});
    check_true(!incompatible_mesh.ok && incompatible_mesh.error == opensim::ErrorCode::IncompatiblePorts,
               "5.4 Shaft cannot use ExternalGearMesh");

    const auto wheel_mesh = graph.connect({
        "wheel", opensim::PortKind::GearTeeth,
        "g24", opensim::PortKind::GearTeeth,
        opensim::ConnectionKind::ExternalGearMesh});
    check_true(!wheel_mesh.ok && wheel_mesh.error == opensim::ErrorCode::IncompatiblePorts,
               "5.5 Wheel cannot use ExternalGearMesh");
}

void test_duplicate_connections_rejected() {
    opensim::ConnectionGraph graph;
    graph.add_component(opensim::Component::make_gear("g24", 24));
    graph.add_component(opensim::Component::make_gear("g8", 8));

    const auto first = graph.connect({
        "g24", opensim::PortKind::GearTeeth,
        "g8", opensim::PortKind::GearTeeth,
        opensim::ConnectionKind::ExternalGearMesh});
    check_true(first.ok, "6.1 First gear mesh succeeds");

    const auto dup_same = graph.connect({
        "g24", opensim::PortKind::GearTeeth,
        "g8", opensim::PortKind::GearTeeth,
        opensim::ConnectionKind::ExternalGearMesh});
    check_true(!dup_same.ok && dup_same.error == opensim::ErrorCode::DuplicateConnection,
               "6.2 Exact duplicate connection rejected");

    const auto dup_reverse = graph.connect({
        "g8", opensim::PortKind::GearTeeth,
        "g24", opensim::PortKind::GearTeeth,
        opensim::ConnectionKind::ExternalGearMesh});
    check_true(!dup_reverse.ok && dup_reverse.error == opensim::ErrorCode::DuplicateConnection,
               "6.3 Reverse-order duplicate connection rejected");
}

void test_invalid_mechanism_produces_no_false_rpms() {
    {
        opensim::Simulation sim;
        sim.graph().clear();
        sim.graph().add_component(opensim::Component::make_motor("motor"));
        sim.graph().add_component(opensim::Component::make_gear("g24", 24));
        sim.graph().add_component(opensim::Component::make_gear("g8", 8));
        sim.graph().connect({
            "motor", opensim::PortKind::RotationalAxis,
            "g24", opensim::PortKind::RotationalAxis,
            opensim::ConnectionKind::Coaxial});

        const auto res = sim.set_io_components("g24", "g8");
        check_true(!res.ok, "7.1 Disconnected mechanism fails validation");
        check_true(!sim.is_mechanism_valid(), "7.2 Mechanism reported invalid");
        check_true(!sim.component_rpm("g8").has_value(), "7.3 Unconnected gear has no RPM");
        check_near(sim.output_rpm(), 0.0, "7.4 Output RPM stays 0 on invalid mechanism");
    }

    {
        opensim::ConnectionGraph graph;
        graph.add_component(opensim::Component::make_motor("motor"));
        graph.add_component(opensim::Component::make_gear("g24", 24));
        graph.add_component(opensim::Component::make_gear("g8", 8));
        graph.add_component(opensim::Component::make_gear("loose", 12));
        graph.connect({
            "motor", opensim::PortKind::RotationalAxis,
            "g24", opensim::PortKind::RotationalAxis,
            opensim::ConnectionKind::Coaxial});
        graph.connect({
            "g24", opensim::PortKind::GearTeeth,
            "g8", opensim::PortKind::GearTeeth,
            opensim::ConnectionKind::ExternalGearMesh});

        opensim::KinematicSolver solver;
        const auto solved = solver.solve(graph, 60.0, opensim::SimulationState::Running);
        check_true(!solved.ok && solved.error == opensim::ErrorCode::DisconnectedMechanism,
                   "7.5 Solver rejects graph with disconnected component");
        check_true(solved.rpms.empty(), "7.6 Failed solve returns empty RPM map");
    }

    {
        opensim::ConnectionGraph graph;
        graph.add_component(opensim::Component::make_motor("motor"));
        graph.add_component(opensim::Component::make_gear("g1", 12));
        graph.add_component(opensim::Component::make_gear("g2", 12));
        graph.add_component(opensim::Component::make_gear("g3", 12));
        graph.connect({
            "motor", opensim::PortKind::RotationalAxis,
            "g1", opensim::PortKind::RotationalAxis,
            opensim::ConnectionKind::Coaxial});
        graph.connect({
            "g1", opensim::PortKind::GearTeeth,
            "g2", opensim::PortKind::GearTeeth,
            opensim::ConnectionKind::ExternalGearMesh});
        graph.connect({
            "g2", opensim::PortKind::GearTeeth,
            "g3", opensim::PortKind::GearTeeth,
            opensim::ConnectionKind::ExternalGearMesh});
        graph.connect({
            "g3", opensim::PortKind::GearTeeth,
            "g1", opensim::PortKind::GearTeeth,
            opensim::ConnectionKind::ExternalGearMesh});

        opensim::KinematicSolver solver;
        const auto solved = solver.solve(graph, 60.0, opensim::SimulationState::Running);
        check_true(!solved.ok && solved.error == opensim::ErrorCode::KinematicConflict,
                   "7.7 Solver detects 3-gear kinematic conflict");
    }
}

void test_studio_wheel_and_partial_connected_mode() {
    opensim::Simulation sim;
    sim.set_strict_mode(false);
    sim.graph().clear();

    sim.graph().add_component(opensim::Component::make_motor("motor_1"));
    sim.graph().add_component(opensim::Component::make_shaft("axle_1"));
    sim.graph().add_component(opensim::Component::make_gear("gear_24", 24));
    sim.graph().add_component(opensim::Component::make_gear("gear_8", 8));
    sim.graph().add_component(opensim::Component::make_shaft("axle_2"));
    sim.graph().add_component(opensim::Component::make_wheel("wheel_out"));
    sim.graph().add_component(opensim::Component::make_wheel("wheel_loose"));

    sim.graph().connect({"motor_1", opensim::PortKind::RotationalAxis, "axle_1", opensim::PortKind::RotationalAxis, opensim::ConnectionKind::Coaxial});
    sim.graph().connect({"axle_1", opensim::PortKind::RotationalAxis, "gear_24", opensim::PortKind::RotationalAxis, opensim::ConnectionKind::Coaxial});
    sim.graph().connect({"gear_24", opensim::PortKind::GearTeeth, "gear_8", opensim::PortKind::GearTeeth, opensim::ConnectionKind::ExternalGearMesh});
    sim.graph().connect({"gear_8", opensim::PortKind::RotationalAxis, "axle_2", opensim::PortKind::RotationalAxis, opensim::ConnectionKind::Coaxial});
    sim.graph().connect({"axle_2", opensim::PortKind::RotationalAxis, "wheel_out", opensim::PortKind::RotationalAxis, opensim::ConnectionKind::Coaxial});

    sim.set_target_rpm(60.0);
    const auto start_res = sim.start();
    check_true(start_res.ok, "8.1 Studio partial mode starts with connected train + loose wheel");
    check_true(sim.is_component_connected("wheel_out"), "8.2 Driven wheel is connected");
    check_near(sim.component_rpm("wheel_out").value_or(0.0), -180.0, "8.3 Driven wheel spins at -180 RPM");
    check_true(!sim.is_component_connected("wheel_loose"), "8.4 Loose wheel reported disconnected");
    check_true(!sim.component_rpm("wheel_loose").has_value(), "8.5 Loose wheel has no fake RPM");
    check_true(sim.disconnected_components().size() == 1 &&
               sim.disconnected_components()[0] == "wheel_loose",
               "8.6 Disconnected list contains wheel_loose");
}

void test_differential_two_motor_drive_and_conflict() {
    opensim::Simulation sim;
    sim.set_strict_mode(false);
    sim.graph().clear();

    // Tren izquierdo (directo 1:1) y tren derecho (reductor 8T -> 24T = -1/3)
    sim.graph().add_component(opensim::Component::make_motor("m_left"));
    sim.graph().add_component(opensim::Component::make_shaft("a_left"));
    sim.graph().add_component(opensim::Component::make_wheel("w_left"));
    sim.graph().connect({"m_left", opensim::PortKind::RotationalAxis, "a_left", opensim::PortKind::RotationalAxis, opensim::ConnectionKind::Coaxial});
    sim.graph().connect({"a_left", opensim::PortKind::RotationalAxis, "w_left", opensim::PortKind::RotationalAxis, opensim::ConnectionKind::Coaxial});

    sim.graph().add_component(opensim::Component::make_motor("m_right"));
    sim.graph().add_component(opensim::Component::make_gear("g8", 8));
    sim.graph().add_component(opensim::Component::make_gear("g24", 24));
    sim.graph().add_component(opensim::Component::make_wheel("w_right"));
    sim.graph().connect({"m_right", opensim::PortKind::RotationalAxis, "g8", opensim::PortKind::RotationalAxis, opensim::ConnectionKind::Coaxial});
    sim.graph().connect({"g8", opensim::PortKind::GearTeeth, "g24", opensim::PortKind::GearTeeth, opensim::ConnectionKind::ExternalGearMesh});
    sim.graph().connect({"g24", opensim::PortKind::RotationalAxis, "w_right", opensim::PortKind::RotationalAxis, opensim::ConnectionKind::Coaxial});

    sim.set_motor_rpm("m_left", 120.0);
    sim.set_motor_rpm("m_right", 90.0);
    check_true(sim.start().ok, "9.1 Differential two-motor robot starts");
    check_near(sim.component_rpm("w_left").value_or(0.0), 120.0, "9.2 Left wheel spins at +120 RPM");
    check_near(sim.component_rpm("w_right").value_or(0.0), -30.0, "9.3 Right reduced wheel spins at -30 RPM");
    check_near(sim.component_ratio("w_right").value_or(0.0), -1.0 / 3.0, "9.4 Right wheel torque/speed ratio is -1/3");

    // Acoplar dos motores en el mismo tren debe rechazarse
    sim.graph().connect({"a_left", opensim::PortKind::RotationalAxis, "g8", opensim::PortKind::RotationalAxis, opensim::ConnectionKind::Coaxial});
    const auto conflict = sim.recompute();
    check_true(!conflict.ok && conflict.error == opensim::ErrorCode::KinematicConflict,
               "9.5 Two motors coupled on same train rejected");
}

} // namespace

int main() {
    test_default_24t_to_8t_forward_reverse_and_stop();
    test_invalid_gear_teeth_rejected();
    test_unknown_and_incompatible_connections_rejected();
    test_duplicate_connections_rejected();
    test_invalid_mechanism_produces_no_false_rpms();
    test_studio_wheel_and_partial_connected_mode();
    test_differential_two_motor_drive_and_conflict();

    if (g_failures == 0) {
        std::cout << "\nALL TESTS PASSED.\n";
        return 0;
    }
    std::cerr << "\nTESTS FAILED: " << g_failures << "\n";
    return 1;
}
#include "opensim/KinematicSolver.hpp"

#include <cmath>
#include <queue>
#include <utility>
#include <vector>

namespace opensim {

namespace {

struct Edge {
    ComponentId target;
    double ratio;
};

double normalize_zero(double value) {
    return (value == 0.0) ? 0.0 : value;
}

} // namespace

SolveResult KinematicSolver::solve(
    const ConnectionGraph& graph,
    Rpm motor_target_rpm,
    SimulationState state,
    SolveMode mode) const {
    if (!std::isfinite(motor_target_rpm)) {
        return SolveResult{
            false, ErrorCode::InvalidArgument, "Target RPM must be a finite number", {}, {}};
    }

    const auto& components = graph.components();
    if (components.empty()) {
        return SolveResult{
            false, ErrorCode::NoMotor, "Mechanism has no components", {}, {}};
    }

    ComponentId motor_id;
    int motor_count = 0;
    for (const auto& [id, comp] : components) {
        if (comp.type == ComponentType::Motor) {
            motor_id = id;
            ++motor_count;
        }
        if (comp.type == ComponentType::Gear && comp.teeth <= 0) {
            return SolveResult{
                false,
                ErrorCode::InvalidArgument,
                "Gear '" + id + "' has invalid tooth count",
                {},
                {}};
        }
    }

    if (motor_count == 0) {
        return SolveResult{
            false, ErrorCode::NoMotor, "Mechanism has no motor", {}, {}};
    }
    if (motor_count > 1) {
        return SolveResult{
            false,
            ErrorCode::MultipleMotors,
            "Multiple motors are not supported in the MVP",
            {},
            {}};
    }

    std::map<ComponentId, std::vector<Edge>> adjacency;
    for (const auto& conn : graph.connections()) {
        const Component* from = graph.find_component(conn.from_id);
        const Component* to = graph.find_component(conn.to_id);
        if (from == nullptr || to == nullptr) {
            return SolveResult{
                false,
                ErrorCode::UnknownComponent,
                "Connection references an unknown component",
                {},
                {}};
        }

        double forward_ratio = 1.0;
        double backward_ratio = 1.0;

        if (conn.kind == ConnectionKind::ExternalGearMesh) {
            if (from->type != ComponentType::Gear || to->type != ComponentType::Gear ||
                from->teeth <= 0 || to->teeth <= 0) {
                return SolveResult{
                    false,
                    ErrorCode::IncompatiblePorts,
                    "ExternalGearMesh requires valid gears with positive teeth",
                    {},
                    {}};
            }
            forward_ratio = -static_cast<double>(from->teeth) / static_cast<double>(to->teeth);
            backward_ratio = -static_cast<double>(to->teeth) / static_cast<double>(from->teeth);
        }

        adjacency[conn.from_id].push_back(Edge{conn.to_id, forward_ratio});
        adjacency[conn.to_id].push_back(Edge{conn.from_id, backward_ratio});
    }

    std::map<ComponentId, double> unit_ratios;
    std::queue<ComponentId> queue;
    unit_ratios[motor_id] = 1.0;
    queue.push(motor_id);

    while (!queue.empty()) {
        const ComponentId current = queue.front();
        queue.pop();

        const double current_ratio = unit_ratios[current];
        const auto adj_it = adjacency.find(current);
        if (adj_it == adjacency.end()) {
            continue;
        }

        for (const auto& edge : adj_it->second) {
            const double candidate_ratio = current_ratio * edge.ratio;
            const auto existing_it = unit_ratios.find(edge.target);
            if (existing_it == unit_ratios.end()) {
                unit_ratios.emplace(edge.target, candidate_ratio);
                queue.push(edge.target);
            } else if (std::abs(existing_it->second - candidate_ratio) > kRpmEpsilon) {
                return SolveResult{
                    false,
                    ErrorCode::KinematicConflict,
                    "Kinematic conflict detected at component '" + edge.target + "'",
                    {},
                    {}};
            }
        }
    }

    std::vector<ComponentId> disconnected;
    for (const auto& [id, comp] : components) {
        (void)comp;
        if (!unit_ratios.contains(id)) {
            disconnected.push_back(id);
        }
    }

    if (mode == SolveMode::Strict && !disconnected.empty()) {
        return SolveResult{
            false,
            ErrorCode::DisconnectedMechanism,
            "One or more components are not connected to the motor",
            {},
            std::move(disconnected)};
    }

    const Rpm effective_motor_rpm =
        (state == SimulationState::Running) ? normalize_zero(motor_target_rpm) : 0.0;

    std::map<ComponentId, Rpm> rpms;
    for (const auto& [id, ratio] : unit_ratios) {
        rpms.emplace(id, normalize_zero(effective_motor_rpm * ratio));
    }

    return SolveResult{true, ErrorCode::None, "", std::move(rpms), std::move(disconnected)};
}

} // namespace opensim
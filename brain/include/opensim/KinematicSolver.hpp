#pragma once

#include "opensim/ConnectionGraph.hpp"
#include "opensim/Types.hpp"

#include <map>
#include <vector>

namespace opensim {

struct SolveResult {
    bool ok = false;
    ErrorCode error = ErrorCode::None;
    std::string message;
    std::map<ComponentId, Rpm> rpms;
    std::map<ComponentId, double> ratios;
    std::vector<ComponentId> disconnected_components;
};

class KinematicSolver {
public:
    [[nodiscard]] SolveResult solve(
        const ConnectionGraph& graph,
        Rpm motor_target_rpm,
        SimulationState state,
        SolveMode mode = SolveMode::Strict) const;

    [[nodiscard]] SolveResult solve_multi(
        const ConnectionGraph& graph,
        const std::map<ComponentId, Rpm>& motor_rpms,
        Rpm default_motor_rpm,
        SimulationState state,
        SolveMode mode = SolveMode::PartialConnected) const;
};

} // namespace opensim
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
    std::vector<ComponentId> disconnected_components;
};

class KinematicSolver {
public:
    [[nodiscard]] SolveResult solve(
        const ConnectionGraph& graph,
        Rpm motor_target_rpm,
        SimulationState state,
        SolveMode mode = SolveMode::Strict) const;
};

} // namespace opensim
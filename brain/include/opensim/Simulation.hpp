#pragma once

#include "opensim/ConnectionGraph.hpp"
#include "opensim/KinematicSolver.hpp"
#include "opensim/Types.hpp"

#include <optional>
#include <vector>

namespace opensim {

class Simulation {
public:
    Simulation();

    void load_default_mvp_mechanism();

    [[nodiscard]] ConnectionGraph& graph() noexcept { return graph_; }
    [[nodiscard]] const ConnectionGraph& graph() const noexcept { return graph_; }

    void set_strict_mode(bool strict);
    [[nodiscard]] bool is_strict_mode() const noexcept { return strict_mode_; }

    OperationResult set_io_components(ComponentId input_id, ComponentId output_id);
    OperationResult set_target_rpm(Rpm rpm);

    OperationResult start();
    void stop();
    OperationResult reverse_direction();
    OperationResult recompute();

    [[nodiscard]] SimulationState state() const noexcept { return state_; }
    [[nodiscard]] bool is_running() const noexcept { return state_ == SimulationState::Running; }
    [[nodiscard]] bool is_mechanism_valid() const noexcept { return last_status_.ok; }
    [[nodiscard]] const OperationResult& status() const noexcept { return last_status_; }

    [[nodiscard]] Rpm target_rpm() const noexcept { return target_rpm_; }
    [[nodiscard]] Rpm input_rpm() const noexcept;
    [[nodiscard]] Rpm output_rpm() const noexcept;
    [[nodiscard]] std::optional<Rpm> component_rpm(const ComponentId& id) const;
    [[nodiscard]] bool is_component_connected(const ComponentId& id) const;
    [[nodiscard]] const std::vector<ComponentId>& disconnected_components() const noexcept {
        return last_solve_.disconnected_components;
    }

private:
    ConnectionGraph graph_;
    KinematicSolver solver_;
    SimulationState state_{SimulationState::Stopped};
    bool strict_mode_{true};
    Rpm target_rpm_{60.0};
    ComponentId input_component_id_;
    ComponentId output_component_id_;
    SolveResult last_solve_;
    OperationResult last_status_{OperationResult::failure(
        ErrorCode::DisconnectedMechanism, "Simulation not initialized")};
};

} // namespace opensim
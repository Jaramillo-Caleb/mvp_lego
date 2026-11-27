#include "opensim/Simulation.hpp"

#include <cmath>

namespace opensim {

Simulation::Simulation() {
    load_default_mvp_mechanism();
}

void Simulation::load_default_mvp_mechanism() {
    graph_.clear();
    motor_targets_.clear();
    state_ = SimulationState::Stopped;
    target_rpm_ = 60.0;

    graph_.add_component(Component::make_motor("motor"));
    graph_.add_component(Component::make_shaft("shaft_in"));
    graph_.add_component(Component::make_gear("gear_24", 24));
    graph_.add_component(Component::make_gear("gear_8", 8));

    graph_.connect(Connection{
        "motor", PortKind::RotationalAxis,
        "shaft_in", PortKind::RotationalAxis,
        ConnectionKind::Coaxial});

    graph_.connect(Connection{
        "shaft_in", PortKind::RotationalAxis,
        "gear_24", PortKind::RotationalAxis,
        ConnectionKind::Coaxial});

    graph_.connect(Connection{
        "gear_24", PortKind::GearTeeth,
        "gear_8", PortKind::GearTeeth,
        ConnectionKind::ExternalGearMesh});

    input_component_id_ = "gear_24";
    output_component_id_ = "gear_8";
    recompute();
}

void Simulation::set_strict_mode(bool strict) {
    strict_mode_ = strict;
    recompute();
}

OperationResult Simulation::set_io_components(ComponentId input_id, ComponentId output_id) {
    input_component_id_ = std::move(input_id);
    output_component_id_ = std::move(output_id);
    return recompute();
}

OperationResult Simulation::set_target_rpm(Rpm rpm) {
    if (!std::isfinite(rpm)) {
        return OperationResult::failure(
            ErrorCode::InvalidArgument, "Target RPM must be finite");
    }
    target_rpm_ = (rpm == 0.0) ? 0.0 : rpm;
    return recompute();
}

OperationResult Simulation::set_motor_rpm(const ComponentId& motor_id, Rpm rpm) {
    if (motor_id.empty() || !std::isfinite(rpm)) {
        return OperationResult::failure(
            ErrorCode::InvalidArgument, "Motor ID and RPM must be valid");
    }
    motor_targets_[motor_id] = (rpm == 0.0) ? 0.0 : rpm;
    return recompute();
}

void Simulation::clear_motor_rpms() {
    motor_targets_.clear();
    recompute();
}

OperationResult Simulation::start() {
    state_ = SimulationState::Running;
    const OperationResult res = recompute();
    if (!res.ok) {
        state_ = SimulationState::Stopped;
    }
    return res;
}

void Simulation::stop() {
    state_ = SimulationState::Stopped;
    recompute();
}

OperationResult Simulation::reverse_direction() {
    if (target_rpm_ != 0.0) {
        target_rpm_ = -target_rpm_;
    }
    for (auto& [id, rpm] : motor_targets_) {
        (void)id;
        if (rpm != 0.0) {
            rpm = -rpm;
        }
    }
    return recompute();
}

OperationResult Simulation::recompute() {
    if (strict_mode_) {
        bool has_gear_mesh = false;
        for (const auto& conn : graph_.connections()) {
            if (conn.kind == ConnectionKind::ExternalGearMesh) {
                has_gear_mesh = true;
                break;
            }
        }

        if (!has_gear_mesh) {
            last_solve_ = SolveResult{};
            last_status_ = OperationResult::failure(
                ErrorCode::NoGearTransmission,
                "Mechanism has no external gear transmission");
            return last_status_;
        }
    }

    const SolveMode solve_mode =
        strict_mode_ ? SolveMode::Strict : SolveMode::PartialConnected;
    last_solve_ = solver_.solve_multi(
        graph_, motor_targets_, target_rpm_, state_, solve_mode);
    if (!last_solve_.ok) {
        last_status_ = OperationResult::failure(last_solve_.error, last_solve_.message);
        return last_status_;
    }

    if (strict_mode_) {
        if (input_component_id_.empty() || !last_solve_.rpms.contains(input_component_id_) ||
            output_component_id_.empty() || !last_solve_.rpms.contains(output_component_id_)) {
            last_solve_.ok = false;
            last_solve_.rpms.clear();
            last_solve_.ratios.clear();
            last_status_ = OperationResult::failure(
                ErrorCode::UnknownComponent,
                "Input or output component is not present in solved mechanism");
            return last_status_;
        }
    }

    last_status_ = OperationResult::success();
    return last_status_;
}

Rpm Simulation::motor_rpm(const ComponentId& motor_id) const noexcept {
    const auto it = motor_targets_.find(motor_id);
    return (it == motor_targets_.end()) ? target_rpm_ : it->second;
}

Rpm Simulation::input_rpm() const noexcept {
    if (!last_status_.ok) {
        return 0.0;
    }
    const auto it = last_solve_.rpms.find(input_component_id_);
    return (it == last_solve_.rpms.end()) ? 0.0 : it->second;
}

Rpm Simulation::output_rpm() const noexcept {
    if (!last_status_.ok) {
        return 0.0;
    }
    const auto it = last_solve_.rpms.find(output_component_id_);
    return (it == last_solve_.rpms.end()) ? 0.0 : it->second;
}

std::optional<Rpm> Simulation::component_rpm(const ComponentId& id) const {
    if (!last_status_.ok) {
        return std::nullopt;
    }
    const auto it = last_solve_.rpms.find(id);
    if (it == last_solve_.rpms.end()) {
        return std::nullopt;
    }
    return it->second;
}

std::optional<double> Simulation::component_ratio(const ComponentId& id) const {
    if (!last_status_.ok) {
        return std::nullopt;
    }
    const auto it = last_solve_.ratios.find(id);
    if (it == last_solve_.ratios.end()) {
        return std::nullopt;
    }
    return it->second;
}

bool Simulation::is_component_connected(const ComponentId& id) const {
    return last_status_.ok && last_solve_.rpms.contains(id);
}

} // namespace opensim
#pragma once

#include <string>

namespace opensim {

using ComponentId = std::string;
using Rpm = double;

inline constexpr double kRpmEpsilon = 1e-9;

enum class ComponentType {
    Motor,
    Shaft,
    Gear,
    Wheel
};

enum class PortKind {
    RotationalAxis,
    GearTeeth
};

enum class ConnectionKind {
    Coaxial,
    ExternalGearMesh
};

enum class SimulationState {
    Stopped,
    Running
};

enum class SolveMode {
    Strict,
    PartialConnected
};

enum class ErrorCode {
    None = 0,
    InvalidArgument,
    DuplicateComponent,
    UnknownComponent,
    SelfConnection,
    IncompatiblePorts,
    DuplicateConnection,
    NoMotor,
    MultipleMotors,
    DisconnectedMechanism,
    NoGearTransmission,
    KinematicConflict
};

struct OperationResult {
    bool ok = true;
    ErrorCode error = ErrorCode::None;
    std::string message;

    static OperationResult success() {
        return OperationResult{true, ErrorCode::None, ""};
    }

    static OperationResult failure(ErrorCode code, std::string msg) {
        return OperationResult{false, code, std::move(msg)};
    }
};

} // namespace opensim
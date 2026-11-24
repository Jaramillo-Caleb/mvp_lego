#pragma once

#include "opensim/Types.hpp"

namespace opensim {

struct Component {
    ComponentId id;
    ComponentType type{ComponentType::Shaft};
    int teeth{0};

    [[nodiscard]] bool supports_port(PortKind port) const noexcept {
        switch (type) {
            case ComponentType::Motor:
            case ComponentType::Shaft:
            case ComponentType::Wheel:
                return port == PortKind::RotationalAxis;
            case ComponentType::Gear:
                return port == PortKind::RotationalAxis || port == PortKind::GearTeeth;
        }
        return false;
    }

    static Component make_motor(ComponentId id) {
        return Component{std::move(id), ComponentType::Motor, 0};
    }

    static Component make_shaft(ComponentId id) {
        return Component{std::move(id), ComponentType::Shaft, 0};
    }

    static Component make_gear(ComponentId id, int teeth) {
        return Component{std::move(id), ComponentType::Gear, teeth};
    }

    static Component make_wheel(ComponentId id) {
        return Component{std::move(id), ComponentType::Wheel, 0};
    }
};

} // namespace opensim
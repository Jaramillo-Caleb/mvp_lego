#pragma once

#include "opensim/Components.hpp"
#include "opensim/Types.hpp"

#include <map>
#include <vector>

namespace opensim {

struct Connection {
    ComponentId from_id;
    PortKind from_port{PortKind::RotationalAxis};
    ComponentId to_id;
    PortKind to_port{PortKind::RotationalAxis};
    ConnectionKind kind{ConnectionKind::Coaxial};
};

class ConnectionGraph {
public:
    OperationResult add_component(const Component& component);
    OperationResult connect(const Connection& connection);
    void clear();

    [[nodiscard]] bool has_component(const ComponentId& id) const;
    [[nodiscard]] const Component* find_component(const ComponentId& id) const;

    [[nodiscard]] const std::map<ComponentId, Component>& components() const noexcept {
        return components_;
    }

    [[nodiscard]] const std::vector<Connection>& connections() const noexcept {
        return connections_;
    }

private:
    std::map<ComponentId, Component> components_;
    std::vector<Connection> connections_;
};

} // namespace opensim
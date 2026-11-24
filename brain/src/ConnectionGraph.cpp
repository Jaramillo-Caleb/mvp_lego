#include "opensim/ConnectionGraph.hpp"

namespace opensim {

namespace {

bool is_same_connection(const Connection& a, const Connection& b) {
    if (a.kind != b.kind) {
        return false;
    }
    const bool same_order =
        a.from_id == b.from_id &&
        a.to_id == b.to_id &&
        a.from_port == b.from_port &&
        a.to_port == b.to_port;

    const bool reversed_order =
        a.from_id == b.to_id &&
        a.to_id == b.from_id &&
        a.from_port == b.to_port &&
        a.to_port == b.from_port;

    return same_order || reversed_order;
}

} // namespace

OperationResult ConnectionGraph::add_component(const Component& component) {
    if (component.id.empty()) {
        return OperationResult::failure(
            ErrorCode::InvalidArgument, "Component ID cannot be empty");
    }
    if (components_.contains(component.id)) {
        return OperationResult::failure(
            ErrorCode::DuplicateComponent,
            "Duplicate component ID: " + component.id);
    }
    if (component.type == ComponentType::Gear && component.teeth <= 0) {
        return OperationResult::failure(
            ErrorCode::InvalidArgument,
            "Gear '" + component.id + "' must have a positive number of teeth");
    }

    components_.emplace(component.id, component);
    return OperationResult::success();
}

OperationResult ConnectionGraph::connect(const Connection& connection) {
    if (connection.from_id.empty() || connection.to_id.empty()) {
        return OperationResult::failure(
            ErrorCode::InvalidArgument, "Connection component IDs cannot be empty");
    }
    if (connection.from_id == connection.to_id) {
        return OperationResult::failure(
            ErrorCode::SelfConnection,
            "Cannot connect component '" + connection.from_id + "' to itself");
    }

    const Component* from = find_component(connection.from_id);
    if (from == nullptr) {
        return OperationResult::failure(
            ErrorCode::UnknownComponent,
            "Unknown source component: " + connection.from_id);
    }

    const Component* to = find_component(connection.to_id);
    if (to == nullptr) {
        return OperationResult::failure(
            ErrorCode::UnknownComponent,
            "Unknown target component: " + connection.to_id);
    }

    if (!from->supports_port(connection.from_port) || !to->supports_port(connection.to_port)) {
        return OperationResult::failure(
            ErrorCode::IncompatiblePorts,
            "Component does not support the requested port kind");
    }

    if (connection.kind == ConnectionKind::Coaxial) {
        if (connection.from_port != PortKind::RotationalAxis ||
            connection.to_port != PortKind::RotationalAxis) {
            return OperationResult::failure(
                ErrorCode::IncompatiblePorts,
                "Coaxial connection requires RotationalAxis ports on both ends");
        }
    } else if (connection.kind == ConnectionKind::ExternalGearMesh) {
        if (connection.from_port != PortKind::GearTeeth ||
            connection.to_port != PortKind::GearTeeth ||
            from->type != ComponentType::Gear ||
            to->type != ComponentType::Gear) {
            return OperationResult::failure(
                ErrorCode::IncompatiblePorts,
                "ExternalGearMesh requires two Gear components connected by GearTeeth ports");
        }
    }

    for (const auto& existing : connections_) {
        if (is_same_connection(existing, connection)) {
            return OperationResult::failure(
                ErrorCode::DuplicateConnection,
                "Duplicate connection between '" + connection.from_id +
                "' and '" + connection.to_id + "'");
        }
    }

    connections_.push_back(connection);
    return OperationResult::success();
}

void ConnectionGraph::clear() {
    components_.clear();
    connections_.clear();
}

bool ConnectionGraph::has_component(const ComponentId& id) const {
    return components_.contains(id);
}

const Component* ConnectionGraph::find_component(const ComponentId& id) const {
    const auto it = components_.find(id);
    return (it == components_.end()) ? nullptr : &it->second;
}

} // namespace opensim
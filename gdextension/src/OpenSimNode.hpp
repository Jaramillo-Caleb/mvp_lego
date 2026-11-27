#pragma once

#include "opensim/Simulation.hpp"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class OpenSimNode : public Node {
    GDCLASS(OpenSimNode, Node)

public:
    OpenSimNode() = default;
    ~OpenSimNode() override = default;

    void reset_default_mechanism();

    void set_strict_mode(bool strict);
    bool is_strict_mode() const;

    void clear_mechanism();
    bool add_motor(const String& id);
    bool add_shaft(const String& id);
    bool add_gear(const String& id, int teeth);
    bool add_wheel(const String& id);
    bool connect_coaxial(const String& from_id, const String& to_id);
    bool connect_external_gears(const String& from_id, const String& to_id);
    bool set_io_components(const String& input_id, const String& output_id);

    bool set_target_rpm(double rpm);
    double get_target_rpm() const;
    bool set_motor_rpm(const String& motor_id, double rpm);
    double get_motor_rpm(const String& motor_id) const;
    void clear_motor_rpms();

    bool start();
    void stop();
    bool reverse_direction();

    bool is_running() const;
    bool is_mechanism_valid() const;

    double get_input_rpm() const;
    double get_output_rpm() const;
    double get_component_rpm(const String& id) const;
    double get_component_ratio(const String& id) const;
    bool is_component_connected(const String& id) const;
    PackedStringArray get_disconnected_components() const;

    int get_error_code() const;
    String get_status_message() const;

protected:
    static void _bind_methods();

private:
    opensim::Simulation sim_;
    opensim::OperationResult last_edit_status_{opensim::OperationResult::success()};
};

} // namespace godot
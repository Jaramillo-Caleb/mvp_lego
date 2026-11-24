#include "OpenSimNode.hpp"

#include <godot_cpp/core/class_db.hpp>

namespace godot {

namespace {

std::string to_std_string(const String& str) {
    const CharString utf8 = str.utf8();
    return std::string(utf8.get_data() ? utf8.get_data() : "");
}

String to_godot_string(const std::string& str) {
    return String::utf8(str.c_str());
}

} // namespace

void OpenSimNode::_bind_methods() {
    ClassDB::bind_method(D_METHOD("reset_default_mechanism"), &OpenSimNode::reset_default_mechanism);
    ClassDB::bind_method(D_METHOD("set_strict_mode", "strict"), &OpenSimNode::set_strict_mode);
    ClassDB::bind_method(D_METHOD("is_strict_mode"), &OpenSimNode::is_strict_mode);

    ClassDB::bind_method(D_METHOD("clear_mechanism"), &OpenSimNode::clear_mechanism);
    ClassDB::bind_method(D_METHOD("add_motor", "id"), &OpenSimNode::add_motor);
    ClassDB::bind_method(D_METHOD("add_shaft", "id"), &OpenSimNode::add_shaft);
    ClassDB::bind_method(D_METHOD("add_gear", "id", "teeth"), &OpenSimNode::add_gear);
    ClassDB::bind_method(D_METHOD("add_wheel", "id"), &OpenSimNode::add_wheel);
    ClassDB::bind_method(D_METHOD("connect_coaxial", "from_id", "to_id"), &OpenSimNode::connect_coaxial);
    ClassDB::bind_method(D_METHOD("connect_external_gears", "from_id", "to_id"), &OpenSimNode::connect_external_gears);
    ClassDB::bind_method(D_METHOD("set_io_components", "input_id", "output_id"), &OpenSimNode::set_io_components);

    ClassDB::bind_method(D_METHOD("set_target_rpm", "rpm"), &OpenSimNode::set_target_rpm);
    ClassDB::bind_method(D_METHOD("get_target_rpm"), &OpenSimNode::get_target_rpm);

    ClassDB::bind_method(D_METHOD("start"), &OpenSimNode::start);
    ClassDB::bind_method(D_METHOD("stop"), &OpenSimNode::stop);
    ClassDB::bind_method(D_METHOD("reverse_direction"), &OpenSimNode::reverse_direction);

    ClassDB::bind_method(D_METHOD("is_running"), &OpenSimNode::is_running);
    ClassDB::bind_method(D_METHOD("is_mechanism_valid"), &OpenSimNode::is_mechanism_valid);

    ClassDB::bind_method(D_METHOD("get_input_rpm"), &OpenSimNode::get_input_rpm);
    ClassDB::bind_method(D_METHOD("get_output_rpm"), &OpenSimNode::get_output_rpm);
    ClassDB::bind_method(D_METHOD("get_component_rpm", "id"), &OpenSimNode::get_component_rpm);
    ClassDB::bind_method(D_METHOD("is_component_connected", "id"), &OpenSimNode::is_component_connected);
    ClassDB::bind_method(D_METHOD("get_disconnected_components"), &OpenSimNode::get_disconnected_components);

    ClassDB::bind_method(D_METHOD("get_error_code"), &OpenSimNode::get_error_code);
    ClassDB::bind_method(D_METHOD("get_status_message"), &OpenSimNode::get_status_message);
}

void OpenSimNode::reset_default_mechanism() {
    sim_.load_default_mvp_mechanism();
    last_edit_status_ = sim_.status();
}

void OpenSimNode::set_strict_mode(bool strict) {
    sim_.set_strict_mode(strict);
    last_edit_status_ = sim_.status();
}

bool OpenSimNode::is_strict_mode() const {
    return sim_.is_strict_mode();
}

void OpenSimNode::clear_mechanism() {
    sim_.stop();
    sim_.graph().clear();
    last_edit_status_ = sim_.recompute();
}

bool OpenSimNode::add_motor(const String& id) {
    last_edit_status_ = sim_.graph().add_component(
        opensim::Component::make_motor(to_std_string(id)));
    if (last_edit_status_.ok) {
        sim_.recompute();
    }
    return last_edit_status_.ok;
}

bool OpenSimNode::add_shaft(const String& id) {
    last_edit_status_ = sim_.graph().add_component(
        opensim::Component::make_shaft(to_std_string(id)));
    if (last_edit_status_.ok) {
        sim_.recompute();
    }
    return last_edit_status_.ok;
}

bool OpenSimNode::add_gear(const String& id, int teeth) {
    last_edit_status_ = sim_.graph().add_component(
        opensim::Component::make_gear(to_std_string(id), teeth));
    if (last_edit_status_.ok) {
        sim_.recompute();
    }
    return last_edit_status_.ok;
}

bool OpenSimNode::add_wheel(const String& id) {
    last_edit_status_ = sim_.graph().add_component(
        opensim::Component::make_wheel(to_std_string(id)));
    if (last_edit_status_.ok) {
        sim_.recompute();
    }
    return last_edit_status_.ok;
}

bool OpenSimNode::connect_coaxial(const String& from_id, const String& to_id) {
    last_edit_status_ = sim_.graph().connect(opensim::Connection{
        to_std_string(from_id),
        opensim::PortKind::RotationalAxis,
        to_std_string(to_id),
        opensim::PortKind::RotationalAxis,
        opensim::ConnectionKind::Coaxial});
    if (last_edit_status_.ok) {
        sim_.recompute();
    }
    return last_edit_status_.ok;
}

bool OpenSimNode::connect_external_gears(const String& from_id, const String& to_id) {
    last_edit_status_ = sim_.graph().connect(opensim::Connection{
        to_std_string(from_id),
        opensim::PortKind::GearTeeth,
        to_std_string(to_id),
        opensim::PortKind::GearTeeth,
        opensim::ConnectionKind::ExternalGearMesh});
    if (last_edit_status_.ok) {
        sim_.recompute();
    }
    return last_edit_status_.ok;
}

bool OpenSimNode::set_io_components(const String& input_id, const String& output_id) {
    last_edit_status_ = sim_.set_io_components(
        to_std_string(input_id), to_std_string(output_id));
    return last_edit_status_.ok;
}

bool OpenSimNode::set_target_rpm(double rpm) {
    last_edit_status_ = sim_.set_target_rpm(rpm);
    return last_edit_status_.ok;
}

double OpenSimNode::get_target_rpm() const {
    return sim_.target_rpm();
}

bool OpenSimNode::start() {
    last_edit_status_ = sim_.start();
    return last_edit_status_.ok;
}

void OpenSimNode::stop() {
    sim_.stop();
    last_edit_status_ = sim_.status();
}

bool OpenSimNode::reverse_direction() {
    last_edit_status_ = sim_.reverse_direction();
    return last_edit_status_.ok;
}

bool OpenSimNode::is_running() const {
    return sim_.is_running();
}

bool OpenSimNode::is_mechanism_valid() const {
    return sim_.is_mechanism_valid();
}

double OpenSimNode::get_input_rpm() const {
    return sim_.input_rpm();
}

double OpenSimNode::get_output_rpm() const {
    return sim_.output_rpm();
}

double OpenSimNode::get_component_rpm(const String& id) const {
    return sim_.component_rpm(to_std_string(id)).value_or(0.0);
}

bool OpenSimNode::is_component_connected(const String& id) const {
    return sim_.is_component_connected(to_std_string(id));
}

PackedStringArray OpenSimNode::get_disconnected_components() const {
    PackedStringArray arr;
    for (const auto& id : sim_.disconnected_components()) {
        arr.push_back(to_godot_string(id));
    }
    return arr;
}

int OpenSimNode::get_error_code() const {
    if (!last_edit_status_.ok) {
        return static_cast<int>(last_edit_status_.error);
    }
    return static_cast<int>(sim_.status().error);
}

String OpenSimNode::get_status_message() const {
    if (!last_edit_status_.ok) {
        return to_godot_string(last_edit_status_.message);
    }
    if (!sim_.status().ok) {
        return to_godot_string(sim_.status().message);
    }
    return String("OK");
}

} // namespace godot
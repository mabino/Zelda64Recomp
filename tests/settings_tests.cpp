#include <array>
#include <iostream>
#include <string>

#include "recomp_controls.hpp"
#include "zelda_app_preferences.hpp"

namespace {
    int failures = 0;

    void expect(bool condition, const char* message) {
        if (!condition) {
            std::cerr << "FAIL: " << message << '\n';
            failures++;
        }
    }

    bool same(const recomp::InputField& left, const recomp::InputField& right) {
        return left.input_type == right.input_type && left.input_id == right.input_id;
    }

    void test_binding_scan_target() {
        recomp::controls::BindingScanTarget target;
        expect(!target.active(), "scan target starts inactive");
        constexpr size_t input_count = static_cast<size_t>(recomp::GameInput::COUNT);
        expect(target.begin(recomp::GameInput::A, 1, recomp::InputDevice::Controller, input_count),
               "valid controller binding scan starts");
        expect(target.active(), "started scan is active");

        const auto captured = target.take();
        expect(captured.has_value(), "completed scan yields its target");
        expect(captured && captured->input == recomp::GameInput::A, "scan keeps selected action");
        expect(captured && captured->binding_index == 1, "scan keeps selected binding slot");
        expect(captured && captured->device == recomp::InputDevice::Controller, "scan keeps selected device");
        expect(!target.active(), "taking scan target clears pending state");
        expect(!target.take().has_value(), "scan target cannot be consumed twice");

        expect(!target.begin(recomp::GameInput::A, recomp::bindings_per_input, recomp::InputDevice::Keyboard,
                             input_count), "out-of-range binding slot is rejected");
        expect(!target.active(), "rejected scan leaves no active target");
        expect(!target.begin(recomp::GameInput::COUNT, 0, recomp::InputDevice::Keyboard,
                             input_count), "out-of-range input is rejected");
        expect(!target.begin(recomp::GameInput::A, 0, recomp::InputDevice::COUNT,
                             input_count), "invalid input device is rejected");

        expect(target.begin(recomp::GameInput::B, 0, recomp::InputDevice::Keyboard,
                            input_count), "keyboard scan starts");
        target.reset();
        expect(!target.active(), "cancelling a scan clears its target");
    }

    void test_complete_mapping_assignment_and_reset() {
        using Bindings = std::array<std::array<recomp::InputField, recomp::bindings_per_input>, 2>;
        Bindings mappings{};
        const recomp::InputField stale{9, 99};
        mappings[0][1] = stale;

        recomp::controls::assign_mapping_complete(
            recomp::InputDevice::Keyboard, recomp::GameInput::A,
            std::vector<recomp::InputField>{{1, 10}},
            [&mappings](recomp::GameInput input, size_t slot, recomp::InputDevice, recomp::InputField value) {
                mappings[static_cast<size_t>(input)][slot] = value;
            });
        expect(same(mappings[0][0], recomp::InputField{1, 10}), "mapping assignment sets first binding");
        expect(same(mappings[0][1], recomp::InputField{}), "complete assignment clears omitted binding slots");

        recomp::DefaultN64Mappings defaults{};
        defaults.a = {{2, 20}, {2, 21}};
        defaults.b = {{3, 30}};
        mappings[1][1] = stale;
        recomp::controls::reset_device_bindings(
            recomp::InputDevice::Controller, defaults, 2,
            [&mappings](recomp::GameInput input, size_t slot, recomp::InputDevice, recomp::InputField value) {
                mappings[static_cast<size_t>(input)][slot] = value;
            });
        expect(same(mappings[0][0], recomp::InputField{2, 20}), "reset applies first default binding");
        expect(same(mappings[0][1], recomp::InputField{2, 21}), "reset applies secondary default binding");
        expect(same(mappings[1][0], recomp::InputField{3, 30}), "reset applies defaults for later inputs");
        expect(same(mappings[1][1], recomp::InputField{}), "reset clears slots absent from defaults");
    }

    void test_control_mapping_json_round_trip() {
        using DeviceBindings = std::array<std::array<recomp::InputField, recomp::bindings_per_input>, 2>;
        DeviceBindings keyboard{};
        keyboard[0] = {recomp::InputField{1, 4}, recomp::InputField{1, 7}};
        keyboard[1] = {recomp::InputField{1, 8}, recomp::InputField{}};
        DeviceBindings controller{};
        controller[0] = {recomp::InputField{2, 11}, recomp::InputField{}};
        controller[1] = {recomp::InputField{2, 12}, recomp::InputField{2, 13}};
        auto name = [](recomp::GameInput input) -> std::string {
            return input == recomp::GameInput::A ? "A" : "B";
        };
        auto get_binding = [&keyboard, &controller](recomp::GameInput input, size_t slot, recomp::InputDevice device)
            -> const recomp::InputField& {
            auto& values = device == recomp::InputDevice::Keyboard ? keyboard : controller;
            return values[static_cast<size_t>(input)][slot];
        };

        nlohmann::json config;
        config["keyboard"] = recomp::controls::serialize_device_bindings(
            recomp::InputDevice::Keyboard, 2, name, get_binding);
        config["controller"] = recomp::controls::serialize_device_bindings(
            recomp::InputDevice::Controller, 2, name, get_binding);

        DeviceBindings loaded_keyboard{};
        DeviceBindings loaded_controller{};
        auto set_binding = [&loaded_keyboard, &loaded_controller](recomp::GameInput input, size_t slot,
                                                                  recomp::InputDevice device, recomp::InputField value) {
            auto& values = device == recomp::InputDevice::Keyboard ? loaded_keyboard : loaded_controller;
            values[static_cast<size_t>(input)][slot] = value;
        };
        recomp::DefaultN64Mappings defaults{};
        defaults.a = {{7, 70}};
        defaults.b = {{8, 80}, {8, 81}};
        auto get_defaults = [&defaults](recomp::GameInput input) -> const std::vector<recomp::InputField>& {
            return recomp::get_default_mapping_for_input(defaults, input);
        };

        expect(recomp::controls::load_device_bindings(config, "keyboard", recomp::InputDevice::Keyboard,
                   2, name, get_defaults, set_binding), "keyboard bindings load from saved config");
        expect(recomp::controls::load_device_bindings(config, "controller", recomp::InputDevice::Controller,
                   2, name, get_defaults, set_binding), "controller bindings load from saved config");
        for (size_t input = 0; input < 2; input++) {
            for (size_t slot = 0; slot < recomp::bindings_per_input; slot++) {
                expect(same(loaded_keyboard[input][slot], keyboard[input][slot]), "keyboard binding round trips");
                expect(same(loaded_controller[input][slot], controller[input][slot]), "controller binding round trips");
            }
        }

        expect(!recomp::controls::load_device_bindings(config, "missing", recomp::InputDevice::Keyboard,
                   2, name, get_defaults, set_binding), "missing device section is reported to caller");

        config["keyboard"]["A"] = nlohmann::json::array({recomp::InputField{5, 50}});
        config["keyboard"].erase("B");
        expect(recomp::controls::load_device_bindings(config, "keyboard", recomp::InputDevice::Keyboard,
                   2, name, get_defaults, set_binding), "partial keyboard config loads");
        expect(same(loaded_keyboard[0][0], recomp::InputField{5, 50}), "saved partial action overrides defaults");
        expect(same(loaded_keyboard[0][1], recomp::InputField{}), "partial saved action clears missing slot");
        expect(same(loaded_keyboard[1][0], recomp::InputField{8, 80}), "missing action restores its default");
        expect(same(loaded_keyboard[1][1], recomp::InputField{8, 81}), "missing action restores secondary default");
    }

    void test_quit_confirmation_preference() {
        expect(zelda64::load_confirm_before_quit(nlohmann::json::object()),
               "missing quit preference defaults to confirmation enabled");
        expect(zelda64::quit_action(zelda64::load_confirm_before_quit(nlohmann::json::object())) ==
                   zelda64::QuitAction::ShowConfirmation,
               "default quit preference selects confirmation");

        nlohmann::json settings;
        zelda64::save_confirm_before_quit(settings, false);
        expect(settings["confirm_before_quit"] == false, "disabled preference is written to config");
        expect(!zelda64::load_confirm_before_quit(settings), "disabled preference reloads from config");
        expect(zelda64::quit_action(zelda64::load_confirm_before_quit(settings)) ==
                   zelda64::QuitAction::ExitImmediately,
               "disabled preference selects immediate exit");

        zelda64::save_confirm_before_quit(settings, true);
        expect(zelda64::load_confirm_before_quit(settings), "enabled preference reloads from config");
    }
}

int main() {
    test_binding_scan_target();
    test_complete_mapping_assignment_and_reset();
    test_control_mapping_json_round_trip();
    test_quit_confirmation_preference();
    if (failures != 0) {
        std::cerr << failures << " settings test(s) failed\n";
        return 1;
    }
    std::cout << "All settings tests passed\n";
    return 0;
}

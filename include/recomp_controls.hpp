#ifndef __RECOMP_CONTROLS_HPP__
#define __RECOMP_CONTROLS_HPP__

#include <algorithm>
#include <optional>
#include <string>

#include "recomp_input.h"

namespace recomp {
    namespace controls {
        struct BindingScanTarget {
            GameInput input = GameInput::COUNT;
            size_t binding_index = bindings_per_input;
            InputDevice device = InputDevice::COUNT;

            bool active() const {
                return input != GameInput::COUNT && binding_index < bindings_per_input && device != InputDevice::COUNT;
            }

            bool begin(GameInput new_input, size_t new_binding_index, InputDevice new_device, size_t input_count) {
                reset();
                if (static_cast<size_t>(new_input) >= input_count ||
                    new_binding_index >= bindings_per_input ||
                    (new_device != InputDevice::Keyboard && new_device != InputDevice::Controller)) {
                    return false;
                }

                input = new_input;
                binding_index = new_binding_index;
                device = new_device;
                return true;
            }

            std::optional<BindingScanTarget> take() {
                if (!active()) {
                    reset();
                    return std::nullopt;
                }

                BindingScanTarget target = *this;
                reset();
                return target;
            }

            void reset() {
                input = GameInput::COUNT;
                binding_index = bindings_per_input;
                device = InputDevice::COUNT;
            }
        };

        template <typename Setter>
        void assign_mapping_complete(InputDevice device, GameInput input, const std::vector<InputField>& values, Setter&& setter) {
            for (size_t binding_index = 0; binding_index < bindings_per_input; binding_index++) {
                const InputField value = binding_index < values.size() ? values[binding_index] : InputField{};
                setter(input, binding_index, device, value);
            }
        }

        template <typename Setter>
        void reset_device_bindings(InputDevice device, const DefaultN64Mappings& defaults, size_t input_count, Setter&& setter) {
            for (size_t i = 0; i < input_count; i++) {
                const GameInput input = static_cast<GameInput>(i);
                assign_mapping_complete(device, input, get_default_mapping_for_input(defaults, input), setter);
            }
        }

        template <typename NameGetter, typename BindingGetter>
        nlohmann::json serialize_device_bindings(InputDevice device, size_t input_count, NameGetter&& get_name, BindingGetter&& get_binding) {
            nlohmann::json mappings = nlohmann::json::object();
            for (size_t i = 0; i < input_count; i++) {
                const GameInput input = static_cast<GameInput>(i);
                nlohmann::json bindings = nlohmann::json::array();
                for (size_t slot = 0; slot < bindings_per_input; slot++) {
                    bindings.push_back(get_binding(input, slot, device));
                }
                mappings[get_name(input)] = std::move(bindings);
            }
            return mappings;
        }

        template <typename NameGetter, typename DefaultGetter, typename Setter>
        bool load_device_bindings(const nlohmann::json& config, const std::string& device_name, InputDevice device, size_t input_count,
                                  NameGetter&& get_name, DefaultGetter&& get_defaults, Setter&& setter) {
            const auto device_it = config.find(device_name);
            if (device_it == config.end()) {
                return false;
            }

            for (size_t i = 0; i < input_count; i++) {
                const GameInput input = static_cast<GameInput>(i);
                const auto input_it = device_it->find(get_name(input));
                if (input_it == device_it->end() || !input_it->is_array()) {
                    assign_mapping_complete(device, input, get_defaults(input), setter);
                    continue;
                }

                for (size_t slot = 0; slot < bindings_per_input; slot++) {
                    InputField value{};
                    if (slot < input_it->size()) {
                        input_it->at(slot).get_to(value);
                    }
                    setter(input, slot, device, value);
                }
            }
            return true;
        }
    }

    inline void to_json(nlohmann::json& json, const InputField& field) {
        json = nlohmann::json{{"input_type", field.input_type}, {"input_id", field.input_id}};
    }

    inline void from_json(const nlohmann::json& json, InputField& field) {
        json.at("input_type").get_to(field.input_type);
        json.at("input_id").get_to(field.input_id);
    }
}

#endif

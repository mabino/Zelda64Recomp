#include "zelda_config.h"
#include "recomp_input.h"
#include "recomp_controls.hpp"
#include "zelda_app_preferences.hpp"
#include "zelda_sound.h"
#include "zelda_render.h"
#include "zelda_support.h"
#include "ultramodern/config.hpp"
#include "librecomp/files.hpp"
#include <filesystem>
#include <fstream>
#include <iomanip>

#if defined(_WIN32)
#include <Shlobj.h>
#elif defined(__linux__)
#include <unistd.h>
#include <pwd.h>
#elif defined(__APPLE__)
#include "apple/rt64_apple.h"
#endif

constexpr std::u8string_view general_filename = u8"general.json";
constexpr std::u8string_view graphics_filename = u8"graphics.json";
constexpr std::u8string_view controls_filename = u8"controls.json";
constexpr std::u8string_view sound_filename = u8"sound.json";

constexpr auto res_default            = ultramodern::renderer::Resolution::Auto;
constexpr auto hr_default             = ultramodern::renderer::HUDRatioMode::Clamp16x9;
constexpr auto api_default            = ultramodern::renderer::GraphicsApi::Auto;
constexpr auto ar_default             = ultramodern::renderer::AspectRatio::Expand;
constexpr auto msaa_default           = ultramodern::renderer::Antialiasing::MSAA2X;
constexpr auto rr_default             = ultramodern::renderer::RefreshRate::Display;
constexpr auto hpfb_default           = ultramodern::renderer::HighPrecisionFramebuffer::Auto;
constexpr int ds_default              = 1;
constexpr int rr_manual_default       = 60;
constexpr bool developer_mode_default = false;

static bool is_steam_deck = false;
static bool confirm_before_quit = zelda64::confirm_before_quit_default;

ultramodern::renderer::WindowMode wm_default() {
    return is_steam_deck ? ultramodern::renderer::WindowMode::Fullscreen : ultramodern::renderer::WindowMode::Windowed;
}

#ifdef __gnu_linux__
void detect_steam_deck() {
    // Check if the board vendor is Valve.
    std::ifstream board_vendor_file("/sys/devices/virtual/dmi/id/board_vendor");
    std::string line;
    if (std::getline(board_vendor_file, line).good() && line == "Valve") {
        is_steam_deck = true;
        return;
    }

    // Check if the SteamDeck variable is set to 1.
    const char* steam_deck_env = getenv("SteamDeck");
    if (steam_deck_env != nullptr && std::string{steam_deck_env} == "1") {
        is_steam_deck = true;
        return;
    }

    is_steam_deck = false;
    return;
}
#else
void detect_steam_deck() { is_steam_deck = false; }
#endif

template <typename T>
T from_or_default(const json& j, const std::string& key, T default_value) {
    T ret;
    auto find_it = j.find(key);
    if (find_it != j.end()) {
        find_it->get_to(ret);
    }
    else {
        ret = default_value;
    }

    return ret;
}

template <typename T>
void call_if_key_exists(void (*func)(T), const json& j, const std::string& key) {
    auto find_it = j.find(key);
    if (find_it != j.end()) {
        T val;
        find_it->get_to(val);
        func(val);
    }
}

namespace ultramodern {
    void to_json(json& j, const renderer::GraphicsConfig& config) {
        j = json{
            {"res_option",      config.res_option},
            {"wm_option",       config.wm_option},
            {"hr_option",       config.hr_option},
            {"api_option",      config.api_option},
            {"ds_option",       config.ds_option},
            {"ar_option",       config.ar_option},
            {"msaa_option",     config.msaa_option},
            {"rr_option",       config.rr_option},
            {"hpfb_option",     config.hpfb_option},
            {"rr_manual_value", config.rr_manual_value},
            {"developer_mode",  config.developer_mode},
        };
    }

    void from_json(const json& j, renderer::GraphicsConfig& config) {
        config.res_option       = from_or_default(j, "res_option",      res_default);
        config.wm_option        = from_or_default(j, "wm_option",       wm_default());
        config.hr_option        = from_or_default(j, "hr_option",       hr_default);
        config.api_option       = from_or_default(j, "api_option",      api_default);
        config.ds_option        = from_or_default(j, "ds_option",       ds_default);
        config.ar_option        = from_or_default(j, "ar_option",       ar_default);
        config.msaa_option      = from_or_default(j, "msaa_option",     msaa_default);
        config.rr_option        = from_or_default(j, "rr_option",       rr_default);
        config.hpfb_option      = from_or_default(j, "hpfb_option",     hpfb_default);
        config.rr_manual_value  = from_or_default(j, "rr_manual_value", rr_manual_default);
        config.developer_mode   = from_or_default(j, "developer_mode",  developer_mode_default);
    }
}

std::filesystem::path zelda64::get_app_folder_path() {
   // directly check for portable.txt (windows and native linux binary)
   if (std::filesystem::exists("portable.txt")) {
       return std::filesystem::current_path();
   }

#if defined(__APPLE__)
   // Check for portable file in the directory containing the app bundle.
   const auto app_bundle_path = zelda64::get_bundle_directory().parent_path();
   if (std::filesystem::exists(app_bundle_path / "portable.txt")) {
       return app_bundle_path;
   }
#endif

   std::filesystem::path recomp_dir{};

#if defined(_WIN32)
   // Deduce local app data path.
   PWSTR known_path = NULL;
   HRESULT result = SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, NULL, &known_path);
   if (result == S_OK) {
       recomp_dir = std::filesystem::path{known_path} / zelda64::program_id;
   }

   CoTaskMemFree(known_path);
#elif defined(__linux__) || defined(__APPLE__)
   // check for APP_FOLDER_PATH env var
   if (getenv("APP_FOLDER_PATH") != nullptr) {
       return std::filesystem::path{getenv("APP_FOLDER_PATH")};
   }

#if defined(__APPLE__)
   const auto supportdir = zelda64::get_application_support_directory();
   if (supportdir) {
       return *supportdir / zelda64::program_id;
   }
#endif

   const char *homedir;

   if ((homedir = getenv("HOME")) == nullptr) {
    #if defined(__linux__)
       homedir = getpwuid(getuid())->pw_dir;
    #elif defined(__APPLE__)
        homedir = GetHomeDirectory();
    #endif
   }

   if (homedir != nullptr) {
       recomp_dir = std::filesystem::path{homedir} / (std::u8string{u8".config/"} + std::u8string{zelda64::program_id});
   }
#endif

    return recomp_dir;
}

bool read_json(std::ifstream input_file, nlohmann::json& json_out) {
    if (!input_file.good()) {
        return false;
    }

    try {
        input_file >> json_out;
    }
    catch (nlohmann::json::parse_error&) {
        return false;
    }
    return true;
}

bool read_json_with_backups(const std::filesystem::path& path, nlohmann::json& json_out) {
    // Try reading and parsing the base file.
    if (read_json(std::ifstream{path}, json_out)) {
        return true;
    }

    // Try reading and parsing the backup file.
    if (read_json(recomp::open_input_backup_file(path), json_out)) {
        return true;
    }

    // Both reads failed.
    return false;
}

bool save_json_with_backups(const std::filesystem::path& path, const nlohmann::json& json_data) {
    {
        std::ofstream output_file = recomp::open_output_file_with_backup(path);
        if (!output_file.good()) {
            return false;
        }

        output_file << std::setw(4) << json_data;
    }
    return recomp::finalize_output_file_with_backup(path);
}

bool save_general_config(const std::filesystem::path& path) {
    nlohmann::json config_json{};

    zelda64::to_json(config_json["targeting_mode"], zelda64::get_targeting_mode());
    recomp::to_json(config_json["background_input_mode"], recomp::get_background_input_mode());
    config_json["rumble_strength"] = recomp::get_rumble_strength();
    config_json["gyro_sensitivity"] = recomp::get_gyro_sensitivity();
    config_json["mouse_sensitivity"] = recomp::get_mouse_sensitivity();
    config_json["joystick_deadzone"] = recomp::get_joystick_deadzone();
    config_json["autosave_mode"] = zelda64::get_autosave_mode();
    config_json["camera_invert_mode"] = zelda64::get_camera_invert_mode();
    config_json["analog_cam_mode"] = zelda64::get_analog_cam_mode();
    config_json["analog_camera_invert_mode"] = zelda64::get_analog_camera_invert_mode();
    config_json["debug_mode"] = zelda64::get_debug_mode_enabled();
    zelda64::save_confirm_before_quit(config_json, zelda64::get_confirm_before_quit());

    return save_json_with_backups(path, config_json);
}

void set_general_settings_from_json(const nlohmann::json& config_json) {
    zelda64::set_targeting_mode(from_or_default(config_json, "targeting_mode", zelda64::TargetingMode::Switch));
    recomp::set_background_input_mode(from_or_default(config_json, "background_input_mode", recomp::BackgroundInputMode::On));
    recomp::set_rumble_strength(from_or_default(config_json, "rumble_strength", 25));
    recomp::set_gyro_sensitivity(from_or_default(config_json, "gyro_sensitivity", 50));
    recomp::set_mouse_sensitivity(from_or_default(config_json, "mouse_sensitivity", is_steam_deck ? 50 : 0));
    recomp::set_joystick_deadzone(from_or_default(config_json, "joystick_deadzone", 5));
    zelda64::set_autosave_mode(from_or_default(config_json, "autosave_mode", zelda64::AutosaveMode::On));
    zelda64::set_camera_invert_mode(from_or_default(config_json, "camera_invert_mode", zelda64::CameraInvertMode::InvertY));
    zelda64::set_analog_cam_mode(from_or_default(config_json, "analog_cam_mode", zelda64::AnalogCamMode::Off));
    zelda64::set_analog_camera_invert_mode(from_or_default(config_json, "analog_camera_invert_mode", zelda64::CameraInvertMode::InvertNone));
    zelda64::set_debug_mode_enabled(from_or_default(config_json, "debug_mode", false));
    zelda64::set_confirm_before_quit(zelda64::load_confirm_before_quit(config_json));
}

bool zelda64::get_confirm_before_quit() {
    return confirm_before_quit;
}

void zelda64::set_confirm_before_quit(bool enabled) {
    confirm_before_quit = enabled;
}

bool load_general_config(const std::filesystem::path& path) {
    nlohmann::json config_json{};
    if (!read_json_with_backups(path, config_json)) {
        return false;
    }

    set_general_settings_from_json(config_json);
    return true;
}

// same as assign_mapping, except will clear unassigned bindings if not in value
void assign_mapping_complete(recomp::InputDevice device, recomp::GameInput input, const std::vector<recomp::InputField>& value) {
    recomp::controls::assign_mapping_complete(device, input, value,
        [](recomp::GameInput target, size_t slot, recomp::InputDevice target_device, recomp::InputField field) {
            recomp::set_input_binding(target, slot, target_device, field);
        });
};

void assign_all_mappings(recomp::InputDevice device, const recomp::DefaultN64Mappings& values) {
    recomp::controls::reset_device_bindings(device, values, recomp::get_num_inputs(),
        [](recomp::GameInput input, size_t slot, recomp::InputDevice target_device, recomp::InputField field) {
            recomp::set_input_binding(input, slot, target_device, field);
        });
};

void zelda64::reset_input_bindings() {
    assign_all_mappings(recomp::InputDevice::Keyboard, recomp::default_n64_keyboard_mappings);
    assign_all_mappings(recomp::InputDevice::Controller, recomp::default_n64_controller_mappings);
}

void zelda64::reset_cont_input_bindings() {
    assign_all_mappings(recomp::InputDevice::Controller, recomp::default_n64_controller_mappings);
}

void zelda64::reset_kb_input_bindings() {
    assign_all_mappings(recomp::InputDevice::Keyboard, recomp::default_n64_keyboard_mappings);
}

void zelda64::reset_single_input_binding(recomp::InputDevice device, recomp::GameInput input) {
    assign_mapping_complete(
        device,
        input,
        recomp::get_default_mapping_for_input(
            device == recomp::InputDevice::Keyboard ?
                recomp::default_n64_keyboard_mappings :
                recomp::default_n64_controller_mappings,
            input
        )
    );
}

void reset_graphics_options() {
    ultramodern::renderer::GraphicsConfig new_config{};
    new_config.res_option = res_default;
    new_config.wm_option = wm_default();
    new_config.hr_option = hr_default;
    new_config.ds_option = ds_default;
    new_config.ar_option = ar_default;
    new_config.msaa_option = msaa_default;
    new_config.rr_option = rr_default;
    new_config.hpfb_option = hpfb_default;
    new_config.rr_manual_value = rr_manual_default;
    new_config.developer_mode = developer_mode_default;
    ultramodern::renderer::set_graphics_config(new_config);
}

bool save_graphics_config(const std::filesystem::path& path) {
    nlohmann::json config_json{};
    ultramodern::to_json(config_json, ultramodern::renderer::get_graphics_config());
    return save_json_with_backups(path, config_json);
}

bool load_graphics_config(const std::filesystem::path& path) {
    nlohmann::json config_json{};
    if (!read_json_with_backups(path, config_json)) {
        return false;
    }

    ultramodern::renderer::GraphicsConfig new_config{};
    ultramodern::from_json(config_json, new_config);
    ultramodern::renderer::set_graphics_config(new_config);
    return true;
}

bool save_controls_config(const std::filesystem::path& path) {
    nlohmann::json config_json{};
    config_json["keyboard"] = recomp::controls::serialize_device_bindings(
        recomp::InputDevice::Keyboard, recomp::get_num_inputs(),
        [](recomp::GameInput input) -> const std::string& { return recomp::get_input_enum_name(input); },
        [](recomp::GameInput input, size_t slot, recomp::InputDevice device) -> const recomp::InputField& {
            return recomp::get_input_binding(input, slot, device);
        });
    config_json["controller"] = recomp::controls::serialize_device_bindings(
        recomp::InputDevice::Controller, recomp::get_num_inputs(),
        [](recomp::GameInput input) -> const std::string& { return recomp::get_input_enum_name(input); },
        [](recomp::GameInput input, size_t slot, recomp::InputDevice device) -> const recomp::InputField& {
            return recomp::get_input_binding(input, slot, device);
        });

    return save_json_with_backups(path, config_json);
}

bool load_input_device_from_json(const nlohmann::json& config_json, recomp::InputDevice device, const std::string& key) {
    const recomp::DefaultN64Mappings& defaults = device == recomp::InputDevice::Keyboard ?
        recomp::default_n64_keyboard_mappings : recomp::default_n64_controller_mappings;
    return recomp::controls::load_device_bindings(
        config_json, key, device, recomp::get_num_inputs(),
        [](recomp::GameInput input) -> const std::string& { return recomp::get_input_enum_name(input); },
        [&defaults](recomp::GameInput input) -> const std::vector<recomp::InputField>& {
            return recomp::get_default_mapping_for_input(defaults, input);
        },
        [](recomp::GameInput input, size_t slot, recomp::InputDevice target_device, recomp::InputField value) {
            recomp::set_input_binding(input, slot, target_device, value);
        });
}

bool load_controls_config(const std::filesystem::path& path) {
    nlohmann::json config_json{};
    if (!read_json_with_backups(path, config_json)) {
        return false;
    }

    if (!load_input_device_from_json(config_json, recomp::InputDevice::Keyboard, "keyboard")) {
        assign_all_mappings(recomp::InputDevice::Keyboard, recomp::default_n64_keyboard_mappings);
    }

    if (!load_input_device_from_json(config_json, recomp::InputDevice::Controller, "controller")) {
        assign_all_mappings(recomp::InputDevice::Controller, recomp::default_n64_controller_mappings);
    }
    return true;
}

bool save_sound_config(const std::filesystem::path& path) {
    nlohmann::json config_json{};

    config_json["main_volume"] = zelda64::get_main_volume();
    config_json["bgm_volume"] = zelda64::get_bgm_volume();
    config_json["low_health_beeps"] = zelda64::get_low_health_beeps_enabled();

    return save_json_with_backups(path, config_json);
}

bool load_sound_config(const std::filesystem::path& path) {
    nlohmann::json config_json{};
    if (!read_json_with_backups(path, config_json)) {
        return false;
    }

    zelda64::reset_sound_settings();
    call_if_key_exists(zelda64::set_main_volume, config_json, "main_volume");
    call_if_key_exists(zelda64::set_bgm_volume, config_json, "bgm_volume");
    call_if_key_exists(zelda64::set_low_health_beeps_enabled, config_json, "low_health_beeps");
    return true;
}

void zelda64::load_config() {
    detect_steam_deck();

    std::filesystem::path recomp_dir = zelda64::get_app_folder_path();
    std::filesystem::path general_path = recomp_dir / general_filename;
    std::filesystem::path graphics_path = recomp_dir / graphics_filename;
    std::filesystem::path controls_path = recomp_dir / controls_filename;
    std::filesystem::path sound_path = recomp_dir / sound_filename;

    if (!recomp_dir.empty()) {
        std::filesystem::create_directories(recomp_dir);
    }

    // TODO error handling for failing to save config files after resetting them.

    if (!load_general_config(general_path)) {
        // Set the general settings from an empty json to use defaults.
        set_general_settings_from_json({});
        save_general_config(general_path);
    }

    if (!load_graphics_config(graphics_path)) {
        reset_graphics_options();
        save_graphics_config(graphics_path);
    }

    if (!load_controls_config(controls_path)) {
        zelda64::reset_input_bindings();
        save_controls_config(controls_path);
    }

    if (!load_sound_config(sound_path)) {
        zelda64::reset_sound_settings();
        save_sound_config(sound_path);
    }
}

void zelda64::save_config() {
    std::filesystem::path recomp_dir = zelda64::get_app_folder_path();

    if (recomp_dir.empty()) {
        return;
    }

    std::filesystem::create_directories(recomp_dir);

    // TODO error handling for failing to save config files.

    save_general_config(recomp_dir / general_filename);
    save_graphics_config(recomp_dir / graphics_filename);
    save_controls_config(recomp_dir / controls_filename);
    save_sound_config(recomp_dir / sound_filename);
}

void zelda64::reset_general_and_sound_settings() {
    const bool confirm_quit = zelda64::get_confirm_before_quit();
    set_general_settings_from_json({});
    zelda64::set_confirm_before_quit(confirm_quit);
    zelda64::reset_sound_settings();
    zelda64::save_config();
}

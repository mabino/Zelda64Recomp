#ifndef ZELDA64_APP_PREFERENCES_HPP
#define ZELDA64_APP_PREFERENCES_HPP

#include "json/json.hpp"

namespace zelda64 {
    inline constexpr bool confirm_before_quit_default = true;

    enum class QuitAction {
        ShowConfirmation,
        ExitImmediately,
    };

    inline bool load_confirm_before_quit(const nlohmann::json& settings) {
        const auto it = settings.find("confirm_before_quit");
        return it == settings.end() ? confirm_before_quit_default : it->get<bool>();
    }

    inline void save_confirm_before_quit(nlohmann::json& settings, bool enabled) {
        settings["confirm_before_quit"] = enabled;
    }

    inline QuitAction quit_action(bool confirm_before_quit) {
        return confirm_before_quit ? QuitAction::ShowConfirmation : QuitAction::ExitImmediately;
    }
}

#endif

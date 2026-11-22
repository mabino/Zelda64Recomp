#import <AppKit/AppKit.h>

#include <cmath>
#include <atomic>
#include <SDL.h>
#include "macos_settings.h"
#include "recomp_ui.h"
#include "recomp_input.h"
#include "librecomp/game.hpp"
#include "zelda_config.h"
#include "zelda_app_preferences.hpp"
#include "zelda_sound.h"

extern SDL_Window *window;

enum : NSInteger {
    ControlAutosave = 1,
    ControlRumble,
    ControlGyro,
    ControlMouse,
    ControlDeadzone,
    ControlMainVolume,
    ControlMusicVolume,
    ControlLowHealthBeeps,
    ControlConfirmQuit,
};

@class ZeldaMacControlsController;

@interface ZeldaMacSettingsController : NSObject <NSWindowDelegate>
    @property(nonatomic, strong) NSWindow *window;
    @property(nonatomic, strong) NSSlider *gyroSlider;
    @property(nonatomic, strong) NSSlider *rumbleSlider;
    @property(nonatomic, strong) NSSlider *mouseSlider;
    @property(nonatomic, strong) NSSlider *deadzoneSlider;
    @property(nonatomic, strong) NSSlider *mainVolumeSlider;
    @property(nonatomic, strong) NSSlider *musicVolumeSlider;
    @property(nonatomic, strong) NSButton *autosaveButton;
    @property(nonatomic, strong) NSButton *lowHealthBeepsButton;
    @property(nonatomic, strong) NSButton *confirmQuitButton;
    - (void)showSettings:(id)sender;
    - (void)openControls:(id)sender;
    - (void)openGameSettings:(id)sender;
    - (void)resetSettings:(id)sender;
    - (void)toggleFullscreen:(id)sender;
    - (void)quitGame:(id)sender;
    - (void)settingChanged:(id)sender;
    - (void)refreshFromGame;
@end

@interface ZeldaMacControlsController : NSObject <NSWindowDelegate>
    @property(nonatomic, strong) NSWindow *window;
    @property(nonatomic, strong) NSSegmentedControl *deviceSelector;
    @property(nonatomic, strong) NSStackView *rows;
    - (void)showControls:(id)sender;
    - (void)deviceChanged:(id)sender;
    - (void)assignBinding:(id)sender;
    - (recomp::InputDevice)selectedDevice;
    - (void)resetSelectedDevice:(id)sender;
    - (void)resetAllBindings:(id)sender;
    - (void)refreshBindings;
@end

namespace {
    static ZeldaMacSettingsController *settingsController;
    static ZeldaMacControlsController *controlsController;
    static std::atomic_bool native_control_scan_pending = false;
    static NSTextField *makeLabel(NSString *text, CGFloat width);
}

@implementation ZeldaMacControlsController

    - (instancetype)init {
        self = [super init];
        if (self) {
            self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 680, 620)
                styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                backing:NSBackingStoreBuffered defer:NO];
            self.window.title = @"Majora's Mask Controls";
            self.window.delegate = self;
            self.window.releasedWhenClosed = NO;

            NSView *root = [NSView new];
            root.translatesAutoresizingMaskIntoConstraints = NO;
            self.window.contentView = root;

            self.deviceSelector = [NSSegmentedControl segmentedControlWithLabels:@[@"Keyboard", @"Controller"]
                trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(deviceChanged:)];
            self.deviceSelector.selectedSegment = 0;
            self.deviceSelector.translatesAutoresizingMaskIntoConstraints = NO;
            [root addSubview:self.deviceSelector];

            NSTextField *instructions = [NSTextField wrappingLabelWithString:@"Choose a binding, then press a key or controller input in the game window. Press Escape to cancel."];
            instructions.textColor = NSColor.secondaryLabelColor;
            instructions.translatesAutoresizingMaskIntoConstraints = NO;
            [root addSubview:instructions];

            NSScrollView *scrollView = [NSScrollView new];
            scrollView.hasVerticalScroller = YES;
            scrollView.translatesAutoresizingMaskIntoConstraints = NO;
            [root addSubview:scrollView];

            self.rows = [NSStackView new];
            self.rows.orientation = NSUserInterfaceLayoutOrientationVertical;
            self.rows.alignment = NSLayoutAttributeLeading;
            self.rows.spacing = 4;
            self.rows.edgeInsets = NSEdgeInsetsMake(8, 8, 8, 8);
            self.rows.translatesAutoresizingMaskIntoConstraints = NO;
            NSView *document = [NSView new];
            document.translatesAutoresizingMaskIntoConstraints = NO;
            [document addSubview:self.rows];
            scrollView.documentView = document;

            NSButton *resetDevice = [NSButton buttonWithTitle:@"Reset This Device…" target:self action:@selector(resetSelectedDevice:)];
            resetDevice.translatesAutoresizingMaskIntoConstraints = NO;
            NSButton *resetAll = [NSButton buttonWithTitle:@"Reset All Controls…" target:self action:@selector(resetAllBindings:)];
            resetAll.translatesAutoresizingMaskIntoConstraints = NO;
            [root addSubview:resetDevice];
            [root addSubview:resetAll];

            [NSLayoutConstraint activateConstraints:@[
                [self.deviceSelector.topAnchor constraintEqualToAnchor:root.topAnchor constant:16],
                [self.deviceSelector.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:18],
                [instructions.centerYAnchor constraintEqualToAnchor:self.deviceSelector.centerYAnchor],
                [instructions.leadingAnchor constraintEqualToAnchor:self.deviceSelector.trailingAnchor constant:16],
                [instructions.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-18],
                [scrollView.topAnchor constraintEqualToAnchor:self.deviceSelector.bottomAnchor constant:14],
                [scrollView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:12],
                [scrollView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-12],
                [scrollView.bottomAnchor constraintEqualToAnchor:resetDevice.topAnchor constant:-12],
                [resetDevice.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:18],
                [resetDevice.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-16],
                [resetAll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-18],
                [resetAll.centerYAnchor constraintEqualToAnchor:resetDevice.centerYAnchor],
                [document.widthAnchor constraintEqualToAnchor:scrollView.contentView.widthAnchor],
                [self.rows.leadingAnchor constraintEqualToAnchor:document.leadingAnchor],
                [self.rows.trailingAnchor constraintEqualToAnchor:document.trailingAnchor],
                [self.rows.topAnchor constraintEqualToAnchor:document.topAnchor],
                [self.rows.bottomAnchor constraintEqualToAnchor:document.bottomAnchor],
            ]];
            [self.window center];
            [self refreshBindings];
        }
        return self;
    }

    - (recomp::InputDevice)selectedDevice {
        return self.deviceSelector.selectedSegment == 0 ? recomp::InputDevice::Keyboard : recomp::InputDevice::Controller;
    }

    - (void)showControls:(id)sender {
        (void)sender;
        [self refreshBindings];
        [NSApp activateIgnoringOtherApps:YES];
        [self.window makeKeyAndOrderFront:nil];
    }

    - (void)deviceChanged:(id)sender {
        (void)sender;
        [self refreshBindings];
    }

    - (void)refreshBindings {
        for (NSView *view in self.rows.arrangedSubviews.copy) {
            [self.rows removeArrangedSubview:view];
            [view removeFromSuperview];
        }

        const recomp::InputDevice device = [self selectedDevice];
        for (size_t i = 0; i < recomp::get_num_inputs(); i++) {
            recomp::GameInput input = static_cast<recomp::GameInput>(i);
            const std::string& inputName = recomp::get_input_name(input);
            NSString *title = [NSString stringWithUTF8String:inputName.c_str()];
            NSTextField *name = makeLabel(title ?: @"", 190);
            NSButton *primary = [NSButton buttonWithTitle:@"" target:self action:@selector(assignBinding:)];
            NSButton *secondary = [NSButton buttonWithTitle:@"" target:self action:@selector(assignBinding:)];
            primary.tag = (NSInteger)(i * recomp::bindings_per_input);
            secondary.tag = (NSInteger)(i * recomp::bindings_per_input + 1);
            primary.toolTip = @"Click to change this binding";
            secondary.toolTip = @"Click to change this binding";
            primary.translatesAutoresizingMaskIntoConstraints = NO;
            secondary.translatesAutoresizingMaskIntoConstraints = NO;
            [primary.widthAnchor constraintGreaterThanOrEqualToConstant:150].active = YES;
            [secondary.widthAnchor constraintGreaterThanOrEqualToConstant:150].active = YES;

            for (size_t slot = 0; slot < recomp::bindings_per_input; slot++) {
                const std::string binding = recomp::get_input_binding(input, slot, device).to_string();
                NSString *bindingTitle = binding.empty() ? @"Unassigned" : [NSString stringWithUTF8String:binding.c_str()];
                (slot == 0 ? primary : secondary).title = bindingTitle ?: @"Unassigned";
            }

            NSStackView *row = [NSStackView stackViewWithViews:@[name, primary, secondary]];
            row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
            row.alignment = NSLayoutAttributeCenterY;
            row.spacing = 8;
            row.translatesAutoresizingMaskIntoConstraints = NO;
            [self.rows addArrangedSubview:row];
        }
    }

    - (void)assignBinding:(id)sender {
        const NSInteger tag = ((NSControl *)sender).tag;
        const size_t inputIndex = (size_t)(tag / recomp::bindings_per_input);
        const size_t bindingIndex = (size_t)(tag % recomp::bindings_per_input);
        if (inputIndex >= recomp::get_num_inputs()) return;

        zelda64::begin_macos_control_binding_scan([self selectedDevice], static_cast<recomp::GameInput>(inputIndex), bindingIndex);
    }

    - (void)resetSelectedDevice:(id)sender {
        (void)sender;
        const bool keyboard = [self selectedDevice] == recomp::InputDevice::Keyboard;
        NSAlert *alert = [NSAlert new];
        alert.messageText = keyboard ? @"Reset keyboard controls?" : @"Reset controller controls?";
        alert.informativeText = @"This restores the selected device's bindings to their defaults.";
        [alert addButtonWithTitle:@"Reset"];
        [alert addButtonWithTitle:@"Cancel"];
        if ([alert runModal] != NSAlertFirstButtonReturn) return;
        if (keyboard) zelda64::reset_kb_input_bindings();
        else zelda64::reset_cont_input_bindings();
        zelda64::save_config();
        [self refreshBindings];
    }

    - (void)resetAllBindings:(id)sender {
        (void)sender;
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Reset all controls?";
        alert.informativeText = @"This restores both keyboard and controller bindings to their defaults.";
        [alert addButtonWithTitle:@"Reset All"];
        [alert addButtonWithTitle:@"Cancel"];
        if ([alert runModal] != NSAlertFirstButtonReturn) return;
        zelda64::reset_input_bindings();
        zelda64::save_config();
        [self refreshBindings];
    }

    - (void)windowDidBecomeKey:(NSNotification *)notification {
        (void)notification;
        [self refreshBindings];
    }

@end

namespace {

    static NSTextField *makeLabel(NSString *text, CGFloat width) {
        NSTextField *label = [NSTextField labelWithString:text];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [label.widthAnchor constraintEqualToConstant:width].active = YES;
        return label;
    }

    static NSStackView *makeRow(NSString *title, NSView *control) {
        NSStackView *row = [NSStackView stackViewWithViews:@[makeLabel(title, 170), control]];
        row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        row.alignment = NSLayoutAttributeCenterY;
        row.spacing = 12;
        row.translatesAutoresizingMaskIntoConstraints = NO;
        return row;
    }

    static NSSlider *makeSlider(id target, NSInteger tag) {
        NSSlider *slider = [NSSlider sliderWithValue:0 minValue:0 maxValue:100 target:target action:@selector(settingChanged:)];
        slider.tag = tag;
        slider.continuous = NO;
        slider.translatesAutoresizingMaskIntoConstraints = NO;
        [slider.widthAnchor constraintGreaterThanOrEqualToConstant:190].active = YES;
        return slider;
    }

}

@implementation ZeldaMacSettingsController

    - (instancetype)init {
        self = [super init];
        if (self) {
            self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 520)
                styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                backing:NSBackingStoreBuffered defer:NO];
            self.window.title = @"Majora's Mask Settings";
            self.window.delegate = self;
            self.window.releasedWhenClosed = NO;
            [self.window center];

            NSStackView *content = [NSStackView new];
            content.orientation = NSUserInterfaceLayoutOrientationVertical;
            content.alignment = NSLayoutAttributeLeading;
            content.spacing = 14;
            content.edgeInsets = NSEdgeInsetsMake(20, 24, 20, 24);
            content.translatesAutoresizingMaskIntoConstraints = NO;
            self.window.contentView = [NSView new];
            [self.window.contentView addSubview:content];
            [NSLayoutConstraint activateConstraints:@[
                [content.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor],
                [content.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor],
                [content.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor],
                [content.bottomAnchor constraintEqualToAnchor:self.window.contentView.bottomAnchor],
            ]];

            NSTextField *generalTitle = [NSTextField labelWithString:@"Gameplay"];
            generalTitle.font = [NSFont boldSystemFontOfSize:15];
            self.autosaveButton = [NSButton checkboxWithTitle:@"Autosave" target:self action:@selector(settingChanged:)];
            self.autosaveButton.tag = ControlAutosave;
            self.rumbleSlider = makeSlider(self, ControlRumble);
            self.gyroSlider = makeSlider(self, ControlGyro);
            self.mouseSlider = makeSlider(self, ControlMouse);
            self.deadzoneSlider = makeSlider(self, ControlDeadzone);
            [content addArrangedSubview:generalTitle];
            [content addArrangedSubview:self.autosaveButton];
            [content addArrangedSubview:makeRow(@"Rumble Strength", self.rumbleSlider)];
            [content addArrangedSubview:makeRow(@"Gyro Sensitivity", self.gyroSlider)];
            [content addArrangedSubview:makeRow(@"Mouse Sensitivity", self.mouseSlider)];
            [content addArrangedSubview:makeRow(@"Joystick Deadzone", self.deadzoneSlider)];

            NSTextField *soundTitle = [NSTextField labelWithString:@"Sound"];
            soundTitle.font = [NSFont boldSystemFontOfSize:15];
            self.mainVolumeSlider = makeSlider(self, ControlMainVolume);
            self.musicVolumeSlider = makeSlider(self, ControlMusicVolume);
            self.lowHealthBeepsButton = [NSButton checkboxWithTitle:@"Low Health Beeps" target:self action:@selector(settingChanged:)];
            self.lowHealthBeepsButton.tag = ControlLowHealthBeeps;
            self.confirmQuitButton = [NSButton checkboxWithTitle:@"Ask before quitting with ⌘Q" target:self action:@selector(settingChanged:)];
            self.confirmQuitButton.tag = ControlConfirmQuit;
            [content addArrangedSubview:soundTitle];
            [content addArrangedSubview:makeRow(@"Overall Volume", self.mainVolumeSlider)];
            [content addArrangedSubview:makeRow(@"Music Volume", self.musicVolumeSlider)];
            [content addArrangedSubview:self.lowHealthBeepsButton];
            [content addArrangedSubview:self.confirmQuitButton];

            NSStackView *buttons = [NSStackView stackViewWithViews:@[
                [NSButton buttonWithTitle:@"Controls…" target:self action:@selector(openControls:)],
                [NSButton buttonWithTitle:@"In-Game Settings…" target:self action:@selector(openGameSettings:)],
                [NSButton buttonWithTitle:@"Reset Gameplay & Sound" target:self action:@selector(resetSettings:)],
            ]];
            buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
            buttons.spacing = 10;
            [content addArrangedSubview:buttons];

            NSTextField *note = [NSTextField wrappingLabelWithString:@"The full settings, including graphics, controller bindings, mods, and debug options, remain available in the in-game menu."];
            note.textColor = NSColor.secondaryLabelColor;
            note.font = [NSFont systemFontOfSize:11];
            [content addArrangedSubview:note];
        }
        return self;
    }

    - (void)showSettings:(id)sender {
        (void)sender;
        [self refreshFromGame];
        [NSApp activateIgnoringOtherApps:YES];
        [self.window makeKeyAndOrderFront:nil];
    }

    - (void)openControls:(id)sender {
        (void)sender;
        [controlsController showControls:nil];
    }

    - (void)openGameSettings:(id)sender {
        (void)sender;
        [self.window orderOut:nil];
        [NSApp activateIgnoringOtherApps:YES];
        if (window != nullptr) SDL_RaiseWindow(window);
        recompui::show_context(recompui::get_config_context_id(), "");
    }

    - (void)resetSettings:(id)sender {
        (void)sender;
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Reset gameplay and sound settings?";
        alert.informativeText = @"This restores the general and sound settings to their defaults. Controller bindings and graphics settings are unchanged.";
        [alert addButtonWithTitle:@"Reset"];
        [alert addButtonWithTitle:@"Cancel"];
        if ([alert runModal] == NSAlertFirstButtonReturn) {
            zelda64::reset_general_and_sound_settings();
            [self refreshFromGame];
        }
    }

    - (void)toggleFullscreen:(id)sender {
        (void)sender;
        if (window == nullptr) return;
        const Uint32 flags = SDL_GetWindowFlags(window);
        SDL_SetWindowFullscreen(window, (flags & SDL_WINDOW_FULLSCREEN) ? 0 : SDL_WINDOW_FULLSCREEN_DESKTOP);
    }

    - (void)quitGame:(id)sender {
        (void)sender;
        [self.window orderOut:nil];
        if (window != nullptr) SDL_RaiseWindow(window);
        if (zelda64::quit_action(zelda64::get_confirm_before_quit()) == zelda64::QuitAction::ShowConfirmation) {
            zelda64::open_quit_game_prompt();
        } else {
            ultramodern::quit();
        }
    }

    - (void)settingChanged:(id)sender {
        NSControl *control = (NSControl *)sender;
        const NSInteger value = (NSInteger)llround(control.doubleValue);
        switch (control.tag) {
            case ControlAutosave:
                zelda64::set_autosave_mode(control.integerValue == NSControlStateValueOn ? zelda64::AutosaveMode::On : zelda64::AutosaveMode::Off);
                break;
            case ControlRumble:
                recomp::set_rumble_strength((int)value);
                break;
            case ControlGyro:
                recomp::set_gyro_sensitivity((int)value);
                break;
            case ControlMouse:
                recomp::set_mouse_sensitivity((int)value);
                break;
            case ControlDeadzone:
                recomp::set_joystick_deadzone((int)value);
                break;
            case ControlMainVolume:
                zelda64::set_main_volume((int)value);
                break;
            case ControlMusicVolume:
                zelda64::set_bgm_volume((int)value);
                break;
            case ControlLowHealthBeeps:
                zelda64::set_low_health_beeps_enabled(control.integerValue == NSControlStateValueOn);
                break;
            case ControlConfirmQuit:
                zelda64::set_confirm_before_quit(control.integerValue == NSControlStateValueOn);
                break;
            default:
                return;
        }
        zelda64::save_config();
        [self refreshFromGame];
    }

    - (void)refreshFromGame {
        self.autosaveButton.state = zelda64::get_autosave_mode() == zelda64::AutosaveMode::On ? NSControlStateValueOn : NSControlStateValueOff;
        self.rumbleSlider.integerValue = recomp::get_rumble_strength();
        self.gyroSlider.integerValue = recomp::get_gyro_sensitivity();
        self.mouseSlider.integerValue = recomp::get_mouse_sensitivity();
        self.deadzoneSlider.integerValue = recomp::get_joystick_deadzone();
        self.mainVolumeSlider.integerValue = zelda64::get_main_volume();
        self.musicVolumeSlider.integerValue = zelda64::get_bgm_volume();
        self.lowHealthBeepsButton.state = zelda64::get_low_health_beeps_enabled() ? NSControlStateValueOn : NSControlStateValueOff;
        self.confirmQuitButton.state = zelda64::get_confirm_before_quit() ? NSControlStateValueOn : NSControlStateValueOff;
    }

    - (void)windowDidBecomeKey:(NSNotification *)notification {
        (void)notification;
        [self refreshFromGame];
    }

@end

namespace {

    static NSMenuItem *menuItem(NSString *title, SEL action, NSString *key, NSEventModifierFlags modifiers, id target) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
        item.keyEquivalentModifierMask = modifiers;
        item.target = target;
        return item;
    }

    static void installMenus() {
        if (settingsController == nil) settingsController = [ZeldaMacSettingsController new];
        if (controlsController == nil) controlsController = [ZeldaMacControlsController new];

        NSMenu *mainMenu = [NSMenu new];
        NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
        NSMenu *appMenu = [NSMenu new];
        [appMenu addItem:menuItem(@"About Majora's Mask", @selector(orderFrontStandardAboutPanel:), @"", 0, NSApp)];
        [appMenu addItem:[NSMenuItem separatorItem]];
        [appMenu addItem:menuItem(@"Settings…", @selector(showSettings:), @",", NSEventModifierFlagCommand, settingsController)];
        [appMenu addItem:[NSMenuItem separatorItem]];
        [appMenu addItem:menuItem(@"Hide Majora's Mask", @selector(hide:), @"h", NSEventModifierFlagCommand, NSApp)];
        [appMenu addItem:menuItem(@"Hide Others", @selector(hideOtherApplications:), @"h", (NSEventModifierFlagCommand | NSEventModifierFlagOption), NSApp)];
        [appMenu addItem:menuItem(@"Show All", @selector(unhideAllApplications:), @"", 0, NSApp)];
        [appMenu addItem:[NSMenuItem separatorItem]];
        [appMenu addItem:menuItem(@"Quit Majora's Mask", @selector(quitGame:), @"q", NSEventModifierFlagCommand, settingsController)];
        appMenuItem.title = @"Majora's Mask";
        appMenuItem.submenu = appMenu;
        [mainMenu addItem:appMenuItem];

        NSMenuItem *gameMenuItem = [[NSMenuItem alloc] initWithTitle:@"Game" action:nil keyEquivalent:@""];
        NSMenu *gameMenu = [NSMenu new];
        [gameMenu addItem:menuItem(@"Controls…", @selector(showControls:), @"c", (NSEventModifierFlagCommand | NSEventModifierFlagShift), controlsController)];
        [gameMenu addItem:[NSMenuItem separatorItem]];
        [gameMenu addItem:menuItem(@"In-Game Settings…", @selector(openGameSettings:), @"o", (NSEventModifierFlagCommand | NSEventModifierFlagOption), settingsController)];
        [gameMenu addItem:menuItem(@"Reset Gameplay & Sound…", @selector(resetSettings:), @"", 0, settingsController)];
        [gameMenu addItem:menuItem(@"Toggle Full Screen", @selector(toggleFullscreen:), @"f", (NSEventModifierFlagCommand | NSEventModifierFlagControl), settingsController)];
        gameMenuItem.submenu = gameMenu;
        [mainMenu addItem:gameMenuItem];

        NSMenuItem *windowMenuItem = [[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""];
        NSMenu *windowMenu = [NSMenu new];
        [windowMenu addItem:menuItem(@"Minimize", @selector(performMiniaturize:), @"m", NSEventModifierFlagCommand, NSApp)];
        [windowMenu addItem:menuItem(@"Zoom", @selector(performZoom:), @"", 0, NSApp)];
        [windowMenu addItem:[NSMenuItem separatorItem]];
        [windowMenu addItem:menuItem(@"Bring All to Front", @selector(arrangeInFront:), @"", 0, NSApp)];
        windowMenuItem.submenu = windowMenu;
        [mainMenu addItem:windowMenuItem];
        NSApp.windowsMenu = windowMenuItem.submenu;
        NSApp.mainMenu = mainMenu;
    }
}

namespace zelda64 {
    void initialize_macos_settings() {
        if ([NSThread isMainThread]) {
            installMenus();
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{ installMenus(); });
        }
    }

    void refresh_macos_settings() {
        if (settingsController == nil) return;
        if ([NSThread isMainThread]) {
            [settingsController refreshFromGame];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{ [settingsController refreshFromGame]; });
        }
    }

    void refresh_macos_controls() {
        if (controlsController == nil) return;
        if ([NSThread isMainThread]) {
            [controlsController refreshBindings];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{ [controlsController refreshBindings]; });
        }
    }

    void begin_macos_control_binding_scan(recomp::InputDevice device, recomp::GameInput input, size_t binding_index) {
        native_control_scan_pending.store(true);
        recompui::start_control_binding_scan(input, binding_index, device);
        if ([NSThread isMainThread]) {
            [controlsController.window orderOut:nil];
            if (window != nullptr) SDL_RaiseWindow(window);
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [controlsController.window orderOut:nil];
                if (window != nullptr) SDL_RaiseWindow(window);
            });
        }
    }

    void complete_macos_control_binding_scan() {
        if (!native_control_scan_pending.exchange(false)) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [controlsController refreshBindings];
            [controlsController showControls:nil];
        });
    }
}

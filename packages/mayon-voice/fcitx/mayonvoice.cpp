#include <array>
#include <iomanip>
#include <sstream>
#include <string>

#include <fcitx-utils/dbus/bus.h>
#include <fcitx-utils/dbus/objectvtable.h>
#include <fcitx/addonfactory.h>
#include <fcitx/addoninstance.h>
#include <fcitx/addonmanager.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputcontextmanager.h>
#include <fcitx/instance.h>

#include <dbus_public.h>

namespace fcitx {
namespace {

std::string tokenFor(const ICUUID &uuid) {
    std::ostringstream out;
    out << std::hex << std::setfill('0');
    for (const auto byte : uuid) {
        out << std::setw(2) << static_cast<unsigned int>(byte);
    }
    return out.str();
}

class VoiceBridgeObject : public dbus::ObjectVTable<VoiceBridgeObject> {
public:
    explicit VoiceBridgeObject(Instance *instance) : instance_(instance) {}

    std::string focusToken() {
        auto *focused = focusedContext();
        return focused ? tokenFor(focused->uuid()) : std::string{};
    }

    std::string focusInfo() {
        std::string info;
        instance_->inputContextManager().foreachFocused([&info](InputContext *ic) {
            if (!info.empty()) { info += "; "; }
            info += std::string(ic->frontend()) + ":" + ic->program() + ":" + tokenFor(ic->uuid());
            return true;
        });
        return info;
    }

    bool commitString(const std::string &text) {
        auto *focused = focusedContext();
        if (!focused || text.empty() || isPassword(focused)) {
            return false;
        }
        focused->commitString(text);
        return true;
    }

    std::string commitStringForFocus(const std::string &expectedToken,
                                     const std::string &text) {
        if (text.empty()) {
            return "empty";
        }
        auto *focused = focusedContext();
        if (!focused) {
            return "no_focus";
        }
        if (tokenFor(focused->uuid()) != expectedToken) {
            return "focus_changed";
        }
        if (isPassword(focused)) {
            return "password";
        }
        focused->commitString(text);
        return "committed";
    }

private:
    InputContext *focusedContext() const {
        // Use Fcitx's active-IC ordering across frontends. mostRecentInputContext
        // may return an unfocused/dummy IC, so it is deliberately not used.
        auto *focused = instance_->inputContextManager().lastFocusedInputContext();
        return focused && focused->hasFocus() ? focused : nullptr;
    }

    static bool isPassword(const InputContext *context) {
        return context->capabilityFlags().test(CapabilityFlag::Password);
    }

    FCITX_OBJECT_VTABLE_METHOD(focusToken, "FocusToken", "", "s");
    FCITX_OBJECT_VTABLE_METHOD(focusInfo, "FocusInfo", "", "s");
    FCITX_OBJECT_VTABLE_METHOD(commitString, "CommitString", "s", "b");
    FCITX_OBJECT_VTABLE_METHOD(commitStringForFocus,
                               "CommitStringForFocus", "ss", "s");

    Instance *instance_;
};

class VoiceBridge : public AddonInstance {
public:
    FCITX_ADDON_DEPENDENCY_LOADER(dbus, instance_->addonManager());

    explicit VoiceBridge(Instance *instance)
        : instance_(instance), object_(instance) {
        auto *dbusAddon = dbus();
        auto *bus = dbusAddon->call<IDBusModule::bus>();
        if (!bus || !bus->addObjectVTable("/mayon/voice",
                                          "org.mayon.Voice1", object_)) {
            throw std::runtime_error("Unable to register mayon voice D-Bus object");
        }
    }

private:
    Instance *instance_;
    VoiceBridgeObject object_;
};

class VoiceBridgeFactory : public AddonFactory {
public:
    AddonInstance *create(AddonManager *manager) override {
        return new VoiceBridge(manager->instance());
    }
};

} // namespace
} // namespace fcitx

FCITX_ADDON_FACTORY_V2(mayonvoice, fcitx::VoiceBridgeFactory)

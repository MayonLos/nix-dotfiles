"""Small Power Profiles D-Bus fixture for the isolated GameMode VM check."""
import pathlib
import sys

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib


PROFILE_FILE = pathlib.Path(sys.argv[1])
BUS_NAME = "org.freedesktop.UPower.PowerProfiles"
OBJECT_PATH = "/org/freedesktop/UPower/PowerProfiles"
INTERFACE = "org.freedesktop.UPower.PowerProfiles"


class PowerProfiles(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, OBJECT_PATH)

    def active_profile(self):
        return PROFILE_FILE.read_text().strip()

    def profiles(self):
        profiles = []
        for name in ("power-saver", "balanced", "performance"):
            profiles.append(
                dbus.Dictionary(
                    {
                        "Profile": dbus.String(name, variant_level=1),
                        "Driver": dbus.String("fixture", variant_level=1),
                        "PlatformDriver": dbus.String("fixture", variant_level=1),
                        "Degraded": dbus.String("", variant_level=1),
                        "Actions": dbus.Array([], signature="s", variant_level=1),
                    },
                    signature="sv",
                )
            )
        return dbus.Array(profiles, signature="a{sv}")

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ss", out_signature="v")
    def Get(self, interface, name):
        if interface != INTERFACE:
            raise dbus.exceptions.DBusException("Unknown interface")
        if name == "ActiveProfile":
            return dbus.String(self.active_profile(), variant_level=1)
        if name == "Profiles":
            return dbus.Array(self.profiles(), signature="a{sv}", variant_level=1)
        if name == "Actions":
            return dbus.Array([], signature="s", variant_level=1)
        if name == "PerformanceDegraded":
            return dbus.String("", variant_level=1)
        raise dbus.exceptions.DBusException("Unknown property")

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        if interface != INTERFACE:
            raise dbus.exceptions.DBusException("Unknown interface")
        return dbus.Dictionary(
            {
                "ActiveProfile": dbus.String(self.active_profile(), variant_level=1),
                "Profiles": dbus.Array(self.profiles(), signature="a{sv}", variant_level=1),
                "Actions": dbus.Array([], signature="s", variant_level=1),
                "PerformanceDegraded": dbus.String("", variant_level=1),
            },
            signature="sv",
        )

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ssv", out_signature="")
    def Set(self, interface, name, value):
        if interface != INTERFACE or name != "ActiveProfile":
            raise dbus.exceptions.DBusException("Property is read-only or unknown")
        profile = str(value)
        if profile not in {"power-saver", "balanced", "performance"}:
            raise dbus.exceptions.DBusException("Unknown profile")
        PROFILE_FILE.write_text(profile + "\n")
        self.PropertiesChanged(
            INTERFACE,
            {"ActiveProfile": dbus.String(profile, variant_level=1)},
            [],
        )

    @dbus.service.signal(
        "org.freedesktop.DBus.Properties",
        signature="sa{sv}as",
    )
    def PropertiesChanged(self, interface, changed, invalidated):
        pass


DBusGMainLoop(set_as_default=True)
bus = dbus.SystemBus()
name = dbus.service.BusName(BUS_NAME, bus=bus)
service = PowerProfiles(bus)
GLib.MainLoop().run()

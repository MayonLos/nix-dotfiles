#!/usr/bin/env python3
"""Two real StatusNotifierItem + DBusMenu services for the isolated test.

Each backend owns its own private D-Bus connection and well-known name, so the
properties of one item cannot be confused with the other. The icon is a solid
colour pixmap so the harness can locate the tray icon in a screenshot without
guessing the bar layout. This script only talks to the bus it inherits in
DBUS_SESSION_BUS_ADDRESS; it never touches the caller's session.
"""

from __future__ import annotations

import argparse
import os
import sys
import time

from gi.repository import Gio, GLib

SNI_XML = """
<node>
  <interface name="org.kde.StatusNotifierItem">
    <property name="Category" type="s" access="read"/>
    <property name="Id" type="s" access="read"/>
    <property name="Title" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="WindowId" type="i" access="read"/>
    <property name="IconName" type="s" access="read"/>
    <property name="IconPixmap" type="a(iiay)" access="read"/>
    <property name="OverlayIconName" type="s" access="read"/>
    <property name="OverlayIconPixmap" type="a(iiay)" access="read"/>
    <property name="AttentionIconName" type="s" access="read"/>
    <property name="AttentionIconPixmap" type="a(iiay)" access="read"/>
    <property name="AttentionMovieName" type="s" access="read"/>
    <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
    <property name="ItemIsMenu" type="b" access="read"/>
    <property name="Menu" type="o" access="read"/>
    <method name="ContextMenu"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
    <method name="Activate"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
    <method name="SecondaryActivate"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
    <signal name="NewIcon"/>
    <signal name="NewStatus"><arg type="s"/></signal>
  </interface>
</node>
"""

MENU_XML = """
<node>
  <interface name="com.canonical.dbusmenu">
    <method name="GetLayout">
      <arg name="parentId" type="i" direction="in"/>
      <arg name="recursionDepth" type="i" direction="in"/>
      <arg name="propertyNames" type="as" direction="in"/>
      <arg name="revision" type="u" direction="out"/>
      <arg name="layout" type="(ia{sv}av)" direction="out"/>
    </method>
    <method name="GetGroupProperties">
      <arg name="ids" type="ai" direction="in"/>
      <arg name="propertyNames" type="as" direction="in"/>
      <arg name="properties" type="a(ia{sv})" direction="out"/>
    </method>
    <method name="AboutToShow">
      <arg name="id" type="i" direction="in"/>
      <arg name="needUpdate" type="b" direction="out"/>
    </method>
    <method name="Event">
      <arg name="id" type="i" direction="in"/>
      <arg name="eventId" type="s" direction="in"/>
      <arg name="data" type="v" direction="in"/>
      <arg name="timestamp" type="u" direction="in"/>
    </method>
    <method name="EventGroup">
      <arg name="events" type="a(isvu)" direction="in"/>
      <arg name="idErrors" type="ai" direction="out"/>
    </method>
    <property name="Version" type="u" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="TextDirection" type="s" access="read"/>
    <property name="IconThemePath" type="as" access="read"/>
    <signal name="LayoutUpdated"><arg type="u"/><arg type="i"/></signal>
  </interface>
</node>
"""


def s(value: str) -> GLib.Variant:
    return GLib.Variant("s", value)


def b(value: bool) -> GLib.Variant:
    return GLib.Variant("b", value)


def i(value: int) -> GLib.Variant:
    return GLib.Variant("i", value)


def node(node_id: int, props: dict[str, GLib.Variant], children: list[GLib.Variant]) -> GLib.Variant:
    return GLib.Variant("(ia{sv}av)", (node_id, props, children))


def item(
    node_id: int,
    label: str,
    *,
    enabled: bool = True,
    toggle_type: str | None = None,
    toggle_state: int | None = None,
    submenu: list[GLib.Variant] | None = None,
) -> GLib.Variant:
    props = {"label": s(label), "enabled": b(enabled), "visible": b(True), "type": s("item")}
    if toggle_type is not None:
        props["toggle-type"] = s(toggle_type)
        props["toggle-state"] = i(toggle_state or 0)
    if submenu is not None:
        props["children-display"] = s("submenu")
    return node(node_id, props, list(submenu or []))


def menu_backend_one() -> GLib.Variant:
    return [
        item(101, "打开设置"),
        item(
            102,
            "配置",
            submenu=[
                item(201, "配置 A", toggle_type="checkmark", toggle_state=1),
                item(202, "配置 B", toggle_type="checkmark", toggle_state=0),
            ],
        ),
        item(103, "正在同步", enabled=False),
        item(104, "退出"),
    ]


def menu_backend_two() -> GLib.Variant:
    return [
        item(111, "播放"),
        item(112, "暂停"),
        item(113, "设备不可用", enabled=False),
        item(
            114,
            "选项",
            submenu=[
                item(211, "低延迟", toggle_type="radio", toggle_state=1),
                item(212, "高保真", toggle_type="radio", toggle_state=0),
            ],
        ),
    ]


def make_pixmap(width: int, height: int, rgba: tuple[int, int, int, int]) -> GLib.Variant:
    r, g, bl, a = rgba
    pixel = bytes((a, r, g, bl))
    data = list(pixel * (width * height))
    return GLib.Variant("a(iiay)", ([(width, height, data)] ))


class Backend:
    def __init__(
        self,
        service: str,
        icon: tuple[int, int, int, int],
        layout: list[GLib.Variant],
        revision: int = 3,
    ) -> None:
        self.service = service
        self.menu_path = "/MenuBar"
        self.icon = icon
        self.layout = layout
        self.revision = revision
        self.connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.sni_info = Gio.DBusNodeInfo.new_for_xml(SNI_XML)
        self.menu_info = Gio.DBusNodeInfo.new_for_xml(MENU_XML)
        self.hold = self.connection.register_object(
            "/StatusNotifierItem",
            self.sni_info.interfaces[0],
            self.on_sni_method,
            self.on_sni_property,
            None,
        )
        if self.hold is None:
            raise RuntimeError(f"{service}: failed to register SNI object")
        menu_hold = self.connection.register_object(
            self.menu_path,
            self.menu_info.interfaces[0],
            self.on_menu_method,
            self.on_menu_property,
            None,
        )
        if menu_hold is None:
            raise RuntimeError(f"{service}: failed to register DBusMenu object")
        self.menu_hold = menu_hold
        self.name_id = Gio.bus_own_name_on_connection(
            self.connection, service, Gio.BusNameOwnerFlags.NONE, None, None
        )

    # --- SNI -------------------------------------------------------------
    def on_sni_method(self, connection, sender, path, iface, method, params, invocation):
        if method in {"Activate", "SecondaryActivate", "ContextMenu"}:
            invocation.return_value(None)
        else:
            invocation.return_value(None)

    def on_sni_property(self, connection, sender, path, iface, prop):
        values = {
            "Category": s("ApplicationStatus"),
            "Id": s(self.service),
            "Title": s(self.service.rsplit(".", 1)[-1]),
            "Status": s("Active"),
            "WindowId": i(0),
            "IconName": s(""),
            "IconPixmap": make_pixmap(22, 22, self.icon),
            "OverlayIconName": s(""),
            "OverlayIconPixmap": make_pixmap(1, 1, (0, 0, 0, 0)),
            "AttentionIconName": s(""),
            "AttentionIconPixmap": make_pixmap(1, 1, (0, 0, 0, 0)),
            "AttentionMovieName": s(""),
            "ToolTip": GLib.Variant("(sa(iiay)ss)", ("", [], "", "")),
            "ItemIsMenu": b(False),
            "Menu": GLib.Variant("o", self.menu_path),
        }
        return values.get(prop)

    # --- DBusMenu --------------------------------------------------------
    def on_menu_method(self, connection, sender, path, iface, method, params, invocation):
        if method == "GetLayout":
            root = GLib.Variant("(ia{sv}av)", (0, {}, list(self.layout)))
            invocation.return_value(GLib.Variant.new_tuple(GLib.Variant("u", self.revision), root))
        elif method == "AboutToShow":
            invocation.return_value(GLib.Variant("(b)", (False,)))
        elif method == "Event":
            invocation.return_value(None)
        elif method == "EventGroup":
            invocation.return_value(GLib.Variant("(ai)", ([],)))
        elif method == "GetGroupProperties":
            invocation.return_value(GLib.Variant("(a(ia{sv}))", ([],)))
        else:
            invocation.return_error_literal(
                Gio.dbus_error_quark(), Gio.DBusError.UNKNOWN_METHOD, method
            )

    def on_menu_property(self, connection, sender, path, iface, prop):
        values = {
            "Version": GLib.Variant("u", 3),
            "Status": s("normal"),
            "TextDirection": s("ltr"),
            "IconThemePath": GLib.Variant("as", []),
        }
        return values.get(prop)


def watcher_owned() -> bool:
    try:
        connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        reply = connection.call_sync(
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "NameHasOwner",
            GLib.Variant("(s)", ("org.kde.StatusNotifierWatcher",)),
            None,
            Gio.DBusCallFlags.NONE,
            1000,
            None,
        )
        return bool(reply.unpack()[0])
    except GLib.Error:
        return False


def register(service: str) -> None:
    connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    connection.call_sync(
        "org.kde.StatusNotifierWatcher",
        "/StatusNotifierWatcher",
        "org.kde.StatusNotifierWatcher",
        "RegisterStatusNotifierItem",
        GLib.Variant("(s)", (service,)),
        None,
        Gio.DBusCallFlags.NONE,
        5000,
        None,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--service", required=True, help="well-known SNI service name")
    parser.add_argument(
        "--variant", required=True, choices=["one", "two"], help="menu content variant"
    )
    parser.add_argument(
        "--wait",
        type=float,
        default=30.0,
        help="seconds to wait for the compositor's StatusNotifierWatcher",
    )
    args = parser.parse_args()
    if not os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
        print("provider: no private session bus", file=sys.stderr)
        return 2

    icon = (255, 0, 255, 255) if args.variant == "one" else (0, 255, 255, 255)
    layout = menu_backend_one() if args.variant == "one" else menu_backend_two()
    backend = Backend(args.service, icon, layout)

    deadline = time.monotonic() + args.wait
    while time.monotonic() < deadline:
        if watcher_owned():
            break
        time.sleep(0.1)
    else:
        print("provider: StatusNotifierWatcher never appeared", file=sys.stderr)
        return 3
    register(args.service)
    print(f"READY {args.service}", flush=True)
    loop = GLib.MainLoop()
    try:
        loop.run()
    except KeyboardInterrupt:
        pass
    Gio.bus_unown_name(backend.name_id)
    return 0


if __name__ == "__main__":
    sys.exit(main())

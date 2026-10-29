"""Keep policy includes; register each explicit bus name once.

The session bus still searches standard XDG directories (including per-user
services). Only services absent from the system profile need an extra directory.
"""

import configparser
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET


def services(directory):
    for path in sorted(directory.glob("*.service")):
        parser = configparser.ConfigParser(interpolation=None, strict=False)
        parser.read(path)
        yield parser["D-BUS Service"]["Name"], path


def main():
    output, profile = map(Path, sys.argv[1:])
    profile_names = dict(services(profile / "share/dbus-1/services"))
    audit = {}
    for bus, suffix in (("system", "system-services"), ("session", "services")):
        config = output / f"{bus}.conf"
        tree = ET.parse(config)
        root = tree.getroot()
        providers = {}
        duplicates = {}
        includes = set()
        for node in list(root):
            if node.tag == "servicedir":
                for name, path in services(Path(node.text)):
                    if name in providers:
                        duplicates.setdefault(name, []).append(str(path))
                    else:
                        providers[name] = path
                root.remove(node)
            elif node.tag == "includedir":
                if node.text in includes:
                    root.remove(node)
                includes.add(node.text)
        directory = output / suffix
        directory.mkdir()
        for name, path in providers.items():
            if bus == "session" and name in profile_names:
                continue
            (directory / f"{name}.service").symlink_to(path)
        ET.SubElement(root, "servicedir").text = str(directory)
        tree.write(config, encoding="UTF-8", xml_declaration=True)
        audit[bus] = {
            "providers": {name: str(path) for name, path in providers.items()},
            "duplicate_sources": duplicates,
            "standard_profile_names": sorted(profile_names) if bus == "session" else [],
        }
    (output / "service-providers.json").write_text(json.dumps(audit, indent=2) + "\n")


if __name__ == "__main__":
    main()

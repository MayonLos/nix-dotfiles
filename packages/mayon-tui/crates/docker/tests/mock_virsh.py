#!/usr/bin/env python3
"""Read-only, allowlisted virsh fixture. Never contacts a libvirt daemon."""
from __future__ import annotations

import json
import os
from pathlib import Path
import sys

UUIDS = {
    "11111111-1111-4111-8111-111111111111": "session-dev",
    "22222222-2222-4222-8222-222222222222": "system-builder",
    "33333333-3333-4333-8333-333333333333": "system-test",
}
URI_DOMAINS = {
    "qemu:///session": ["11111111-1111-4111-8111-111111111111"],
    "qemu:///system": [
        "22222222-2222-4222-8222-222222222222",
        "33333333-3333-4333-8333-333333333333",
    ],
}
POOLS = {"session-images": "session", "default": "system"}
VOLUMES = {
    "session-images": ["session-dev.qcow2", "tools.iso"],
    "default": [
        "base-shared.qcow2", "overlay-a.qcow2", "orphan.qcow2",
        "installer.iso", "unused-installer.iso", "snapshot-clean-install.qcow2", "named-data.qcow2",
    ],
}


class MockError(Exception):
    pass


def root_dir() -> Path:
    raw = os.environ.get("VM_MOCK_ROOT")
    if not raw:
        raise MockError("VM_MOCK_ROOT is required")
    root = Path(raw).resolve()
    repo_work = Path(__file__).resolve().parents[5] / ".work"
    if root != repo_work and repo_work not in root.parents:
        raise MockError("VM_MOCK_ROOT must be inside this repository's .work")
    return root


def xml_domain(uuid: str, root: Path) -> str:
    name = UUIDS[uuid]
    disks: list[tuple[str, str, str | None]] = []
    if name == "session-dev":
        disks = [("vda", "session/session-dev.qcow2", None), ("sda", "session/tools.iso", None),
                 ("vdb", "session/raw-data.raw", None)]
    elif name == "system-builder":
        disks = [("vda", "system/overlay-a.qcow2", "system/base-shared.qcow2"),
                 ("sda", "system/installer.iso", None)]
    else:
        disks = [("vda", "system/base-shared.qcow2", None)]
    device_nodes = []
    for target, rel, backing in disks:
        device = "cdrom" if rel.endswith(".iso") else "disk"
        image_type = "raw" if rel.endswith((".iso", ".raw")) else "qcow2"
        source = f'<source file="{root / rel}"/>'
        if backing:
            terminal = "" if os.environ.get("VM_MOCK_CHAIN_UNKNOWN") == "1" and name == "system-test" else "<backingStore/>"
            backing_xml = f'<backingStore><format type="qcow2"/><source file="{root / backing}"/>{terminal}</backingStore>'
        elif os.environ.get("VM_MOCK_CHAIN_UNKNOWN") == "1" and name == "system-test" and target == "vda":
            backing_xml = ""
        else:
            backing_xml = "<backingStore/>"
        device_nodes.append(f'<disk type="file" device="{device}"><driver name="qemu" type="{image_type}"/>{source}<target dev="{target}"/>{backing_xml}</disk>')
    if name == "system-test":
        device_nodes.append('<disk type="volume" device="disk"><driver name="qemu" type="qcow2"/><source pool="default" volume="named-data.qcow2"/><target dev="vdb"/><backingStore/></disk>')
        device_nodes.append('<disk type="network" device="disk"><driver name="qemu" type="raw"/><source protocol="rbd" name="pool/image"/><target dev="vdc"/><backingStore/></disk>')
    state = "running" if name == "system-builder" else "shut off"
    return (f'<domain><name>{name}</name><uuid>{uuid}</uuid><state>{state}</state>'
            f'<devices>{"".join(device_nodes)}</devices></domain>')


def snapshot_xml(root: Path, name: str) -> str:
    if name != "clean-install":
        raise MockError("unknown snapshot")
    snapshot_backing_end = "" if os.environ.get("VM_MOCK_SNAPSHOT_UNKNOWN") == "1" else "<backingStore/>"
    return (f'<domainsnapshot><name>{name}</name><disks><disk name="vda" snapshot="external">'
            f'<driver name="qemu" type="qcow2"/><source file="{root / "system/snapshot-clean-install.qcow2"}"/>'
            f'{snapshot_backing_end}</disk></disks>'
            f'<memory snapshot="external" file="{root / "system/snapshot-clean-install-memory"}"/>'
            '</domainsnapshot>')


def pool_xml(root: Path, pool: str) -> str:
    if pool not in POOLS:
        raise MockError("unknown pool")
    path = root / POOLS[pool]
    return f'<pool type="dir"><name>{pool}</name><target><path>{path}</path></target></pool>'


def volume_path(root: Path, pool: str, volume: str) -> Path:
    if pool not in VOLUMES or volume not in VOLUMES[pool] or Path(volume).name != volume:
        raise MockError("unknown volume")
    return root / POOLS[pool] / volume


def resolve_volume(root: Path, volume: str, pool: str | None = None) -> Path:
    """Resolve only paths enumerated by the fixture; never stat arbitrary paths."""
    for pool_name, names in VOLUMES.items():
        if pool is not None and pool_name != pool:
            continue
        for name in names:
            candidate = volume_path(root, pool_name, name)
            if volume == name or volume == str(candidate):
                return candidate
    raise MockError("unknown volume")


def run(uri: str, args: list[str], root: Path) -> str:
    if uri not in URI_DOMAINS:
        raise MockError("unsupported connection URI")
    if uri == "qemu:///system" and os.environ.get("VM_MOCK_SYSTEM_DENIED") == "1":
        raise PermissionError("permission denied opening qemu:///system")
    if args == ["list", "--all", "--uuid"]:
        return "\n".join(URI_DOMAINS[uri]) + "\n"
    if args and args[0] in ("domname", "domstate", "dumpxml"):
        command = args[0]
        domain = args[1] if len(args) > 1 and not args[1].startswith("--") else None
        if "--domain" in args:
            domain = args[args.index("--domain") + 1]
        if "--inactive" in args:
            pass
        if domain not in URI_DOMAINS[uri]:
            raise MockError("unknown domain for this connection")
        if command == "domname":
            return UUIDS[domain] + "\n"
        if command == "domstate":
            return ("running" if UUIDS[domain] == "system-builder" else "shut off") + "\n"
        return xml_domain(domain, root) + "\n"
    if args and args[0] == "snapshot-list":
        domain = args[1] if len(args) > 1 and not args[1].startswith("--") else None
        if "--domain" in args:
            domain = args[args.index("--domain") + 1]
        if domain not in URI_DOMAINS[uri]:
            raise MockError("unknown domain for this connection")
        if "--name" not in args:
            raise MockError("snapshot-list requires --name")
        return "clean-install\n" if domain == "22222222-2222-4222-8222-222222222222" else ""
    if args and args[0] == "snapshot-dumpxml":
        domain = args[1] if len(args) > 1 and not args[1].startswith("--") else None
        snap = args[2] if len(args) > 2 and not args[2].startswith("--") else None
        if "--domain" in args:
            domain = args[args.index("--domain") + 1]
        if "--snapshotname" in args:
            snap = args[args.index("--snapshotname") + 1]
        if domain not in URI_DOMAINS[uri]:
            raise MockError("unknown domain for this connection")
        return snapshot_xml(root, snap or "") + "\n"
    if args == ["pool-list", "--all", "--name"]:
        return "\n".join(POOLS) + "\n"
    if args and args[0] == "pool-dumpxml":
        pool = args[1] if len(args) > 1 and not args[1].startswith("--") else None
        if "--pool" in args:
            pool = args[args.index("--pool") + 1]
        return pool_xml(root, pool or "") + "\n"
    if args and args[0] == "vol-list":
        pool = args[1] if len(args) > 1 and not args[1].startswith("--") else None
        if "--pool" in args:
            pool = args[args.index("--pool") + 1]
        if pool not in VOLUMES or "--name" in args:
            raise MockError("vol-list requires --pool and does not support --name")
        rows = [" Name              Path", "--------------------------"]
        rows.extend(f" {name:<17} {volume_path(root, pool, name)}" for name in VOLUMES[pool])
        return "\n".join(rows) + "\n"
    if args and args[0] == "vol-info":
        pool = args[args.index("--pool") + 1] if "--pool" in args else None
        volume = args[args.index("--vol") + 1] if "--vol" in args else None
        if volume is None or "--bytes" not in args:
            raise MockError("vol-info requires --vol and --bytes")
        path = resolve_volume(root, volume, pool)
        capacity = {"session-dev.qcow2": 2147483648, "tools.iso": 734003200,
                    "base-shared.qcow2": 8589934592, "overlay-a.qcow2": 8589934592,
                    "orphan.qcow2": 4294967296, "installer.iso": 943718400,
                    "unused-installer.iso": 681574400,
                    "snapshot-clean-install.qcow2": 2147483648,
                    "named-data.qcow2": 1073741824}.get(path.name, 0)
        allocation = path.stat().st_blocks * 512
        return f"Name: {path.name}\nType: file\nCapacity: {capacity}\nAllocation: {allocation}\n"
    if args and args[0] == "vol-path":
        pool = args[args.index("--pool") + 1] if "--pool" in args else None
        volume = args[args.index("--vol") + 1] if "--vol" in args else None
        if pool is None or volume is None:
            raise MockError("vol-path requires --pool and --vol")
        return str(resolve_volume(root, volume, pool)) + "\n"
    if args and args[0] == "domblkinfo":
        domain = args[1] if len(args) > 1 and not args[1].startswith("--") else None
        target = args[2] if len(args) > 2 and not args[2].startswith("--") else None
        if "--domain" in args:
            domain = args[args.index("--domain") + 1]
        if "--device" in args:
            target = args[args.index("--device") + 1]
        if domain not in URI_DOMAINS[uri]:
            raise MockError("unknown domain for this connection")
        name = UUIDS[domain]
        if (name, target) == ("system-test", "vdb"):
            path = root / "system/named-data.qcow2"
            allocation = path.stat().st_blocks * 512
            return f"Capacity: 1073741824\nAllocation: {allocation}\nPhysical: {allocation}\n"
        if (name, target) == ("system-test", "vdc"):
            return "Capacity: 10737418240\nAllocation: 0\nPhysical: 0\n"
        rel = {("session-dev", "vda"): "session/session-dev.qcow2",
               ("system-builder", "vda"): "system/overlay-a.qcow2",
               ("system-test", "vda"): "system/base-shared.qcow2",
               ("session-dev", "vdb"): "session/raw-data.raw"}.get((name, target))
        if rel is None:
            raise MockError("unknown disk target")
        path = root / rel
        allocation = path.stat().st_blocks * 512
        capacity = 8589934592 if "system/" in rel else 134217728 if rel.endswith(".raw") else 2147483648
        return f"Capacity: {capacity}\nAllocation: {allocation}\nPhysical: {allocation}\n"
    raise MockError("command or arguments are not on the read-only allowlist")


def main() -> int:
    args = sys.argv[1:]
    uri = ""
    try:
        if len(args) < 4 or args[0] != "--readonly" or args[1] != "--connect":
            raise MockError("required invocation: virsh --readonly --connect URI COMMAND...")
        uri = args[2]
        root = root_dir()
        result = run(uri, args[3:], root)
        status, error = 0, ""
    except PermissionError as exc:
        status, result, error = 1, "", str(exc)
    except (MockError, OSError, ValueError) as exc:
        status, result, error = 2, "", str(exc)
    log = os.environ.get("VM_MOCK_LOG")
    if log:
        log_path = Path(log).resolve()
        try:
            root = root_dir()
            if root != log_path.parent and root not in log_path.parents:
                raise MockError("VM_MOCK_LOG must be inside VM_MOCK_ROOT")
            with log_path.open("a", encoding="utf-8") as stream:
                stream.write(json.dumps({"connect": uri, "args": args[3:], "readonly": args[:1] == ["--readonly"], "status": status}) + "\n")
        except (MockError, OSError) as exc:
            print(str(exc), file=sys.stderr)
            return 2
    if error:
        print(error, file=sys.stderr)
    else:
        sys.stdout.write(result)
    return status


if __name__ == "__main__":
    raise SystemExit(main())

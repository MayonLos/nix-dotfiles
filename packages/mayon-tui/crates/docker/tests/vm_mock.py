#!/usr/bin/env python3
"""Exercise df VM reporting using only sparse local fixtures and mock virsh.

Usage: python -B packages/mayon-tui/crates/docker/tests/vm_mock.py /path/to/dockertui-mayon
No real Docker or libvirt socket is opened.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

MOCK = Path(__file__).with_name("mock_virsh.py")


def make_file(path: Path, logical_size: int, markers: tuple[int, ...] = (0,)) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as stream:
        stream.truncate(logical_size)
        for offset in markers:
            if offset < logical_size:
                stream.seek(offset)
                stream.write(b"x")


def fixture(root: Path) -> None:
    # Sparse files contain only harmless marker bytes; the mock inspects stat metadata only.
    make_file(root / "session/session-dev.qcow2", 96 * 1024 * 1024)
    make_file(root / "session/tools.iso", 8 * 1024 * 1024)
    make_file(root / "session/raw-data.raw", 128 * 1024 * 1024, (0,))
    make_file(root / "system/base-shared.qcow2", 256 * 1024 * 1024, (0, 128 * 1024 * 1024))
    make_file(root / "system/overlay-a.qcow2", 128 * 1024 * 1024, (0, 64 * 1024 * 1024))
    make_file(root / "system/orphan.qcow2", 64 * 1024 * 1024, (0,))
    make_file(root / "system/installer.iso", 16 * 1024 * 1024, (0,))
    make_file(root / "system/unused-installer.iso", 12 * 1024 * 1024, (0,))
    make_file(root / "system/snapshot-clean-install.qcow2", 32 * 1024 * 1024, (0,))
    make_file(root / "system/snapshot-clean-install-memory", 4 * 1024 * 1024, (0,))
    make_file(root / "system/named-data.qcow2", 48 * 1024 * 1024, (0,))


def run(
    binary: Path,
    root: Path,
    denied: bool,
    chain_unknown: bool = False,
    snapshot_unknown: bool = False,
) -> subprocess.CompletedProcess[str]:
    bindir = root / "bin"
    bindir.mkdir(exist_ok=True)
    virsh = bindir / "virsh"
    if not virsh.exists():
        virsh.symlink_to(MOCK)
    log_name = (
        "virsh-denied.jsonl" if denied else "virsh-snapshot-unknown.jsonl" if snapshot_unknown
        else "virsh-chain-unknown.jsonl" if chain_unknown else "virsh.jsonl"
    )
    log = root / log_name
    env = {
        "PATH": f"{bindir}:{Path(shutil.which('python3') or '/usr/bin/python3').parent}",
        "HOME": str(root / "home"),
        "XDG_RUNTIME_DIR": str(root / "runtime"),
        "DOCKER_HOST": f"unix://{root / 'missing-docker.sock'}",
        "VM_MOCK_ROOT": str(root),
        "VM_MOCK_LOG": str(log),
    }
    if denied:
        env["VM_MOCK_SYSTEM_DENIED"] = "1"
    if chain_unknown:
        env["VM_MOCK_CHAIN_UNKNOWN"] = "1"
    if snapshot_unknown:
        env["VM_MOCK_SNAPSHOT_UNKNOWN"] = "1"
    Path(env["HOME"]).mkdir(exist_ok=True)
    Path(env["XDG_RUNTIME_DIR"]).mkdir(exist_ok=True)
    return subprocess.run([str(binary), "df"], text=True, capture_output=True, env=env, timeout=30)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path, help="built dockertui-mayon executable")
    args = parser.parse_args()
    binary = args.binary.resolve()
    if not binary.is_file():
        parser.error(f"binary does not exist: {binary}")
    repo = Path(__file__).resolve().parents[5]
    work = repo / ".work"
    work.mkdir(exist_ok=True)
    checks = 0
    with tempfile.TemporaryDirectory(prefix="docker-vm-mock-", dir=work) as temporary:
        root = Path(temporary).resolve()
        fixture(root)
        normal = run(binary, root, denied=False)
        checks += 1
        if normal.returncode != 0:
            raise AssertionError(f"df failed: {normal.stderr}\n{normal.stdout}")
        output = normal.stdout
        for phrase in (
            "VM 空间（严格只读）", "qemu:///session", "qemu:///system",
            "session-dev", "system-builder", "base-shared.qcow2", "overlay-a.qcow2",
            "orphan.qcow2", "installer.iso", "snapshot-clean-install.qcow2",
            "snapshot-clean-install-memory", "named-data.qcow2", "占用", "虚拟",
            "raw-data.raw", "虚拟 128.0 MiB", "qcow2 虚拟大小未知：禁止读取镜像头",
        ):
            checks += 1
            if phrase not in output:
                raise AssertionError(f"df output missing {phrase!r}:\n{output}")
        checks += 1
        if f"路径：{root / 'session/raw-data.raw'}" not in output:
            raise AssertionError(f"df output missed the complete raw disk path:\n{output}")
        checks += 1
        if f"路径：{root / 'session/session-dev.qcow2'}" not in output or "虚拟 未知" not in output:
            raise AssertionError(f"qcow2 virtual size should remain unknown without image reads:\n{output}")
        calls = [json.loads(line) for line in (root / "virsh.jsonl").read_text(encoding="utf-8").splitlines()]
        checks += 1
        if not calls or any(call["status"] != 0 for call in calls):
            raise AssertionError(f"normal mock virsh calls failed: {calls}")
        checks += 1
        if any(call.get("readonly") is not True for call in calls):
            raise AssertionError(f"virsh invoked without --readonly: {calls}")
        forbidden = {"domblkinfo", "vol-info", "vol-dumpxml", "qemu-monitor-command"}
        checks += 1
        if any(call["args"] and call["args"][0] in forbidden for call in calls):
            raise AssertionError(f"VM query attempted to probe image metadata: {calls}")

        unknown = run(binary, root, denied=False, chain_unknown=True)
        checks += 1
        if unknown.returncode != 0:
            raise AssertionError(f"df failed with incomplete backing chain: {unknown.stderr}\n{unknown.stdout}")
        checks += 1
        if "未引用待核实" not in unknown.stdout:
            raise AssertionError(f"df did not mark references uncertain when the chain terminator is absent:\n{unknown.stdout}")
        unknown_calls = [json.loads(line) for line in (root / "virsh-chain-unknown.jsonl").read_text(encoding="utf-8").splitlines()]
        checks += 1
        if any(call["args"] and call["args"][0] in forbidden for call in unknown_calls):
            raise AssertionError(f"incomplete-chain scenario probed image metadata: {unknown_calls}")

        snapshot_unknown = run(binary, root, denied=False, snapshot_unknown=True)
        checks += 1
        if snapshot_unknown.returncode != 0:
            raise AssertionError(f"df failed with incomplete snapshot chain: {snapshot_unknown.stderr}\n{snapshot_unknown.stdout}")
        checks += 1
        if "未引用待核实" not in snapshot_unknown.stdout:
            raise AssertionError(f"df did not mark references uncertain when snapshot chain termination is absent:\n{snapshot_unknown.stdout}")
        snapshot_calls = [json.loads(line) for line in (root / "virsh-snapshot-unknown.jsonl").read_text(encoding="utf-8").splitlines()]
        checks += 1
        if any(call["args"] and call["args"][0] in forbidden for call in snapshot_calls):
            raise AssertionError(f"incomplete snapshot-chain scenario probed image metadata: {snapshot_calls}")

        denied = run(binary, root, denied=True)
        checks += 1
        if denied.returncode != 0:
            raise AssertionError(f"df exited on unavailable libvirt connection: {denied.stderr}\n{denied.stdout}")
        for phrase in ("VM 空间（严格只读）", "session-dev", "qemu:///system"):
            checks += 1
            if phrase not in denied.stdout:
                raise AssertionError(f"degraded df output missing {phrase!r}:\n{denied.stdout}")
        checks += 1
        if not any(word in denied.stdout for word in ("权限", "permission", "不可用")):
            raise AssertionError(f"df omitted the inaccessible connection reason:\n{denied.stdout}")
        denied_calls = [json.loads(line) for line in (root / "virsh-denied.jsonl").read_text(encoding="utf-8").splitlines()]
        checks += 1
        if not any(call["status"] != 0 and call["connect"] == "qemu:///system" for call in denied_calls):
            raise AssertionError(f"denied system connection was not recorded: {denied_calls}")
        checks += 1
        if any(call["args"] and call["args"][0] in forbidden for call in denied_calls):
            raise AssertionError(f"degraded connection scenario probed image metadata: {denied_calls}")

    print(f"VM mock df checks passed: {checks}; fixtures were sparse local files; no Docker/libvirt daemon used.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

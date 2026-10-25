#!/usr/bin/env python3
"""Exercise Noctalia 5.3's real template-config CLI with production inputs.

The IPC-only TemplateApplyService has no standalone headless entrypoint. This
projects its enabled builtin entries and buildUserTemplateRoot table into the
same TemplateEngine config CLI, including dynamic outputs and real hooks. It
cannot test service scheduling/state bookkeeping. No GUI/daemon is launched.
"""
import copy
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tomllib

import tomlkit

out = Path(os.environ["out"])
cfg = Path(os.environ["XDG_CONFIG_HOME"])
home = Path.home()
assets = Path(os.environ["NOCTALIA_ASSETS_DIR"]) / "templates"
metadata = json.loads(Path(os.environ["INPUTS"]).read_text())
settings = metadata["templates"]
palette = metadata["palette"]
noctalia = os.environ["NOCTALIA"]
root = tomllib.loads((assets / "builtin.toml").read_text())
assert settings["enable_builtin_templates"]
ids = settings["builtin_ids"]
assert {"gtk3", "gtk4", "qt"} <= set(ids)
# This is the enabledTemplates filter used by TemplateApplyService. No custom
# colors from the main config may be injected into this independent engine.
root["templates"] = {k: v for k, v in root["templates"].items() if k in ids}
assert set(root["templates"]) == set(ids)
assert not root.get("config", {}).get("custom_colors")
catalog = Path(os.environ["TMPDIR"]) / "catalog"
catalog.mkdir()
for child in assets.iterdir():
    if child.name != "builtin.toml":
        (catalog / child.name).symlink_to(child)
(catalog / "builtin.toml").write_text(tomlkit.dumps(root))
(cfg / "noctalia").mkdir()
shutil.copyfile(os.environ["MAIN_CONFIG"], cfg / "noctalia/config.toml")

# Initialized clients + deliberately stale files reproduce the reported update
# failure. The real service creates the GTK extension indices before rendering.
for version in (3, 4):
    directory = cfg / f"gtk-{version}.0"
    directory.mkdir()
    (directory / "noctalia.css").write_text("STALE OLD PALETTE\n")
    (directory / "noctalia-extensions.css").write_text("")
    (directory / "gtk.css").write_text("/* existing user CSS */\n")
for version in (5, 6):
    directory = cfg / f"qt{version}ct/colors"
    directory.mkdir(parents=True)
    (directory / "noctalia.conf").write_text("STALE OLD PALETTE\n")

# Real Firefox profile and registered Obsidian vault fixtures force their
# production hooks/dynamic outputs to run, rather than silently skipping them.
profile_root = cfg / "mozilla/firefox"
profile = profile_root / "runtime.default"
(profile / "chrome").mkdir(parents=True)
(profile_root / "profiles.ini").write_text(
    "[Profile0]\nName=runtime\nIsRelative=1\nPath=runtime.default\nDefault=1\n"
)
vault = home / "Registered Vault"
(vault / ".obsidian").mkdir(parents=True)
(cfg / "obsidian").mkdir()
(cfg / "obsidian/obsidian.json").write_text(json.dumps({"vaults": {"runtime": {"path": str(vault)}}}))


def apply(config, log_name, succeeds=True):
    result = subprocess.run(
        [noctalia, "theme", "--theme-json", os.environ["THEME_JSON"], "--config", str(config)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90,
    )
    (out / log_name).write_text(result.stdout)
    errors = re.search(r"template error|failed to (?:render|apply|resolve)|hook .* failed|error:", result.stdout, re.I)
    if succeeds:
        assert result.returncode == 0 and not errors, result.stdout
    else:
        assert result.returncode != 0 and "template error" in result.stdout, result.stdout
    return result


def verified(path):
    path = Path(path)
    assert path.is_relative_to(cfg) or path.is_relative_to(home) or path.is_relative_to(Path(os.environ["XDG_CACHE_HOME"])), path
    text = path.read_text()
    assert "STALE OLD PALETTE" not in text and "{{" not in text and "}}" not in text, path
    for name in ("bg", "blue", "selection"):
        assert palette[name].lower() in text.lower(), (path, name)
    return str(path)


# Negative control: the pre-fix raw GTK/Qt templates must fail without custom colors,
# leave the old file untouched, and produce a nonzero CLI exit plus error log.
negative = catalog / "negative.toml"
negative.write_text(tomlkit.dumps({"templates": {
    "old-gtk3": {"input_path": os.environ["RAW_GTK3"], "output_path": "$XDG_CONFIG_HOME/gtk-3.0/noctalia.css"},
    "old-gtk4": {"input_path": os.environ["RAW_GTK4"], "output_path": "$XDG_CONFIG_HOME/gtk-4.0/noctalia.css"},
    "old-qt": {"input_path": os.environ["RAW_QT"], "output_path": [
        "$XDG_CONFIG_HOME/qt5ct/colors/noctalia.conf", "$XDG_CONFIG_HOME/qt6ct/colors/noctalia.conf",
    ]},
}}))
negative_result = apply(negative, "negative-control.log", succeeds=False)
assert negative_result.stdout.count("template error(s); output not written") == 4
for path in [cfg / "gtk-3.0/noctalia.css", cfg / "gtk-4.0/noctalia.css", cfg / "qt5ct/colors/noctalia.conf", cfg / "qt6ct/colors/noctalia.conf"]:
    assert path.read_text() == "STALE OLD PALETTE\n"

apply(catalog / "builtin.toml", "builtin-apply.log")
builtin_outputs = []
for version in (3, 4):
    directory = cfg / f"gtk-{version}.0"
    builtin_outputs.append(verified(directory / "noctalia.css"))
    text = (directory / "gtk.css").read_text()
    assert '/* existing user CSS */' in text and '@import url("noctalia.css");' in text
for version in (5, 6):
    builtin_outputs.append(verified(cfg / f"qt{version}ct/colors/noctalia.conf"))

# buildUserTemplateRoot (template_apply_service.cpp:78-154): custom colors only
# enter this separate table; disabled user entries are omitted. Preserve every
# configured input/output/dynamic command/hook, rather than cherry-picking files.
user = {name: copy.deepcopy(entry) for name, entry in settings.get("user", {}).items() if entry.get("enabled", True)}
assert user, "No configured user templates exercised"
user_root = {"config": {"custom_colors": settings.get("custom_colors", {})}, "templates": user}
# A non-.toml suffix avoids ConfigService auto-loading the test projection as
# a second main configuration fragment. The directory matches service config_dir.
user_config = cfg / "noctalia/user-templates.fixture"
user_config.write_text(tomlkit.dumps(user_root))
expected = {}
for name, entry in user.items():
    paths = entry.get("output_path", [])
    if isinstance(paths, str):
        paths = [paths]
    if entry.get("output_path_dynamic"):
        command = entry["output_path_dynamic"]
        # Current production command has no template expressions. Force future
        # additions to provide an explicit fixture instead of skipping coverage.
        assert "{{" not in command, (name, "dynamic command needs a fixture")
        result = subprocess.run(["bash", "-c", command], check=True, text=True, stdout=subprocess.PIPE, timeout=30)
        paths += result.stdout.splitlines()
    assert paths, (name, "no output targets; add a fixture")
    expected[name] = [os.path.expandvars(os.path.expanduser(p)) for p in paths]
apply(user_config, "user-apply.log")
coverage = {name: [verified(path) for path in paths] for name, paths in expected.items()}
# Assert hook effects too: the CLI can otherwise silently ignore hook-render
# errors. Future feature hooks need a corresponding side-effect fixture here.
assert set(user) == {"documents-zathura", "documents-obsidian", "noctalia-firefox"}, "Add hook/output fixtures for new user templates"
verified(profile / "chrome/userChrome.css")
verified(profile / "chrome/userContent.css")
assert "noctalia" in json.loads((vault / ".obsidian/appearance.json").read_text())["enabledCssSnippets"]

# All successful logs must stay free of template errors even when values did not
# change on a second apply. Preserve production hooks and configured list order.
apply(catalog / "builtin.toml", "builtin-repeat.log")
apply(user_config, "user-repeat.log")
shutil.copytree(cfg, out / "config")
shutil.copytree(vault, out / "registered-vault")
shutil.copytree(Path(os.environ["XDG_CACHE_HOME"]) / "noctalia/firefox", out / "firefox")

# Retaining builtin IDs also retains upstream undo hooks; run the real scripts
# against only this private fixture, checking import removal and user CSS retention.
for name in ("gtk3", "gtk4", "qt"):
    hook = root["templates"][name]["undo_hook"].replace("{{ config_dir }}", str(catalog))
    assert "{{" not in hook
    result = subprocess.run(["bash", "-c", hook], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    (out / f"undo-{name}.log").write_text(result.stdout)
    assert result.returncode == 0, result.stdout
for version in (3, 4):
    directory = cfg / f"gtk-{version}.0"
    assert not (directory / "noctalia.css").exists()
    text = (directory / "gtk.css").read_text()
    assert "existing user CSS" in text and 'noctalia.css' not in text
for version in (5, 6):
    assert not (cfg / f"qt{version}ct/colors/noctalia.conf").exists()
(out / "coverage.json").write_text(json.dumps({
    "builtin_ids": ids, "builtin_outputs": builtin_outputs, "user_outputs": coverage,
    "engine": "locked Noctalia theme --config; no service/GUI", "undo_hooks": ["gtk3", "gtk4", "qt"],
}, indent=2) + "\n")
print("Template CLI integration: four GTK/Qt outputs, all user outputs/hooks, repeated apply and builtin undo passed")

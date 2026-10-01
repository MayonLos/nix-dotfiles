{ lib, pkgs, ... }:

let
  firefoxChrome = ./_firefox/userChrome.css;
in
{
  home.activation.seedFirefoxProfileUi = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.python3}/bin/python3 - ${firefoxChrome} <<'PY'
    import configparser
    import os
    import re
    from pathlib import Path
    import sys
    import tempfile

    style_source = Path(sys.argv[1])
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
    profile_root = config_home / "mozilla" / "firefox"
    profiles_ini = profile_root / "profiles.ini"
    if not profiles_ini.is_file():
        print(f"Firefox profile not initialized at {profiles_ini}; skipping UI seed until a later activation")
        raise SystemExit(0)

    ini = configparser.ConfigParser(interpolation=None)
    ini.read(profiles_ini)
    sections = ini.sections()
    install_default = next(
        (ini[s].get("Default") for s in sections if s.startswith("Install") and ini[s].get("Default")),
        None,
    )
    selected = None
    if install_default:
        selected = next(
            (ini[s] for s in sections if s.startswith("Profile") and ini[s].get("Path") == install_default),
            None,
        )
    if selected is None:
        selected = next(
            (ini[s] for s in sections if s.startswith("Profile") and ini[s].getboolean("Default", fallback=False)),
            None,
        )
    if selected is None:
        raise SystemExit(f"No default Firefox profile found in {profiles_ini}")

    profile_path = Path(selected["Path"])
    if selected.getboolean("IsRelative", fallback=True):
        profile_path = profile_root / profile_path
    profile_path = profile_path.expanduser().resolve()
    if not profile_path.is_dir():
        raise SystemExit(f"Firefox default profile does not exist: {profile_path}")

    def replace_managed_block(path, begin, end, content):
        if path.is_symlink() or path.parent.is_symlink():
            raise SystemExit(f"Refusing to modify symlinked Firefox config: {path}")
        old = path.read_text() if path.exists() else ""
        if (begin in old) != (end in old):
            raise SystemExit(f"Incomplete managed markers in {path}; preserving the file")
        block = f"{begin}\n{content.rstrip()}\n{end}"
        if begin in old:
            start = old.index(begin)
            finish = old.index(end, start) + len(end)
            new = old[:start] + block + old[finish:]
        else:
            new = old.rstrip() + ("\n\n" if old.strip() else "") + block + "\n"
        if new == old:
            return
        path.parent.mkdir(parents=True, exist_ok=True)
        mode = path.stat().st_mode & 0o777 if path.exists() else 0o644
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as out:
            out.write(new)
            temp_path = Path(out.name)
        temp_path.chmod(mode)
        temp_path.replace(path)

    user_prefs = "\n".join(
        [
            'user_pref("sidebar.revamp", true);',
            'user_pref("sidebar.verticalTabs", true);',
            'user_pref("sidebar.visibility", "always-show");',
            # Override Firefox's persisted open launcher state on every start.
            'user_pref("sidebar.backupState", "{\\"launcherExpanded\\":false,\\"launcherVisible\\":true,\\"panelOpen\\":false}");',
            'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);',
            'user_pref("browser.ctrlTab.sortByRecentlyUsed", true);',
            'user_pref("findbar.highlightAll", true);',
            'user_pref("browser.tabs.splitView.enabled", true);',
        ]
    )
    replace_managed_block(
        profile_path / "user.js",
        "// BEGIN nix-dotfiles managed Firefox UI",
        "// END nix-dotfiles managed Firefox UI",
        user_prefs,
    )
    rendered_theme = (
        Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")))
        / "noctalia"
        / "firefox"
        / "userChrome.css"
    )
    theme_css = style_source.read_text()
    if rendered_theme.is_file():
        candidate = rendered_theme.read_text()
        if "{{" not in candidate and "}}" not in candidate:
            # Keep the rendered palette, but always install the current CSS
            # structure. Noctalia's cache may predate this system generation.
            for name, value in re.findall(r"(--tn-[a-z-]+):\s*(#[0-9a-fA-F]{6});", candidate):
                theme_css = re.sub(
                    rf"({re.escape(name)}:)\s*#[0-9a-fA-F]{{6}};",
                    rf"\g<1> {value};",
                    theme_css,
                )

    replace_managed_block(
        profile_path / "chrome" / "userChrome.css",
        "/* BEGIN nix-dotfiles managed Firefox theme */",
        "/* END nix-dotfiles managed Firefox theme */",
        theme_css,
    )
    print(f"Ensured managed Firefox UI settings in {profile_path}")
    PY
  '';
}

{
  pkgs,
  lib,
  home,
  nixos,
  ...
}:
let
  fileManager = import ./packages.nix { inherit pkgs; };
  actions = home.home.file.".config/Thunar/uca.xml".text;
  actionsFile = pkgs.writeText "thunar-uca.xml" actions;
  templateActivation = pkgs.writeText "thunar-template-activation.sh" ''
    run() { "$@"; }
    ${home.home.activation.seedThunarTemplates.data}
  '';
  mimeDefaults = home.xdg.mimeApps.defaultApplications or { };
  serviceFile = "${fileManager.thunarWithPlugins}/share/dbus-1/services/org.freedesktop.FileManager1.service";
  archivePlugin = builtins.head fileManager.plugins;
in
assert !(builtins.elem fileManager.thunarWithPlugins home.home.packages);
assert builtins.elem fileManager.thunarWithPlugins nixos.environment.systemPackages;
assert builtins.elem fileManager.thunarWithPlugins nixos.services.dbus.packages;
assert builtins.elem fileManager.thunarWithPlugins nixos.systemd.packages;
assert nixos.programs.xfconf.enable;
assert !(home.xdg.dataFile ? "dbus-1/services/org.freedesktop.FileManager1.service");
{

  file-manager-actions =
    pkgs.runCommand "file-manager-actions-check"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.bash
          pkgs.coreutils
          pkgs.gnugrep
        ];
      }
      ''
        python3 - <<'PY'
        import xml.etree.ElementTree as ET
        import os
        import shlex
        from pathlib import Path
        root = ET.parse("${actionsFile}").getroot()
        actions = {item.findtext("name"): item for item in root.findall("action")}
        expected = {
            "Open Terminal Here", "Open in Neovim", "Open herdr Here",
            "Open lazygit Here", "Set as Wallpaper", "Copy as Image",
            "Copy Path", "Paste Clipboard Image", "Paste as Link",
        }
        assert expected <= actions.keys(), expected - actions.keys()
        commands = {name: item.findtext("command") for name, item in actions.items()}
        assert "exo-open" not in " ".join(commands.values())
        for name, command in commands.items():
            executable = shlex.split(command)[0]
            assert executable.startswith("/nix/store/"), (name, executable)
            assert Path(executable).is_file() and os.access(executable, os.X_OK), (name, executable)
        for path in """${
          builtins.concatStringsSep "\n" [
            "${home.home.sessionVariables.TERMINAL}"
            "${home.home.sessionVariables.EDITOR}"
            "${pkgs.coreutils}/bin/dirname"
            "${pkgs.coreutils}/bin/install"
            "${pkgs.file}/bin/file"
            "${pkgs.imagemagick}/bin/magick"
            "${pkgs.wl-clipboard}/bin/wl-copy"
            "${pkgs.wl-clipboard}/bin/wl-paste"
            "${pkgs.xclip}/bin/xclip"
            "${pkgs.gnugrep}/bin/grep"
            "${pkgs.python3}/bin/python3"
            "${pkgs.libnotify}/bin/notify-send"
            "${pkgs.kitty}/bin/kitty"
            "${pkgs.local.herdr}/bin/herdr"
            "${pkgs.lazygit}/bin/lazygit"
            "${pkgs.feh}/bin/feh"
            "${home.programs.noctalia.package}/bin/noctalia"
            "${pkgs.file-roller}/bin/file-roller"
          ]
        }""".splitlines():
            assert Path(path).is_file() and os.access(path, os.X_OK), path
        wallpaper = Path(shlex.split(commands["Set as Wallpaper"])[0]).read_text()
        assert "wallpaper-set" in wallpaper
        PY

        test '${builtins.head mimeDefaults."application/pdf"}' = 'org.pwmt.zathura-pdf-mupdf.desktop'
        test '${builtins.head mimeDefaults."inode/directory"}' = 'thunar.desktop'
        ! printf '%s\n' '${builtins.toJSON mimeDefaults}' | grep -qi okular

        fixture="$TMPDIR/templates-home"
        mkdir -p "$fixture"
        export HOME="$fixture"
        bash -e ${templateActivation}
        for name in blank.txt blank.md blank.py blank.sh blank.lua blank.nix; do
          test -f "$HOME/Templates/$name"
          test ! -s "$HOME/Templates/$name"
        done
        printf 'user content\n' > "$HOME/Templates/blank.txt"
        bash -e ${templateActivation}
        grep -qx 'user content' "$HOME/Templates/blank.txt"
        mkdir "$TMPDIR/user-templates"
        mv "$HOME/Templates" "$HOME/Templates-seeded"
        ln -s "$TMPDIR/user-templates" "$HOME/Templates"
        bash -e ${templateActivation}
        test -L "$HOME/Templates"
        test -z "$(ls -A "$TMPDIR/user-templates")"
        touch "$out"
      '';

  file-manager-dbus = pkgs.runCommand "file-manager-dbus-check" { } ''
    test -x ${fileManager.thunarWithPlugins}/bin/Thunar
    test -x ${fileManager.thunarWithPlugins}/bin/thunar-settings
    test ! -e ${fileManager.thunarWithPlugins}/lib/thunarx-3/thunar-wallpaper-plugin.so
    for app in thunar thunar-settings; do
      grep -F 'if [ "''${LANGUAGE+x}" != x ]; then' \
        ${fileManager.thunarWithPlugins}/bin/$app
      grep -F 'export LANGUAGE="zh_CN:en_US"' ${fileManager.thunarWithPlugins}/bin/$app
      grep -F 'export LC_MESSAGES="zh_CN.UTF-8"' ${fileManager.thunarWithPlugins}/bin/$app
      ! grep -F 'LC_ALL=' ${fileManager.thunarWithPlugins}/bin/$app
    done
    grep -Fx 'Name=org.freedesktop.FileManager1' ${serviceFile}
    grep -Fx 'Exec=${fileManager.thunarWithPlugins}/bin/Thunar --gapplication-service' ${serviceFile}
    grep -Fx 'SystemdService=thunar.service' ${serviceFile}
    grep -Fx 'ExecStart=${fileManager.thunarWithPlugins}/bin/Thunar --daemon' \
      ${fileManager.thunarWithPlugins}/lib/systemd/user/thunar.service
    test -f ${archivePlugin}/libexec/thunar-archive-plugin/file-roller.tap
    grep -F '${pkgs.file-roller}/bin/file-roller' \
      ${archivePlugin}/libexec/thunar-archive-plugin/file-roller.tap
    touch "$out"
  '';
}

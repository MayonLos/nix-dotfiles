{ pkgs, home, ... }:
let
  configText = home.xdg.configFile."swayimg/config".text;
in
{
  swayimg-image-viewer =
    pkgs.runCommand "swayimg-image-viewer-check"
      {
        nativeBuildInputs = [
          pkgs.swayimg
          pkgs.python3
        ];
      }
      ''
        cat > swayimg.ini <<'INI'
        ${configText}
        INI
        swayimg --version > version.txt
        python3 - <<'PY'
        import configparser
        import os
        import shlex

        parser = configparser.ConfigParser(interpolation=None)
        parser.read("swayimg.ini")
        assert parser["list"].get("fsmon") == "yes"
        expected = {
            "info": {"show": "yes", "info_timeout": "0"},
            "info.viewer": {
                "top_left": "none",
                "top_right": "none",
                "bottom_left": "name,imagesize,scale",
                "bottom_right": "index",
            },
            "keys.viewer": {
                "r": "rotate_right",
                "shift+r": "rotate_left",
                "f": "zoom fit",
                "1": "zoom real",
            },
            "keys.gallery": {
                "delete": "none",
                "shift+delete": "none",
                "d": "none",
            },
        }
        for section, options in expected.items():
            assert section in parser, f"missing [{section}]"
            for key, value in options.items():
                actual = parser[section].get(key)
                assert actual == value, f"[{section}] {key}: {actual!r} != {value!r}"

        delete_action = parser["keys.viewer"].get("delete", "")
        assert "swayimg-trash" in delete_action and "%q" in delete_action, delete_action
        for key in ("delete", "ctrl+c", "ctrl+g"):
            argv = shlex.split(parser["keys.viewer"][key].removeprefix("exec "))
            assert len(argv) == 2 and argv[1] == "%q", argv
            assert os.path.isabs(argv[0]) and os.access(argv[0], os.X_OK), argv[0]

        copy_helper = shlex.split(parser["keys.viewer"]["ctrl+c"].removeprefix("exec "))[0]
        with open(copy_helper, encoding="utf-8") as helper:
            copy_script = helper.read()
        assert '"''${image}[0]"' in copy_script, "copy action must select only the first animation frame"
        assert "set -o pipefail" in copy_script, "copy action must propagate decoder/clipboard pipe failures"

        with open("version.txt", encoding="utf-8") as source:
            version = source.read().lower()
        for image_format in ("gif", "webp", "heif", "avif", "jxl"):
            assert image_format in version, f"locked swayimg build lacks {image_format}: {version}"

        viewer_keys = parser["keys.viewer"]
        assert "swayimg-copy-image" in viewer_keys.get("ctrl+c", "")
        assert "swayimg-open-in-gimp" in viewer_keys.get("ctrl+g", "")
        assert "%q" in viewer_keys["ctrl+c"] and "%q" in viewer_keys["ctrl+g"]
        PY
        touch "$out"
      '';

  swayimg-shell-escaping =
    pkgs.runCommand "swayimg-shell-escaping-check"
      {
        nativeBuildInputs = [
          pkgs.stdenv.cc
          pkgs.patch
          pkgs.bash
        ];
        upstreamSource = pkgs.swayimg.src;
      }
      ''
        cp -R "$upstreamSource" source
        chmod -R u+w source
        cd source
        patch -p1 < ${./resources/swayimg-shellcmd-safe-path.patch}
        cc -ffunction-sections -fdata-sections -Wl,--gc-sections \
          -I src ${./resources/swayimg-shellcmd-check.c} src/shellcmd.c src/array.c \
          -o shellcmd-check
        marker="$TMPDIR/swayimg-shellcmd-injection-marker"
        SHELL=${pkgs.bash}/bin/bash ./shellcmd-check "$marker"
        test ! -e "$marker"
        touch "$out"
      '';
}

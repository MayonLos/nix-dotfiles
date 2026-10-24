{ pkgs, home }:
let
  python = pkgs.python3.withPackages (p: [ p.pyyaml ]);
  rime = builtins.head (
    builtins.filter (p: pkgs.lib.getName p == "fcitx5-rime") home.i18n.inputMethod.fcitx5.addons
  );
  inherit (rime) engine;
  theme = home.xdg.dataFile."fcitx5/themes/One-Dark-Darker".source;
  files = [
    "default.custom.yaml"
    "rime_ice.custom.yaml"
    "rime_ice_technical.dict.yaml"
    "nixdotfiles_technical.dict.yaml"
  ];
in
pkgs.runCommand "rime-technical-runtime"
  {
    nativeBuildInputs = [
      pkgs.stdenv.cc
      python
      pkgs.binutils
    ];
    buildInputs = [ engine ];
  }
  ''
    export HOME="$TMPDIR/home" XDG_DATA_HOME="$TMPDIR/data"
    mkdir -p "$HOME" "$XDG_DATA_HOME" "$TMPDIR/rime" "$out"
    ${pkgs.lib.concatMapStringsSep "\n" (name: ''
      cp ${home.xdg.dataFile."fcitx5/rime/${name}".source} "$TMPDIR/rime/${name}"
    '') files}
    # Both plugins are merged into this library by the pinned nixpkgs recipe.
    find ${engine}/lib -name '*.so*' > "$out/libraries.log"
    nm -D ${engine}/lib/librime.so > "$out/symbols.log"
    grep 'rime_require_module_lua' "$out/symbols.log"
    grep 'rime_require_module_octagram' "$out/symbols.log"
    test -L ${rime}/share/rime-data/wanxiang-lts-zh-hans.gram
    test "$(stat -Lc %s ${rime}/share/rime-data/wanxiang-lts-zh-hans.gram)" = 398497836
    echo '9eedac1d836f3fdafb61b162035c8937253aedc106be40b2b957d9ab64e9ed89  ${rime}/share/rime-data/wanxiang-lts-zh-hans.gram' | sha256sum -c - > "$out/model.log"
    cc -Wall -Wextra -Werror -I${engine}/include ${./resources/rime-smoke.c} \
      -L${engine}/lib -Wl,-rpath,${engine}/lib -lrime -o "$TMPDIR/rime-smoke"
    "$TMPDIR/rime-smoke" ${rime}/share/rime-data "$TMPDIR/rime" \
      nihao 你好 shurufa 输入法 \
      shengmingshipeizhi 声明式配置 kefuxiangoujian 可复现构建 \
      zhongzishuyun 中子输运 hongshizhongjiqi 红石中继器 \
      zhognzi 中子 hello hello > "$out/candidates.log" 2> "$out/deploy.log" \
      || { cat "$out/candidates.log" "$out/deploy.log"; exit 1; }
    grep -F 'loading gram db: ${rime}/share/rime-data/wanxiang-lts-zh-hans.gram' "$out/deploy.log"
    grep -F 'found double array image of size' "$out/deploy.log"
    if grep -Ei 'error|failed|cannot|could not' "$out/deploy.log"; then exit 1; fi
    python3 - "$TMPDIR/rime" ${theme} <<'PY'
    import configparser, pathlib, sys, yaml
    user = pathlib.Path(sys.argv[1])
    schema = yaml.safe_load((user / "build/rime_ice.schema.yaml").read_text())
    translator = schema["translator"]
    assert translator["dictionary"] == "rime_ice_technical"
    assert translator["user_dict"] == "rime_ice"
    assert translator["enable_user_dict"] and translator["enable_sentence"]
    assert translator["contextual_suggestions"] is True
    assert translator["max_homophones"] == 4
    assert translator["max_homographs"] == 2
    assert schema["grammar"]["language"] == "wanxiang-lts-zh-hans"
    assert schema["grammar"]["collocation_max_length"] == 5
    default = yaml.safe_load((user / "build/default.yaml").read_text())
    assert default["menu"]["page_size"] == 7
    theme = pathlib.Path(sys.argv[2])
    panel = configparser.ConfigParser()
    panel.read(theme / "theme.conf")
    # These are the public roles in the One Dark Darker palette consumed here.
    assert panel["InputPanel"]["highlightcandidatecolor"] == "#4fa6ed"
    assert panel["InputPanel"]["highlightbackgroundcolor"] == "#30363f"
    assert panel["InputPanel"]["candidatelabelcolor"] == "#7a818e"
    assert panel["InputPanel"]["candidatecommentcolor"] == "#7a818e"
    assert panel["InputPanel"]["fullwidthhighlight"] == "False"
    assert panel["InputPanel/Background/Margin"]["left"] == "12"
    assert panel["InputPanel/ContentMargin"]["left"] == "8"
    assert panel["InputPanel/TextMargin"]["left"] == "12"
    assert panel["InputPanel/PrevPage/ClickMargin"]["top"] == "6"
    assert panel["InputPanel/NextPage/ClickMargin"]["top"] == "6"
    images = [s["image"] for s in panel.values() if "image" in s]
    assert len(images) == 8
    assert set(images) == {"panel.svg", "highlight.svg", "prev.svg", "next.svg", "radio.svg", "arrow.svg"}
    assert all((theme / image).is_file() for image in images)
    selected = (theme / "highlight.svg").read_text()
    assert 'rx="7.5"' in selected and 'fill="#30363f"' in selected
    assert 'stroke="#4fa6ed"' in selected
    for name in ("prev.svg", "next.svg"):
        icon = (theme / name).read_text()
        assert 'width="20" height="20"' in icon and 'stroke-width="2"' in icon
    assert schema["reduce_english_filter"]["mode"] == "all"
    assert translator["always_show_comments"] and translator["spelling_hints"] == 8
    assert (user / "rime_ice.userdb").is_dir()
    assert not (user / "rime_ice_technical.userdb").exists()
    PY
  ''

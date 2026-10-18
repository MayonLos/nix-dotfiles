{ pkgs, home }:
let
  python = pkgs.python3.withPackages (p: [ p.pyyaml ]);
  rime = builtins.head (
    builtins.filter (p: pkgs.lib.getName p == "fcitx5-rime") home.i18n.inputMethod.fcitx5.addons
  );
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
    ];
    buildInputs = [ pkgs.librime ];
  }
  ''
    export HOME="$TMPDIR/home" XDG_DATA_HOME="$TMPDIR/data"
    mkdir -p "$HOME" "$XDG_DATA_HOME" "$TMPDIR/rime" "$out"
    ${pkgs.lib.concatMapStringsSep "\n" (name: ''
      cp ${home.xdg.dataFile."fcitx5/rime/${name}".source} "$TMPDIR/rime/${name}"
    '') files}
    cc -Wall -Wextra -Werror -I${pkgs.librime}/include ${./resources/rime-smoke.c} \
      -L${pkgs.librime}/lib -Wl,-rpath,${pkgs.librime}/lib -lrime -o "$TMPDIR/rime-smoke"
    "$TMPDIR/rime-smoke" ${rime}/share/rime-data "$TMPDIR/rime" \
      nihao 你好 shurufa 输入法 \
      shengmingshipeizhi 声明式配置 kefuxiangoujian 可复现构建 \
      zhongzishuyun 中子输运 hongshizhongjiqi 红石中继器 \
      zhognzi 中子 hello hello > "$out/candidates.log" 2> "$out/deploy.log" \
      || { cat "$out/candidates.log" "$out/deploy.log"; exit 1; }
    python3 - "$TMPDIR/rime" <<'PY'
    import pathlib, sys, yaml
    user = pathlib.Path(sys.argv[1])
    schema = yaml.safe_load((user / "build/rime_ice.schema.yaml").read_text())
    translator = schema["translator"]
    assert translator["dictionary"] == "rime_ice_technical"
    assert translator["user_dict"] == "rime_ice"
    assert translator["enable_user_dict"] and translator["enable_sentence"]
    assert schema["reduce_english_filter"]["mode"] == "all"
    assert translator["always_show_comments"] and translator["spelling_hints"] == 8
    assert (user / "rime_ice.userdb").is_dir()
    assert not (user / "rime_ice_technical.userdb").exists()
    PY
  ''

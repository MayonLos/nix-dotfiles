{ pkgs, lib, ... }:
let
  # nixpkgs 的 JetBrains 2026.2 包里 lib/skiko-awt-runtime-all/libskiko-linux-x64.so
  # 的 RPATH 被 autoPatchelf 写成了构建目录 /build/...，运行时解析不到
  # libGL/libX11/libfontconfig/libstdc++。Compose 渲染器加载失败后欢迎界面一直转圈、
  # 点击无响应。上游的 extraLdPath 参数走 extendMkDerivation，overrideAttrs 传不进去,
  # 所以在包外面再套一层 wrapper 把这几个库补进 LD_LIBRARY_PATH。
  skikoLibs = with pkgs; [
    libGL
    libx11
    fontconfig
    stdenv.cc.cc.lib
  ];

  fixSkiko =
    ide:
    pkgs.symlinkJoin {
      name = "${ide.pname}-${ide.version}-skiko-fix";
      paths = [ ide ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        # buildEnv 只有一个输入时会把 $out/bin 直接软链到原包，先展开成真实目录
        if [ -L "$out/bin" ]; then
          target=$(readlink -f "$out/bin")
          rm "$out/bin"
          mkdir "$out/bin"
          ln -s "$target"/* "$out/bin/"
        fi
        wrapProgram "$out/bin/${ide.meta.mainProgram}" \
          --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath skikoLibs}"
      '';
      inherit (ide) meta;
    };
in
{
  home.packages = map fixSkiko (
    with pkgs.jetbrains;
    [
      idea
      pycharm
      clion
      webstorm
      datagrip
      rust-rover
    ]
  );
}

{ pkgs }:
let
  # Keep the locked binary/ABI; patch only its DAP Python data, with a checked
  # source hunk. Remote disconnect(false) must detach instead of killing.
  gdbData = pkgs.runCommand "nvim-gdb-dap-data" { nativeBuildInputs = [ pkgs.patch ]; } ''
    mkdir -p "$out"
    cp -rs ${pkgs.gdb}/share/gdb/. "$out/"
    chmod -R u+w "$out"
    rm "$out/python/gdb/dap/server.py"
    cp ${pkgs.gdb}/share/gdb/python/gdb/dap/server.py "$out/python/gdb/dap/server.py"
    chmod u+w "$out/python/gdb/dap/server.py"
    patch --directory="$out" -p1 < ${./patches/gdb-dap-detach.patch}
  '';
  gdb = pkgs.writeShellScriptBin "gdb" ''
    exec ${pkgs.gdb}/bin/gdb --data-directory=${gdbData} "$@"
  '';
  python = pkgs.python3.withPackages (ps: [ ps.debugpy ]);
  codelldb = pkgs.vscode-extensions.vadimcn.vscode-lldb.adapter;
  extensions = pkgs.vscode-extensions.vscjava;
  bundles = pkgs.runCommand "nvim-java-debug-bundles" { } ''
    mkdir -p "$out"
    echo 'return {' > "$out/bundles.lua"
    for jar in ${extensions.vscode-java-debug}/share/vscode/extensions/vscjava.vscode-java-debug/server/*.jar \
               ${extensions.vscode-java-test}/share/vscode/extensions/vscjava.vscode-java-test/server/*.jar; do
      test -f "$jar"
      case "$(basename "$jar")" in
        com.microsoft.java.test.runner-jar-with-dependencies.jar|jacocoagent.jar) continue ;;
      esac
      printf '  [=[%s]=],\n' "$jar" >> "$out/bundles.lua"
    done
    echo '}' >> "$out/bundles.lua"
  '';
in
{
  tools = {
    gdb = "${gdb}/bin/gdb";
    codelldb = "${codelldb}/bin/codelldb";
    debugpy_python = "${python}/bin/python3";
    python = "${pkgs.python3}/bin/python3";
    java_debug_manifest = "${bundles}/bundles.lua";
    jdtls = "${pkgs.jdt-language-server}/bin/jdtls";
    java = "${pkgs.jdk}/bin/java";
  };
  versions = {
    gdb = pkgs.gdb.version;
    codelldb = codelldb.version;
    debugpy = pkgs.python3Packages.debugpy.version;
    java_debug = extensions.vscode-java-debug.version;
    java_test = extensions.vscode-java-test.version;
    jdtls = pkgs.jdt-language-server.version;
  };
}

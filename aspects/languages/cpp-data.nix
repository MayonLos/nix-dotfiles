{
  id = "cpp";
  neovim.servers.clangd = {
    cmd = [
      "clangd"
      "--background-index"
      "--clang-tidy"
    ];
    filetypes = [
      "c"
      "cpp"
      "objc"
      "objcpp"
      "cuda"
    ];
    root_markers = [
      "compile_commands.json"
      ".clangd"
      "CMakeLists.txt"
      ".git"
    ];
  };
}

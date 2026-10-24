{ pkgs }:

let
  grammarNames = [
    "c"
    "cpp"
    "cuda"
    "python"
    "nix"
    "lua"
    "luadoc"
    "vim"
    "vimdoc"
    "html"
    "markdown"
    "markdown_inline"
    "bash"
    "java"
    "matlab"
    "latex"
    "bibtex"
    "yaml"
    "json"
    "toml"
    "kdl"
    "gitcommit"
    "diff"
    "regex"
    "query"
    "css"
    "javascript"
    "scss"
    "svelte"
    "tsx"
    "typst"
    "vue"
  ];

  treesitter = pkgs.vimPlugins.nvim-treesitter;
  grammars = map (name: treesitter.builtGrammars.${name}) grammarNames;

  # The stable nixpkgs override turns each selected grammar into a plugin,
  # adds its declared parser dependencies, and includes its associated query
  # resources as dependency plugins. Keep that pinned package implementation.
  plugin = treesitter.withPlugins (_: grammars);
  queryNames = builtins.filter (name: builtins.hasAttr name treesitter.queries) grammarNames;
  queries = map (name: treesitter.queries.${name}) queryNames;
in
{
  inherit
    grammarNames
    grammars
    plugin
    queries
    ;
}

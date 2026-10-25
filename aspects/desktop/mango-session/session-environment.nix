{ lib }:
variables:
lib.filterAttrs (
  name: value:
  (
    builtins.elem name [
      "NIXOS_OZONE_WL"
      "_JAVA_AWT_WM_NONREPARENTING"
      "QT_QPA_PLATFORMTHEME"
      "QT_PLUGIN_PATH"
      "GTK_USE_PORTAL"
      "GTK_PATH"
      "GLFW_IM_MODULE"
      "SDL_IM_MODULE"
      "XMODIFIERS"
      "XCURSOR_THEME"
      "XCURSOR_SIZE"
      "JAVA_HOME"
      "TERMINAL"
      "EDITOR"
      "VISUAL"
      "BROWSER"
      "NVIM_CODEX_ACP"
      "NVIM_CLAUDE_ACP"
    ]
    || builtins.match "JAVA[0-9]+_HOME" name != null
  )
  && builtins.isString value
  && !(lib.hasInfix "$" value)
) variables

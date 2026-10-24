{ pkgs, palette }:
let
  hexToRgb =
    color:
    let
      hex = builtins.substring 1 6 color;
    in
    builtins.concatStringsSep ", " (
      map (offset: toString (pkgs.lib.fromHexString (builtins.substring offset 2 hex))) [
        0
        2
        4
      ]
    );
  selectionRgb = hexToRgb palette.selection;
in
{
  zathura = pkgs.writeText "documents-zathura-palette" ''
    set default-bg "${palette.bg}"
    set default-fg "${palette.brightFg}"
    set recolor-lightcolor "${palette.bg}"
    set recolor-darkcolor "${palette.brightFg}"

    set statusbar-bg "${palette.surface}"
    set statusbar-fg "${palette.brightFg}"
    set inputbar-bg "${palette.deep}"
    set inputbar-fg "${palette.brightFg}"

    set notification-bg "${palette.surface}"
    set notification-fg "${palette.brightFg}"
    set notification-error-bg "${palette.surface}"
    set notification-error-fg "${palette.brightFg}"
    set notification-warning-bg "${palette.surface}"
    set notification-warning-fg "${palette.brightFg}"

    set index-bg "${palette.deep}"
    set index-fg "${palette.fg}"
    set index-active-bg "${palette.selection}"
    set index-active-fg "${palette.brightFg}"
    set highlight-color "${palette.selection}"
    set highlight-active-color "${palette.selection}"
    set highlight-fg "${palette.brightFg}"

    set completion-bg "${palette.deep}"
    set completion-fg "${palette.brightFg}"
    set completion-group-bg "${palette.deep}"
    set completion-group-fg "${palette.blue}"
    set completion-highlight-fg "${palette.brightFg}"
    set completion-highlight-bg "${palette.selection}"
  '';

  obsidian = pkgs.writeText "documents-obsidian-palette.css" ''
    /* Feature-owned One Dark palette for registered Obsidian vaults. */
    .theme-dark {
      --background-primary: ${palette.bg};
      --background-primary-alt: ${palette.deep};
      --background-secondary: ${palette.deep};
      --background-secondary-alt: ${palette.surface};
      --background-modifier-border: ${palette.border};
      --background-modifier-hover: ${palette.selection};
      --background-modifier-active-hover: ${palette.selection};
      --background-modifier-box-shadow: ${palette.black};
      --background-modifier-cover: ${palette.black};
      --background-modifier-form-field: ${palette.deep};
      --background-modifier-form-field-highlighted: ${palette.selection};

      --text-normal: ${palette.brightFg};
      --text-muted: ${palette.fg};
      --text-faint: ${palette.fg};
      --text-accent: ${palette.blue};
      --text-on-accent: ${palette.brightFg};
      --text-selection: ${palette.selection};
      --text-highlight-bg: ${palette.selection};
      --text-error: ${palette.brightFg};
      --text-success: ${palette.green};

      --interactive-normal: ${palette.surface};
      --interactive-hover: ${palette.selection};
      --interactive-accent: ${palette.selection};
      --interactive-accent-hover: ${palette.selection};
      --interactive-accent-rgb: ${selectionRgb};
      --color-accent: ${palette.blue};
      --color-accent-1: ${palette.selection};
      --color-accent-2: ${palette.selection};

      --tab-text-color: ${palette.fg};
      --tab-text-color-focused: ${palette.brightFg};
      --tab-text-color-focused-active: ${palette.blue};
      --tab-background-active: ${palette.selection};
      --tab-divider-color: ${palette.border};
      --nav-item-color: ${palette.fg};
      --nav-item-color-hover: ${palette.brightFg};
      --nav-item-color-active: ${palette.brightFg};
      --nav-item-background-hover: ${palette.selection};
      --nav-item-background-active: ${palette.selection};

      --titlebar-background: ${palette.surface};
      --titlebar-background-focused: ${palette.surface};
      --titlebar-text-color: ${palette.brightFg};
      --titlebar-text-color-focused: ${palette.brightFg};
      --status-bar-background: ${palette.surface};
      --status-bar-text-color: ${palette.fg};
      --modal-background: ${palette.surface};
      --modal-border-color: ${palette.border};
      --prompt-border-color: ${palette.blue};
      --divider-color: ${palette.border};
      --divider-color-hover: ${palette.blue};
      --icon-color: ${palette.fg};
      --icon-color-hover: ${palette.brightFg};
      --icon-color-active: ${palette.blue};
      --icon-color-focused: ${palette.blue};
      --scrollbar-bg: ${palette.deep};
      --scrollbar-thumb-bg: ${palette.border};
      --scrollbar-active-thumb-bg: ${palette.blue};

      --h1-color: ${palette.brightFg};
      --h2-color: ${palette.brightFg};
      --h3-color: ${palette.brightFg};
      --h4-color: ${palette.brightFg};
      --h5-color: ${palette.brightFg};
      --h6-color: ${palette.brightFg};
      --link-color: ${palette.blue};
      --link-color-hover: ${palette.blue};
      --link-external-color: ${palette.blue};
      --link-unresolved-color: ${palette.brightFg};
      --code-normal: ${palette.cyan};
      --code-background: ${palette.deep};
      --code-comment: ${palette.fg};
      --blockquote-border-color: ${palette.blue};
      --checkbox-color: ${palette.selection};
      --checkbox-color-hover: ${palette.selection};
      --checkbox-marker-color: ${palette.blue};
      --checkbox-border-color: ${palette.blue};
      --graph-line: ${palette.border};
      --graph-node: ${palette.blue};
      --graph-node-focused: ${palette.cyan};
      --graph-node-tag: ${palette.green};
      --graph-node-attachment: ${palette.purple};
      --vault-name-color: ${palette.brightFg};
      --indentation-guide-color: ${palette.border};
      --indentation-guide-color-active: ${palette.blue};
      --bold-color: ${palette.brightFg};
      --italic-color: ${palette.brightFg};
      --list-marker-color: ${palette.blue};
      --tag-color: ${palette.cyan};
      --tag-background: ${palette.deep};
      --tag-color-hover: ${palette.cyan};
      --tag-background-hover: ${palette.selection};
    }

    .theme-dark .workspace-tab-header,
    .theme-dark .nav-file-title,
    .theme-dark .nav-folder-title {
      border-radius: 8px;
    }

    .theme-dark .workspace-tab-header.is-active {
      background: ${palette.selection};
      color: ${palette.brightFg};
      box-shadow: inset 0 -1px ${palette.blue};
    }

    .theme-dark .nav-file-title.is-active,
    .theme-dark .nav-folder-title.is-active {
      background: ${palette.selection};
      color: ${palette.brightFg};
      box-shadow: inset 2px 0 ${palette.blue};
    }

    .theme-dark .mod-cta {
      background: ${palette.selection};
      border: 1px solid ${palette.blue};
      color: ${palette.brightFg};
    }

    .theme-dark .internal-link.is-unresolved {
      text-decoration: underline wavy ${palette.red};
      text-underline-offset: 2px;
    }

    .theme-dark .workspace-ribbon.mod-left,
    .theme-dark .workspace-sidedock-vault-profile {
      background: ${palette.deep};
    }

    .theme-dark .workspace-toolbar,
    .theme-dark .workspace-tab-header-container,
    .theme-dark .status-bar {
      background: ${palette.surface};
    }
  '';
}

# Private factory: seed defaults, never a Home Manager settings.json source.
{ palette }:
let
  p = palette;
in
{
  "workbench.colorTheme" = "One Dark Pro";
  "editor.fontFamily" = "'${p.fonts.mono}', monospace";
  "editor.fontSize" = 15;
  "editor.fontLigatures" = true;
  "editor.minimap.enabled" = false;
  "editor.bracketPairColorization.enabled" = false;
  "workbench.startupEditor" = "none";
  "extensions.ignoreRecommendations" = true;
  "workbench.activityBar.location" = "default";
  "workbench.editor.tabActionCloseVisibility" = "active";
  "workbench.editor.tabSizing" = "shrink";
  "window.commandCenter" = false;
  "workbench.secondarySideBar.defaultVisibility" = "hidden";
  "terminal.integrated.fontFamily" = "'${p.fonts.mono}'";
  "terminal.integrated.fontSize" = 15;
  "workbench.colorCustomizations" = {
    foreground = p.brightFg;
    focusBorder = p.blue;
    "widget.border" = p.border;
    "editor.background" = p.deep;
    "editor.foreground" = p.brightFg;
    "editorLineNumber.foreground" = p.muted;
    "editorLineNumber.activeForeground" = p.fg;
    "editor.lineHighlightBackground" = p.bg;
    "editor.selectionBackground" = p.selection;
    "editor.inactiveSelectionBackground" = p.selection + "80";
    "editorCursor.foreground" = p.blue;
    "editorWhitespace.foreground" = p.border + "80";
    "editorIndentGuide.background1" = p.surface;
    "editorIndentGuide.activeBackground1" = p.border;
    "editorGroup.border" = p.border;
    "editorGroupHeader.tabsBackground" = p.bg;
    "editorGroupHeader.tabsBorder" = p.border;
    "tab.activeBackground" = p.deep;
    "tab.activeForeground" = p.brightFg;
    "tab.inactiveBackground" = p.bg;
    "tab.inactiveForeground" = p.fg;
    "tab.border" = p.surface;
    "tab.activeBorderTop" = p.blue;
    "tab.unfocusedActiveBorderTop" = p.blue + "80";
    "tab.activeBorder" = p.deep;
    "tab.unfocusedActiveBorder" = p.deep;
    "tab.activeModifiedBorder" = p.orange;
    "tab.inactiveModifiedBorder" = p.orange;
    "activityBar.background" = p.bg;
    "activityBar.foreground" = p.brightFg;
    "activityBar.inactiveForeground" = p.fg;
    "activityBar.border" = p.border;
    "activityBar.activeBorder" = p.blue;
    "activityBar.activeBackground" = p.bg;
    "activityBarBadge.background" = p.selection;
    "activityBarBadge.foreground" = p.brightFg;
    "sideBar.background" = p.bg;
    "sideBar.foreground" = p.brightFg;
    "sideBar.border" = p.border;
    "sideBarTitle.foreground" = p.fg;
    "sideBarSectionHeader.background" = p.bg;
    "sideBarSectionHeader.border" = p.surface;
    "list.activeSelectionBackground" = p.selection;
    "list.activeSelectionForeground" = p.brightFg;
    "list.inactiveSelectionBackground" = p.surface;
    "list.inactiveSelectionForeground" = p.brightFg;
    "list.focusOutline" = p.blue;
    "list.hoverBackground" = p.surface;
    "list.highlightForeground" = p.blue;
    "titleBar.activeBackground" = p.bg;
    "titleBar.activeForeground" = p.brightFg;
    "titleBar.inactiveBackground" = p.bg;
    "titleBar.inactiveForeground" = p.fg;
    "titleBar.border" = p.border;
    "statusBar.background" = p.bg;
    "statusBar.foreground" = p.fg;
    "statusBar.border" = p.border;
    "statusBar.noFolderBackground" = p.bg;
    "statusBar.noFolderForeground" = p.fg;
    "statusBar.debuggingBackground" = p.orange;
    "statusBar.debuggingForeground" = p.black;
    "statusBarItem.remoteBackground" = p.surface;
    "statusBarItem.remoteForeground" = p.blue;
    "statusBarItem.prominentBackground" = p.surface;
    "statusBarItem.hoverBackground" = p.selection;
    "panel.background" = p.deep;
    "panel.border" = p.border;
    "panelTitle.activeBorder" = p.blue;
    "panelTitle.activeForeground" = p.brightFg;
    "panelTitle.inactiveForeground" = p.fg;
    "terminal.background" = p.deep;
    "terminal.foreground" = p.brightFg;
    "terminal.selectionBackground" = p.selection;
    "terminalCursor.foreground" = p.blue;
    "terminal.ansiBlack" = p.black;
    "terminal.ansiRed" = p.red;
    "terminal.ansiGreen" = p.green;
    "terminal.ansiYellow" = p.yellow;
    "terminal.ansiBlue" = p.blue;
    "terminal.ansiMagenta" = p.purple;
    "terminal.ansiCyan" = p.cyan;
    "terminal.ansiWhite" = p.fg;
    "terminal.ansiBrightBlack" = p.muted;
    "terminal.ansiBrightRed" = p.red;
    "terminal.ansiBrightGreen" = p.green;
    "terminal.ansiBrightYellow" = p.yellow;
    "terminal.ansiBrightBlue" = p.blue;
    "terminal.ansiBrightMagenta" = p.purple;
    "terminal.ansiBrightCyan" = p.cyan;
    "terminal.ansiBrightWhite" = p.brightFg;
    "input.background" = p.deep;
    "input.foreground" = p.brightFg;
    "input.border" = p.border;
    "dropdown.background" = p.bg;
    "dropdown.border" = p.border;
    "button.background" = p.selection;
    "button.foreground" = p.brightFg;
    "button.hoverBackground" = p.surface;
    "editorWidget.background" = p.bg;
    "editorWidget.border" = p.border;
    "editorSuggestWidget.background" = p.bg;
    "editorSuggestWidget.foreground" = p.brightFg;
    "editorSuggestWidget.border" = p.border;
    "editorSuggestWidget.selectedBackground" = p.selection;
    "editorSuggestWidget.selectedForeground" = p.brightFg;
    "editorSuggestWidget.highlightForeground" = p.blue;
    "editorSuggestWidget.focusHighlightForeground" = p.blue;
    "quickInput.background" = p.bg;
    "quickInput.foreground" = p.brightFg;
    "quickInputList.focusBackground" = p.selection;
    "quickInputList.focusForeground" = p.brightFg;
    "notificationCenterHeader.background" = p.bg;
    "notifications.background" = p.bg;
    "notifications.foreground" = p.brightFg;
    "notifications.border" = p.border;
    "diffEditor.insertedLineBackground" = p.green + "14";
    "diffEditor.removedLineBackground" = p.red + "14";
    "diffEditor.insertedTextBackground" = p.green + "1f";
    "diffEditor.removedTextBackground" = p.red + "1f";
    "diffEditor.border" = p.border;
    "diffEditor.diagonalFill" = p.surface;
  };
  # Keep the upstream One Dark Pro grammar/scopes, with readable shared roles.
  "editor.tokenColorCustomizations" = {
    comments = p.fg;
    keywords = p.brightFg;
    strings = p.green;
    numbers = p.orange;
    functions = p.blue;
    types = p.cyan;
    variables = p.brightFg;
    textMateRules = [
      {
        scope = [
          "keyword"
          "keyword.operator"
          "keyword.operator.assignment"
          "keyword.operator.arithmetic"
          "keyword.operator.c"
          "keyword.operator.cpp"
          "keyword.operator.assignment.c"
          "keyword.operator.assignment.cpp"
          "keyword.operator.arithmetic.c"
          "keyword.operator.arithmetic.cpp"
          "keyword.operator.comparison.c"
          "keyword.operator.comparison.cpp"
          "keyword.operator.increment.c"
          "keyword.operator.increment.cpp"
          "keyword.operator.decrement.c"
          "keyword.operator.decrement.cpp"
          "keyword.operator.bitwise.shift.c"
          "keyword.operator.bitwise.shift.cpp"
          "punctuation.separator.c"
          "punctuation.separator.cpp"
          "storage"
          "storage.type"
          "storage.modifier"
          "punctuation.separator.statement.nix"
        ];
        settings.foreground = p.brightFg;
      }
      {
        scope = [
          "comment"
          "punctuation.definition.comment"
          "comment.line.double-slash"
          "comment.block.documentation"
        ];
        settings = {
          foreground = p.fg;
          fontStyle = "";
        };
      }
      {
        scope = "variable.parameter";
        settings = {
          foreground = p.brightFg;
          fontStyle = "";
        };
      }
    ];
  };
}

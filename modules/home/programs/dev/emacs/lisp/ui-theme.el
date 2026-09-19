;;; ui-theme.el --- Colour scheme  -*- lexical-binding: t; -*-

;;; Commentary:
;; Counterpart to nixvim/plugins/appearance/colorscheme.nix and
;; nixvim/highlights.nix.
;;
;; Deliberately *not* the same palette as Neovim.  nvim runs OneDark; this runs
;; doom-nord, because the Emacs frame shares a screen with fcitx5's candidate
;; window, which base/input-method.nix themes Nord-Dark, and with the noctalia
;; shell.  The two editors agree on structure, not on hue — changing this is a
;; one-line edit if that ever stops being wanted.

;;; Code:

(use-package doom-themes
  :config
  (setq doom-themes-enable-bold t
        doom-themes-enable-italic t)
  ;; doom-tokyo-night, not a standalone tokyonight package: doom-themes ships
  ;; the face definitions magit, org and doom-modeline expect, which a bare
  ;; theme does not.
  ;;
  ;; The scheme is not a taste call made here -- it is the host's. noctalia
  ;; renders the live palette into foot, gtk, qt, mango, btop, cava, yazi,
  ;; zathura, vscode and zen, and that palette is Tokyo Night (#1a1b26 /
  ;; #c0caf5 / #7aa2f7, read straight out of ~/.config/foot/themes/noctalia).
  ;; Emacs cannot follow it at runtime, so it is pinned to the same scheme, as
  ;; are nvim, tmux and fcitx5.
  (load-theme 'doom-tokyo-night t)
  ;; Org face tweaks live in a separate file that the nixpkgs build does not
  ;; generate an autoload for, so `doom-themes-org-config' is void until it is
  ;; required by hand.
  (when (require 'doom-themes-ext-org nil t)
    (doom-themes-org-config))

  ;; Built-in faces doom-nord does not claim, which therefore keep Emacs' own
  ;; hardcoded greys and show up as off-palette slabs against #1a1b26.
  ;;
  ;; `help-key-binding' is the one that shows: its dark default is
  ;; `:background "grey19" :box (:color "grey35")', which is what drew the grey
  ;; rectangle around the key in eldoc's "M-SPC l a: Extract to ..." hint.
  ;; Measured off a screenshot: 3019 pixels of #303030 in a frame whose palette
  ;; contains no grey at all.
  ;;
  ;; These run after `load-theme' on purpose -- a theme load resets faces, so
  ;; anything set before it would be thrown away.
  (set-face-attribute 'help-key-binding nil
                      :background "#292e42"   ; bg_highlight
                      :foreground "#7dcfff"   ; cyan
                      :box '(:line-width (1 . -1) :color "#414868")))

(provide 'ui-theme)
;;; ui-theme.el ends here

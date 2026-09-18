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
  ;; doom-nord rather than plain nord-theme: it ships the face definitions that
  ;; magit, org and doom-modeline expect.
  (load-theme 'doom-nord t)
  ;; Org face tweaks live in a separate file that the nixpkgs build does not
  ;; generate an autoload for, so `doom-themes-org-config' is void until it is
  ;; required by hand.
  (when (require 'doom-themes-ext-org nil t)
    (doom-themes-org-config)))

(provide 'ui-theme)
;;; ui-theme.el ends here

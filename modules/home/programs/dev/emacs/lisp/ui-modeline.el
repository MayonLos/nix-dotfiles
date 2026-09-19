;;; ui-modeline.el --- Mode line and breadcrumb  -*- lexical-binding: t; -*-

;;; Commentary:
;; Counterpart to nixvim/plugins/appearance/heirline.nix (the status line) and
;; navic.nix (the winbar breadcrumb).

;;; Code:

(use-package doom-modeline
  :init (doom-modeline-mode 1)
  :config
  (setq doom-modeline-height 28
        doom-modeline-buffer-file-name-style 'relative-to-project
        ;; The icon set needs nerd-fonts.symbols-only, which fonts.nix installs.
        doom-modeline-icon t))

;; Header line: project-relative path, then the function or class point is
;; inside — what navic renders into nvim's winbar.  `breadcrumb-local-mode'
;; rather than the global mode, which would also claim the header line in
;; magit, dired and the agenda.
(use-package breadcrumb
  :hook (prog-mode . breadcrumb-local-mode))

;; A popup already announces itself by sitting at the bottom of the frame; a
;; mode line in each one is redundant chrome.
(use-package hide-mode-line
  :hook ((help-mode helpful-mode pdf-view-mode) . hide-mode-line-mode))

(provide 'ui-modeline)
;;; ui-modeline.el ends here

;;; ui-icons.el --- Nerd font icons everywhere they fit  -*- lexical-binding: t; -*-

;;; Commentary:
;; Counterpart to nixvim/plugins/appearance/icons.nix.  Every one of these needs
;; a Nerd Font carrying the symbol range — system/user/fonts.nix installs
;; nerd-fonts.symbols-only for exactly this.

;;; Code:

(use-package nerd-icons)

;; Completion candidates: file kinds in find-file, buffer kinds in switch-buffer.
(use-package nerd-icons-completion
  :after (marginalia nerd-icons)
  :config
  (nerd-icons-completion-mode 1)
  (add-hook 'marginalia-mode-hook #'nerd-icons-completion-marginalia-setup))

;; In-buffer completion: the LSP kind (function, variable, module) as a glyph.
(use-package nerd-icons-corfu
  :after corfu
  :config (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))

(use-package nerd-icons-dired
  :hook (dired-mode . nerd-icons-dired-mode))

(use-package nerd-icons-ibuffer
  :hook (ibuffer-mode . nerd-icons-ibuffer-mode))

(provide 'ui-icons)
;;; ui-icons.el ends here

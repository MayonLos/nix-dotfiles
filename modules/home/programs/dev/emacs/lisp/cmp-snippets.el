;;; cmp-snippets.el --- Snippets  -*- lexical-binding: t; -*-

;;; Commentary:
;; Counterpart to nixvim/plugins/completion/snippets.nix.

;;; Code:

(use-package yasnippet
  :init (yas-global-mode 1)
  :config (setq yas-verbosity 1))

(use-package yasnippet-snippets
  :after yasnippet)

(provide 'cmp-snippets)
;;; cmp-snippets.el ends here

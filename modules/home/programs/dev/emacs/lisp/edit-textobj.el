;;; edit-textobj.el --- Tree-sitter text objects  -*- lexical-binding: t; -*-

;;; Commentary:
;; Counterpart to nixvim/plugins/editing/treesitter-textobjects.nix: `af'/`if'
;; for a function, `ac'/`ic' for a class, `aa'/`ia' for a parameter — off the
;; same grammars early-init.el put on `treesit-extra-load-path'.

;;; Code:

(use-package evil-textobj-tree-sitter
  :after evil
  :config
  (define-key evil-outer-text-objects-map "f"
              (evil-textobj-tree-sitter-get-textobj "function.outer"))
  (define-key evil-inner-text-objects-map "f"
              (evil-textobj-tree-sitter-get-textobj "function.inner"))
  (define-key evil-outer-text-objects-map "c"
              (evil-textobj-tree-sitter-get-textobj "class.outer"))
  (define-key evil-inner-text-objects-map "c"
              (evil-textobj-tree-sitter-get-textobj "class.inner"))
  (define-key evil-outer-text-objects-map "a"
              (evil-textobj-tree-sitter-get-textobj "parameter.outer"))
  (define-key evil-inner-text-objects-map "a"
              (evil-textobj-tree-sitter-get-textobj "parameter.inner"))

  ;; nvim binds `]f'/`[f' to move by function through the same queries.  evil
  ;; leaves those free, and the goto helper takes the query directly.
  (evil-define-key 'normal 'global
    (kbd "] f") (lambda ()
                  (interactive)
                  (evil-textobj-tree-sitter-goto-textobj "function.outer"))
    (kbd "[ f") (lambda ()
                  (interactive)
                  (evil-textobj-tree-sitter-goto-textobj "function.outer" t))
    (kbd "] c") (lambda ()
                  (interactive)
                  (evil-textobj-tree-sitter-goto-textobj "class.outer"))
    (kbd "[ c") (lambda ()
                  (interactive)
                  (evil-textobj-tree-sitter-goto-textobj "class.outer" t))))

(provide 'edit-textobj)
;;; edit-textobj.el ends here

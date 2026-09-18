;;; fmt-apheleia.el --- Format on save  -*- lexical-binding: t; -*-

;;; Commentary:
;; Counterpart to nixvim/plugins/formatting/conform.nix.  Same formatters, same
;; binaries — they come from programs/dev/toolchain.nix, so a file formatted in
;; one editor does not get reformatted by the other.

;;; Code:

;; Runs the formatter in a subprocess and patches the buffer, so a slow
;; formatter cannot freeze a single-threaded editor mid-save.
(use-package apheleia
  :init (apheleia-global-mode 1)
  :config
  ;; The stock alist keys the classic major modes; these are the tree-sitter
  ;; ones edit-treesit.el remaps to.  nixfmt is the same formatter `nix fmt'
  ;; runs through treefmt, so save-time and CI cannot disagree.
  (dolist (entry '((nix-ts-mode    . nixfmt)
                   (lua-ts-mode    . stylua)
                   (c-ts-mode      . clang-format)
                   (c++-ts-mode    . clang-format)
                   (python-ts-mode . ruff)
                   (bash-ts-mode   . shfmt)
                   (json-ts-mode   . prettier-json)
                   (yaml-ts-mode   . prettier-yaml)
                   (java-ts-mode   . google-java-format)))
    (setf (alist-get (car entry) apheleia-mode-alist) (cdr entry))))

(provide 'fmt-apheleia)
;;; fmt-apheleia.el ends here

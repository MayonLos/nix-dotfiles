;;; edit-treesit.el --- Tree-sitter modes and folding  -*- lexical-binding: t; -*-

;;; Commentary:
;; Counterpart to nixvim/plugins/editing/treesitter.nix (which grammars are in
;; play) and ufo.nix (folding driven by the grammar rather than by indentation).
;;
;; Emacs 30 ships the *-ts-mode major modes but no grammars; early-init.el
;; points `treesit-extra-load-path' at the curated set default.nix builds.

;;; Code:

;; Prefer the tree-sitter major modes where Emacs 30 ships one and a grammar was
;; found.  Anything not listed keeps its classic mode.
(setq major-mode-remap-alist
      '((bash-mode       . bash-ts-mode)
        (sh-mode         . bash-ts-mode)
        (c-mode          . c-ts-mode)
        (c++-mode        . c++-ts-mode)
        (cmake-mode      . cmake-ts-mode)
        (css-mode        . css-ts-mode)
        (java-mode       . java-ts-mode)
        (javascript-mode . js-ts-mode)
        (js-mode         . js-ts-mode)
        (json-mode       . json-ts-mode)
        (js-json-mode    . json-ts-mode)
        (python-mode     . python-ts-mode)
        (conf-toml-mode  . toml-ts-mode)
        (yaml-mode       . yaml-ts-mode)))

;; The remap above only fires for extensions Emacs already recognises.  These
;; have no classic major mode installed to remap *from*, so they need a direct
;; `auto-mode-alist' entry — without it .yaml opens in fundamental-mode and
;; go.mod, of all things, opens in m2-mode.
(dolist (entry '(("\\.ya?ml\\'"                            . yaml-ts-mode)
                 ("\\(?:Dockerfile\\|\\.dockerfile\\)\\'"  . dockerfile-ts-mode)
                 ("\\.rs\\'"                               . rust-ts-mode)
                 ("\\.go\\'"                               . go-ts-mode)
                 ("/go\\.mod\\'"                           . go-mod-ts-mode)
                 ("\\.ts\\'"                               . typescript-ts-mode)
                 ("\\.tsx\\'"                              . tsx-ts-mode)
                 ("\\.lua\\'"                              . lua-ts-mode)
                 ("\\(?:CMakeLists\\.txt\\|\\.cmake\\)\\'" . cmake-ts-mode)))
  (add-to-list 'auto-mode-alist entry))

;; Nix has no built-in mode at all.
(use-package nix-ts-mode
  :mode "\\.nix\\'")

;; Folding driven by the grammar rather than by indentation, wired to the vim
;; keys evil would otherwise point at hideshow.
(use-package treesit-fold
  :init (global-treesit-fold-mode 1)
  :config
  (with-eval-after-load 'evil
    (evil-define-key 'normal 'global
      (kbd "z a") #'treesit-fold-toggle
      (kbd "z c") #'treesit-fold-close
      (kbd "z o") #'treesit-fold-open
      (kbd "z M") #'treesit-fold-close-all
      (kbd "z R") #'treesit-fold-open-all)))

(provide 'edit-treesit)
;;; edit-treesit.el ends here

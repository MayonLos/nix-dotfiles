;;; tool-utility.el --- The rest of nixvim/plugins/utility/  -*- lexical-binding: t; -*-

;;; Commentary:
;;   helpful          better help buffers
;;   vundo            undotree.nvim
;;   undo-fu-session  undo history that survives a daemon restart
;;   keycast          the "what did I just press" learning aid
;;   eros             inline evaluation results, for editing this config
;;   envrc            direnv, so a buffer gets its project's toolchain
;;   verb             HTTP requests written as org documents

;;; Code:

(use-package helpful
  :bind (([remap describe-function] . helpful-callable)
         ([remap describe-variable] . helpful-variable)
         ([remap describe-key]      . helpful-key)
         ([remap describe-command]  . helpful-command)))

;; The undo *tree*, not the undo list: branches you created by undoing and then
;; typing are otherwise unreachable without knowing `undo-redo' by heart.
(use-package vundo
  :commands (vundo)
  :config (setq vundo-glyph-alist vundo-unicode-symbols))

;; Undo history persisted per file. This matters more here than on most setups
;; because pgtk takes the whole daemon down when the Wayland socket drops.
(use-package undo-fu-session
  :init (undo-fu-session-global-mode 1)
  :config
  (setq undo-fu-session-directory (expand-file-name "undo" user-emacs-directory)
        undo-fu-session-incompatible-files
        '("/COMMIT_EDITMSG\\'" "/git-rebase-todo\\'")))

;; Shows the key just pressed and the command it ran. Off by default, since it
;; is a learning aid rather than a permanent fixture — `SPC u k' turns it on.
(use-package keycast
  :commands (keycast-mode-line-mode keycast-log-mode))

;; Inline evaluation results, printed next to the form instead of flashing past
;; in the echo area. `C-x C-e' in any elisp buffer.
(use-package eros
  :hook (emacs-lisp-mode . eros-mode))

;; direnv, so a buffer under a project with an .envrc gets that project's
;; toolchain instead of the daemon's login environment. Without this, eglot
;; would start whatever clangd the daemon happened to inherit.
(use-package envrc
  :init (envrc-global-mode 1))

;; An HTTP client whose request definitions are org documents.  Loaded here
;; rather than in lang-org.el because it is a tool that happens to use org as
;; its file format, not part of the note-taking setup.
(use-package verb
  :after org
  :config (define-key org-mode-map (kbd "C-c C-r") verb-command-map))

(provide 'tool-utility)
;;; tool-utility.el ends here

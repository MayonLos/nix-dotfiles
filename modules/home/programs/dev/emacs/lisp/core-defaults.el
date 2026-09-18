;;; core-defaults.el --- Editor defaults  -*- lexical-binding: t; -*-

;;; Commentary:
;; Counterpart to nixvim/options.nix: the settings that make stock Emacs behave
;; the way the Neovim config already does.

;;; Code:

(use-package emacs
  :init
  (setq inhibit-startup-screen t
        initial-scratch-message nil
        ;; A GUI dialog on a tiling compositor is a floating window that steals
        ;; focus; the minibuffer prompt is strictly better.
        use-dialog-box nil
        use-short-answers t
        ;; Emacs asks about symlinked files under version control on every save
        ;; otherwise, and this whole config is symlinks.
        vc-follow-symlinks t
        ;; Backups and autosaves in the file's own directory pollute every repo.
        backup-directory-alist `(("." . ,(expand-file-name "backups" user-emacs-directory)))
        auto-save-file-name-transforms `((".*" ,(expand-file-name "autosave/" user-emacs-directory) t))
        create-lockfiles nil
        ;; Follow the file on disk when something else changed it — git
        ;; checkouts, formatters, the other editor.
        auto-revert-verbose nil
        ;; Scrolling that does not recentre the window every time point leaves
        ;; the viewport, which is what makes stock Emacs feel unlike vim.
        scroll-conservatively 101
        scroll-margin 4
        ;; `M-x' offers commands that make no sense in the current mode by
        ;; default; this hides them.
        read-extended-command-predicate #'command-completion-default-include-p
        ;; The minibuffer can be recursive, which consult and embark rely on.
        enable-recursive-minibuffers t)

  ;; These three are automatically buffer-local, so plain `setq' would only
  ;; ever affect *scratch*.
  (setq-default fill-column 80
                indent-tabs-mode nil
                tab-width 4)

  :config
  (global-auto-revert-mode 1)
  (savehist-mode 1)          ; minibuffer history across restarts
  (save-place-mode 1)        ; reopen files at the last cursor position
  (recentf-mode 1)           ; feeds consult-recent-file
  (delete-selection-mode 1)
  (column-number-mode 1)
  (global-so-long-mode 1)    ; do not hang on minified files
  (electric-pair-mode 1)     ; nixvim/plugins/editing/autopairs.nix

  ;; Relative numbers in prog buffers only; org and magit are worse with them.
  (add-hook 'prog-mode-hook #'display-line-numbers-mode)
  (setq display-line-numbers-type 'relative)

  ;; A little air between lines. At 0 the default face sits tight enough that
  ;; CJK text and Latin text visibly disagree about line height.
  (setq-default line-spacing 0.15)

  ;; ediff otherwise spawns a separate frame for its control panel, which on a
  ;; tiling compositor lands as a floating window in the wrong workspace.
  (setq ediff-window-setup-function #'ediff-setup-windows-plain
        ediff-split-window-function #'split-window-horizontally))

;; Trailing whitespace is trimmed only on lines this session actually touched.
;; A global `delete-trailing-whitespace' on save rewrites lines the commit never
;; went near and buries the real change in the diff.
(use-package ws-butler
  :init (ws-butler-global-mode 1))

(provide 'core-defaults)
;;; core-defaults.el ends here

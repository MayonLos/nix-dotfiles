;;; tool-session.el --- Session persistence  -*- lexical-binding: t; -*-

;;; Commentary:
;; Counterpart to nixvim/plugins/utility/persistence.nix, and one of the four
;; capabilities the Neovim config had that this one did not.
;;
;; persistence.nvim keys a session to the current working directory and
;; restores it on demand; easysession keys a session to a *name*, so this file
;; derives that name from the project root and keeps the same three keys:
;;
;;   SPC p s   restore the session for this directory
;;   SPC p l   reload the session currently in effect
;;   SPC p d   stop saving this session
;;
;; Loading is deliberately never automatic.  `easysession-save-mode' only
;; writes; nothing here calls `easysession-setup', so starting Emacs gives an
;; empty frame rather than whatever was open three days ago — same as nvim,
;; where a bare `nvim' does not restore either.

;;; Code:

(use-package easysession
  :commands (easysession-switch-to easysession-load easysession-save
             easysession-delete easysession-rename easysession-save-mode)
  :init
  (setq easysession-directory (expand-file-name "easysession" user-emacs-directory)
        ;; The frame geometry belongs to the compositor here: mango places
        ;; windows by its own rules, and restoring a saved geometry fights the
        ;; tiling layout rather than reproducing it.
        easysession-enable-frameset-restore nil
        easysession-save-interval 60)
  ;; Autosave from the start, so `SPC p s' tomorrow finds something to restore.
  ;; The mode is cheap: it writes buffer and window state, not buffer contents.
  (easysession-save-mode 1))

(defun my/session-name-for-directory ()
  "Return a session name derived from the current project or directory."
  (let* ((root (abbreviate-file-name (my/project-root-or-default)))
         (trimmed (string-trim root "/" "/")))
    (if (string-empty-p trimmed)
        "root"
      (replace-regexp-in-string "[/ ]" "-" trimmed))))

(defun my/session-restore-for-directory ()
  "Restore the session belonging to this directory, creating it if new."
  (interactive)
  (easysession-switch-to (my/session-name-for-directory)))

(defun my/session-reload ()
  "Reload the session currently in effect, discarding unsaved window changes."
  (interactive)
  (easysession-load))

(defun my/session-stop-saving ()
  "Stop autosaving the current session for the rest of this Emacs run."
  (interactive)
  (easysession-save-mode -1)
  (message "Session autosave off — this session will not be written again"))

(provide 'tool-session)
;;; tool-session.el ends here

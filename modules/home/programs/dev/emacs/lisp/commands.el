;;; commands.el --- Helpers the other modules and keymaps call  -*- lexical-binding: t; -*-

;;; Commentary:
;; Small functions with no package of their own.  Loaded before every module
;; that calls one, and before keymaps.el, which binds most of them.

;;; Code:

;; The daemon starts before the compositor has a frame, so anything that probes
;; frame parameters at load time has to wait for the first client instead.
(defun my/on-first-frame (fn)
  "Run FN now if a graphical frame exists, otherwise once one does."
  (if (daemonp)
      (add-hook 'server-after-make-frame-hook fn)
    (funcall fn)))

;; Both org and org-roam need this, and org-roam's :config would otherwise read
;; `org-directory' — a variable that only exists once org.el has loaded.
(defconst my/org-directory (expand-file-name "~/org"))

(defun my/read-secret (name)
  "Return the contents of the sops secret NAME, or nil if unreadable.
The daemon inherits the systemd user environment, which never sourced the
zsh profile that exports these as variables, so they are read from disk."
  (let ((file (expand-file-name name "/run/secrets")))
    (when (file-readable-p file)
      (string-trim (with-temp-buffer
                     (insert-file-contents file)
                     (buffer-string))))))

(defun my/project-root-or-default ()
  "Return the current project root, or `default-directory' outside a project."
  (if-let* ((project (project-current)))
      (project-root project)
    default-directory))

(defun my/open-nix-dotfiles ()
  "Open the NixOS configuration repository."
  (interactive)
  (project-switch-project (expand-file-name "~/nix-dotfiles/")))

(defun my/find-org-file ()
  "Find a file under `org-directory'."
  (interactive)
  (require 'org)
  (let ((default-directory org-directory))
    (call-interactively #'find-file)))

(defun my/yank-buffer-path ()
  "Copy the current buffer's path, relative to the project when there is one."
  (interactive)
  (if-let* ((file (buffer-file-name)))
      (let* ((project (project-current))
             (path (if project
                       (file-relative-name file (project-root project))
                     file)))
        (kill-new path)
        (message "%s" path))
    (user-error "This buffer is not visiting a file")))

(defun my/find-file-in-project-or-cwd ()
  "Find a file in the current project, falling back to `find-file'.
nvim's `<leader>ff' is project-scoped when there is a project and a plain file
picker when there is not; `project-find-file' errors out instead."
  (interactive)
  (if (project-current)
      (project-find-file)
    (call-interactively #'find-file)))

(defun my/search-project-or-cwd ()
  "Ripgrep the project, or `default-directory' when outside one."
  (interactive)
  (require 'consult)
  (consult-ripgrep (my/project-root-or-default)))

(defun my/rename-this-file ()
  "Rename the file this buffer visits, telling the language server about it.
`rename-visited-file' is built in since Emacs 29 and already updates the
buffer; eglot's `eglot-rename-file' equivalent is the server-side half, which
eglot performs through `eglot--managed-mode' file-watch notifications."
  (interactive)
  (unless buffer-file-name
    (user-error "This buffer is not visiting a file"))
  (call-interactively #'rename-visited-file))

;;;; ------------------------------------------------------------------ toggles

(defvar-local my/zen--state nil
  "Saved buffer state for `my/zen-mode', or nil when it is off.")

(define-minor-mode my/zen-mode
  "Distraction-free editing: wide margins, no line numbers, no mode line.
The equivalent of snacks' zen mode in the Neovim config."
  :init-value nil
  :lighter " Zen"
  (if my/zen-mode
      (let ((pad (max 0 (/ (- (window-total-width) fill-column) 2))))
        ;; `header-line-format' has to go too: ui-modeline.el puts
        ;; breadcrumb-local-mode on every prog buffer, so without this the
        ;; breadcrumb path stayed on screen while everything else was stripped.
        (setq my/zen--state
              (list display-line-numbers mode-line-format header-line-format))
        (setq display-line-numbers nil
              mode-line-format nil
              header-line-format nil)
        ;; Centre the text by padding the window rather than the buffer, so
        ;; nothing about the file on disk changes.
        (set-window-margins nil pad pad))
    (when my/zen--state
      (setq display-line-numbers (nth 0 my/zen--state)
            mode-line-format (nth 1 my/zen--state)
            header-line-format (nth 2 my/zen--state)))
    (set-window-margins nil 0 0)))

(defun my/toggle-inlay-hints ()
  "Toggle eglot's inlay hints in this buffer."
  (interactive)
  (unless (bound-and-true-p eglot--managed-mode)
    (user-error "No language server is managing this buffer"))
  (eglot-inlay-hints-mode (if (bound-and-true-p eglot-inlay-hints-mode) -1 1)))

(defun my/toggle-diagnostics-at-eol ()
  "Toggle diagnostics rendered at end of line.
The Emacs 30 equivalent of nvim's `virtual_lines' diagnostic toggle."
  (interactive)
  (setq flymake-show-diagnostics-at-end-of-line
        (if flymake-show-diagnostics-at-end-of-line nil 'short))
  ;; The variable is read when the overlays are built, so an already-on flymake
  ;; has to be cycled for the change to show.
  (when (bound-and-true-p flymake-mode)
    (flymake-mode -1)
    (flymake-mode 1))
  (message "Diagnostics at end of line: %s"
           (if flymake-show-diagnostics-at-end-of-line "on" "off")))

(defun my/toggle-relative-line-numbers ()
  "Switch `display-line-numbers-type' between relative and absolute."
  (interactive)
  (setq display-line-numbers-type
        (if (eq display-line-numbers-type 'relative) t 'relative))
  (when display-line-numbers-mode
    (display-line-numbers-mode 1))
  (message "Line numbers: %s"
           (if (eq display-line-numbers-type 'relative) "relative" "absolute")))

(provide 'commands)
;;; commands.el ends here

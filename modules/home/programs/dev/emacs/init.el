;;; init.el --- Loader for the module tree in lisp/  -*- lexical-binding: t; -*-

;;; Commentary:
;; Managed by modules/home/programs/dev/emacs.  This file only decides *what*
;; loads and *in what order*; every actual setting lives in one file under
;; lisp/, laid out to mirror the nixvim tree at the repository root so that a
;; change to one editor has an obvious address in the other:
;;
;;   nixvim/core/…                 lisp/core-*.el
;;   nixvim/options.nix            lisp/core-defaults.el
;;   nixvim/autocmds.nix           lisp/core-autocmds.el
;;   nixvim/theme.nix              lisp/ui-theme.el
;;   nixvim/plugins/appearance/    lisp/ui-*.el
;;   nixvim/plugins/editing/       lisp/edit-*.el
;;   nixvim/plugins/completion/    lisp/cmp-*.el
;;   nixvim/plugins/navigation/    lisp/nav-*.el
;;   nixvim/plugins/lsp/           lisp/lsp-eglot.el, lisp/diag-trouble.el
;;   nixvim/plugins/formatting/    lisp/fmt-apheleia.el
;;   nixvim/plugins/git/           lisp/git-magit.el
;;   nixvim/plugins/debug/         lisp/dbg-dape.el
;;   nixvim/plugins/ai/            lisp/ai-gptel.el
;;   nixvim/plugins/terminal/      lisp/tool-terminal.el
;;   nixvim/plugins/utility/       lisp/tool-*.el
;;   (snacks.image maths)          lisp/lang-math.el
;;   nixvim/keymappings.nix        lisp/keymaps.el
;;
;; Every package on the load-path was put there by the Nix wrapper, so no
;; use-package form needs :ensure and `M-x package-install' will not work — add
;; the package in default.nix and rebuild instead.
;;
;; This file and everything under lisp/ is a read-only /nix/store symlink.  For
;; throwaway experiments that should not need a rebuild, write
;; ~/.config/emacs/personal.el; it is loaded last.
;;
;; Leader is SPC in normal state and M-SPC anywhere.  `SPC H b' lists every
;; binding currently in effect; `SPC H k' explains whichever key you press next.

;;; Code:

;; Bundled with Emacs since 29, but only autoloaded — requiring it explicitly
;; keeps this file working if that ever changes.
(require 'use-package)

(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

(defconst my/modules
  '(;; core — must come first: perf tuning, then the defaults everything
    ;; else assumes, then the helper functions later modules call.
    core-perf
    core-defaults
    core-autocmds
    commands

    ;; appearance
    ui-fonts
    ui-theme
    ui-icons
    ui-modeline
    ui-frame

    ;; editing
    edit-evil
    edit-textobj
    edit-multicursor
    edit-treesit

    ;; completion
    cmp-corfu
    cmp-snippets

    ;; navigation
    nav-minibuffer
    nav-harpoon
    nav-dired

    ;; code intelligence
    lsp-eglot
    diag-trouble
    fmt-apheleia

    ;; version control and debugging
    git-magit
    dbg-dape

    ;; tools
    ai-gptel
    tool-terminal
    tool-session
    tool-utility

    ;; languages
    lang-markdown
    lang-tex
    lang-org
    ;; after lang-org and lang-markdown: it configures both of them.
    lang-math

    ;; last: every command it binds has been defined or autoloaded by now.
    keymaps)
  "Modules under lisp/, loaded in this order.")

;; A module that fails must not take the editor down with it: an Emacs that
;; starts with one broken feature is debuggable, an Emacs that drops to
;; *Warnings* with no keybindings is not.  Failures are collected and reported
;; once, after startup, rather than one popup per module.
(defvar my/module-errors nil
  "Alist of (MODULE . ERROR) for modules that failed to load.")

(dolist (module my/modules)
  (condition-case err
      (require module)
    (error (push (cons module err) my/module-errors))))

(when my/module-errors
  (add-hook 'emacs-startup-hook
            (lambda ()
              (dolist (failure (nreverse my/module-errors))
                (display-warning
                 'my/init
                 (format "%s failed to load: %S" (car failure) (cdr failure))
                 :error)))))

;;;; ------------------------------------------------------------------- local

;; Customize writes here; early-init.el pointed it at a writable path.
(when (file-exists-p custom-file)
  (load custom-file nil t))

;; Anything being tried out before it earns a place in lisp/.
(let ((personal (expand-file-name "personal.el" user-emacs-directory)))
  (when (file-exists-p personal)
    (load personal nil t)))

;;; init.el ends here

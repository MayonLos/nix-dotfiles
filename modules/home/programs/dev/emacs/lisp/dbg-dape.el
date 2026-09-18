;;; dbg-dape.el --- Debug Adapter Protocol  -*- lexical-binding: t; -*-

;;; Commentary:
;; Counterpart to nixvim/plugins/debug/dap.nix.  The one large capability eglot
;; does not cover.  gdb 17.2 speaks DAP natively (`gdb --interpreter=dap'), so C
;; and C++ need no separate adapter; Python goes through debugpy, which rides
;; along with python.nix's `python3.withPackages' rather than sitting in the
;; user profile — see the dev-toolchain skill for why that distinction matters.

;;; Code:

(use-package dape
  ;; Every one of these is on a `SPC d' key, and only `dape' and
  ;; `dape-breakpoint-toggle' carry their own autoload cookie — without the
  ;; rest listed here, `SPC d c' before a session exists is a void-function
  ;; error rather than a no-op.
  :commands (dape dape-breakpoint-toggle dape-breakpoint-remove-all
             dape-continue dape-next dape-step-in dape-step-out
             dape-restart dape-quit dape-pause dape-repl
             dape-evaluate-expression)
  :config
  (setq dape-buffer-window-arrangement 'right
        ;; Without this the adapter starts in whatever directory the daemon was
        ;; launched from rather than the project root.
        dape-cwd-function #'my/project-root-or-default)
  ;; Save any modified buffer before starting a session; debugging a stale
  ;; binary against fresh source is a special kind of waste.
  (add-hook 'dape-start-hook (lambda () (save-some-buffers t t))))

(provide 'dbg-dape)
;;; dbg-dape.el ends here

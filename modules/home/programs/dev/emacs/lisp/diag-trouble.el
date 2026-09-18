;;; diag-trouble.el --- Diagnostics, symbols and the quickfix list  -*- lexical-binding: t; -*-

;;; Commentary:
;; Counterpart to nixvim/plugins/utility/trouble.nix, and one of the four
;; capabilities the Neovim config had that this one did not.  trouble.nvim is
;; one panel with several sources behind it; Emacs already ships every source,
;; so what is missing is the panel discipline — one reusable window at the
;; bottom of the frame rather than a buffer stealing whichever split had focus.
;; tool-terminal.el's popper configuration owns that window; this file puts the
;; diagnostic buffers into it and gives them the `SPC x' group.
;;
;; Source mapping:
;;   trouble diagnostics (project)  flymake-show-project-diagnostics
;;   trouble diagnostics (buffer)   flymake-show-buffer-diagnostics
;;   trouble symbols                consult-imenu / consult-eglot-symbols
;;   trouble lsp definitions/refs   xref-find-references
;;   trouble quickfix               consult-compile-error
;;   trouble todo                   consult-todo-project

;;; Code:

(use-package flymake
  :hook (prog-mode . flymake-mode)
  :commands (flymake-mode flymake-goto-next-error flymake-goto-prev-error
             flymake-show-buffer-diagnostics flymake-show-project-diagnostics)
  :config
  ;; eglot drives flymake for every managed buffer.  In an unmanaged one the
  ;; built-in backends still apply (elisp gets byte-compile and checkdoc,
  ;; python gets `python-flymake-command'); the point of enabling it globally
  ;; is that `SPC x x' means the same thing in both kinds of buffer.
  (setq flymake-no-changes-timeout 0.5
        ;; Do not report a problem the moment a line is half-typed.
        flymake-start-on-newline nil
        ;; Emacs 30 renders diagnostics at end of line rather than only in the
        ;; fringe.  `SPC l l' toggles it, mirroring nvim's virtual-lines key.
        flymake-show-diagnostics-at-end-of-line 'short)

  ;; The project diagnostics buffer is only useful if it lists files that are
  ;; not open yet, which needs the project backend rather than the buffer one.
  (setq flymake-suppress-zero-counters t))

;; Every TODO/FIXME in the project as a completion list — nvim reaches the same
;; set through trouble's todo source, which is todo-comments' data.
(use-package consult-todo
  :commands (consult-todo consult-todo-project))

(provide 'diag-trouble)
;;; diag-trouble.el ends here

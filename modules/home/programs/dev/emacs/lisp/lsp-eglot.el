;;; lsp-eglot.el --- Language servers  -*- lexical-binding: t; -*-

;;; Commentary:
;; Counterpart to nixvim/plugins/lsp/.  eglot is built into Emacs since 29, so
;; there is no package to install — only the question of which servers start
;; automatically and where their binaries come from.
;;
;; **Every server named here is a bare binary name.**  The same rule the
;; dev-toolchain skill states for `nixvim/plugins/lsp/servers.nix' applies:
;; interpolating a store path would drag the server into the editor's runtime
;; closure.  They are on PATH because programs/dev/toolchain.nix installs them,
;; which is also what stops nvim and Emacs drifting onto different versions.

;;; Code:

(use-package eglot
  ;; Auto-started only for languages whose server is installed and whose
  ;; project shape makes an unattended start safe.  Everywhere else `SPC l e'
  ;; starts it by hand.
  :hook ((c-ts-mode c++-ts-mode lua-ts-mode nix-ts-mode LaTeX-mode) . eglot-ensure)
  ;; `eglot' carries its own autoload cookie; none of its verbs below do, and
  ;; eglot.el is not loaded until a server starts.  Listing them here installs
  ;; the autoloads, so a key bound to one loads eglot instead of failing with
  ;; void-function -- the same job lz-n's `keys' trigger does in nvim.
  :commands (eglot eglot-rename eglot-code-actions eglot-shutdown
             eglot-reconnect eglot-find-implementation
             eglot-find-typeDefinition eglot-inlay-hints-mode)
  :config
  (setq eglot-autoshutdown t
        ;; `eglot-events-buffer-size' has been obsolete since eglot 1.16 and
        ;; setting it does nothing — the log stayed at its 2 MB default, quietly
        ;; recording every LSP message. This is the option that replaced it.
        ;; Set :size to a number instead of nil when a server needs debugging.
        eglot-events-buffer-config '(:size 0 :format short)
        eglot-sync-connect nil
        ;; How long after a keystroke the server is told what changed. The
        ;; default 0.5 means a completion request fired at 0.3 s describes text
        ;; the server has not seen yet, and eglot has to flush first.
        eglot-send-changes-idle-time 0.2)

  ;; nixd needs to be told which flake to evaluate before it can complete
  ;; NixOS and Home Manager option names rather than just builtins.
  (add-to-list 'eglot-server-programs '(nix-ts-mode . ("nixd")))

  ;; The servers nixvim configures that Emacs has no default for.  Bare names,
  ;; as above; a mode with no entry here still works via `SPC l l' if eglot's
  ;; own default happens to match.
  (dolist (entry '((bash-ts-mode       . ("bash-language-server" "start"))
                   (cmake-ts-mode      . ("cmake-language-server"))
                   (yaml-ts-mode       . ("yaml-language-server" "--stdio"))
                   (dockerfile-ts-mode . ("docker-langserver" "--stdio"))))
    (add-to-list 'eglot-server-programs entry)))

;; eglot puts signatures in the echo area, which is one line tall and gone as
;; soon as anything else prints.  This is the same content in a child frame —
;; the role nvim gives to its LSP hover float.
(use-package eldoc-box
  :hook (eglot-managed-mode . eldoc-box-hover-at-point-mode)
  ;; eldoc-box.el:85 defines `eldoc-box-border' as literally `:background
  ;; "white"' on any dark background, so the hover frame came up as a white
  ;; slab in the middle of a Nord buffer. Both faces are pinned to the palette
  ;; here; `:custom-face' rather than a `setq' because the face has to exist
  ;; before it can be set, and this form is deferred until eldoc-box loads.
  :custom-face
  (eldoc-box-border ((t (:background "#4C566A"))))
  (eldoc-box-body ((t (:background "#272C36" :inherit nil)))))

;; Workspace-wide symbol lookup from the language server.  consult-imenu only
;; ever sees the current file, which is the distinction nvim draws between
;; document symbols and workspace symbols.
(use-package consult-eglot
  :commands (consult-eglot-symbols))

(provide 'lsp-eglot)
;;; lsp-eglot.el ends here

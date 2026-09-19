;;; nav-minibuffer.el --- Minibuffer completion and pickers  -*- lexical-binding: t; -*-

;;; Commentary:
;; Counterpart to nixvim/plugins/navigation/fzf.nix.  fzf-lua is one plugin; the
;; Emacs equivalent is a stack, each piece replaceable:
;;
;;   vertico     the vertical candidate list
;;   orderless   the matching style (space-separated fragments, any order)
;;   marginalia  the annotations down the right-hand side
;;   consult     the pickers themselves (buffer, line, ripgrep, imenu…)
;;   embark      act on a candidate without leaving the prompt
;;   wgrep       make an exported grep buffer writable

;;; Code:

(use-package vertico
  :init (vertico-mode 1)
  :config
  (setq vertico-cycle t
        vertico-count 15))

(use-package orderless
  :init
  ;; Space-separated fragments matched in any order — the closest thing to
  ;; fzf's fuzzy behaviour.  `basic' stays as a fallback so that TAB on a
  ;; file path still completes literally.
  (setq completion-styles '(orderless basic)
        completion-category-defaults nil
        completion-category-overrides '((file (styles partial-completion)))))

(use-package marginalia
  :init (marginalia-mode 1))

(use-package consult
  :config
  ;; Preview on an explicit key rather than on every cursor move: the default
  ;; `any' opens remote and very large files just by scrolling past them.  This
  ;; is the plain variable rather than `consult-customize' on purpose — the
  ;; latter is a macro, and macros inside a deferred :config block break if this
  ;; file is ever byte-compiled.
  (setq consult-preview-key "M-."
        consult-narrow-key "<"
        ;; project.el decides what "the project" is, so ripgrep and buffer
        ;; scoping agree with `SPC P'.
        consult-project-function (lambda (_) (when-let* ((p (project-current))) (project-root p)))))

;; Switch the directory a find-file prompt is rooted at, mid-prompt.
(use-package consult-dir
  :commands (consult-dir)
  :init
  (with-eval-after-load 'vertico
    (define-key vertico-map (kbd "C-x C-d") #'consult-dir)))

(use-package embark
  :bind (("C-." . embark-act)
         ("C-;" . embark-dwim))
  :init
  ;; evil's normal-state map binds C-. to `evil-repeat-pop', and a state map
  ;; shadows the global one — so the :bind above reaches the minibuffer but
  ;; never a normal-state buffer, which is half of what embark is for.
  (with-eval-after-load 'evil
    (evil-define-key '(normal visual insert) 'global (kbd "C-.") #'embark-act))
  :config
  ;; embark-act on a candidate is the "what can I do with this?" key: rename a
  ;; file from the find-file prompt, kill a buffer from the switch prompt.
  (setq prefix-help-command #'embark-prefix-help-command))

(use-package embark-consult
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))

;; Makes an exported grep buffer writable.  `SPC s e' on a ripgrep result, edit
;; the lines, `C-c C-c' — the equivalent of grug-far's apply step.
(use-package wgrep
  :after embark-consult
  :config (setq wgrep-auto-save-buffer t))

(provide 'nav-minibuffer)
;;; nav-minibuffer.el ends here

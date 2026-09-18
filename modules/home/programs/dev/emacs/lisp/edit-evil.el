;;; edit-evil.el --- Modal editing  -*- lexical-binding: t; -*-

;;; Commentary:
;; evil and the pieces of the vim experience it leaves out.  The Neovim config
;; gets these for free; here each is a package:
;;
;;   evil / evil-collection   the modal editor itself, in every mode
;;   evil-surround            nvim-surround      (editing/surround.nix)
;;   evil-numbers             dial.nvim          (editing/dial.nix)
;;   evil-goggles             mini.operators-ish flash on an operator
;;   avy / ace-window         flash.nvim         (editing/flash.nix)
;;
;; Multiple cursors and tree-sitter text objects are large enough to have their
;; own files (edit-multicursor.el, edit-textobj.el).

;;; Code:

(use-package evil
  :init
  ;; Both of these are read when evil loads, so they cannot move to :config.
  ;; evil-collection refuses to load unless the first one is nil.
  (setq evil-want-keybinding nil
        evil-want-integration t
        evil-want-C-u-scroll t
        evil-want-C-i-jump t
        evil-respect-visual-line-mode t
        ;; vim-style splits.
        evil-split-window-below t
        evil-vsplit-window-right t
        ;; Emacs 28+ has real undo-redo; without this, `C-r' does nothing.
        evil-undo-system 'undo-redo
        ;; Y should behave like D and C, not like yy.
        evil-want-Y-yank-to-eol t)
  :config
  (evil-mode 1)
  ;; The minibuffer is not a text editor; modal state there fights completion.
  (setq evil-echo-state nil)
  ;; State shows in the mode line, but the cursor is where the eye already is.
  ;; Nord: frost blue normal, aurora yellow insert, purple visual, red replace.
  (setq evil-normal-state-cursor   '("#81a1c1" box)
        evil-insert-state-cursor   '("#ebcb8b" (bar . 2))
        evil-visual-state-cursor   '("#b48ead" box)
        evil-replace-state-cursor  '("#bf616a" hbar)
        evil-operator-state-cursor '("#88c0d0" hollow)))

(use-package evil-collection
  :after evil
  :config
  ;; Rebinds ~800 keymaps (magit, dired, org, help, vterm…) to evil-style keys.
  ;; This is the difference between "vim keys in files" and "vim keys in Emacs".
  (evil-collection-init))

(use-package evil-surround
  :after evil
  :config (global-evil-surround-mode 1))

;; vim's C-a / C-x, which evil leaves unbound because Emacs already owns C-a.
;; `g +' / `g -' rather than the vim keys for the same reason.
(use-package evil-numbers
  :after evil
  :config
  (evil-define-key '(normal visual) 'global
    (kbd "g +") #'evil-numbers/inc-at-pt
    (kbd "g -") #'evil-numbers/dec-at-pt))

;; Flashes the region an operator just acted on.  Without it, `d2}' gives no
;; feedback at all about what was deleted.
(use-package evil-goggles
  :after evil
  :config
  (setq evil-goggles-duration 0.1
        evil-goggles-pulse nil)
  (evil-goggles-mode 1)
  (evil-goggles-use-diff-faces))

;;;; -------------------------------------------------------------- jump motions

;; flash.nvim's role: get to a visible position without counting lines.  `SPC j'
;; types a couple of characters and labels every match; `SPC J' does it by line.
(use-package avy
  :commands (avy-goto-char-timer avy-goto-line)
  :config (setq avy-timeout-seconds 0.3))

;; Jump to any visible window by letter, which beats counting `C-w w'.
;; Registered inside evil's own window map so it lives under `SPC w a' too.
(use-package ace-window
  :commands (ace-window)
  :init (with-eval-after-load 'evil (define-key evil-window-map "a" #'ace-window))
  :config (setq aw-scope 'frame
                aw-keys '(?a ?s ?d ?f ?g ?h ?j ?k ?l)))

(provide 'edit-evil)
;;; edit-evil.el ends here

;;; ui-frame.el --- How the frame itself reads  -*- lexical-binding: t; -*-

;;; Commentary:
;; Counterpart to the rest of nixvim/plugins/appearance/ — the decorations that
;; are about orientation rather than about syntax: padding, dimming, motion
;; cues, indent guides, colour swatches and TODO highlighting.

;;; Code:

;; Stock Emacs packs text flush against the window border and glues the mode
;; line to the bottom edge. This gives the frame an internal border, real
;; window dividers, and a mode line that floats.
(use-package spacious-padding
  :init
  ;; The widths have to be set *before* the mode turns on — it reads them once
  ;; when enabled, so a `:config' setq would silently leave the defaults in
  ;; place (verified: internal-border-width came out 15, not the value here).
  (setq spacious-padding-widths
        '(:internal-border-width 16
          :header-line-width 4
          :mode-line-width 5
          :tab-width 4
          :right-divider-width 20
          :scroll-bar-width 8
          :fringe-width 10))

  ;; Without this the mode line and header line keep their own background, and
  ;; the padding above turns each of them into a wide filled block: the dirvish
  ;; header, the breadcrumb, and both halves of the mode line all read as slabs
  ;; of a different colour rather than as edges. `subtle-frame-lines' drops
  ;; those backgrounds to the frame's own and draws a hairline instead — an
  ;; overline under the mode line, an underline under the header line — so the
  ;; chrome marks a boundary without becoming a shape.
  ;;
  ;; Read once at enable, same as the widths. Colours are doom-nord's own:
  ;; Nord10 for the focused window, base3 everywhere else, both dark enough to
  ;; sit against bg #2E3440 without drawing the eye.
  (setq spacious-padding-subtle-frame-lines
        '(:mode-line-active "#5E81AC"
          :mode-line-inactive "#373E4C"
          :header-line-active "#373E4C"
          :header-line-inactive "#373E4C"))

  (spacious-padding-mode 1))

;; Buffers that are not visiting a file get a slightly different background,
;; so magit, help, dired and the popup window read as chrome while the code
;; reads as content.
(use-package solaire-mode
  :init (solaire-global-mode 1))

;; A brief pulse on the line jumped to.  With avy, xref and window switching all
;; moving point across the frame, this is the cheapest way not to lose it.  It
;; is also what core-autocmds.el advises `kill-ring-save' with, standing in for
;; nvim's TextYankPost highlight.
(use-package pulsar
  :init (pulsar-global-mode 1)
  :config
  (setq pulsar-pulse t
        pulsar-delay 0.055
        pulsar-iterations 8)
  (dolist (fn '(evil-scroll-down evil-scroll-up evil-goto-line
                evil-window-down evil-window-up
                evil-window-left evil-window-right))
    (add-to-list 'pulsar-pulse-functions fn)))

;; Indentation guides.  `indent-bars-prefer-character' draws them with a real
;; glyph instead of a stipple bitmap: stipples are computed per frame, and under
;; the daemon the first frame does not exist yet when the mode turns on.
(use-package indent-bars
  :hook ((python-ts-mode yaml-ts-mode nix-ts-mode) . indent-bars-mode)
  :config
  (setq indent-bars-prefer-character t
        indent-bars-treesit-support t
        indent-bars-no-descend-string t))

(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

(use-package hl-todo
  :hook (prog-mode . hl-todo-mode))

;; Draws a swatch beside #rrggbb, named colours and hsl() rather than
;; recolouring the text itself, which would fight the Nord ground.
(use-package colorful-mode
  :hook ((css-ts-mode conf-mode nix-ts-mode) . colorful-mode)
  :config (setq colorful-use-prefix t))

;; Prose in org and markdown gets the proportional face; code blocks, tables
;; and inline verbatim stay on the monospace one.
(use-package mixed-pitch
  :hook ((org-mode markdown-mode) . mixed-pitch-mode))

;; Built into Emacs 30 — no package needed.  keymaps.el registers the leader
;; group names with it.
(use-package which-key
  :init (which-key-mode 1)
  :config
  (setq which-key-idle-delay 0.4
        which-key-sort-order #'which-key-key-order-alpha))

(provide 'ui-frame)
;;; ui-frame.el ends here

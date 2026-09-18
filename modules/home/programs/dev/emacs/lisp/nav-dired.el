;;; nav-dired.el --- File manager  -*- lexical-binding: t; -*-

;;; Commentary:
;; The file manager.  nvim's counterpart is snacks' explorer on `<leader>e' --
;; oil.nvim, which this file used to mirror, was removed from that config on
;; 2026-09-18 for being a second file manager that never actually owned
;; `nvim <dir>'.
;;
;; Emacs needs no oil equivalent: dired *is* "edit the directory as a buffer",
;; and `wdired-change-to-wdired-mode' (`C-x C-q') is the rename-by-editing part.
;; dirvish adds the preview pane, icons and header line that make it usable as a
;; file manager rather than a listing.

;;; Code:

(use-package dirvish
  :init (dirvish-override-dired-mode 1)
  ;; `dirvish-hl-line' inherits `highlight', and the doom themes define
  ;; `highlight' as plain `blue' -- a full-brightness accent used as the
  ;; background of a row that spans the whole sidebar. Measured under doom-nord:
  ;; 5964 pixels of #81A1C1 in one line, the loudest block on the frame. Tokyo
  ;; Night's own selection background says "this row is current" without being
  ;; the first thing the eye lands on.
  ;; doom-tokyo-night paints `dired-directory' in the palette's red, and
  ;; `dired-flagged' -- files marked for deletion -- in the *same* red (queried
  ;; on a live frame: both #f7768e). Two consequences, one cosmetic and one not:
  ;; every folder glyph takes it, giving a sidebar of red folders; and a file
  ;; flagged for deletion is indistinguishable from an ordinary directory. Blue
  ;; is both the conventional directory colour and this palette's primary
  ;; accent, so red goes back to meaning danger.
  ;;
  ;; It has to be `:custom-face', not a `set-face-attribute' next to the theme
  ;; in ui-theme.el -- that was tried and measured as having no effect. dired.el
  ;; is not loaded at startup, so its `defface' runs later, and the recalc that
  ;; follows re-applies the *theme* spec over anything set imperatively before
  ;; it. A custom spec outranks a theme spec whenever the recalc happens.
  :custom-face
  (dirvish-hl-line ((t (:background "#283457" :extend t))))
  (dired-directory ((t (:foreground "#7aa2f7"))))
  :config
  (setq dirvish-attributes '(nerd-icons file-size vc-state git-msg)
        dirvish-mode-line-format '(:left (sort file-time symlink) :right (omit yank index))
        ;; `dired-listing-switches' has to sort directories first or the preview
        ;; pane is unusable in a large tree.
        dired-listing-switches "-l --almost-all --human-readable --group-directories-first --no-group")

  ;; `SPC e' is the side panel, matching nvim's `<leader>e'.  The `SPC o'
  ;; group is Emacs-only: dired is reached far more often here than a file
  ;; tree is in nvim, so it keeps its own entry points.
  (setq dirvish-side-width 35)

  ;; dirvish keeps `major-mode' as `dired-mode' for compatibility, so
  ;; evil-collection's `dired-mode-map' bindings apply -- and its per-state
  ;; auxiliary map wins over `dirvish-mode-map', which is only a *child* of
  ;; dired-mode-map. The visible effect: `q' ran `quit-window' instead of
  ;; `dirvish-quit', skipping `dirvish--clear-session' and leaking the hidden
  ;; dired buffers and session bookkeeping every time.
  ;;
  ;; Binding on the mode's own map through evil puts it above that aux layer.
  (with-eval-after-load 'evil
    (evil-define-key 'normal dirvish-mode-map (kbd "q") #'dirvish-quit)))

(provide 'nav-dired)
;;; nav-dired.el ends here

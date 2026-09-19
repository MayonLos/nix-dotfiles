;;; edit-multicursor.el --- Simultaneous edits  -*- lexical-binding: t; -*-

;;; Commentary:
;; Counterpart to nixvim/plugins/editing/multicursors.nix, which owns the
;; `SPC m' group there.  evil-multiedit is the closest thing in Emacs: rather
;; than N independent cursors it edits every match at once, which is what people
;; actually want from "multiple cursors" most of the time.
;;
;; The default keybinds (`M-d' to add the next occurrence, `R' in visual state
;; to take every match in the region) are installed as they come; keymaps.el
;; adds the `SPC m' group on top so the two editors agree on where to look.

;;; Code:

(use-package evil-multiedit
  :after evil
  :commands (evil-multiedit-match-all
             evil-multiedit-match-and-next
             evil-multiedit-match-and-prev
             evil-multiedit-toggle-or-restrict-region
             evil-multiedit-abort)
  :config (evil-multiedit-default-keybinds))

(provide 'edit-multicursor)
;;; edit-multicursor.el ends here

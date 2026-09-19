;;; lang-markdown.el --- Markdown  -*- lexical-binding: t; -*-

;;; Commentary:
;; Counterpart to nixvim/plugins/utility/render-markdown.nix, and one of the
;; four capabilities the Neovim config had that this one did not.
;;
;; render-markdown.nvim replaces the markup with the thing it describes: `#'
;; becomes a styled heading, a table gets drawn, a code block gets a background.
;; markdown-mode can do the first and third by itself once the markup is hidden
;; and the faces are scaled; tables are the hard part, because a CJK character
;; is two columns wide in a monospace font but not exactly two of anything in a
;; proportional one — which is what valign measures and pads for.

;;; Code:

(use-package markdown-mode
  :mode (("\\.md\\'" . markdown-mode)
         ("README\\.md\\'" . gfm-mode))
  ;; `markdown-table-face' inherits `markdown-code-face', which doom-tokyo-night
  ;; paints #23242e -- a band behind every table cell. That reads fine on its
  ;; own and badly next to lang-math.el's previews: a preview image carries the
  ;; *buffer* background, so each formula punched a #1a1b26 hole in the band and
  ;; the table came out as a field of mismatched blocks. valign draws the
  ;; structure here, so the band is not carrying any information anyway.
  ;; `:custom-face', not `set-face-attribute' -- see nav-dired.el for why.
  :custom-face
  (markdown-table-face ((t (:background unspecified :inherit fixed-pitch))))
  :config
  ;; `setq-default', not `setq'. markdown-mode.el calls
  ;; `make-variable-buffer-local' on `markdown-enable-math' (line 372) and
  ;; `markdown-hide-markup' (line 1923), so a plain `setq' here sets them in
  ;; whatever buffer happened to be current while this file loaded and leaves
  ;; the default alone. Measured on a live frame before this was written: both
  ;; read nil in an open .md buffer while the three ordinary variables in the
  ;; same form read t -- maths was never fontified and markup never hid, with
  ;; no error and nothing to see in the config.
  (setq-default markdown-enable-math t
                ;; Hide `**', `_' and heading hashes until point enters the
                ;; construct, the way org-appear does for org.
                markdown-hide-markup t)

  (setq markdown-enable-highlighting-syntax t
        ;; Fontify a fenced block in its own language, which is what makes a
        ;; code block read as code rather than as prose.
        markdown-fontify-code-blocks-natively t
        markdown-header-scaling t
        ;; A list item continues at the indentation of its content.
        markdown-list-indent-width 2)

  ;; `markdown-hide-markup' makes text readable but un-editable in place, so
  ;; give it a toggle on the same key org's equivalent has.
  (define-key markdown-mode-map (kbd "C-c C-x m") #'markdown-toggle-markup-hiding))

;; Pixel-aligned tables.  Emacs aligns a markdown or org table by counting
;; characters, which is wrong twice over here: the CJK glyphs in these notes are
;; wider than one column, and mixed-pitch (ui-frame.el) puts the prose in a
;; proportional face where no character has a fixed width at all.  valign
;; measures the rendered pixels and pads with display properties, changing
;; nothing on disk.
(use-package valign
  :hook ((markdown-mode org-mode) . valign-mode)
  :config
  (setq valign-fancy-bar t)

  ;; valign 3.1.1 does not recognise a separator row written `| :--- |'.
  ;; `valign--separator-p' (valign.el:327) tests the character *immediately*
  ;; after the bar for `:' or `-', and a space fails it.  GitHub-flavoured
  ;; markdown allows that space, prettier emits it, and every table in the
  ;; notes vault has it.
  ;;
  ;; The failure is silent and looks like something else entirely.
  ;; `valign--calculate-alignment' finds no separator row, returns nil instead
  ;; of a per-column alignment list, and `valign--cell' then matches neither
  ;; the `left' nor the `right' branch of its `pcase' -- so it puts no padding
  ;; overlay at all.  valign still renders the bars, still reports success, and
  ;; the table is left at whatever width its source characters happened to
  ;; produce.  With lang-math.el replacing formulae by images of unrelated
  ;; widths, that reads as "the maths broke the table".  It did not; this did.
  ;; Measured before and after: `(valign--calculate-alignment (quote markdown) end)'
  ;; returned nil, and returns (left left left) with these advices installed.
  (defun my/valign--skip-space-before-separator (orig &optional point)
    "Let a separator cell start with whitespace, as GFM allows."
    (save-excursion
      (goto-char (or point (point)))
      (skip-chars-forward " \t")
      (funcall orig (point))))
  (advice-add 'valign--separator-p :around
              #'my/valign--skip-space-before-separator)

  ;; Same leading space, and here it is not merely missed but *misread*:
  ;; `valign--alignment-from-seperator' looks for `:' at point, skips `-' if it
  ;; is not there, and looks again.  Sitting on a space it finds neither and
  ;; falls through to `left', so `| ---: |' would silently right-align nothing.
  (defun my/valign--skip-space-before-alignment (orig)
    "Skip leading whitespace in a separator cell before reading alignment."
    (save-excursion
      (skip-chars-forward " \t")
      (funcall orig)))
  (advice-add 'valign--alignment-from-seperator :around
              #'my/valign--skip-space-before-alignment)

  ;; valign draws the separator row as a horizontal rule but deliberately
  ;; leaves a leading `:' uncovered (valign.el:660), so `|:---|' renders as a
  ;; colon followed by the rule while `| :--- |' -- where the colon falls
  ;; inside the covered span -- renders clean. Same table, two looks, decided
  ;; by a space. Cover it, and tag the overlay `valign' so
  ;; `valign--clean-text-property' deletes it with the rest (valign.el:625).
  (defun my/valign--hide-separator-colon (beg _end _right-pos)
    "Hide the `:' alignment marker at BEG on a separator row."
    (when (eq (char-after beg) ?:)
      (let ((ov (make-overlay beg (1+ beg))))
        (overlay-put ov 'display "")
        (overlay-put ov 'valign t))))
  (advice-add 'valign--separator-row-add-overlay :after
              #'my/valign--hide-separator-colon))

(provide 'lang-markdown)
;;; lang-markdown.el ends here

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
  :config
  (setq markdown-enable-math t
        markdown-enable-highlighting-syntax t
        ;; Fontify a fenced block in its own language, which is what makes a
        ;; code block read as code rather than as prose.
        markdown-fontify-code-blocks-natively t
        ;; Hide `**', `_' and heading hashes until point enters the construct,
        ;; the way org-appear does for org.
        markdown-hide-markup t
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
  :config (setq valign-fancy-bar t))

(provide 'lang-markdown)
;;; lang-markdown.el ends here

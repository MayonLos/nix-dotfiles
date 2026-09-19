;;; lang-math.el --- LaTeX previewed in place  -*- lexical-binding: t; -*-

;;; Commentary:
;; The Emacs half of what nixvim/plugins/appearance/snacks.nix does for Neovim:
;; a formula written as LaTeX is shown typeset instead of as source.
;;
;; Emacs has the easier job of the two, and it is worth knowing why.  A terminal
;; can only place an image on the character grid, so snacks has to choose
;; between drawing a formula in the buffer and leaving the buffer's layout
;; alone.  Emacs composes text and images in one layout pass, and valign
;; (lang-markdown.el) measures table columns in *pixels*, so a formula can sit
;; inside a table cell and the table still lines up.
;;
;; Both paths below need latex plus a rasteriser; texliveFull and ghostscript
;; come from programs/dev/latex.nix.

;;; Code:

;;;; --------------------------------------------------------------------- org

(use-package org
  :defer t
  :config
  ;; dvisvgm, not the dvipng default: this display is 2560x1600 at scale 1.5,
  ;; and a PNG baked at one size is soft at any other. SVG is resolution
  ;; independent, so a preview stays crisp through `C-x C-=' and on an external
  ;; monitor.
  (setq org-preview-latex-default-process 'dvisvgm)

  (setq org-format-latex-options
        (plist-put (copy-sequence org-format-latex-options) :scale 1.4))
  ;; `:foreground default' makes a formula inherit the buffer's text colour, so
  ;; it follows the theme instead of being baked black -- the same reason
  ;; snacks passes the palette into its LaTeX template.
  (setq org-format-latex-options
        (plist-put org-format-latex-options :foreground 'default))
  (setq org-format-latex-options
        (plist-put org-format-latex-options :background 'default)))

;; Preview every fragment, but un-preview the one point is inside so it can be
;; edited. Without this, previewing is a manual `C-c C-x C-l' that has to be
;; undone by hand before a formula can be touched.
(use-package org-fragtog
  :hook (org-mode . org-fragtog-mode))

;;;; ---------------------------------------------------------------- markdown

;; markdown-mode has no LaTeX preview of its own. texfrag supplies one by
;; reusing AUCTeX's `preview' machinery -- which is already installed for
;; lang-tex.el -- and it ships markdown support out of the box
;; (`texfrag-setup-alist' pairs `texfrag-markdown' with `markdown-mode').
;;
;; This is the mode the notes vault is written in, so this is the one that
;; matters day to day.

(defun my/texfrag-scale ()
  "Factor that makes a preview image match the buffer's own text size.

`texfrag-scale' multiplies `preview-scale-from-face', which is a ratio of
*point* sizes: face height over the document's 10pt.  Converting that to
pixels is left to `preview-resolution', and on this machine the two ends
disagree badly.  Measured live, 2026-09-19:

  face height           113  (11.3 pt)
  font pixel size        15  -> the frame draws 1.33 px per pt (96 dpi)
  `preview-resolution'  255  ->     gs draws 3.54 px per pt

so an image came out 2.7x the surrounding text.  Emacs lays the frame out in
*logical* pixels (`frame-pixel-width' is 928 for a 936-wide mango window) and
the compositor scales that by 1.5, but `display-pixel-width' reports 3414 for
a 2560px panel -- it is counting the scale twice, and `preview-resolution' is
derived straight from it.

Rather than pin the quotient, recompute it: the correction is exactly the
frame's px-per-pt over the one gs is told to use."
  (let* ((font (face-attribute 'default :font))
         (info (and (fontp font) (font-info font)))
         (font-px (and info (aref info 2)))
         (font-pt (/ (face-attribute 'default :height) 10.0))
         (display-dpi (ignore-errors
                        (/ (* 25.4 (display-pixel-width))
                           (float (display-mm-width))))))
    (if (and font-px (> font-pt 0) display-dpi (> display-dpi 0))
        (/ (/ (float font-px) font-pt) (/ display-dpi 72.0))
      ;; Any of those can be nil on a tty or a frameless daemon start; 1.0 is
      ;; texfrag's own default and is merely wrong, not broken.
      1.0)))

(defun my/texfrag-set-scale ()
  "Set `texfrag-scale' for the current buffer.
1.05 rather than 1.0: a formula reads better very slightly larger than the
prose around it, and `\\frac' needs the vertical room."
  (setq-local texfrag-scale (* 1.05 (my/texfrag-scale))))

(defvar-local my/valign--realign-pending nil
  "Non-nil while a post-preview re-align is already queued.")

(defun my/valign-after-preview (&rest _)
  "Re-align the source buffer's tables once a preview image has been placed.

valign measures a cell by rendering it, so a cell whose formula has not been
replaced by its image yet measures as *source text* and the column comes out
the wrong width.  Previews arrive asynchronously -- latex, then gs, one image
at a time -- so the alignment valign computed during the initial fontification
is stale by the time the table is readable.

valign already re-aligns after `org-toggle-inline-images' for exactly this
reason (valign.el:1139); texfrag has no equivalent hook, so this is it.
Debounced on an idle timer because `preview-gs-place' fires once per image and
there are ~99 of them in one of these files."
  (let ((buf (and (boundp 'TeX-command-buffer)
                  (buffer-live-p TeX-command-buffer)
                  TeX-command-buffer)))
    (when buf
      (with-current-buffer buf
        (when (and (bound-and-true-p valign-mode)
                   (not my/valign--realign-pending))
          (setq my/valign--realign-pending t)
          (run-with-idle-timer
           0.5 nil
           (lambda ()
             (when (buffer-live-p buf)
               (with-current-buffer buf
                 (setq my/valign--realign-pending nil)
                 (when (bound-and-true-p valign-mode)
                   (valign-reset-buffer)))))))))))

(use-package texfrag
  :hook (markdown-mode . texfrag-mode)
  :init
  ;; In `:init', not `:config': `texfrag-mode' reads this while switching on
  ;; (texfrag.el:1228) to decide whether to queue `texfrag-post-command-preview'
  ;; on `post-command-hook'. Set it afterwards and the first buffer of the
  ;; session opens unrendered -- the hook has already not been added.
  ;;
  ;; Without it texfrag is a manual previewer: the mode turns on, the lighter
  ;; appears, and nothing is rendered until `texfrag-document' is called by
  ;; hand. Measured that way first -- the buffer showed raw `$$...$$'.
  (setq texfrag-preview-buffer-at-start t)

  ;; Everything below is in `:init' for the same reason, and it is the trap
  ;; this config keeps re-learning: `:hook' turns the mode on, turning the mode
  ;; on loads the package, and only *then* does `:config' run -- after the
  ;; first buffer has already been set up with the old values.

  ;; Leave image *links* alone. texfrag would otherwise also fetch and render
  ;; `![](...)' targets, which is a different feature with different failure
  ;; modes (network, missing files) bolted onto a maths previewer.
  (setq texfrag-markdown-preview-image-links nil)

  ;; Keep the image while point is inside it. preview-latex's default replaces
  ;; the image with its LaTeX source the moment an arrow key lands there
  ;; (`preview-auto-reveal' defaults to a form that consults
  ;; `preview-auto-reveal-commands'), which in evil normal mode means simply
  ;; scrolling through a document dismantles it a line at a time. nil makes
  ;; `preview-auto-reveal-p' return nil unconditionally (preview.el:1782), so
  ;; a formula is only opened deliberately, with `C-c C-p C-p'.
  (setq preview-auto-reveal nil)

  (add-hook 'texfrag-mode-hook #'my/texfrag-set-scale)
  (advice-add 'preview-gs-place :after #'my/valign-after-preview))

;; `preview-gs-place' is autoloaded from preview.el only once texfrag pulls it
;; in; `advice-add' on a not-yet-defined function is fine and the advice
;; attaches when the definition arrives.

(provide 'lang-math)
;;; lang-math.el ends here

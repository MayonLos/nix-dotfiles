;;; lang-tex.el --- LaTeX and PDF viewing  -*- lexical-binding: t; -*-

;;; Commentary:
;; AUCTeX replaces the built-in latex-mode outright: it knows the document
;; structure, runs the toolchain with `C-c C-c', and does forward/inverse
;; search against pdf-tools.  texlab (started by lsp-eglot.el) handles
;; completion and diagnostics; the two do not overlap.
;;
;; pdf-tools is also what makes `SPC o' on a PDF useful inside Emacs — the
;; desktop default is still zathura (base/xdg.nix).

;;; Code:

(use-package tex
  :mode ("\\.tex\\'" . LaTeX-mode)
  :config
  (setq TeX-auto-save t
        TeX-parse-self t
        TeX-source-correlate-mode t
        TeX-source-correlate-start-server t
        TeX-view-program-selection '((output-pdf "PDF Tools"))
        TeX-after-compilation-finished-functions
        (list #'TeX-revert-document-buffer)))

;; `pdf-loader-install' rather than `pdf-tools-install': the latter checks for
;; and offers to *build* epdfinfo, which under Nix is already built and not
;; writable anyway.
(use-package pdf-tools
  :magic ("%PDF" . pdf-view-mode)
  :config (pdf-loader-install :no-query))

(provide 'lang-tex)
;;; lang-tex.el ends here

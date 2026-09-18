;;; core-perf.el --- Startup and runtime cost  -*- lexical-binding: t; -*-

;;; Commentary:
;; Counterpart to nixvim/core/performance.nix.  early-init.el turns the garbage
;; collector off to get through startup; this hands a sane value back.

;;; Code:

;; A threshold large enough not to thrash and small enough not to stall.  Left
;; at `most-positive-fixnum' (what early-init.el sets) the first collection
;; after startup walks a heap that has been allowed to grow without bound.
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 64 1024 1024)
                  gc-cons-percentage 0.1)))

;; Reading a file's own encoding cookie is worth it; probing every file for
;; every coding system is not.  UTF-8 everywhere, with CJK filenames intact.
(set-language-environment "UTF-8")
(setq default-input-method nil)  ; set-language-environment sets this; fcitx5 owns input

;; Emacs is single-threaded: a 20 MB minified file with long lines will lock the
;; UI on font-lock alone.  `global-so-long-mode' (enabled in core-defaults)
;; needs these to recognise one.
(setq so-long-threshold 500
      so-long-max-lines 10)

;; Process output in bigger chunks. The default 4 kB pipe read is a measurable
;; share of the latency of an LSP server that answers with a large payload
;; (jdtls' workspace symbols, clangd's AST).
(setq read-process-output-max (* 1024 1024)
      process-adaptive-read-buffering nil)

;; Do not spend startup time on a mode line nobody has seen yet.
(setq inhibit-compacting-font-caches t)

(provide 'core-perf)
;;; core-perf.el ends here

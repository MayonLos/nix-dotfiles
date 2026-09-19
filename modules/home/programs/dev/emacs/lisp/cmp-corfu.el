;;; cmp-corfu.el --- In-buffer completion  -*- lexical-binding: t; -*-

;;; Commentary:
;; Counterpart to nixvim/plugins/completion/blink.nix.  corfu is the popup,
;; cape supplies the extra sources blink gets from its own providers.

;;; Code:

(use-package corfu
  :init (global-corfu-mode 1)
  :config
  (setq corfu-auto t
        ;; Measured 2026-08-21: the capfs themselves cost 2-3 ms and nixd
        ;; answers in under 30 ms, so a 0.15 delay was ~98% of the latency
        ;; between keystroke and popup. Nothing here needs the grace period.
        corfu-auto-delay 0.02
        corfu-auto-prefix 2
        corfu-cycle t
        ;; RET should insert a newline when nothing was explicitly selected,
        ;; which is what every other editor does.
        corfu-preselect 'prompt)
  ;; Documentation popup beside the candidate list.  It is a corfu extension,
  ;; not part of corfu.el, and it carries no autoload — hence the explicit,
  ;; failure-tolerant require.
  (when (require 'corfu-popupinfo nil t)
    ;; The docs popup asks the language server to resolve the selected
    ;; candidate. Keep it lazy so arrowing through a list does not fire a
    ;; request per keystroke.
    (setq corfu-popupinfo-delay '(1.0 . 0.5))
    (corfu-popupinfo-mode 1)))

(use-package cape
  :init
  ;; File-path and dabbrev completion in every buffer, including comments and
  ;; strings where the LSP has nothing to say.
  ;;
  ;; APPEND matters. `add-hook' prepends by default, which had put cape-dabbrev
  ;; at the *head* of `completion-at-point-functions' — every buffer's own capf
  ;; and eglot's ran behind a dabbrev scan, and in non-LSP buffers dabbrev's
  ;; guesses shadowed the real candidates entirely.
  (add-hook 'completion-at-point-functions #'cape-file t)
  (add-hook 'completion-at-point-functions #'cape-dabbrev t)
  :config
  ;; cape's own docstring: "In case you observe a performance issue with
  ;; auto-completion and cape-dabbrev it is strongly recommended to disable
  ;; scanning in other buffers." With 80-odd buffers open that scan is the one
  ;; part of this chain that grows without bound, so restrict it to buffers in
  ;; the same major mode.
  (setq cape-dabbrev-min-length 4
        cape-dabbrev-check-other-buffers #'cape--buffers-major-mode))

(provide 'cmp-corfu)
;;; cmp-corfu.el ends here

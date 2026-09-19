;;; tool-terminal.el --- Terminal and the popup window  -*- lexical-binding: t; -*-

;;; Commentary:
;; Counterpart to nixvim/plugins/terminal/snacks-terminal.nix.  snacks gives
;; nvim a float and a bottom split off the same toggle; popper is what makes a
;; window reusable here, and it is shared with the diagnostics buffers from
;; diag-trouble.el and the help buffers from tool-utility.el.

;;; Code:

(use-package vterm
  :commands vterm
  :config (setq vterm-max-scrollback 10000))

;; Help, compilation, vterm and friends open in one reusable bottom window
;; instead of stealing whichever split happened to be focused.
(use-package popper
  :init
  (setq popper-reference-buffers
        '("\\*Messages\\*"
          "\\*Warnings\\*"
          "\\*Async Shell Command\\*"
          "\\*eldoc\\*"
          "\\*vterm\\*"
          help-mode
          helpful-mode
          compilation-mode
          flymake-diagnostics-buffer-mode
          flymake-project-diagnostics-mode
          vterm-mode))
  (popper-mode 1)
  (popper-echo-mode 1)
  :config (setq popper-window-height 0.35))

(defun my/vterm-bottom ()
  "Open vterm in the popper window at the bottom of the frame."
  (interactive)
  (let ((buffer (save-window-excursion (vterm) (current-buffer))))
    (display-buffer buffer)))

(defun my/vterm-project ()
  "Open a vterm rooted at the current project."
  (interactive)
  (let ((default-directory (my/project-root-or-default)))
    (vterm)))

(provide 'tool-terminal)
;;; tool-terminal.el ends here

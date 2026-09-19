;;; core-autocmds.el --- Hooks that mirror nixvim/autocmds.nix  -*- lexical-binding: t; -*-

;;; Commentary:
;; nvim has two autocommands: restore the cursor position on BufReadPost, and
;; flash the region on TextYankPost.  The first is `save-place-mode', already on
;; in core-defaults.  The second is below; pulsar (ui-frame.el) provides the
;; flash itself.

;;; Code:

;; `pulsar-pulse-line' is autoloaded, but pulsar may still be absent if its
;; module failed — hence the guard rather than a bare call.
(defun my/pulse-after-yank (&rest _)
  "Briefly highlight the region a yank or kill just covered."
  (when (fboundp 'pulsar-pulse-line)
    (pulsar-pulse-line)))

(advice-add 'kill-ring-save :after #'my/pulse-after-yank)

;; Emacs has no BufWritePre "create missing parent directories" behaviour, and
;; writing a new file into a directory that does not exist is a hard error
;; rather than a prompt.
(defun my/create-parent-directories ()
  "Offer to create the parent directory of the file being saved."
  (let ((dir (file-name-directory buffer-file-name)))
    (when (and dir (not (file-directory-p dir))
               (y-or-n-p (format "Directory %s does not exist.  Create it? " dir)))
      (make-directory dir t))))

(add-hook 'before-save-hook #'my/create-parent-directories)

(provide 'core-autocmds)
;;; core-autocmds.el ends here

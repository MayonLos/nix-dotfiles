;;; git-magit.el --- Version control  -*- lexical-binding: t; -*-

;;; Commentary:
;; Counterpart to nixvim/plugins/git/ — gitsigns (the in-buffer hunk layer) and
;; diffview (the review UI).  This is the half of the split where Emacs is
;; ahead rather than catching up: magit is the reason to run it at all.
;;
;;   gitsigns hunks/staging   diff-hl + magit
;;   diffview file history    magit-log-buffer-file, git-timemachine
;;   lazygit                  magit-status

;;; Code:

(use-package magit
  :commands (magit-status magit-blame magit-blame-addition magit-log-buffer-file
             magit-diff-buffer-file magit-diff-working-tree magit-stage-file
             magit-file-checkout magit-mode-bury-buffer)
  :config
  (setq magit-diff-refine-hunk 'all
        ;; Open the status buffer full-frame and restore the layout on quit.
        magit-display-buffer-function #'magit-display-buffer-fullframe-status-v1))

;; GitHub issues and pull requests as magit sections.  Needs a token in
;; ~/.authinfo.gpg (machine api.github.com login <user>^forge password <token>);
;; until then `SPC g f' simply prompts for one.
(autoload 'forge-dispatch "forge" nil t)
(autoload 'forge-browse-dwim "forge" nil t)

(use-package forge
  :after magit)

;; Scans the repository for TODO/FIXME and lists them in the status buffer.
(use-package magit-todos
  :after magit
  :config (magit-todos-mode 1))

;; Pipes magit's diffs through delta, which programs/dev/git.nix sets as git's
;; pager (`enableGitIntegration'), so a hunk looks the same in the terminal and
;; in Emacs.  `magit-diff-refine-hunk' is turned off here because delta does its
;; own intra-line highlighting and the two draw over each other.
(use-package magit-delta
  :hook (magit-mode . magit-delta-mode)
  :config (setq magit-delta-default-dark-theme "Nord"
                magit-diff-refine-hunk nil))

;; Step a single file backwards through its own history, one commit per key.
(use-package git-timemachine
  :commands (git-timemachine))

;; The gitsigns layer: fringe marks, hunk navigation, stage/revert in place.
(use-package diff-hl
  :hook ((prog-mode . diff-hl-mode)
         (dired-mode . diff-hl-dired-mode))
  :commands (diff-hl-mode diff-hl-next-hunk diff-hl-previous-hunk
             diff-hl-show-hunk diff-hl-revert-hunk diff-hl-stage-dwim)
  :config
  ;; Without these two hooks the fringe indicators go stale the moment magit
  ;; stages or commits anything.
  (add-hook 'magit-pre-refresh-hook #'diff-hl-magit-pre-refresh)
  (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh)
  ;; Update as you type rather than only on save, which is what makes the marks
  ;; comparable to gitsigns'.
  (diff-hl-flydiff-mode 1))

(provide 'git-magit)
;;; git-magit.el ends here

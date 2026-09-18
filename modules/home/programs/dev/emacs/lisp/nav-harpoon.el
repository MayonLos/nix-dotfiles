;;; nav-harpoon.el --- Pinned files per project  -*- lexical-binding: t; -*-

;;; Commentary:
;; Counterpart to nixvim/plugins/navigation/harpoon.nix, and one of the four
;; capabilities the Neovim config had that this one did not.
;;
;; The idea it implements is not "recent files": a project has three or four
;; files you bounce between all day, and they should be on fixed keys rather
;; than at whatever position an MRU list has drifted to.  `SPC h a' pins the
;; current file; `SPC h 1'-`SPC h 4' jump to the first four pins; `SPC h h'
;; lists them.
;;
;; The list is per project *and* per git branch (`harpoon-separate-by-branch'),
;; which is the behaviour that makes it worth using across feature branches.

;;; Code:

(use-package harpoon
  :commands (harpoon-add-file
             harpoon-toggle-file
             harpoon-toggle-quick-menu
             harpoon-clear
             harpoon-go-to-1 harpoon-go-to-2 harpoon-go-to-3 harpoon-go-to-4
             harpoon-go-to-next harpoon-go-to-prev)
  :init
  ;; Same convention as the backup, autosave and undo directories in
  ;; core-defaults.el: state lives under `user-emacs-directory', not next to
  ;; the files it describes.
  (setq harpoon-cache-file (expand-file-name "harpoon/" user-emacs-directory)
        ;; project.el, not projectile — nothing here installs projectile, and
        ;; harpoon's own default probes for it at load time.
        harpoon-project-package 'project
        harpoon-separate-by-branch t)
  :config
  ;; `harpoon-toggle-quick-menu' goes through `completing-read', so it lands in
  ;; vertico with marginalia annotations rather than needing harpoon's own
  ;; hydra UI (which would pull hydra in for one menu).
  (with-eval-after-load 'evil
    (evil-set-initial-state 'harpoon-mode 'normal)))

(provide 'nav-harpoon)
;;; nav-harpoon.el ends here

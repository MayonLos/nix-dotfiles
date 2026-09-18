;;; lang-org.el --- Org and the note vault  -*- lexical-binding: t; -*-

;;; Commentary:
;; No nixvim counterpart — this is the half of the config that has no reason to
;; exist in Neovim.  keymaps.el gives it `SPC N' (capital), because `SPC n' is
;; the Docs group in the Neovim keymap this config now mirrors.

;;; Code:

(use-package org
  :commands (org-agenda org-capture org-store-link)
  :config
  (setq org-directory my/org-directory
        org-agenda-files (list my/org-directory)
        org-default-notes-file (expand-file-name "inbox.org" my/org-directory)
        org-startup-indented t
        org-startup-folded 'content
        org-hide-emphasis-markers t
        org-pretty-entities t
        ;; Refuse to mark a parent DONE while a child is not.
        org-enforce-todo-dependencies t
        org-log-done 'time
        ;; Run source blocks without a confirmation prompt for the languages
        ;; that are actually loaded below.
        org-confirm-babel-evaluate nil
        org-capture-templates
        '(("t" "Todo" entry
           (file+headline org-default-notes-file "Inbox")
           "* TODO %?\n  %U\n  %a")
          ("n" "Note" entry
           (file+headline org-default-notes-file "Notes")
           "* %?\n  %U")))
  ;; org-agenda errors out if the directory does not exist yet.
  (make-directory my/org-directory t)
  ;; Literate programming: `C-c C-c' inside a block runs it and inserts the
  ;; result underneath.
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((emacs-lisp . t)
     (shell . t)
     (python . t))))

(use-package org-modern
  :after org
  :hook ((org-mode . org-modern-mode)
         (org-agenda-finalize . org-modern-agenda)))

;; `org-hide-emphasis-markers' above makes *bold* readable but un-editable;
;; this reveals the markers only for the construct point is inside.
(use-package org-appear
  :hook (org-mode . org-appear-mode))

;; Zettelkasten on top of org: every note is a file, links are bidirectional,
;; and the backlink buffer shows what points here.
(use-package org-roam
  :commands (org-roam-node-find org-roam-node-insert org-roam-capture org-roam-buffer-toggle)
  :init (setq org-roam-v2-ack t)
  :config
  (setq org-roam-directory (expand-file-name "roam" my/org-directory)
        ;; Emacs 30 links against SQLite itself, so no compiled connector and
        ;; no emacsql binary download are needed.
        org-roam-database-connector 'sqlite-builtin
        org-roam-db-location (expand-file-name "org-roam.db" org-roam-directory))
  (make-directory org-roam-directory t)
  (org-roam-db-autosync-mode 1))

;; Clipboard image straight into the document: written to an attachment
;; directory beside the org file and inlined as a link. `C-c C-x C-v' toggles
;; whether images render in the buffer.
(use-package org-download
  ;; Deliberately no `:after org': that would defer this form's autoloads as
  ;; well, and `SPC N p' has to work in a buffer that has not touched org yet.
  ;; org-download requires org itself, so nothing is lost by dropping it.
  :commands (org-download-clipboard org-download-yank org-download-screenshot)
  :config
  (setq org-download-method 'directory
        org-download-image-dir (expand-file-name "images" my/org-directory)
        org-download-heading-lvl nil
        ;; The default annotation stamps the source URL above every image,
        ;; which is noise for a clipboard paste.
        org-download-annotate-function (lambda (_link) "")))

;; evil bindings for org's own structure editing and for the agenda, which
;; evil-collection deliberately leaves to this package.
(use-package evil-org
  :after (evil org)
  :hook (org-mode . evil-org-mode)
  :config
  (require 'evil-org-agenda)
  (evil-org-agenda-set-keys))

(provide 'lang-org)
;;; lang-org.el ends here

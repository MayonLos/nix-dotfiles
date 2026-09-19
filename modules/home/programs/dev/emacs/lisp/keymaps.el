;;; keymaps.el --- The leader map  -*- lexical-binding: t; -*-

;;; Commentary:
;; Counterpart to nixvim/keymappings.nix and
;; nixvim/plugins/utility/which-key.nix.  Loaded last, so every command it
;; names has already been defined or autoloaded.
;;
;; The groups are the Neovim config's groups, letter for letter:
;;
;;   a AI      b Buffer   c Code      d Debug    f Find     g Git
;;   h Harpoon i Insert   l LSP       m Cursors  n Docs
;;   p Session s Search   t Terminal  u Toggle   w Window   x Diagnostics
;;
;; Four things Emacs has and Neovim does not had to go somewhere, so they took
;; the shifted key of whatever displaced them:
;;
;;   SPC H   help-map   (SPC h is Harpoon, as in nvim; `C-h' still works too)
;;   SPC P   project    (SPC p is Session, as in nvim)
;;   SPC N   org notes  (SPC n is Docs, as in nvim)
;;   SPC o   dired      (nvim had `o' for oil and no longer has the group at
;;                       all; dired is central enough here to keep one)
;;
;; `SPC U' is `universal-argument', which used to be `SPC u' before that letter
;; became the toggle group.
;;
;; Leader is SPC in normal/visual/motion state and M-SPC everywhere else,
;; including insert state and the minibuffer.

;;; Code:

(use-package general
  :after evil
  :demand t
  :config
  ;; `general-define-key' is a function, not a macro, so this stays correct even
  ;; if this file is ever byte- or native-compiled.
  (general-define-key
   :states '(normal visual motion)
   :keymaps 'override
   :prefix "SPC"
   :global-prefix "M-SPC"

   ;; ---- top level ------------------------------------------------------
   "SPC" #'my/find-file-in-project-or-cwd
   "."   #'find-file
   ","   #'consult-buffer
   "/"   #'my/search-project-or-cwd
   ":"   #'execute-extended-command
   "`"   #'evil-switch-to-windows-last-buffer
   "e"   #'dirvish-side
   "j"   #'avy-goto-char-timer
   "J"   #'avy-goto-line
   "U"   #'universal-argument
   "q"   #'delete-frame
   "Q"   #'save-buffers-kill-emacs
   ;; nvim binds these two at the top level as well as inside their groups.
   "rn"  #'eglot-rename

   ;; ---- a: ai ----------------------------------------------------------
   "a a" #'gptel-send
   "a c" #'gptel
   "a m" #'gptel-menu
   "a r" #'gptel-rewrite
   "a A" #'gptel-add

   ;; ---- b: buffer ------------------------------------------------------
   "b b" #'consult-buffer
   "b d" #'kill-current-buffer
   "b i" #'ibuffer
   "b r" #'revert-buffer
   "b s" #'save-buffer
   "b S" #'save-some-buffers

   ;; ---- c: code --------------------------------------------------------
   "c a" #'eglot-code-actions
   "c c" #'project-compile
   "c f" #'apheleia-format-buffer
   "c r" #'eglot-rename
   "c x" #'consult-flymake

   ;; ---- d: debug (dape) ------------------------------------------------
   "d d" #'dape
   "d b" #'dape-breakpoint-toggle
   "d B" #'dape-breakpoint-remove-all
   "d c" #'dape-continue
   "d n" #'dape-next
   "d i" #'dape-step-in
   "d o" #'dape-step-out
   "d r" #'dape-restart
   "d q" #'dape-quit
   "d l" #'dape-repl
   "d e" #'dape-evaluate-expression

   ;; ---- f: find --------------------------------------------------------
   "f f" #'my/find-file-in-project-or-cwd
   "f g" #'my/search-project-or-cwd
   "f b" #'consult-buffer
   "f r" #'consult-recent-file
   "f h" #'describe-symbol
   "f ." #'consult-line
   "f s" #'consult-theme
   "f t" #'consult-todo-project
   "f R" #'my/rename-this-file
   "f d" #'dired-jump
   "f D" #'consult-dir
   "f y" #'my/yank-buffer-path
   "f S" #'write-file

   ;; ---- g: git ---------------------------------------------------------
   "g g" #'magit-status
   "g s" #'diff-hl-stage-dwim
   "g r" #'diff-hl-revert-hunk
   "g S" #'magit-stage-file
   "g R" #'magit-file-checkout
   "g p" #'diff-hl-show-hunk
   "g b" #'magit-blame-addition
   "g B" #'magit-blame
   "g d" #'magit-diff-buffer-file
   "g D" #'magit-diff-working-tree
   "g H" #'magit-log-buffer-file
   "g C" #'magit-mode-bury-buffer
   "g o" #'forge-browse-dwim
   "g f" #'forge-dispatch
   "g t" #'git-timemachine
   "g [" #'diff-hl-previous-hunk
   "g ]" #'diff-hl-next-hunk

   ;; ---- h: harpoon -----------------------------------------------------
   "h a" #'harpoon-add-file
   "h h" #'harpoon-toggle-quick-menu
   "h 1" #'harpoon-go-to-1
   "h 2" #'harpoon-go-to-2
   "h 3" #'harpoon-go-to-3
   "h 4" #'harpoon-go-to-4
   "h n" #'harpoon-go-to-next
   "h p" #'harpoon-go-to-prev
   "h e" #'harpoon-toggle-file
   "h c" #'harpoon-clear

   ;; ---- i: insert ------------------------------------------------------
   "i s" #'yas-insert-snippet
   "i y" #'consult-yank-pop

   ;; ---- l: lsp ---------------------------------------------------------
   ;; `l l' and `l r' are the two nvim binds this group exists for: toggle the
   ;; inline diagnostic rendering, and step to the next diagnostic.
   "l l" #'my/toggle-diagnostics-at-eol
   "l r" #'flymake-goto-next-error
   "l R" #'flymake-goto-prev-error
   "l a" #'eglot-code-actions
   "l f" #'apheleia-format-buffer
   "l d" #'xref-find-definitions
   "l D" #'xref-find-references
   "l i" #'eglot-find-implementation
   "l t" #'eglot-find-typeDefinition
   "l h" #'eldoc-box-help-at-point
   "l s" #'consult-eglot-symbols
   "l e" #'eglot
   "l q" #'eglot-shutdown

   ;; ---- m: multiple cursors --------------------------------------------
   "m m" #'evil-multiedit-match-all
   "m n" #'evil-multiedit-match-and-next
   "m p" #'evil-multiedit-match-and-prev
   "m s" #'evil-multiedit-match-symbol-and-next
   "m r" #'evil-multiedit-toggle-or-restrict-region
   "m x" #'evil-multiedit-abort

   ;; ---- n: docs --------------------------------------------------------
   ;; nvim's `n' is neogen, which generates a docstring.  Emacs has no
   ;; equivalent generator, so this group *reads* documentation instead.
   "n d" #'eldoc-box-help-at-point
   "n m" #'man
   "n i" #'info
   "n s" #'describe-symbol

   ;; ---- N: org notes (Emacs only) --------------------------------------
   "N a"   #'org-agenda
   "N c"   #'org-capture
   "N l"   #'org-store-link
   "N f"   #'my/find-org-file
   "N p"   #'org-download-clipboard
   "N r f" #'org-roam-node-find
   "N r i" #'org-roam-node-insert
   "N r c" #'org-roam-capture
   "N r t" #'org-roam-buffer-toggle

   ;; ---- o: dired (Emacs only) ------------------------------------------
   "o o" #'dired-jump
   "o O" #'dirvish-side
   "o d" #'dirvish

   ;; ---- p: session -----------------------------------------------------
   "p s" #'my/session-restore-for-directory
   "p l" #'my/session-reload
   "p d" #'my/session-stop-saving
   "p S" #'easysession-save
   "p D" #'easysession-delete
   "p r" #'easysession-rename

   ;; ---- P: project (Emacs only) ----------------------------------------
   "P p" #'project-switch-project
   "P f" #'project-find-file
   "P b" #'project-switch-to-buffer
   "P d" #'project-dired
   "P k" #'project-kill-buffers
   "P r" #'project-query-replace-regexp
   "P c" #'my/open-nix-dotfiles

   ;; ---- s: search ------------------------------------------------------
   "s s" #'consult-line
   "s p" #'my/search-project-or-cwd
   "s i" #'consult-imenu
   "s o" #'consult-outline
   "s m" #'consult-mark
   ;; Export a search into an editable buffer: edit the matches, `C-c C-c',
   ;; and every file is rewritten. Project-wide refactor with no extra tool.
   "s e" #'embark-export
   "s r" #'project-query-replace-regexp

   ;; ---- t: terminal ----------------------------------------------------
   "t t" #'vterm
   "t f" #'my/vterm-project
   "t h" #'my/vterm-bottom
   "t e" #'eshell

   ;; ---- u: utility / toggle --------------------------------------------
   "u u" #'vundo
   "u z" #'my/zen-mode
   "u s" #'scratch-buffer
   "u S" #'ibuffer
   "u c" #'colorful-mode
   "u d" #'hl-line-mode
   "u l" #'display-line-numbers-mode
   "u r" #'my/toggle-relative-line-numbers
   "u w" #'visual-line-mode
   "u p" #'flyspell-mode
   "u x" #'flymake-mode
   "u i" #'my/toggle-inlay-hints
   "u t" #'treesit-fold-mode
   "u k" #'keycast-mode-line-mode
   "u f" #'toggle-frame-fullscreen
   "u h" #'view-echo-area-messages
   "u e" #'flymake-show-buffer-diagnostics

   ;; ---- w: window — evil's own C-w map, verbatim -----------------------
   "w" evil-window-map

   ;; ---- x: diagnostics (trouble) ---------------------------------------
   "x x" #'flymake-show-project-diagnostics
   "x X" #'flymake-show-buffer-diagnostics
   "x s" #'consult-imenu
   "x S" #'consult-eglot-symbols
   "x l" #'xref-find-references
   "x q" #'consult-compile-error
   "x t" #'consult-todo-project
   "x f" #'consult-flymake

   ;; ---- H: help — the whole of `C-h' -----------------------------------
   "H" help-map)

  ;; which-key shows command names on its own; these just name the prefixes,
  ;; with the same labels the Neovim config gives them.
  (which-key-add-key-based-replacements
    "SPC a"   "ai"
    "SPC b"   "buffer"
    "SPC c"   "code"
    "SPC d"   "debug"
    "SPC f"   "find"
    "SPC g"   "git"
    "SPC h"   "harpoon"
    "SPC i"   "insert"
    "SPC l"   "lsp"
    "SPC m"   "multiple cursors"
    "SPC n"   "docs"
    "SPC N"   "notes"
    "SPC N r" "roam"
    "SPC o"   "dired"
    "SPC p"   "session"
    "SPC P"   "project"
    "SPC s"   "search"
    "SPC t"   "terminal"
    "SPC u"   "utility / toggle"
    "SPC w"   "window"
    "SPC x"   "diagnostics"
    "SPC H"   "help"))

(provide 'keymaps)
;;; keymaps.el ends here

;;; init.el --- Emacs configuration  -*- lexical-binding: t; -*-

;;; Commentary:
;; Managed by modules/home/programs/dev/emacs.  Every package on the load-path
;; was put there by the Nix wrapper, so no use-package form needs :ensure and
;; `M-x package-install' will not work — add the package in default.nix and
;; rebuild instead.
;;
;; This file is a read-only /nix/store symlink.  For throwaway experiments that
;; should not need a rebuild, write ~/.config/emacs/personal.el; it is loaded
;; last, and anything worth keeping can be promoted into this file afterwards.
;;
;; Leader is SPC in normal state and M-SPC anywhere (including insert state and
;; the minibuffer).  `SPC h b' lists every binding currently in effect, and
;; `SPC h k' explains whichever key you press next.
;;
;; Nothing here is byte-compiled, which is why macros from a package (rather
;; than functions) are safe to call inside a deferred :config block.

;;; Code:

;; Bundled with Emacs since 29, but only autoloaded — requiring it explicitly
;; keeps this file working if that ever changes.
(require 'use-package)

;;;; ------------------------------------------------------------------ startup

;; early-init.el turned the collector off to get through this file; put it back
;; on a threshold large enough not to thrash and small enough not to stall.
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 64 1024 1024)
                  gc-cons-percentage 0.1)))

;; The daemon starts before the compositor has a frame, so anything that probes
;; frame parameters at load time has to wait for the first client instead.
(defun my/on-first-frame (fn)
  "Run FN now if a graphical frame exists, otherwise once one does."
  (if (daemonp)
      (add-hook 'server-after-make-frame-hook fn)
    (funcall fn)))

;; Both org and org-roam need this, and org-roam's :config would otherwise read
;; `org-directory' — a variable that only exists once org.el has loaded. That
;; happens to work today because org-roam pulls org in, but it is an ordering
;; assumption with no reason to hold.
(defconst my/org-directory (expand-file-name "~/org"))

(defun my/read-secret (name)
  "Return the contents of the sops secret NAME, or nil if unreadable.
The daemon inherits the systemd user environment, which never sourced the
zsh profile that exports these as variables, so they are read from disk."
  (let ((file (expand-file-name name "/run/secrets")))
    (when (file-readable-p file)
      (string-trim (with-temp-buffer
                     (insert-file-contents file)
                     (buffer-string))))))

;;;; ------------------------------------------------------------- sane defaults

(use-package emacs
  :init
  (setq inhibit-startup-screen t
        initial-scratch-message nil
        ;; A GUI dialog on a tiling compositor is a floating window that steals
        ;; focus; the minibuffer prompt is strictly better.
        use-dialog-box nil
        use-short-answers t
        ;; Emacs asks about symlinked files under version control on every save
        ;; otherwise, and this whole config is symlinks.
        vc-follow-symlinks t
        ;; Backups and autosaves in the file's own directory pollute every repo.
        backup-directory-alist `(("." . ,(expand-file-name "backups" user-emacs-directory)))
        auto-save-file-name-transforms `((".*" ,(expand-file-name "autosave/" user-emacs-directory) t))
        create-lockfiles nil
        ;; Follow the file on disk when something else changed it — git
        ;; checkouts, formatters, the other editor.
        auto-revert-verbose nil
        ;; Scrolling that does not recentre the window every time point leaves
        ;; the viewport, which is what makes stock Emacs feel unlike vim.
        scroll-conservatively 101
        scroll-margin 4
        ;; `M-x' offers commands that make no sense in the current mode by
        ;; default; this hides them.
        read-extended-command-predicate #'command-completion-default-include-p
        ;; The minibuffer can be recursive, which consult and embark rely on.
        enable-recursive-minibuffers t)

  ;; These three are automatically buffer-local, so plain `setq' would only
  ;; ever affect *scratch*.
  (setq-default fill-column 80
                indent-tabs-mode nil
                tab-width 4)

  :config
  (global-auto-revert-mode 1)
  (savehist-mode 1)          ; minibuffer history across restarts
  (save-place-mode 1)        ; reopen files at the last cursor position
  (recentf-mode 1)           ; feeds consult-recent-file
  (delete-selection-mode 1)
  (column-number-mode 1)
  (global-so-long-mode 1)    ; do not hang on minified files
  (electric-pair-mode 1)

  ;; Relative numbers in prog buffers only; org and magit are worse with them.
  (add-hook 'prog-mode-hook #'display-line-numbers-mode)
  (setq display-line-numbers-type 'relative)

  ;; A little air between lines. At 0 the default face sits tight enough that
  ;; CJK text and Latin text visibly disagree about line height.
  (setq-default line-spacing 0.15)

  ;; ediff otherwise spawns a separate frame for its control panel, which on a
  ;; tiling compositor lands as a floating window in the wrong workspace.
  (setq ediff-window-setup-function #'ediff-setup-windows-plain
        ediff-split-window-function #'split-window-horizontally))

;; Trailing whitespace is trimmed only on lines this session actually touched.
;; A global `delete-trailing-whitespace' on save rewrites lines the commit never
;; went near and buries the real change in the diff.
(use-package ws-butler
  :init (ws-butler-global-mode 1))

;;;; ------------------------------------------------------------------- fonts

;; JetBrainsMono Nerd Font matches foot; Noto Sans CJK SC is the system CJK
;; default from system/user/fonts.nix.  Height is in tenths of a point — raise
;; or lower this one number if the whole UI is the wrong size.  `C-x C-=' and
;; `C-x C--' adjust the current buffer without a rebuild.
(defvar my/font-height 110)

(defun my/setup-fonts ()
  "Apply the monospace and CJK fonts to the current frame."
  (set-face-attribute 'default nil
                      :family "JetBrainsMono Nerd Font"
                      :height my/font-height)
  (set-face-attribute 'fixed-pitch nil :family "JetBrainsMono Nerd Font")
  ;; Variable-pitch is only used by org-modern headings and a few help buffers.
  (set-face-attribute 'variable-pitch nil :family "Noto Sans CJK SC" :height 1.0)
  ;; Without this, Han characters fall back to whatever fontconfig picks first,
  ;; which is rarely the CJK face and never lines up on the character grid.
  (dolist (charset '(han cjk-misc kana hangul bopomofo))
    (set-fontset-font t charset (font-spec :family "Noto Sans CJK SC"))))

(my/on-first-frame #'my/setup-fonts)

;; JetBrains Mono ships programming ligatures; Emacs renders them through
;; HarfBuzz but only for the character sequences it is told about.
(use-package ligature
  :config
  (ligature-set-ligatures
   'prog-mode
   '("|||>" "<|||" "<==>" "<!--" "####" "~~>" "***" "||=" "||>"
     ":::" "::=" "=:=" "===" "==>" "=!=" "=>>" "=<<" "=/=" "!=="
     "!!." ">=>" ">>=" ">>>" ">>-" ">->" "->>" "-->" "---" "-<<"
     "<~~" "<~>" "<*>" "<||" "<|>" "<$>" "<==" "<=>" "<=<" "<->"
     "<--" "<-<" "<<=" "<<-" "<<<" "<+>" "</>" "###" "#_(" "..<"
     "..." "+++" "/==" "///" "_|_" "www" "&&" "^=" "~~" "~@" "~="
     "~>" "~-" "**" "*>" "*/" "||" "|}" "|]" "|=" "|>" "|-" "{|"
     "[|" "]#" "::" ":=" ":>" ":<" "$>" "==" "=>" "!=" "!!" ">:"
     ">=" ">>" ">-" "-~" "-|" "->" "--" "-<" "<~" "<*" "<|" "<:"
     "<$" "<=" "<>" "<-" "<<" "<+" "</" "#{" "#[" "#:" "#=" "#!"
     "##" "#(" "#?" "#_" "%%" ".=" ".-" ".." ".?" "+>" "++" "?:"
     "?=" "?." "??" ";;" "/*" "/=" "/>" "//" "__" "~~" "(*" "*)"
     "\\\\" "://"))
  (global-ligature-mode 1))

;;;; ------------------------------------------------------------------- theme

(use-package doom-themes
  :config
  (setq doom-themes-enable-bold t
        doom-themes-enable-italic t)
  ;; doom-nord rather than plain nord-theme: it ships the face definitions that
  ;; magit, org and doom-modeline expect, and it matches the fcitx5 Nord-Dark
  ;; candidate window in base/input-method.nix.
  (load-theme 'doom-nord t)
  ;; Org face tweaks live in a separate file that the nixpkgs build does not
  ;; generate an autoload for, so `doom-themes-org-config' is void until it is
  ;; required by hand.
  (when (require 'doom-themes-ext-org nil t)
    (doom-themes-org-config)))

(use-package nerd-icons)

(use-package doom-modeline
  :init (doom-modeline-mode 1)
  :config
  (setq doom-modeline-height 28
        doom-modeline-buffer-file-name-style 'relative-to-project
        ;; The icon set needs nerd-fonts.symbols-only, which fonts.nix installs.
        doom-modeline-icon t))

(use-package hl-todo
  :hook (prog-mode . hl-todo-mode))

;; Header line: project-relative path, then the function or class point is
;; inside. `breadcrumb-local-mode' rather than the global mode, which would
;; also claim the header line in magit, dired and the agenda.
(use-package breadcrumb
  :hook (prog-mode . breadcrumb-local-mode))

;; Prose in org and markdown gets the proportional face; code blocks, tables
;; and inline verbatim stay on the monospace one.
(use-package mixed-pitch
  :hook ((org-mode markdown-mode) . mixed-pitch-mode))

;; A popup already announces itself by sitting at the bottom of the frame; a
;; mode line in each one is redundant chrome.
(use-package hide-mode-line
  :hook ((help-mode helpful-mode pdf-view-mode) . hide-mode-line-mode))

(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

;; Draws a swatch beside #rrggbb, named colours and hsl() rather than
;; recolouring the text itself, which would fight the Nord ground.
(use-package colorful-mode
  :hook ((css-ts-mode conf-mode nix-ts-mode) . colorful-mode)
  :config (setq colorful-use-prefix t))

;; ---- the three that change how the frame itself reads -------------------

;; Stock Emacs packs text flush against the window border and glues the mode
;; line to the bottom edge. This gives the frame an internal border, real
;; window dividers, and a mode line that floats.
(use-package spacious-padding
  :init
  ;; The widths have to be set *before* the mode turns on — it reads them once
  ;; when enabled, so a `:config' setq would silently leave the defaults in
  ;; place (verified: internal-border-width came out 15, not the value here).
  (setq spacious-padding-widths
        '(:internal-border-width 16
          :header-line-width 4
          :mode-line-width 5
          :tab-width 4
          :right-divider-width 20
          :scroll-bar-width 8
          :fringe-width 10))
  (spacious-padding-mode 1))

;; Buffers that are not visiting a file get a slightly different background,
;; so magit, help, dired and the popup window read as chrome while the code
;; reads as content.
(use-package solaire-mode
  :init (solaire-global-mode 1))

;; A brief pulse on the line jumped to. With avy, xref and window switching all
;; moving point across the frame, this is the cheapest way not to lose it.
(use-package pulsar
  :init (pulsar-global-mode 1)
  :config
  (setq pulsar-pulse t
        pulsar-delay 0.055
        pulsar-iterations 8)
  (dolist (fn '(evil-scroll-down evil-scroll-up evil-goto-line
                evil-window-down evil-window-up
                evil-window-left evil-window-right))
    (add-to-list 'pulsar-pulse-functions fn)))

;; Indentation guides.  `indent-bars-prefer-character' draws them with a real
;; glyph instead of a stipple bitmap: stipples are computed per frame, and under
;; the daemon the first frame does not exist yet when the mode turns on.
(use-package indent-bars
  :hook ((python-ts-mode yaml-ts-mode nix-ts-mode) . indent-bars-mode)
  :config
  (setq indent-bars-prefer-character t
        indent-bars-treesit-support t
        indent-bars-no-descend-string t))

;; Built into Emacs 30 — no package needed.
(use-package which-key
  :init (which-key-mode 1)
  :config
  (setq which-key-idle-delay 0.4
        which-key-sort-order #'which-key-key-order-alpha))

;;;; ------------------------------------------------------------------- evil

(use-package evil
  :init
  ;; Both of these are read when evil loads, so they cannot move to :config.
  ;; evil-collection refuses to load unless the first one is nil.
  (setq evil-want-keybinding nil
        evil-want-integration t
        evil-want-C-u-scroll t
        evil-want-C-i-jump t
        evil-respect-visual-line-mode t
        ;; vim-style splits.
        evil-split-window-below t
        evil-vsplit-window-right t
        ;; Emacs 28+ has real undo-redo; without this, `C-r' does nothing.
        evil-undo-system 'undo-redo
        ;; Y should behave like D and C, not like yy.
        evil-want-Y-yank-to-eol t)
  :config
  (evil-mode 1)
  ;; The minibuffer is not a text editor; modal state there fights completion.
  (setq evil-echo-state nil)
  ;; State shows in the mode line, but the cursor is where the eye already is.
  ;; Nord: frost blue normal, aurora yellow insert, purple visual, red replace.
  (setq evil-normal-state-cursor   '("#81a1c1" box)
        evil-insert-state-cursor   '("#ebcb8b" (bar . 2))
        evil-visual-state-cursor   '("#b48ead" box)
        evil-replace-state-cursor  '("#bf616a" hbar)
        evil-operator-state-cursor '("#88c0d0" hollow)))

(use-package evil-collection
  :after evil
  :config
  ;; Rebinds ~800 keymaps (magit, dired, org, help, vterm…) to evil-style keys.
  ;; This is the difference between "vim keys in files" and "vim keys in Emacs".
  (evil-collection-init))

(use-package evil-surround
  :after evil
  :config (global-evil-surround-mode 1))

;; vim's C-a / C-x, which evil leaves unbound because Emacs already owns C-a.
(use-package evil-numbers
  :after evil
  :config
  (evil-define-key '(normal visual) 'global
    (kbd "g +") #'evil-numbers/inc-at-pt
    (kbd "g -") #'evil-numbers/dec-at-pt))

;; `af'/`if' for a function, `ac'/`ic' for a class, `aa'/`ia' for a parameter —
;; the same text objects nvim-treesitter-textobjects provides, off the same
;; grammars early-init.el already loaded.
(use-package evil-textobj-tree-sitter
  :after evil
  :config
  (define-key evil-outer-text-objects-map "f"
              (evil-textobj-tree-sitter-get-textobj "function.outer"))
  (define-key evil-inner-text-objects-map "f"
              (evil-textobj-tree-sitter-get-textobj "function.inner"))
  (define-key evil-outer-text-objects-map "c"
              (evil-textobj-tree-sitter-get-textobj "class.outer"))
  (define-key evil-inner-text-objects-map "c"
              (evil-textobj-tree-sitter-get-textobj "class.inner"))
  (define-key evil-outer-text-objects-map "a"
              (evil-textobj-tree-sitter-get-textobj "parameter.outer"))
  (define-key evil-inner-text-objects-map "a"
              (evil-textobj-tree-sitter-get-textobj "parameter.inner")))

;; Simultaneous edits of every match, which is what people actually want from
;; "multiple cursors" most of the time.  `R' in visual state edits all matches
;; in the region; `M-d' adds the next occurrence of the symbol at point.
(use-package evil-multiedit
  :after evil
  :config (evil-multiedit-default-keybinds))

;; Flashes the region an operator just acted on.  Without it, `d2}' gives no
;; feedback at all about what was deleted.
(use-package evil-goggles
  :after evil
  :config
  (setq evil-goggles-duration 0.1
        evil-goggles-pulse nil)
  (evil-goggles-mode 1)
  (evil-goggles-use-diff-faces))

(use-package evil-org
  :after (evil org)
  :hook (org-mode . evil-org-mode)
  :config
  (require 'evil-org-agenda)
  (evil-org-agenda-set-keys))

;;;; ---------------------------------------------------------------- keybinds

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

   "SPC" #'project-find-file
   "."   #'find-file
   ","   #'consult-buffer
   "/"   #'consult-ripgrep
   ":"   #'execute-extended-command
   "`"   #'evil-switch-to-windows-last-buffer
   "u"   #'universal-argument
   "j"   #'avy-goto-char-timer
   "J"   #'avy-goto-line

   ;; ai — gptel, pointed at the DeepSeek key already in sops
   "a a" #'gptel-send
   "a c" #'gptel
   "a m" #'gptel-menu
   "a r" #'gptel-rewrite
   "a A" #'gptel-add

   ;; buffer
   "b b" #'consult-buffer
   "b i" #'ibuffer
   "b k" #'kill-current-buffer
   "b r" #'revert-buffer
   "b s" #'save-buffer
   "b S" #'save-some-buffers

   ;; code — eglot is built in since Emacs 29
   "c a" #'eglot-code-actions
   "c c" #'project-compile
   "c d" #'xref-find-definitions
   "c D" #'xref-find-references
   "c f" #'apheleia-format-buffer
   "c l" #'eglot
   "c r" #'eglot-rename
   "c s" #'consult-eglot-symbols
   "c t" #'consult-todo-project
   "c x" #'consult-flymake

   ;; debug — dape
   "d d" #'dape
   "d b" #'dape-breakpoint-toggle
   "d B" #'dape-breakpoint-remove-all
   "d c" #'dape-continue
   "d n" #'dape-next
   "d i" #'dape-step-in
   "d o" #'dape-step-out
   "d r" #'dape-restart
   "d q" #'dape-quit

   ;; file
   "f f" #'find-file
   "f d" #'dired-jump
   "f D" #'consult-dir
   "f r" #'consult-recent-file
   "f s" #'save-buffer
   "f S" #'write-file
   "f y" #'my/yank-buffer-path

   ;; git
   "g g" #'magit-status
   "g b" #'magit-blame-addition
   "g l" #'magit-log-buffer-file
   "g d" #'magit-diff-buffer-file
   "g f" #'forge-dispatch
   "g t" #'git-timemachine
   "g s" #'diff-hl-show-hunk
   "g [" #'diff-hl-previous-hunk
   "g ]" #'diff-hl-next-hunk

   ;; help — the whole of `C-h' lives here
   "h" help-map

   ;; insert
   "i s" #'yas-insert-snippet
   "i y" #'consult-yank-pop

   ;; notes (org)
   "n a" #'org-agenda
   "n c" #'org-capture
   "n l" #'org-store-link
   "n f" #'my/find-org-file
   "n r f" #'org-roam-node-find
   "n r i" #'org-roam-node-insert
   "n r c" #'org-roam-capture
   "n r t" #'org-roam-buffer-toggle
   "n p" #'org-download-clipboard

   ;; open
   "o t" #'vterm
   "o e" #'eshell
   "o d" #'dired
   "o -" #'dired-jump
   "o p" #'popper-toggle
   "o P" #'popper-cycle

   ;; project
   "p p" #'project-switch-project
   "p f" #'project-find-file
   "p b" #'project-switch-to-buffer
   "p d" #'project-dired
   "p k" #'project-kill-buffers
   "p c" #'my/open-nix-dotfiles

   ;; search
   "s s" #'consult-line
   "s p" #'consult-ripgrep
   "s i" #'consult-imenu
   "s o" #'consult-outline
   "s m" #'consult-mark
   ;; Export a search into an editable buffer: edit the matches, `C-c C-c',
   ;; and every file is rewritten. Project-wide refactor with no extra tool.
   "s e" #'embark-export

   ;; toggle
   "t l" #'display-line-numbers-mode
   "t w" #'visual-line-mode
   "t f" #'toggle-frame-fullscreen
   "t u" #'vundo
   "t c" #'colorful-mode
   "t k" #'keycast-mode-line-mode

   ;; window — evil's own C-w map, verbatim
   "w" evil-window-map

   ;; quit.  Under the daemon `q q' must close the frame, not the session; the
   ;; capital is the one that takes every other frame down with it.
   "q q" #'delete-frame
   "q Q" #'save-buffers-kill-emacs)

  ;; which-key shows command names on its own; these just name the prefixes.
  (which-key-add-key-based-replacements
    "SPC a" "ai"
    "SPC b" "buffer"
    "SPC c" "code"
    "SPC d" "debug"
    "SPC f" "file"
    "SPC g" "git"
    "SPC h" "help"
    "SPC i" "insert"
    "SPC n" "notes"
    "SPC n r" "roam"
    "SPC o" "open"
    "SPC p" "project"
    "SPC s" "search"
    "SPC t" "toggle"
    "SPC w" "window"
    "SPC q" "quit"))

;; Jump to any visible window by letter, which beats counting `C-w w'.
(use-package ace-window
  :commands (ace-window)
  :init (with-eval-after-load 'evil (define-key evil-window-map "a" #'ace-window))
  :config (setq aw-scope 'frame
                aw-keys '(?a ?s ?d ?f ?g ?h ?j ?k ?l)))

(use-package avy
  :commands (avy-goto-char-timer avy-goto-line)
  :config (setq avy-timeout-seconds 0.3))

;;;; ------------------------------------------------------------- completion

(use-package vertico
  :init (vertico-mode 1)
  :config
  (setq vertico-cycle t
        vertico-count 15))

(use-package orderless
  :init
  ;; Space-separated fragments matched in any order — the closest thing to
  ;; telescope's fuzzy behaviour.  `basic' stays as a fallback so that TAB on a
  ;; file path still completes literally.
  (setq completion-styles '(orderless basic)
        completion-category-defaults nil
        completion-category-overrides '((file (styles partial-completion)))))

(use-package marginalia
  :init (marginalia-mode 1))

(use-package nerd-icons-completion
  :after (marginalia nerd-icons)
  :config
  (nerd-icons-completion-mode 1)
  (add-hook 'marginalia-mode-hook #'nerd-icons-completion-marginalia-setup))

(use-package consult
  :config
  ;; Preview on an explicit key rather than on every cursor move: the default
  ;; `any' opens remote and very large files just by scrolling past them.  This
  ;; is the plain variable rather than `consult-customize' on purpose — the
  ;; latter is a macro, and macros inside a deferred :config block break if this
  ;; file is ever byte-compiled.
  (setq consult-preview-key "M-."
        consult-narrow-key "<"
        ;; project.el decides what "the project" is, so ripgrep and buffer
        ;; scoping agree with `SPC p'.
        consult-project-function (lambda (_) (when-let* ((p (project-current))) (project-root p)))))

;; Switch the directory a find-file prompt is rooted at, mid-prompt.
(use-package consult-dir
  :commands (consult-dir)
  :init
  (with-eval-after-load 'vertico
    (define-key vertico-map (kbd "C-x C-d") #'consult-dir)))

(use-package embark
  :bind (("C-." . embark-act)
         ("C-;" . embark-dwim))
  :init
  ;; evil's normal-state map binds C-. to `evil-repeat-pop', and a state map
  ;; shadows the global one — so the :bind above reaches the minibuffer but
  ;; never a normal-state buffer, which is half of what embark is for.
  (with-eval-after-load 'evil
    (evil-define-key '(normal visual insert) 'global (kbd "C-.") #'embark-act))
  :config
  ;; embark-act on a candidate is the "what can I do with this?" key: rename a
  ;; file from the find-file prompt, kill a buffer from the switch prompt.
  (setq prefix-help-command #'embark-prefix-help-command))

(use-package embark-consult
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))

;; Makes an exported grep buffer writable.  `SPC s e' on a ripgrep result, edit
;; the lines, `C-c C-c'.
(use-package wgrep
  :after embark-consult
  :config (setq wgrep-auto-save-buffer t))

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

(use-package nerd-icons-corfu
  :after corfu
  :config (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))

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

(use-package yasnippet
  :init (yas-global-mode 1)
  :config (setq yas-verbosity 1))

(use-package yasnippet-snippets
  :after yasnippet)

;;;; ---------------------------------------------------------------- version

(use-package magit
  :commands (magit-status magit-blame-addition magit-log-buffer-file)
  :config
  (setq magit-diff-refine-hunk 'all
        ;; Open the status buffer full-frame and restore the layout on quit.
        magit-display-buffer-function #'magit-display-buffer-fullframe-status-v1))

;; GitHub issues and pull requests as magit sections.  Needs a token in
;; ~/.authinfo.gpg (machine api.github.com login <user>^forge password <token>);
;; until then `SPC g f' simply prompts for one.
(use-package forge
  :after magit)

;; Scans the repository for TODO/FIXME and lists them in the status buffer.
(use-package magit-todos
  :after magit
  :config (magit-todos-mode 1))

;; Pipes magit's diffs through delta, which programs.git.delta already sets as
;; git's pager — so a hunk looks the same in the terminal and in Emacs.
;; `magit-diff-refine-hunk' is turned off here because delta does its own
;; intra-line highlighting and the two draw over each other.
(use-package magit-delta
  :hook (magit-mode . magit-delta-mode)
  :config (setq magit-delta-default-dark-theme "Nord"
                magit-diff-refine-hunk nil))

;; Step a single file backwards through its own history, one commit per key.
(use-package git-timemachine
  :commands (git-timemachine))

(use-package diff-hl
  :hook ((prog-mode . diff-hl-mode)
         (dired-mode . diff-hl-dired-mode))
  :config
  ;; Without these two hooks the fringe indicators go stale the moment magit
  ;; stages or commits anything.
  (add-hook 'magit-pre-refresh-hook #'diff-hl-magit-pre-refresh)
  (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh)
  (diff-hl-flydiff-mode 1))

;;;; ------------------------------------------------------------------ tools

(use-package envrc
  :init (envrc-global-mode 1))

(use-package vterm
  :commands vterm
  :config (setq vterm-max-scrollback 10000))

;; A dired that behaves like a file manager: preview pane, icons, a header line
;; with the path, and `TAB' to peek at whatever is under point.
(use-package dirvish
  :init (dirvish-override-dired-mode 1)
  :config
  (setq dirvish-attributes '(nerd-icons file-size vc-state git-msg)
        dirvish-mode-line-format '(:left (sort file-time symlink) :right (omit yank index))
        ;; `dired-listing-switches' has to sort directories first or the preview
        ;; pane is unusable in a large tree.
        dired-listing-switches "-l --almost-all --human-readable --group-directories-first --no-group"))

(use-package nerd-icons-dired
  :hook (dired-mode . nerd-icons-dired-mode))

;; Help, compilation, vterm and friends open in one reusable bottom window
;; instead of stealing whichever split happened to be focused.
(use-package popper
  :init
  (setq popper-reference-buffers
        '("\\*Messages\\*"
          "\\*Warnings\\*"
          "\\*Async Shell Command\\*"
          "\\*eldoc\\*"
          help-mode
          helpful-mode
          compilation-mode
          flymake-diagnostics-buffer-mode
          vterm-mode))
  (popper-mode 1)
  (popper-echo-mode 1)
  :config (setq popper-window-height 0.35))

(use-package helpful
  :bind (([remap describe-function] . helpful-callable)
         ([remap describe-variable] . helpful-variable)
         ([remap describe-key]      . helpful-key)
         ([remap describe-command]  . helpful-command)))

;; The undo *tree*, not the undo list: branches you created by undoing and then
;; typing are otherwise unreachable without knowing `undo-redo' by heart.
(use-package vundo
  :commands (vundo)
  :config (setq vundo-glyph-alist vundo-unicode-symbols))

;; Undo history persisted per file. This matters more here than on most setups
;; because pgtk takes the whole daemon down when the Wayland socket drops.
(use-package undo-fu-session
  :init (undo-fu-session-global-mode 1)
  :config
  (setq undo-fu-session-directory (expand-file-name "undo" user-emacs-directory)
        undo-fu-session-incompatible-files
        '("/COMMIT_EDITMSG\\'" "/git-rebase-todo\\'")))

;; Shows the key just pressed and the command it ran. Off by default, since it
;; is a learning aid rather than a permanent fixture — `SPC t k' turns it on.
(use-package keycast
  :commands (keycast-mode-line-mode keycast-log-mode))

;; Inline evaluation results, printed next to the form instead of flashing past
;; in the echo area. `C-x C-e' in any elisp buffer.
(use-package eros
  :hook (emacs-lisp-mode . eros-mode))

(use-package nerd-icons-ibuffer
  :hook (ibuffer-mode . nerd-icons-ibuffer-mode))

;; Debug Adapter Protocol — the one large capability eglot does not cover.
;; gdb 17.2 speaks DAP natively (`gdb --interpreter=dap'), so C and C++ need no
;; separate adapter; Python goes through debugpy, installed in default.nix.
(use-package dape
  ;; Every one of these is on a `SPC d' key, and only `dape' and
  ;; `dape-breakpoint-toggle' carry their own autoload cookie — without the
  ;; rest listed here, `SPC d c' before a session exists is a void-function
  ;; error rather than a no-op.
  :commands (dape dape-breakpoint-toggle dape-breakpoint-remove-all
             dape-continue dape-next dape-step-in dape-step-out
             dape-restart dape-quit dape-pause)
  :config
  (setq dape-buffer-window-arrangement 'right
        ;; Without this the adapter starts in whatever directory the daemon was
        ;; launched from rather than the project root.
        dape-cwd-function #'my/project-root-or-default)
  ;; Save any modified buffer before starting a session; debugging a stale
  ;; binary against fresh source is a special kind of waste.
  (add-hook 'dape-start-hook (lambda () (save-some-buffers t t))))

;; Workspace-wide symbol lookup from the language server. consult-imenu only
;; ever sees the current file.
(use-package consult-eglot
  :commands (consult-eglot-symbols))

;; Every TODO/FIXME in the project as a completion list.
(use-package consult-todo
  :commands (consult-todo consult-todo-project))

;; Runs the formatter in a subprocess and patches the buffer, so a slow
;; formatter cannot freeze a single-threaded editor mid-save.
(use-package apheleia
  :init (apheleia-global-mode 1)
  :config
  ;; The stock alist keys the classic major modes; these are the tree-sitter
  ;; ones this config remaps to.  nixfmt is the same formatter `nix fmt' runs
  ;; through treefmt, so save-time and CI cannot disagree.
  (dolist (entry '((nix-ts-mode    . nixfmt)
                   (lua-ts-mode    . stylua)
                   (c-ts-mode      . clang-format)
                   (c++-ts-mode    . clang-format)
                   (python-ts-mode . ruff)
                   (bash-ts-mode   . shfmt)
                   (json-ts-mode   . prettier-json)
                   (yaml-ts-mode   . prettier-yaml)))
    (setf (alist-get (car entry) apheleia-mode-alist) (cdr entry))))

;; Folding driven by the grammar rather than by indentation, wired to the vim
;; keys evil would otherwise point at hideshow.
(use-package treesit-fold
  :init (global-treesit-fold-mode 1)
  :config
  (with-eval-after-load 'evil
    (evil-define-key 'normal 'global
      (kbd "z a") #'treesit-fold-toggle
      (kbd "z c") #'treesit-fold-close
      (kbd "z o") #'treesit-fold-open
      (kbd "z M") #'treesit-fold-close-all
      (kbd "z R") #'treesit-fold-open-all)))

;;;; --------------------------------------------------------------- languages

;; Prefer the tree-sitter major modes where Emacs 30 ships one and early-init.el
;; found a grammar.  Anything not listed keeps its classic mode.
(setq major-mode-remap-alist
      '((bash-mode       . bash-ts-mode)
        (sh-mode         . bash-ts-mode)
        (c-mode          . c-ts-mode)
        (c++-mode        . c++-ts-mode)
        (cmake-mode      . cmake-ts-mode)
        (css-mode        . css-ts-mode)
        (java-mode       . java-ts-mode)
        (javascript-mode . js-ts-mode)
        (js-mode         . js-ts-mode)
        (json-mode       . json-ts-mode)
        (js-json-mode    . json-ts-mode)
        (python-mode     . python-ts-mode)
        (conf-toml-mode  . toml-ts-mode)
        (yaml-mode       . yaml-ts-mode)))

;; The remap above only fires for extensions Emacs already recognises.  These
;; have no classic major mode installed to remap *from*, so they need a direct
;; `auto-mode-alist' entry — without it .yaml opens in fundamental-mode and
;; go.mod, of all things, opens in m2-mode.
(dolist (entry '(("\\.ya?ml\\'"                    . yaml-ts-mode)
                 ("\\(?:Dockerfile\\|\\.dockerfile\\)\\'" . dockerfile-ts-mode)
                 ("\\.rs\\'"                       . rust-ts-mode)
                 ("\\.go\\'"                       . go-ts-mode)
                 ("/go\\.mod\\'"                   . go-mod-ts-mode)
                 ("\\.ts\\'"                       . typescript-ts-mode)
                 ("\\.tsx\\'"                      . tsx-ts-mode)
                 ("\\.lua\\'"                      . lua-ts-mode)
                 ("\\(?:CMakeLists\\.txt\\|\\.cmake\\)\\'" . cmake-ts-mode)))
  (add-to-list 'auto-mode-alist entry))

(use-package nix-ts-mode
  :mode "\\.nix\\'")

(use-package markdown-mode
  :mode ("\\.md\\'" . markdown-mode))

;; eglot is built in since Emacs 29.  It is auto-started only for languages
;; whose server is installed: clangd from llvm.nix, lua-language-server from
;; lua.nix, texlab from latex.nix, and nixd from this module.  Everywhere else
;; `SPC c l' starts it by hand once a server is on PATH.
(use-package eglot
  :hook ((c-ts-mode c++-ts-mode lua-ts-mode nix-ts-mode LaTeX-mode) . eglot-ensure)
  :config
  (setq eglot-autoshutdown t
        ;; `eglot-events-buffer-size' has been obsolete since eglot 1.16 and
        ;; setting it does nothing — the log stayed at its 2 MB default, quietly
        ;; recording every LSP message. This is the option that replaced it.
        ;; Set :size to a number instead of nil when a server needs debugging.
        eglot-events-buffer-config '(:size 0 :format short)
        eglot-sync-connect nil
        ;; How long after a keystroke the server is told what changed. The
        ;; default 0.5 means a completion request fired at 0.3 s describes text
        ;; the server has not seen yet, and eglot has to flush first.
        eglot-send-changes-idle-time 0.2)
  ;; nixd needs to be told which flake to evaluate before it can complete
  ;; NixOS and Home Manager option names rather than just builtins.
  (add-to-list 'eglot-server-programs
               '(nix-ts-mode . ("nixd"))))

;; eglot puts signatures in the echo area, which is one line tall and gone as
;; soon as anything else prints.  This is the same content in a child frame.
(use-package eldoc-box
  :hook (eglot-managed-mode . eldoc-box-hover-at-point-mode))

;; AUCTeX replaces the built-in latex-mode outright: it knows the document
;; structure, runs the toolchain with `C-c C-c', and does forward/inverse
;; search against pdf-tools.
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

;;;; -------------------------------------------------------------------- org

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
  :after org
  ;; Bound to `SPC n p', which has to work without org-download having been
  ;; touched yet.
  :commands (org-download-clipboard org-download-yank org-download-screenshot)
  :config
  (setq org-download-method 'directory
        org-download-image-dir (expand-file-name "images" my/org-directory)
        org-download-heading-lvl nil
        ;; The default annotation stamps the source URL above every image,
        ;; which is noise for a clipboard paste.
        org-download-annotate-function (lambda (_link) "")))

;; HTTP requests written as org documents: describe the request under a
;; heading, `C-c C-r C-r' to send it, response opens in its own buffer.
(use-package verb
  :after org
  :config (define-key org-mode-map (kbd "C-c C-r") verb-command-map))

;;;; --------------------------------------------------------------------- ai

;; The API key is the sops secret at /run/secrets/deepseek-api-key. It is read
;; lazily through a lambda so the token never sits in a variable that
;; `describe-variable' or a backtrace could print.
(use-package gptel
  :commands (gptel gptel-send gptel-menu gptel-rewrite gptel-add)
  :config
  (setq gptel-default-mode #'org-mode)
  (let ((deepseek
         (gptel-make-openai "DeepSeek"
           :host "api.deepseek.com"
           :endpoint "/chat/completions"
           :stream t
           :key (lambda () (my/read-secret "deepseek-api-key"))
           ;; These are the slugs codex/models.json pins. If the chat endpoint
           ;; rejects them, `gptel-menu' switches model at runtime — no rebuild.
           :models '(deepseek-v4-flash deepseek-v4-pro))))
    (setq gptel-backend deepseek
          gptel-model 'deepseek-v4-flash)))

;;;; ---------------------------------------------------------------- commands

(defun my/project-root-or-default ()
  "Return the current project root, or `default-directory' outside a project."
  (if-let* ((project (project-current)))
      (project-root project)
    default-directory))

(defun my/open-nix-dotfiles ()
  "Open the NixOS configuration repository."
  (interactive)
  (project-switch-project (expand-file-name "~/nix-dotfiles/")))

(defun my/find-org-file ()
  "Find a file under `org-directory'."
  (interactive)
  (require 'org)
  (let ((default-directory org-directory))
    (call-interactively #'find-file)))

(defun my/yank-buffer-path ()
  "Copy the current buffer's path, relative to the project when there is one."
  (interactive)
  (if-let* ((file (buffer-file-name)))
      (let* ((project (project-current))
             (path (if project
                       (file-relative-name file (project-root project))
                     file)))
        (kill-new path)
        (message "%s" path))
    (user-error "This buffer is not visiting a file")))

;;;; ------------------------------------------------------------------- local

;; Customize writes here; early-init.el pointed it at a writable path.
(when (file-exists-p custom-file)
  (load custom-file nil t))

;; Anything being tried out before it earns a place in this file.
(let ((personal (expand-file-name "personal.el" user-emacs-directory)))
  (when (file-exists-p personal)
    (load personal nil t)))

;;; init.el ends here

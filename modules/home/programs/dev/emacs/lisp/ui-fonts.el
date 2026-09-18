;;; ui-fonts.el --- Faces and ligatures  -*- lexical-binding: t; -*-

;;; Commentary:
;; JetBrainsMono Nerd Font matches foot; Noto Sans CJK SC is the system CJK
;; default from system/user/fonts.nix.

;;; Code:

;; Height is in tenths of a point — raise or lower this one number if the whole
;; UI is the wrong size.  `C-x C-=' and `C-x C--' adjust the current buffer
;; without a rebuild.
(defvar my/font-height 110)

(defun my/setup-fonts ()
  "Apply the monospace and CJK fonts to the current frame."
  (set-face-attribute 'default nil
                      :family "JetBrainsMono Nerd Font"
                      :height my/font-height)
  (set-face-attribute 'fixed-pitch nil :family "JetBrainsMono Nerd Font")
  ;; Variable-pitch is used by org-modern headings, mixed-pitch prose and a few
  ;; help buffers.
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

(provide 'ui-fonts)
;;; ui-fonts.el ends here

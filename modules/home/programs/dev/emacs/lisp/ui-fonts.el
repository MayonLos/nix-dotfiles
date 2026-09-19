;;; ui-fonts.el --- Faces and ligatures  -*- lexical-binding: t; -*-

;;; Commentary:
;; JetBrainsMono Nerd Font matches kitty (programs/terminal/kitty.nix); Noto
;; Sans CJK SC is the system CJK default from system/user/fonts.nix.

;;; Code:

;; Height is in tenths of a point — raise or lower this one number if the whole
;; UI is the wrong size.  `C-x C-=' and `C-x C--' adjust the current buffer
;; without a rebuild.
;;
;; Do not raise this to fight the soft rendering. It was tried: Emacs 30 is
;; pgtk, GTK3 never binds `wp_fractional_scale_v1' (traced with
;; `WAYLAND_DEBUG=1' — mango advertises the global, Emacs ignores it, reads
;; `wl_output.scale(2)' and calls `set_buffer_scale(2)'), so Emacs renders at
;; 2x and the compositor resamples down to this output's 1.5x. A bigger glyph
;; does survive that better, measured on a screenshot crop of one string by
;; counting ink pixels landing between background and foreground:
;;
;;   height 113   36.8% blurred edge, 42.7% solid   97 columns
;;   height 130   30.0%               50.2%         87 columns
;;   height 150   30.5%               54.3%         73 columns
;;
;; but a fifth less fringing is not worth ten columns and a frame that no
;; longer matches the rest of the desktop — judged on screen, not on the
;; numbers.
;;
;; The output scale was then tried too, in full: `monitorrule' to `scale:2',
;; `Xft.dpi' 144 -> 192, and every length on the host multiplied by 0.75 so the
;; physical sizes came out unchanged (mango borders/gaps/radius/cursor, kitty
;; font and padding, the noctalia bar, this number 110 -> 83). At *matched
;; physical glyph size* that is the only thing that actually works, because at
;; an integer scale there is nothing left to resample:
;;
;;   scale 1.5 + 11.0pt   37.1% blurred edge, 41.7% solid
;;   scale 2.0 +  8.3pt   27.5%               56.5%
;;
;; It was still turned down — a whole-host change for a cosmetic gain — and
;; reverted. Do not re-propose it; the numbers above are the argument, and they
;; already lost.
;;
;; Dead ends, all measured, so nobody spends the afternoon again:
;;   * `GDK_SCALE=2'      — no effect; Emacs is already at buffer_scale 2.
;;   * `GDK_BACKEND=x11'  — the pgtk build refuses to start under X at all
;;     ("that configuration is unsupported … sporadic crashes").
;;   * a compositor filter knob — mango's `parse_config.c' has none, and
;;     wlroots already defaults a scene buffer to WLR_SCALE_FILTER_BILINEAR,
;;     the better of its two filters.
;;   * toggling the window floating — the workaround in mangowm/mango#896. That
;;     bug is a *stale* buffer_scale; ours is correct, and it changed nothing.
;;   * a newer Emacs — there is no emacs31 in nixpkgs and no upstream pgtk work
;;     on fractional scale. It needs a GTK4 port, which does not exist.
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

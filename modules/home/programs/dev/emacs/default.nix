{ pkgs, ... }:

let
  # PGTK, not the plain `emacs` attribute: that one is still the Lucid/X11
  # build, so it would run through Mango's built-in Xwayland and inherit the X11
  # scale rather than Mango's 1.5 logical scale. PGTK talks Wayland directly and, with
  # GTK_IM_MODULE deliberately unset by the fcitx5 module (waylandFrontend =
  # true), reaches fcitx5 over text-input-v3 — the same path QQ uses, so the
  # candidate window is the one PerScreenDPI in base/input-method.nix fixes.
  emacsPackage = pkgs.emacs30-pgtk;

  # Emacs 30 ships the *-ts-mode major modes but no grammars; it looks for
  # libtree-sitter-<lang>.so on `treesit-extra-load-path`. `with-all-grammars`
  # is 279 MiB of closure for 280 languages, so this is the subset that matches
  # the remaps in lisp/edit-treesit.el.
  grammars = emacsPackage.pkgs.treesit-grammars.with-grammars (
    g: with g; [
      tree-sitter-bash
      tree-sitter-c
      tree-sitter-cmake
      tree-sitter-cpp
      tree-sitter-css
      tree-sitter-dockerfile
      tree-sitter-go
      tree-sitter-gomod
      tree-sitter-html
      tree-sitter-java
      tree-sitter-javascript
      tree-sitter-json
      tree-sitter-lua
      tree-sitter-markdown
      tree-sitter-markdown-inline
      tree-sitter-nix
      tree-sitter-python
      tree-sitter-rust
      tree-sitter-toml
      tree-sitter-tsx
      tree-sitter-typescript
      tree-sitter-yaml
    ]
  );
in
{
  programs.emacs = {
    enable = true;
    package = emacsPackage;

    # Everything on the load-path is put there by this wrapper, which is why no
    # use-package form in lisp/ needs :ensure. Adding a package here is the only
    # way to install one — `M-x package-install` has no writable directory to
    # install into.
    #
    # Grouped to match the module tree in lisp/, which in turn mirrors
    # nixvim/plugins/. A package added here belongs in exactly one of those
    # files; if it does not fit one, that is a sign the tree needs a new module
    # rather than a sign to put it anywhere.
    extraPackages =
      epkgs: with epkgs; [
        # -- lisp/keymaps.el ------------------------------------------------
        general

        # -- lisp/edit-evil.el ----------------------------------------------
        # evil-collection has to see evil-want-keybinding = nil before evil
        # loads; edit-evil.el sets that in an :init block.
        evil
        evil-collection
        evil-surround
        # The pieces of the vim experience evil itself leaves out: C-a/C-x on
        # numbers, and a flash on whatever an operator just acted on.
        evil-numbers
        evil-goggles
        # flash.nvim's job — reach a visible position without counting lines.
        avy
        ace-window

        # -- lisp/edit-textobj.el, edit-multicursor.el, edit-treesit.el ------
        # `af`/`if`-style tree-sitter text objects (the nvim textobjects
        # equivalent) and simultaneous edits of every match.
        evil-textobj-tree-sitter
        evil-multiedit
        treesit-fold
        nix-ts-mode

        # -- lisp/core-defaults.el ------------------------------------------
        # ws-butler instead of a global `delete-trailing-whitespace' on save:
        # the latter rewrites lines the commit never touched and turns every
        # diff into noise.
        ws-butler

        # -- lisp/nav-minibuffer.el -----------------------------------------
        # vertico/orderless/marginalia/consult replace ido and ivy.
        vertico
        orderless
        marginalia
        consult
        consult-dir
        embark
        embark-consult
        # `embark-export' a consult-ripgrep result into a grep buffer, edit it
        # like any other buffer, `C-c C-c' — that is project-wide refactoring
        # with no dedicated tool involved.
        wgrep

        # -- lisp/nav-harpoon.el --------------------------------------------
        # harpoon.nvim's model: three or four files per project on fixed keys,
        # separated by git branch. Pulls in f.el as a dependency.
        harpoon

        # -- lisp/nav-dired.el ----------------------------------------------
        # A dired worth using as a file manager: preview pane, icons, header.
        dirvish

        # -- lisp/cmp-corfu.el, cmp-snippets.el ------------------------------
        # corfu/cape replace company.
        corfu
        cape
        yasnippet
        yasnippet-snippets

        # -- lisp/lsp-eglot.el, diag-trouble.el ------------------------------
        # eglot is built in; these are the things around it.
        eldoc-box
        # Workspace-wide symbol search from the language server, as opposed to
        # consult-imenu which only ever sees the current file.
        consult-eglot
        # Jump to any TODO/FIXME in the project, not just the ones magit-todos
        # surfaces on the status screen.
        consult-todo

        # -- lisp/fmt-apheleia.el --------------------------------------------
        # Formats on save in a subprocess, so a slow formatter cannot freeze
        # the (single-threaded) editor the way a `before-save-hook' would.
        apheleia

        # -- lisp/git-magit.el -----------------------------------------------
        # The two reasons to run Emacs at all, plus the things that make them
        # complete: GitHub PRs and issues inside magit, per-file history
        # scrubbing, and the repository's TODOs on the status screen.
        magit
        forge
        git-timemachine
        magit-todos
        # Renders magit's diffs through delta, which programs/dev/git.nix
        # configures as git's pager — so a hunk looks the same in both places.
        magit-delta
        diff-hl

        # -- lisp/dbg-dape.el ------------------------------------------------
        # Debug Adapter Protocol client — the one large capability eglot does
        # not cover. Drives gdb directly (17.2 speaks DAP natively) for C/C++
        # and debugpy for Python.
        dape

        # -- lisp/ai-gptel.el ------------------------------------------------
        # An LLM client wired to the DeepSeek key already in sops.
        gptel

        # -- lisp/tool-terminal.el -------------------------------------------
        # A real terminal, since eshell is not one and ansi-term is worse.
        vterm
        popper

        # -- lisp/tool-session.el --------------------------------------------
        # persistence.nvim's job: restore the window layout for a directory.
        easysession

        # -- lisp/tool-utility.el --------------------------------------------
        helpful
        vundo
        # Undo history survives a daemon restart, which matters more here than
        # usual because a Wayland disconnect takes the daemon down with it.
        undo-fu-session
        # Shows the key just pressed and the command it ran. Worth leaving on
        # while the muscle memory is still forming.
        keycast
        # Evaluation results appear inline next to the form instead of flashing
        # in the echo area — the difference between reading elisp and poking it.
        eros
        # direnv, so a buffer under a project with an .envrc gets that project's
        # toolchain instead of the daemon's login environment. Without this,
        # eglot would start whatever clangd the daemon happened to inherit.
        envrc
        # An HTTP client whose request definitions are org documents.
        verb

        # -- lisp/ui-*.el ----------------------------------------------------
        # doom-modeline and nerd-icons need a Nerd Font with the symbol range —
        # system/user/fonts.nix carries nerd-fonts.symbols-only for exactly this.
        doom-themes
        doom-modeline
        nerd-icons
        nerd-icons-completion
        nerd-icons-corfu
        # No nerd-icons-dired: dirvish draws dired's icons itself, and having
        # both put two glyphs on every row.
        nerd-icons-ibuffer
        indent-bars
        ligature
        # colorful-mode rather than rainbow-mode: it recognises more notations
        # (named colours, hsl, Tailwind-style) and draws a swatch instead of
        # recolouring the text, which stays readable against the Nord ground.
        colorful-mode
        # Frame padding, window dividers and a mode line that is not glued to
        # the bottom edge. This is the single biggest visual change here — the
        # stock frame packs text flush against the window border.
        spacious-padding
        # Dims buffers that are not visiting a file, so sidebars, popups and
        # magit read as chrome and the code reads as content.
        solaire-mode
        # Pulses the line after a jump, a window switch or a search landing.
        # Cheap orientation cue that costs nothing when idle.
        pulsar
        # Header line with the project-relative path and the enclosing function
        # or class, the way an IDE breadcrumb does.
        breadcrumb
        # Proportional type for org and markdown prose while code blocks and
        # tables stay monospaced.
        mixed-pitch
        # popper's popups already announce themselves by position; a mode line
        # in each one is pure noise.
        hide-mode-line
        rainbow-delimiters
        hl-todo

        # -- lisp/lang-markdown.el, lang-tex.el ------------------------------
        markdown-mode
        # Tables aligned by rendered pixel width rather than character count,
        # which is the only way a table holding CJK survives a proportional
        # face. render-markdown.nvim's job on the Neovim side.
        valign
        # Real LaTeX editing rather than the built-in latex-mode, and a viewer
        # that renders the PDF inside Emacs with forward/inverse search.
        auctex
        pdf-tools

        # -- lisp/lang-math.el ------------------------------------------------
        # LaTeX shown typeset rather than as source. org previews natively;
        # markdown has nothing of its own, so texfrag lends it AUCTeX's
        # `preview' machinery. Both render through texliveFull + ghostscript
        # from programs/dev/latex.nix.
        org-fragtog
        texfrag

        # -- lisp/lang-org.el -------------------------------------------------
        org-modern
        org-appear
        org-roam
        # Clipboard image straight into an org file: saved next to the document
        # and inlined as a link.
        org-download
        evil-org
      ];
  };

  # The language servers eglot starts and the formatters apheleia shells out
  # to all come from programs/dev/toolchain.nix, which nvim shares. Declaring
  # them here as well would let the two editors drift onto different versions.

  xdg.configFile = {
    # Substituted rather than plain-sourced because the grammar directory is a
    # store path that only Nix knows.
    "emacs/early-init.el".source = pkgs.replaceVars ./early-init.el {
      treesitGrammars = "${grammars}/lib";
    };

    # init.el is only a loader; every setting lives in one file under lisp/,
    # laid out to mirror nixvim/. The whole directory is linked in one go, so
    # adding a module means adding the file and naming it in `my/modules`.
    "emacs/init.el".source = ./init.el;
    "emacs/lisp".source = ./lisp;
  };
}

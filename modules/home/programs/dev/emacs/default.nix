{ pkgs, ... }:

let
  # PGTK, not the plain `emacs` attribute: that one is still the Lucid/X11
  # build, so it would run through xwayland-satellite and inherit the integer
  # scale X11 sees rather than niri's 1.5. PGTK talks Wayland directly and, with
  # GTK_IM_MODULE deliberately unset by the fcitx5 module (waylandFrontend =
  # true), reaches fcitx5 over text-input-v3 — the same path QQ uses, so the
  # candidate window is the one ForceWaylandDPI in base/input-method.nix fixes.
  emacsPackage = pkgs.emacs30-pgtk;

  # Emacs 30 ships the *-ts-mode major modes but no grammars; it looks for
  # libtree-sitter-<lang>.so on `treesit-extra-load-path`. `with-all-grammars`
  # is 279 MiB of closure for 280 languages, so this is the subset that matches
  # the remaps in init.el.
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

    # Everything on the load-path is put there by this wrapper, which is why
    # early-init.el sets `package-enable-at-startup` to nil and every
    # use-package form in init.el resolves without :ensure. Adding a package
    # here is the only way to install one — `M-x package-install` has no
    # writable directory to install into.
    extraPackages =
      epkgs: with epkgs; [
        # Modal editing. evil-collection has to see evil-want-keybinding = nil
        # before evil loads; init.el sets that in an :init block.
        evil
        evil-collection
        evil-surround
        evil-org
        general
        # The pieces of the vim experience evil itself leaves out: C-a/C-x on
        # numbers, `af`/`if`-style tree-sitter text objects (the nvim
        # textobjects equivalent), simultaneous edits, and a flash on whatever
        # an operator just acted on.
        evil-numbers
        evil-textobj-tree-sitter
        evil-multiedit
        evil-goggles

        # Minibuffer and in-buffer completion. vertico/orderless/marginalia/
        # consult replace ido and ivy; corfu/cape replace company.
        vertico
        orderless
        marginalia
        consult
        consult-dir
        embark
        embark-consult
        corfu
        cape
        # `embark-export' a consult-ripgrep result into a grep buffer, edit it
        # like any other buffer, `C-c C-c' — that is project-wide refactoring
        # with no dedicated tool involved.
        wgrep

        # The two reasons to run Emacs at all, plus the things that make them
        # complete: GitHub PRs and issues inside magit, per-file history
        # scrubbing, and the repository's TODOs on the status screen.
        magit
        forge
        git-timemachine
        magit-todos
        # Renders magit's diffs through delta, which programs.git.delta already
        # configures as the pager — so a hunk looks the same in both places.
        magit-delta
        org-modern
        org-appear
        org-roam

        # Appearance. doom-modeline and nerd-icons need a Nerd Font with the
        # symbol range — system/user/fonts.nix carries nerd-fonts.symbols-only
        # for exactly this.
        doom-themes
        doom-modeline
        nerd-icons
        nerd-icons-completion
        nerd-icons-corfu
        nerd-icons-dired
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

        # Editing and VCS affordances.
        diff-hl
        hl-todo
        rainbow-delimiters
        helpful
        eldoc-box
        # ws-butler instead of a global `delete-trailing-whitespace' on save:
        # the latter rewrites lines the commit never touched and turns every
        # diff into noise.
        ws-butler
        vundo
        avy
        ace-window
        popper
        treesit-fold
        yasnippet
        yasnippet-snippets
        # Formats on save in a subprocess, so a slow formatter cannot freeze
        # the (single-threaded) editor the way a `before-save-hook' would.
        apheleia

        # Major modes Emacs does not ship. Everything else in init.el's
        # major-mode-remap-alist is built in.
        nix-ts-mode
        markdown-mode
        # Real LaTeX editing rather than the built-in latex-mode, and a viewer
        # that renders the PDF inside Emacs with forward/inverse search.
        auctex
        pdf-tools

        # direnv, so a buffer under a project with an .envrc gets that project's
        # toolchain instead of the daemon's login environment. Without this,
        # eglot would start whatever clangd the daemon happened to inherit.
        envrc

        # A real terminal, since eshell is not one and ansi-term is worse, and
        # a dired that is worth using as a file manager.
        vterm
        dirvish

        # An HTTP client whose request definitions are org documents, and an
        # LLM client wired to the DeepSeek key already in sops.
        verb
        gptel

        # Debug Adapter Protocol client — the one large capability eglot does
        # not cover. Drives gdb directly (17.2 speaks DAP natively) for C/C++
        # and debugpy for Python.
        dape
        # Workspace-wide symbol search from the language server, as opposed to
        # consult-imenu which only ever sees the current file.
        consult-eglot
        # Jump to any TODO/FIXME in the project, not just the ones magit-todos
        # surfaces on the status screen.
        consult-todo
        # Undo history survives a daemon restart, which matters more here than
        # usual because a Wayland disconnect takes the daemon down with it.
        undo-fu-session
        # Shows the key just pressed and the command it ran. Worth leaving on
        # while the muscle memory is still forming.
        keycast
        # Clipboard image straight into an org file: saved next to the document
        # and inlined as a link.
        org-download
        # Evaluation results appear inline next to the form instead of flashing
        # in the echo area — the difference between reading elisp and poking it.
        eros
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

    "emacs/init.el".source = ./init.el;
  };
}

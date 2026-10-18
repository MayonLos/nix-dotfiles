{ pkgs, ... }:

let
  tmuxTheme = ''
    # tmux draws its own status bar, so use ANSI palette indexes and the
    # default background to follow the terminal, including opaque Kitty.
    set -g status on
    set -g status-position bottom
    set -g status-interval 30
    set -g status-style "bg=default,fg=colour7"

    set -g status-left-length 30
    set -g status-left "#[fg=colour0,bg=colour4,bold] #S #[default] "
    set -g status-right-length 52
    set -g status-right "#{prefix_highlight}#[default]#{?#{>=:#{client_width},100}, #[fg=colour8]│ #[fg=colour7]%a %d %b #[fg=colour4,bold]%H:%M#[default],} "

    set -g window-status-separator "#[fg=colour8]·#[default]"
    setw -g window-status-format         "#[fg=colour8] #I #[fg=colour7]#W #[default]"
    setw -g window-status-current-format "#[fg=colour0,bg=colour4,bold] #I:#W #[default]"

    set -g pane-border-style        "fg=colour8"
    set -g pane-active-border-style "fg=colour4"
    set -g message-style            "bg=colour8,fg=colour15"
    set -g mode-style               "bg=colour3,fg=colour0"

    set -g @prefix_highlight_fg 'colour0'
    set -g @prefix_highlight_bg 'colour4'
    set -g @prefix_highlight_show_copy_mode 'on'
    set -g @prefix_highlight_copy_mode_attr 'fg=colour0,bg=colour3'
    set -g @prefix_highlight_output_prefix ' '
    set -g @prefix_highlight_output_suffix ' '

    TMUX_FZF_LAUNCH_KEY="F"
    TMUX_FZF_ORDER="session|window|pane|command|keybinding"
  '';
in
{
  programs.tmux = {
    enable = true;
    package = pkgs.tmux;

    prefix = "C-a";
    keyMode = "vi";
    mouse = true;
    clock24 = true;
    escapeTime = 0;
    baseIndex = 1;
    historyLimit = 50000;
    terminal = "tmux-256color";

    plugins = with pkgs.tmuxPlugins; [
      sensible
      {
        plugin = yank;
        # Set the final status format after sensible defaults, before
        # continuum adds its save marker and prefix-highlight expands its token.
        extraConfig = tmuxTheme;
      }
      {
        plugin = resurrect;
        extraConfig = ''
          # Layout and nvim sessions only. Pane contents copy scrollback, including
          # secrets, into the resurrect directory every save.
          set -g @resurrect-capture-pane-contents 'off'
          set -g @resurrect-strategy-nvim 'session'
        '';
      }
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '15'
        '';
      }
      prefix-highlight
      tmux-fzf
    ];

    extraConfig = ''
      ##### Core #####

      unbind C-b
      bind C-a send-prefix
      bind r source-file ~/.config/tmux/tmux.conf \; display-message "Config reloaded"

      setw -g pane-base-index 1
      set -g renumber-windows on
      set -g focus-events on
      set -g detach-on-destroy off

      # True color + undercurl support
      set -sa terminal-overrides ",*256col*:Tc"
      set -sa terminal-overrides ",*:Smulx=\\E[4::%p1%dm"
      set -sa terminal-overrides ",*:Setulc=\\E[58::2::%p1%{65536}%/%d::%p1%{256}%/%{255}%&%d::%p1%{255}%&%d%;m"
      # Passthrough for sixel/kitty graphics (used by yazi image preview)
      set -g allow-passthrough on
      set -ga update-environment TERM
      set -ga update-environment TERM_PROGRAM

      ##### Splits & Windows #####

      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      unbind '"'
      unbind %
      bind c new-window -c "#{pane_current_path}"

      ##### Prefix Navigation #####

      # Release the former root-table navigation bindings when this file is
      # reloaded into an already-running tmux server.
      unbind -n M-h
      unbind -n M-j
      unbind -n M-k
      unbind -n M-l
      unbind -n M-z
      unbind -n M-n
      unbind -n M-p
      unbind -n M-Tab
      unbind -n M-1
      unbind -n M-2
      unbind -n M-3
      unbind -n M-4
      unbind -n M-5
      unbind -n M-6
      unbind -n M-7
      unbind -n M-8
      unbind -n M-9

      # Keep Alt combinations available to shells, TUIs, and Neovim.
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R
      bind Tab last-window
      bind n next-window
      bind p previous-window
      bind 1 select-window -t 1
      bind 2 select-window -t 2
      bind 3 select-window -t 3
      bind 4 select-window -t 4
      bind 5 select-window -t 5
      bind 6 select-window -t 6
      bind 7 select-window -t 7
      bind 8 select-window -t 8
      bind 9 select-window -t 9

      ##### Resize Panes (prefix, repeatable) #####

      bind -r H resize-pane -L 5
      bind -r J resize-pane -D 5
      bind -r K resize-pane -U 5
      bind -r L resize-pane -R 5

      ##### Copy Mode #####

      bind -T copy-mode-vi v send-keys -X begin-selection
      bind -T copy-mode-vi C-v send-keys -X rectangle-toggle
      bind -T copy-mode-vi y send-keys -X copy-selection-and-cancel
    '';
  };
}

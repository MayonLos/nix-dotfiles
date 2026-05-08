{ pkgs, ... }:

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
      yank
      {
        plugin = resurrect;
        extraConfig = ''
          set -g @resurrect-capture-pane-contents 'on'
          set -g @resurrect-strategy-nvim 'session'
        '';
      }
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '10'
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
      set -sa terminal-overrides ",*:Smulx=\E[4::%p1%dm"
      set -sa terminal-overrides ",*:Setulc=\E[58::2::%p1%{65536}%/%d::%p1%{256}%/%{255}%&%d::%p1%{255}%&%d%;m"
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

      ##### Pane Navigation (no prefix) #####

      bind -n M-h select-pane -L
      bind -n M-j select-pane -D
      bind -n M-k select-pane -U
      bind -n M-l select-pane -R
      bind -n M-z resize-pane -Z

      ##### Window Navigation (no prefix) #####

      bind -n M-n next-window
      bind -n M-p previous-window
      bind -n M-Tab last-window
      bind -n M-1 select-window -t 1
      bind -n M-2 select-window -t 2
      bind -n M-3 select-window -t 3
      bind -n M-4 select-window -t 4
      bind -n M-5 select-window -t 5
      bind -n M-6 select-window -t 6
      bind -n M-7 select-window -t 7
      bind -n M-8 select-window -t 8
      bind -n M-9 select-window -t 9

      ##### Resize Panes (prefix, repeatable) #####

      bind -r H resize-pane -L 5
      bind -r J resize-pane -D 5
      bind -r K resize-pane -U 5
      bind -r L resize-pane -R 5

      ##### Copy Mode #####

      bind -T copy-mode-vi v send-keys -X begin-selection
      bind -T copy-mode-vi C-v send-keys -X rectangle-toggle
      bind -T copy-mode-vi y send-keys -X copy-selection-and-cancel

      ##### tmux-fzf #####

      TMUX_FZF_LAUNCH_KEY="F"
      TMUX_FZF_ORDER="session|window|pane|command|keybinding"

      ##### Theme: Minimal Dark #####

      # bg=#1e1e2e  bg-alt=#26263a  fg=#dcd7ba  muted=#6e6a86  accent=#7aa2f7

      set -g status on
      set -g status-position bottom
      set -g status-interval 2
      set -g status-style "bg=#1e1e2e,fg=#dcd7ba"

      set -g status-left-length 50
      set -g status-left "#[fg=#7aa2f7,bold] #S #[fg=#6e6a86]│ "

      set -g status-right-length 100
      set -g status-right "#{prefix_highlight}#[fg=#6e6a86] %Y-%m-%d #[fg=#dcd7ba]%H:%M "

      setw -g window-status-format         "#[fg=#6e6a86] #I:#W "
      setw -g window-status-current-format "#[fg=#dcd7ba,bold] #I:#W "

      set -g pane-border-style        "fg=#2f2f44"
      set -g pane-active-border-style "fg=#7aa2f7"
      set -g message-style            "bg=#26263a,fg=#dcd7ba"
      set -g mode-style               "bg=#7aa2f7,fg=#1e1e2e"

      ##### Prefix Highlight #####

      set -g @prefix_highlight_fg '#1e1e2e'
      set -g @prefix_highlight_bg '#7aa2f7'
      set -g @prefix_highlight_show_copy_mode 'on'
      set -g @prefix_highlight_copy_mode_attr 'fg=#1e1e2e,bg=#e0af68'
      set -g @prefix_highlight_output_prefix ' '
      set -g @prefix_highlight_output_suffix ' '
    '';
  };
}

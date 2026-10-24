{ palette }:
{ pkgs, ... }:

let
  # Embedded composition fixtures may omit appearance. They retain a readable
  # ANSI fallback; deployed instances always pass the shared palette.
  colors =
    if palette == null then
      {
        bg = "colour0";
        deep = "colour0";
        surface = "colour8";
        selection = "colour8";
        fg = "colour7";
        muted = "colour8";
        brightFg = "colour15";
        border = "colour8";
        blue = "colour4";
        cyan = "colour6";
        purple = "colour5";
        yellow = "colour3";
      }
    else
      palette;
  tmuxTheme = ''
    # Keep the status bar flat and quiet. The selected window uses a text
    # underline, matching Kitty's active tab and the desktop bar indicator.
    set -g status on
    set -g status-position bottom
    set -g status-interval 30
    set -g status-style "bg=${colors.deep},fg=${colors.brightFg}"

    set -g status-left-length 24
    set -g status-left " #[fg=${colors.blue},bold]#S #[fg=${colors.border}]│ #[default]"

    setw -g window-status-separator "#[fg=${colors.border}]  #[default]"
    setw -g window-status-format "#[fg=${colors.fg}]#I #W#{?window_zoomed_flag,#[fg=${colors.yellow}] Z,}#[default]"
    setw -g window-status-current-format "#[fg=${colors.brightFg},us=${colors.blue},bold,underscore]#I #W#[nounderscore,nobold,us=default]#{?window_zoomed_flag,#[fg=${colors.yellow}]#[bold] Z,}#[default]"

    # Keep style attributes separate inside conditionals: raw commas delimit
    # tmux format arguments even when they occur inside a #[style] string.
    set -g status-right-length 64
    set -g status-right "#{?#{e|>=:#{client_width},80},#[fg=${colors.muted}]#{b;=24:pane_current_path} #[default],}#{?client_prefix,#[fg=${colors.blue}]#[bg=${colors.surface}]#[bold] 前缀 #[default],}#{?#{m/r:(copy|view)-mode,#{pane_mode}},#[fg=${colors.yellow}]#[bg=${colors.surface}]#[bold] 复制 #[default],}#{?client_prefix,,#{?#{m/r:(copy|view)-mode,#{pane_mode}},,#{?window_zoomed_flag,#[fg=${colors.purple}]#[bg=${colors.surface}]#[bold] 缩放 #[default],}}}#[fg=${colors.brightFg},bold]%H:%M#[default] "

    set -g pane-border-style        "fg=${colors.surface}"
    set -g pane-active-border-style "fg=${colors.blue}"
    set -g message-style            "bg=${colors.surface},fg=${colors.brightFg}"
    set -g mode-style               "bg=${colors.selection},fg=${colors.brightFg}"

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
        # Apply palette formats after sensible defaults and before continuum's
        # save marker is added to the right side.
        extraConfig = tmuxTheme;
      }
      {
        plugin = resurrect;
        # Layout and nvim sessions only. Pane contents copy scrollback, including
        # secrets, into the resurrect directory every save.
        extraConfig = ''
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

      # Release root-table mappings when reloading over an existing tmux server.
      unbind -n M-h
      unbind -n M-j
      unbind -n M-k
      unbind -n M-l
      unbind -n C-h
      unbind -n C-j
      unbind -n C-k
      unbind -n C-l
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

      # smart-splits sets @pane-is-vim per pane; when there is no nvim pane,
      # these same keys move between tmux panes. This stays inert outside tmux.
      bind-key -n C-h if -F "#{@pane-is-vim}" 'send-keys C-h' 'select-pane -L'
      bind-key -n C-j if -F "#{@pane-is-vim}" 'send-keys C-j' 'select-pane -D'
      bind-key -n C-k if -F "#{@pane-is-vim}" 'send-keys C-k' 'select-pane -U'
      bind-key -n C-l if -F "#{@pane-is-vim}" 'send-keys C-l' 'select-pane -R'
      bind-key -n M-h if -F "#{@pane-is-vim}" 'send-keys M-h' 'resize-pane -L 3'
      bind-key -n M-j if -F "#{@pane-is-vim}" 'send-keys M-j' 'resize-pane -D 3'
      bind-key -n M-k if -F "#{@pane-is-vim}" 'send-keys M-k' 'resize-pane -U 3'
      bind-key -n M-l if -F "#{@pane-is-vim}" 'send-keys M-l' 'resize-pane -R 3'

      # Keep prefix navigation for users and tmuxp layouts that rely on it.
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

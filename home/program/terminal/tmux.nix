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
      resurrect
      continuum
      prefix-highlight
    ];

    extraConfig = ''
      ##### Core #####

      unbind C-b
      bind C-a send-prefix
      bind r source-file ~/.config/tmux/tmux.conf \; display-message "Reloaded"

      setw -g pane-base-index 1
      set -g renumber-windows on
      set -g focus-events on

      ##### Splits #####

      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      unbind '"'
      unbind %

      ##### Navigation #####

      bind -n M-h select-pane -L
      bind -n M-j select-pane -D
      bind -n M-k select-pane -U
      bind -n M-l select-pane -R

      ##### ===== Minimal Clean Theme ===== #####

      # Color palette (balanced dark, not too purple)
      # bg      = #1e1e2e
      # bg-alt  = #26263a
      # fg      = #dcd7ba
      # muted   = #6e6a86
      # accent  = #7aa2f7

      set -g status on
      set -g status-position bottom
      set -g status-interval 2
      set -g status-style "bg=#1e1e2e,fg=#dcd7ba"

      # —— 左侧：只显示 Session ——
      set -g status-left-length 50
      set -g status-left "#[fg=#7aa2f7,bold] #S "

      # —— 右侧：时间 + prefix 状态 ——
      set -g status-right-length 100
      set -g status-right "#{prefix_highlight} #[fg=#6e6a86]%H:%M "

      # —— 删除当前窗口高亮块效果 —— 
      setw -g window-status-format "#[fg=#6e6a86] #W "
      setw -g window-status-current-format "#[fg=#dcd7ba] #W "

      # —— Pane 边框 —— 
      set -g pane-border-style "fg=#2f2f44"
      set -g pane-active-border-style "fg=#7aa2f7"

      # —— 消息样式 —— 
      set -g message-style "bg=#26263a,fg=#dcd7ba"

      ##### Prefix Highlight #####

      set -g @prefix_highlight_fg '#1e1e2e'
      set -g @prefix_highlight_bg '#7aa2f7'
      set -g @prefix_highlight_output_prefix ' '
      set -g @prefix_highlight_output_suffix ' '

      ##### Continuum #####

      set -g @continuum-restore 'on'
      set -g @continuum-save-interval '10'
    '';
  };
}

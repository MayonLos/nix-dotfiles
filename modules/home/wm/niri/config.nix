{
  pkgs,
  lib,
  config,
  ...
}:

{
  xdg.configFile."niri/config.kdl".text = ''
    prefer-no-csd
    screenshot-path "~/Pictures/Screenshots/%Y%m%d-%H%M%S.png"

    environment {
        QT_QPA_PLATFORMTHEME "qt6ct"
    }

    debug {
        honor-xdg-activation-with-invalid-serial
    }

    hotkey-overlay {
        skip-at-startup
        hide-not-bound
    }

    cursor {
        xcursor-size 24
        hide-when-typing
    }

    xwayland-satellite {
        path "${pkgs.xwayland-satellite}/bin/xwayland-satellite"
    }

    spawn-at-startup "dbus-update-activation-environment" "--systemd" "WAYLAND_DISPLAY" "XDG_CURRENT_DESKTOP" "XDG_SESSION_TYPE" "DISPLAY"
    spawn-at-startup "noctalia"

    blur {
        passes 3
        offset 3.0
        noise 0.02
        saturation 1.5
    }

    layout {
        background-color "#00000000"

        focus-ring {
            width 2
            active-color "#61afefcc"
            inactive-color "#3b4252"
        }

        gaps 6
        center-focused-column "on-overflow"

        struts {
            left 10
            right 10
            top 10
            bottom 10
        }

        preset-column-widths {
            proportion 0.33333
            proportion 0.5
            proportion 0.66667
            proportion 1.0
        }
    }

    input {
        keyboard {
            xkb {
                layout "us"
            }
            numlock
            repeat-delay 400
            repeat-rate 30
        }

        touchpad {
            click-method "button-areas"
            dwt
            dwtp
            natural-scroll
            scroll-method "two-finger"
            tap
            tap-button-map "left-right-middle"
            middle-emulation
            accel-profile "adaptive"
        }

        focus-follows-mouse
        workspace-auto-back-and-forth
    }

    output "eDP-1" {
        mode "2560x1600@165.002"
        scale 1.5
        position x=0 y=0
        focus-at-startup
        variable-refresh-rate on-demand=true
    }

    animations {
        slowdown 2.0

        workspace-switch {
            spring damping-ratio=1.0 stiffness=1000 epsilon=0.0001
        }
        window-open {
            duration-ms 150
            curve "ease-out-expo"
        }
        window-close {
            duration-ms 150
            curve "ease-out-quad"
        }
        horizontal-view-movement {
            spring damping-ratio=1.0 stiffness=800 epsilon=0.0001
        }
        window-movement {
            spring damping-ratio=1.0 stiffness=800 epsilon=0.0001
        }
        window-resize {
            spring damping-ratio=1.0 stiffness=800 epsilon=0.0001
        }
        config-notification-open-close {
            spring damping-ratio=0.6 stiffness=1000 epsilon=0.001
        }
        exit-confirmation-open-close {
            spring damping-ratio=0.6 stiffness=500 epsilon=0.01
        }
        screenshot-ui-open {
            duration-ms 200
            curve "ease-out-quad"
        }
        overview-open-close {
            spring damping-ratio=1.0 stiffness=800 epsilon=0.0001
        }
    }


    window-rule {
        geometry-corner-radius 18
        clip-to-geometry true
        draw-border-with-background false
        shadow {
            on
            softness 30
            spread 5
            offset x=0 y=5
            color "#00000088"
            inactive-color "#00000055"
        }
    }

    window-rule {
        background-effect {
            blur true
            xray false
        }
    }

    window-rule {
        match app-id="foot"
        opacity 0.8
        background-effect {
            blur true
        }
    }

    window-rule {
        match app-id="swayimg"
        open-floating true
        default-column-width { proportion 0.5; }
        border {
            off
        }
    }

    window-rule {
        match app-id="com.gabm.satty"
        open-floating true
    }

    window-rule {
        match app-id="thunar" title="^(Rename|重命名)"
        open-floating true
    }

    window-rule {
        match app-id="zen-beta" title="^Picture-in-Picture$"
        open-floating true
        default-column-width { fixed 480; }
    }

    window-rule {
        match app-id="^(pavucontrol|org.pulseaudio.pavucontrol|blueman-manager|nm-connection-editor|org.gnome.Calculator|xdg-desktop-portal-gtk)$"
        open-floating true
    }

    window-rule {
        match app-id="^(polkit-.*|org.freedesktop.PolicyKit.*)$"
        open-floating true
    }

    window-rule {
        match app-id="dev.noctalia.Noctalia.Settings"
        open-floating true
        default-column-width { fixed 1080; }
        default-window-height { fixed 920; }
    }

    window-rule {
        match app-id="^steam_app_"
        variable-refresh-rate true
        geometry-corner-radius 0
    }

    layer-rule {
        match namespace="^noctalia-backdrop"
        place-within-backdrop true
    }

    layer-rule {
        match namespace="^noctalia-(bar-.*|notification|dock|panel|attached-panel|osd)$"
        background-effect {
            xray false
        }
    }



    binds {
        Mod+E { spawn "thunar"; }
        Mod+Shift+Slash { show-hotkey-overlay; }
        Mod+Shift+Return hotkey-overlay-title="Open a Terminal: foot" { spawn "foot"; }
        Mod+P hotkey-overlay-title="Run an Application: Noctalia Launcher" { spawn "noctalia" "msg" "panel-toggle" "launcher"; }
        Mod+S hotkey-overlay-title="Control Center: Noctalia" { spawn "noctalia" "msg" "panel-toggle" "control-center"; }
        Super+Alt+L hotkey-overlay-title="Lock the Screen: Noctalia" { spawn "noctalia" "msg" "session" "lock"; }

        Mod+0 repeat=false { toggle-overview; }
        Mod+Shift+C repeat=false { close-window; }


        Mod+H { focus-column-left; }
        Mod+Left { focus-column-left; }
        Mod+J { focus-window-down; }
        Mod+Down { focus-window-down; }
        Mod+K { focus-window-up; }
        Mod+Up { focus-window-up; }
        Mod+L { focus-column-right; }
        Mod+Right { focus-column-right; }


        Mod+Ctrl+H { move-column-left; }
        Mod+Ctrl+Left { move-column-left; }
        Mod+Ctrl+J { move-window-down; }
        Mod+Ctrl+Down { move-window-down; }
        Mod+Ctrl+K { move-window-up; }
        Mod+Ctrl+Up { move-window-up; }
        Mod+Ctrl+L { move-column-right; }
        Mod+Ctrl+Right { move-column-right; }


        Mod+Shift+H { focus-monitor-left; }
        Mod+Shift+Left { focus-monitor-left; }
        Mod+Shift+J { focus-monitor-down; }
        Mod+Shift+Down { focus-monitor-down; }
        Mod+Shift+K { focus-monitor-up; }
        Mod+Shift+Up { focus-monitor-up; }
        Mod+Shift+L { focus-monitor-right; }
        Mod+Shift+Right { focus-monitor-right; }


        Mod+Shift+Ctrl+H { move-column-to-monitor-left; }
        Mod+Shift+Ctrl+Left { move-column-to-monitor-left; }
        Mod+Shift+Ctrl+J { move-column-to-monitor-down; }
        Mod+Shift+Ctrl+Down { move-column-to-monitor-down; }
        Mod+Shift+Ctrl+K { move-column-to-monitor-up; }
        Mod+Shift+Ctrl+Up { move-column-to-monitor-up; }
        Mod+Shift+Ctrl+L { move-column-to-monitor-right; }
        Mod+Shift+Ctrl+Right { move-column-to-monitor-right; }


        Mod+Page_Down { focus-workspace-down; }
        Mod+U { focus-workspace-down; }
        Mod+Page_Up { focus-workspace-up; }
        Mod+I { focus-workspace-up; }
        Mod+Ctrl+Page_Down { move-column-to-workspace-down; }
        Mod+Ctrl+U { move-column-to-workspace-down; }
        Mod+Ctrl+Page_Up { move-column-to-workspace-up; }
        Mod+Ctrl+I { move-column-to-workspace-up; }
        Mod+Shift+Page_Down { move-workspace-down; }
        Mod+Shift+U { move-workspace-down; }
        Mod+Shift+Page_Up { move-workspace-up; }
        Mod+Shift+I { move-workspace-up; }


        Mod+1 { focus-workspace 1; }
        Mod+2 { focus-workspace 2; }
        Mod+3 { focus-workspace 3; }
        Mod+4 { focus-workspace 4; }
        Mod+5 { focus-workspace 5; }
        Mod+6 { focus-workspace 6; }
        Mod+7 { focus-workspace 7; }
        Mod+8 { focus-workspace 8; }
        Mod+9 { focus-workspace 9; }

        Mod+Ctrl+1 { move-column-to-workspace 1; }
        Mod+Ctrl+2 { move-column-to-workspace 2; }
        Mod+Ctrl+3 { move-column-to-workspace 3; }
        Mod+Ctrl+4 { move-column-to-workspace 4; }
        Mod+Ctrl+5 { move-column-to-workspace 5; }
        Mod+Ctrl+6 { move-column-to-workspace 6; }
        Mod+Ctrl+7 { move-column-to-workspace 7; }
        Mod+Ctrl+8 { move-column-to-workspace 8; }
        Mod+Ctrl+9 { move-column-to-workspace 9; }

        Mod+Shift+1 { move-window-to-workspace 1; }
        Mod+Shift+2 { move-window-to-workspace 2; }
        Mod+Shift+3 { move-window-to-workspace 3; }
        Mod+Shift+4 { move-window-to-workspace 4; }
        Mod+Shift+5 { move-window-to-workspace 5; }
        Mod+Shift+6 { move-window-to-workspace 6; }
        Mod+Shift+7 { move-window-to-workspace 7; }
        Mod+Shift+8 { move-window-to-workspace 8; }
        Mod+Shift+9 { move-window-to-workspace 9; }

        Mod+Home { focus-column-first; }
        Mod+End { focus-column-last; }
        Mod+Ctrl+Home { move-column-to-first; }
        Mod+Ctrl+End { move-column-to-last; }

        Mod+Tab { focus-workspace-previous; }

        Mod+BracketLeft { consume-or-expel-window-left; }
        Mod+BracketRight { consume-or-expel-window-right; }
        Mod+Comma { consume-window-into-column; }
        Mod+Period { expel-window-from-column; }

        Mod+R { switch-preset-column-width; }
        Mod+Shift+R { switch-preset-window-height; }
        Mod+Ctrl+R { reset-window-height; }
        Mod+F { maximize-column; }
        Mod+Shift+F { fullscreen-window; }
        Mod+Ctrl+F { expand-column-to-available-width; }

        Mod+C { center-column; }
        Mod+Ctrl+C { center-visible-columns; }

        Mod+Minus { set-column-width "-10%"; }
        Mod+Equal { set-column-width "+10%"; }
        Mod+Shift+Minus { set-window-height "-10%"; }
        Mod+Shift+Equal { set-window-height "+10%"; }

        Mod+Shift+Space { toggle-window-floating; }
        Mod+Shift+V { switch-focus-between-floating-and-tiling; }
        Mod+W { toggle-column-tabbed-display; }

        Print hotkey-overlay-title="Screenshot: Region" { spawn "screenshot"; }
        Alt+Print hotkey-overlay-title="Screenshot: Window" { screenshot-window; }

        Mod+Escape allow-inhibiting=false { toggle-keyboard-shortcuts-inhibit; }
        Mod+Shift+E { spawn "noctalia" "msg" "panel-toggle" "session"; }
        Ctrl+Alt+Delete { quit; }
        Mod+V { spawn "noctalia" "msg" "panel-toggle" "clipboard"; }
        Mod+Shift+P { power-off-monitors; }


        Mod+Shift+W hotkey-overlay-title="Random Wallpaper: Noctalia" { spawn "noctalia" "msg" "wallpaper-random"; }
        Mod+Shift+A hotkey-overlay-title="Toggle Caffeine / idle inhibitor: Noctalia" { spawn "noctalia" "msg" "caffeine-toggle"; }


        XF86AudioRaiseVolume allow-when-locked=true { spawn "noctalia" "msg" "volume-up"; }
        XF86AudioLowerVolume allow-when-locked=true { spawn "noctalia" "msg" "volume-down"; }
        XF86AudioMute allow-when-locked=true { spawn "noctalia" "msg" "volume-mute"; }
        XF86AudioMicMute allow-when-locked=true { spawn "noctalia" "msg" "mic-mute"; }

        XF86AudioPlay allow-when-locked=true { spawn "playerctl" "play-pause"; }
        XF86AudioStop allow-when-locked=true { spawn "playerctl" "stop"; }
        XF86AudioPrev allow-when-locked=true { spawn "playerctl" "previous"; }
        XF86AudioNext allow-when-locked=true { spawn "playerctl" "next"; }
        XF86MonBrightnessUp allow-when-locked=true { spawn "noctalia" "msg" "brightness-up"; }
        XF86MonBrightnessDown allow-when-locked=true { spawn "noctalia" "msg" "brightness-down"; }
    }

    include "noctalia.kdl"
  '';

  home.activation.seedNiriNoctaliaTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e "${config.xdg.configHome}/niri/noctalia.kdl" ]; then
      run mkdir -p "${config.xdg.configHome}/niri"
      run ${pkgs.coreutils}/bin/install -m 0644 /dev/null "${config.xdg.configHome}/niri/noctalia.kdl"
    fi
  '';
}

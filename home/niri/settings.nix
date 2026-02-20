{
  ...
}:

{
  programs.niri.settings = {
      prefer-no-csd = true;
      hotkey-overlay = {
        skip-at-startup = true;
      };
      layout = {
        background-color = "#00000000";
        focus-ring = {
          enable = true;
          width = 1;
          active = {
            color = "#f0f0f0cc";
          };
          inactive = {
            color = "#505050";
          };
        };

        gaps = 6;

        struts = {
          left = 10;
          right = 10;
          top = 10;
          bottom = 10;
        };
      };

      input = {
        keyboard.xkb.layout = "us";
        touchpad = {
          click-method = "button-areas";
          dwt = true;
          dwtp = true;
          natural-scroll = true;
          scroll-method = "two-finger";
          tap = true;
          tap-button-map = "left-right-middle";
          middle-emulation = true;
          accel-profile = "adaptive";
        };
        focus-follows-mouse.enable = true;
        warp-mouse-to-focus.enable = false;
      };

      outputs = {
        "eDP-1" = {
          mode = {
            width = 2560;
            height = 1600;
            refresh = 165.002;
          };
          scale = 1.5;
          position = {
            x = 0;
            y = 0;
          };
          focus-at-startup = true;
        };
      };
      animations = {
        enable = true;
        slowdown = 2;

        workspace-switch = {
          enable = true;
          kind = {
            spring = {
              damping-ratio = 1.0;
              stiffness = 1000;
              epsilon = 0.0001;
            };
          };
        };

        window-open = {
          enable = true;
          kind = {
            easing = {
              duration-ms = 150;
              curve = "ease-out-expo";
              curve-args = [];
            };
          };
        };

        window-close = {
          enable = true;
          kind = {
            easing = {
              duration-ms = 150;
              curve = "ease-out-quad";
              curve-args = [];
            };
          };
        };

        horizontal-view-movement = {
          enable = true;
          kind = {
            spring = {
              damping-ratio = 1.0;
              stiffness = 800;
              epsilon = 0.0001;
            };
          };
        };

        window-movement = {
          enable = true;
          kind = {
            spring = {
              damping-ratio = 1.0;
              stiffness = 800;
              epsilon = 0.0001;
            };
          };
        };

        window-resize = {
          enable = true;
          kind = {
            spring = {
              damping-ratio = 1.0;
              stiffness = 800;
              epsilon = 0.0001;
            };
          };
        };

        config-notification-open-close = {
          enable = true;
          kind = {
            spring = {
              damping-ratio = 0.6;
              stiffness = 1000;
              epsilon = 0.001;
            };
          };
        };

        exit-confirmation-open-close = {
          enable = true;
          kind = {
            spring = {
              damping-ratio = 0.6;
              stiffness = 500;
              epsilon = 0.01;
            };
          };
        };

        screenshot-ui-open = {
          enable = true;
          kind = {
            easing = {
              duration-ms = 200;
              curve = "ease-out-quad";
              curve-args = [];
            };
          };
        };

        overview-open-close = {
          enable = true;
          kind = {
            spring = {
              damping-ratio = 1.0;
              stiffness = 800;
              epsilon = 0.0001;
            };
          };
        };
      };
  };
}

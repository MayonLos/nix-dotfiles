{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  isNoctalia = config.my.desktop.shell == "noctalia";
  wallpaperPath = "${../../wallpaper/wallpaper.jpg}";
in
{
  imports = [
    inputs.noctalia.homeModules.default
  ];

  config = lib.mkIf isNoctalia {
    programs.noctalia-shell = {
      enable = true;
      package = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;

      systemd.enable = false;

      colors = {
        mError = "#e06c75";
        mOnError = "#111111";
        mOnPrimary = "#111111";
        mOnSecondary = "#111111";
        mOnSurface = "#abb2bf";
        mOnSurfaceVariant = "#9aa3b2";
        mOnTertiary = "#111111";
        mOnHover = "#e6eaf2";
        mOutline = "#3b4252";
        mPrimary = "#61afef";
        mSecondary = "#56b6c2";
        mShadow = "#000000";
        mSurface = "#1f2329";
        mHover = "#30384a";
        mSurfaceVariant = "#282c34";
        mTertiary = "#98c379";
      };

      settings = {
        general = {
          language = "zh-CN";
          radiusRatio = 0.6;
          boxRadiusRatio = 0.8;
          screenRadiusRatio = 0.7;
          animationSpeed = 0.95;
          enableShadows = true;
          enableBlurBehind = true;
        };

        ui = {
          fontDefault = "Noto Sans CJK SC";
          fontFixed = "JetBrains Mono Nerd Font";
          fontDefaultScale = 1;
          fontFixedScale = 1;
          tooltipsEnabled = true;
          panelBackgroundOpacity = 0.9;
          settingsPanelMode = "attached";
          panelsAttachedToBar = true;
        };

        bar = {
          barType = "simple";
          density = "compact";
          position = "top";
          floating = true;
          marginVertical = 6;
          marginHorizontal = 8;
          frameThickness = 10;
          frameRadius = 16;
          widgetSpacing = 8;
          contentPadding = 3;
          showCapsule = true;
          capsuleOpacity = 0.96;
          backgroundOpacity = 0.88;
          hideOnOverview = true;
          widgets = {
            left = [
              {
                id = "Launcher";
              }
              {
                id = "Workspace";
                hideUnoccupied = false;
                labelMode = "none";
              }
              {
                id = "MediaMini";
              }
            ];
            center = [ ];
            right = [
              {
                id = "Network";
              }
              {
                id = "Bluetooth";
              }
              {
                id = "Volume";
              }
              {
                id = "Brightness";
              }
              {
                id = "SystemMonitor";
              }
              {
                id = "Tray";
              }
              {
                id = "Battery";
                alwaysShowPercentage = true;
                warningThreshold = 28;
              }
              {
                id = "Clock";
                formatHorizontal = "HH:mm";
                formatVertical = "HH mm";
                useMonospacedFont = true;
                usePrimaryColor = true;
              }
              {
                id = "ControlCenter";
              }
            ];
          };
        };

        location = {
          name = "Jingkou Qu, China";
          monthBeforeDay = false;
          use12hourFormat = false;
          weatherEnabled = true;
          weatherShowEffects = true;
          useFahrenheit = false;
          hideWeatherCityName = false;
          hideWeatherTimezone = false;
          showCalendarWeather = true;
          showWeekNumberInCalendar = true;
          firstDayOfWeek = 1;
        };

        wallpaper = {
          enabled = true;
          overviewEnabled = true;
          fillMode = "crop";
          useSolidColor = false;
          transitionDuration = 1200;
          transitionType = "random";
          overviewBlur = 0.55;
          overviewTint = 0.65;
          hideWallpaperFilenames = true;
        };

        colorSchemes = {
          useWallpaperColors = false;
          predefinedScheme = "Noctalia (default)";
          darkMode = true;
        };

        appLauncher = {
          enableClipboardHistory = true;
          enableClipPreview = true;
          position = "center";
          viewMode = "list";
          density = "compact";
          iconMode = "tabler";
          showIconBackground = true;
          showCategories = true;
          terminalCommand = "foot -e";
        };

        controlCenter = {
          position = "close_to_bar_button";
          cards = [
            {
              enabled = true;
              id = "profile-card";
            }
            {
              enabled = true;
              id = "shortcuts-card";
            }
            {
              enabled = true;
              id = "audio-card";
            }
            {
              enabled = true;
              id = "brightness-card";
            }
            {
              enabled = true;
              id = "weather-card";
            }
            {
              enabled = true;
              id = "media-sysmon-card";
            }
          ];
        };

        notifications = {
          enabled = true;
          density = "compact";
          location = "top_right";
          overlayLayer = true;
          backgroundOpacity = 0.95;
          respectExpireTimeout = true;
        };

        osd = {
          enabled = true;
          location = "top_right";
          backgroundOpacity = 0.95;
        };

        idle = {
          enabled = true;
          screenOffTimeout = 600;
          lockTimeout = 660;
          suspendTimeout = 1800;
          fadeDuration = 5;
        };

        dock = {
          enabled = true;
          position = "bottom";
          displayMode = "auto_hide";
          dockType = "floating";
          backgroundOpacity = 0.92;
          floatingRatio = 1;
          size = 1;
          onlySameOutput = true;
          colorizeIcons = false;
          showLauncherIcon = true;
          launcherPosition = "end";
          inactiveIndicators = true;
          groupApps = true;
          groupContextMenuMode = "extended";
          groupIndicatorStyle = "dots";
          deadOpacity = 0.65;
          animationSpeed = 1;
          showDockIndicator = true;
          indicatorThickness = 3;
          indicatorColor = "primary";
          indicatorOpacity = 0.75;
        };
      };
    };

    home.file.".cache/noctalia/wallpapers.json".text = builtins.toJSON {
      defaultWallpaper = wallpaperPath;
      wallpapers = {
        "eDP-1" = wallpaperPath;
      };
    };
  };
}

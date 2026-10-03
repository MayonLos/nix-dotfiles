{ pkgs, pkgs-unstable, ... }:

let
  firefoxAddons = {
    darkReader = pkgs.fetchurl {
      name = "darkreader-4.9.133.xpi";
      url = "https://addons.mozilla.org/firefox/downloads/file/5055786/darkreader-4.9.133.xpi";
      hash = "sha256-6wbFCW12FhbH8dlUwRUkykv/T+cikETcH84oiowIU6s=";
    };
  };

  firefoxWithManagedThemeAndExtensions = pkgs.firefox.override {
    extraPolicies = {
      ExtensionSettings = {
        "addon@darkreader.org" = {
          installation_mode = "force_installed";
          install_url = "file://${firefoxAddons.darkReader}";
          updates_disabled = true;
        };
        # Sync kept Frostlit active in the real profile despite the locked
        # theme preference. Block these four old theme add-ons so the built-in
        # dark theme and Noctalia browser chrome can actually take effect.
        "{74da71cc-4d66-48f5-95d1-1f017f18ffab}".installation_mode = "blocked";
        "{443bf4af-0884-4c22-886b-21f936e899df}".installation_mode = "blocked";
        "{7efc2a80-496f-49b1-88db-4ddd7d312757}".installation_mode = "blocked";
        "{894e1fa0-bfe2-4ee8-ad01-6e9ff4092ad0}".installation_mode = "blocked";
      };
    };
    extraPrefs = ''
      lockPref("extensions.activeThemeID", "firefox-compact-dark@mozilla.org");
    '';
  };
in
{
  home.packages = with pkgs; [
    qt6Packages.qt6ct
    # Qt5 counterpart, for Octave's Qt5 GUI -- see base/qt.nix. Only
    # 1.1 MiB on top, because Octave already drags Qt5 in.
    libsForQt5.qt5ct
    pkgs-unstable.github-copilot-cli
    # codex, dsh, grok, opencode and the agent-side tooling come from
    # programs/dev/ai-agents.nix — packaged by the llm-agents.nix input.
    # nvim comes from programs/dev/nvim.nix — built from ./nixvim in this repo.
    imagemagick
    nodejs
    bat
    eza
    ripgrep
    duf
    nix-output-monitor
    # `find` to ripgrep/eza/bat's `grep`/`ls`/`cat`; the one missing sibling of
    # the set above.
    fd
    # Not only for interactive use: screenshot.nix's activation reaches for it
    # through lib.getExe, and mmsg / noctalia both speak JSON.
    jq
    hexyl
    # `duf` covers filesystems; this is the "what ate the disk" half. Worth
    # having when the system closure is 60+ GiB.
    dust
    # tldr client. Complements nix-index + comma, which answer "which package
    # has this binary" rather than "how do I use it".
    tealdeer
    # Editing secrets/secrets.yaml is routine enough to want outside `nix develop`.
    sops
    wl-clipboard
    xclip
    grim
    slurp
    # OCR engine behind noctalia's fel/ocr plugin (see wm/mango/noctalia.nix),
    # which shells out to `tesseract` on a grim+slurp region. The override in
    # pkgs/tesseract-ocr.nix adds chi_sim, and screenshot.nix uses the same
    # derivation so its `-l eng+chi_sim` pass has the data.
    (callPackage ../../pkgs/tesseract-ocr.nix { })
    swayimg
    libheif
    brightnessctl
    # Noctalia external-monitor brightness. eDP-1 stays on the backlight backend.
    ddcutil
    pamixer
    pavucontrol
    playerctl
    libdecor
    lenovo-legion
    # No nvtop. Every variant with the NVIDIA backend pulls cuda-merged, i.e.
    # nvcc + cublas + cufft + cusolver + cusparse + npp -- 2.9 GiB of CUDA for a
    # GPU monitor, verified with `nix why-depends --derivation` on the system
    # toplevel. `nvidia-smi` ships with the driver and already answers the same
    # questions; CUDA proper stays in the `.#cuda` dev shell where it belongs.
    # imagemagick above covers stills; this is the video/audio half. OBS bundles
    # its own copy but does not put it on PATH.
    ffmpeg
    yt-dlp
    # system/user/environment.nix has unzip and unrar; 7z covers the rest.
    p7zip
    # ships the `qalc` CLI calculator.
    libqalculate
    protonup-qt
    obsidian
    zotero
    kicad
    kdePackages.kdenlive
    stellarium
    gimp
    go-musicfox
    firefoxWithManagedThemeAndExtensions
    # Official client. The nixpkgs wrapper follows NIXOS_OZONE_WL from
    # session-vars.nix, and Noctalia's notification daemon is already on
    # (wm/mango/noctalia.nix). That daemon is what the NixOS wiki says
    # Discord crashes without on a compositor that is not a full desktop.
    # Screen sharing uses the existing xdg-desktop-portal-wlr path, which
    # is pinned to eDP-1. Stock build, no withVencord: a June 2026 nixpkgs
    # report left that override opening a window that ignored input.
    discord
    typora
  ];
}

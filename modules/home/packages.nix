{
  pkgs,
  pkgs-unstable,
  ...
}:

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
    # which shells out to `tesseract` on a grim+slurp region. nixpkgs builds it
    # with English only; chi_sim is enabled explicitly because Chinese text is
    # the case that actually comes up here. The language set is baked in at
    # build time, so adding one later means another rebuild.
    (tesseract5.override {
      enableLanguages = [
        "eng"
        "chi_sim"
      ];
    })
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
    go-musicfox
    google-chrome
    typora
  ];
}

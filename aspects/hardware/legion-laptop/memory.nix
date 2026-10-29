_: {
  # The locked NixOS default starts oomd without monitoring any slices. Keep
  # one userspace OOM policy: the existing system-wide earlyoom thresholds.
  systemd.oomd.enable = false;

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };
  boot.kernel.sysctl = {
    # zram has no seek cost. Reclaim cold anonymous pages as readily as file
    # cache, and avoid decompressing adjacent pages that were not requested.
    "vm.swappiness" = 100;
    "vm.page-cluster" = 0;
  };

  # 28 logical CPUs do not imply enough RAM for 28 independent builds, each
  # with 28 compiler workers. Leave headroom for this 31 GiB laptop's desktop.
  # These are concurrency budgets, not hard memory limits on individual builds.
  nix.settings = {
    max-jobs = 2;
    cores = 8;
  };

  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;
    freeSwapThreshold = 10;
    enableNotifications = true;
  };
}

{
  pkgs,
  inputs,
  ...
}:
let
  # 直接用插件仓库里的采集脚本（flake input 的 store path），不复制一份，
  # 这样脚本跟着 nix flake update 一起走，不会和插件版本脱节。
  collectRaw = "${inputs.noctalia-plugins-community}/drive-health/scripts/collect_raw.sh";
in
{
  # drive-health 插件在无特权模式下只能拿到温度和容量，SMART 健康度是 Unknown
  # （面板上那句 "Full SMART details require the read-only system collector"）。
  # 它自带的安装器会用 pkexec 往 /etc/systemd/system 和 /usr/local/libexec 里
  # 写文件 —— 在 NixOS 上属于命令式污染，重装即丢、也不受配置管理。
  #
  # 这里把那个 collector 按上游 packaging/*.service.in 的语义声明式复刻：同样的
  # 采集脚本、同样的输出路径 /run/noctalia-drive-health/raw.json、同样的
  # RuntimeDirectory 权限（0750 + Group=users，让桌面用户能读），硬化选项照抄。
  systemd.services.noctalia-drive-health = {
    description = "Collect read-only SMART data for Noctalia Drive Health";
    documentation = [ "man:smartctl(8)" ];
    after = [ "local-fs.target" ];

    path = with pkgs; [
      smartmontools # smartctl
      util-linux # lsblk
      coreutils
    ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.runtimeShell} ${collectRaw} --output /run/noctalia-drive-health/raw.json";

      # mayon 的主组，对应上游脚本里的 `id -g "$target_user"`
      Group = "users";
      RuntimeDirectory = "noctalia-drive-health";
      RuntimeDirectoryMode = "0750";
      RuntimeDirectoryPreserve = "yes";
      UMask = "0027";

      StandardOutput = "null";
      StandardError = "journal";
      TimeoutStartSec = "60s";

      # 以下硬化项与上游 noctalia-drive-health.service.in 一致
      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateNetwork = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      RestrictAddressFamilies = [ "AF_UNIX" ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      # 读 NVMe/SATA 的 SMART 需要这几个能力
      CapabilityBoundingSet = [
        "CAP_DAC_OVERRIDE"
        "CAP_SYS_ADMIN"
        "CAP_SYS_RAWIO"
      ];
      ReadWritePaths = [ "/run/noctalia-drive-health" ];
    };
  };

  systemd.timers.noctalia-drive-health = {
    description = "Refresh SMART data for Noctalia";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "20s";
      OnUnitActiveSec = "15min";
      AccuracySec = "5s";
      Unit = "noctalia-drive-health.service";
    };
  };
}

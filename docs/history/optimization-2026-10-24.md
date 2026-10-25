# 2026-10-24 仓库与系统优化执行记录

光标历史说明：本文保留当轮 Bibata 的实现与测量；第二十六轮已改为共享 `phinger-cursors-light` 32，当前声明、1.5 缩放对比和验证见[应用层记录](apps-r26-2026-10-25.md)。

本文件合并当天各轮实施记录；各轮中的版本、路径、样本与验证结论仅对应记录时间。


---

## 第一轮：项目入口、udev 与输入更新

2026-10-24。基线为 `85010b2`，开始时工作树干净。审核由主代理完成，本轮按确认任务执行；
只修改仓库配置与文档，不应用配置、不删除应用数据，不提交或推送。

### 审核发现与改动

- 主代理确认 `~/Documents/NewNuclear` 与 NewNuclear-Workspace 已不存在，用户确认移除。
  删除 `inventory/hosts/nixos-btw/default.nix` 的 `workspaceProjects.newnuclear`，
  同步根 README 与 `docs/workflow-design.md`。全仓库跟踪文件搜索后，旧引用仅留在历史叙述中。
  仓库外 nn-dashboard 用户单元已由主代理处理，本轮未操作。
- 主代理实机日志反复出现 OpenOCD 的 `60-openocd.rules` 无法解析 `plugdev`。
  `aspects/embedded-workbench/host.nix` 声明空组，仅让规则可解析，不向用户授予该组；
  USB 访问仍由 logind 的 `uaccess` 动态 ACL 提供。对应 README 同步，
  `tests/composition/embedded.nix` 检查空成员与选择用户不在该组。
- 根 `treefmt-nix.inputs.nixpkgs` 与 `flake-parts.inputs.nixpkgs-lib` 改为 follows 根
  `nixpkgs`，移除两份独立锁定源。mango、noctalia-greeter、mark-shot、wayscrollshot、
  llm-agents 保持自己的依赖 pin，没有新增 follows。
- 首次完整系统构建发现 DSH 本地补丁与新版上游配方重复：上游已对 app-boot 的
  `index.js` 和 `worker/profile-resolution-bootstrap.js` 应用相同的 Node 兼容替换，
  本地再次 `--replace-fail` 因目标已消失而失败。读取失败 derivation 的 `postInstall`
  确认原因后，移除 `aspects/ai-workbench/ai-agents.nix` 的重复 override，直接复用上游
  `agents.dsh`；CLI 与桌面继续调用同一包。`docs/dsh.md` 同步为 0.2.1-rc.3。

### 输入更新

实际执行 `nix flake update`，返回 0。下表日期取锁文件 `lastModified` 的 UTC 日期；
包含根输入、传递锁定输入与此次变更的 follows，未变化的 follows 省略。
“未变”表示更新命令执行后 rev/日期仍相同，不表示跳过更新命令。

| 输入路径 | 旧 rev（日期） | 新 rev（日期） | 结果 |
|---|---|---|---|
| `den` | `37eb88ce28a9e42d5b367b967a9097030ff4f665` (2026-09-24) | `37eb88ce28a9e42d5b367b967a9097030ff4f665` (2026-09-24) | 未变 |
| `flake-parts` | `024633cd702b10285db5cb19b40ad48d2399ba60` (2026-10-01) | `024633cd702b10285db5cb19b40ad48d2399ba60` (2026-10-01) | 未变 |
| `flake-parts/nixpkgs-lib` | `f7cd230690d9fc982d06129f9189b101fddcfa3b` (2026-09-27) | follows nixpkgs | 更新 |
| `home-manager` | `32904dfe1cf86039f3c8c9f41f94e1cfd76dbb34` (2026-10-14) | `24f2190587513b9c2f73db112a17844ae912d965` (2026-10-24) | 更新 |
| `llm-agents` | `6eb6a99cbc74f65804751ca91869cd13a9006e91` (2026-10-14) | `9934bc184f4f1e2ad253e64e6739016aa4dead07` (2026-10-24) | 更新 |
| `llm-agents/bun2nix` | `07a5bfc8ac36c5370199343fa620b69f63186e33` (2026-09-21) | `07a5bfc8ac36c5370199343fa620b69f63186e33` (2026-09-21) | 未变 |
| `llm-agents/flake-parts` | `024633cd702b10285db5cb19b40ad48d2399ba60` (2026-10-01) | `024633cd702b10285db5cb19b40ad48d2399ba60` (2026-10-01) | 未变 |
| `llm-agents/nixpkgs` | `8edc0c72e3a38faf5434e40d1f19431125fe4b30` (2026-10-08) | `f20cd90e28fe0403873f473b29e42662cd86e8c4` (2026-10-16) | 更新 |
| `llm-agents/systems` | `d36eeed142f88b5a636f2e3856a53c61654cf29b` (2026-10-05) | `d36eeed142f88b5a636f2e3856a53c61654cf29b` (2026-10-05) | 未变 |
| `llm-agents/treefmt-nix` | `0d6d739a833ba9a9c93034862e4a7b061a062a1c` (2026-10-13) | `0d6d739a833ba9a9c93034862e4a7b061a062a1c` (2026-10-13) | 未变 |
| `mango` | `1cfb497eea7b18a2fb8372321b7927629208436a` (2026-10-14) | `900b8d7e06c396a20b6d4e56f242c4e240a69dfa` (2026-10-24) | 更新 |
| `mango/flake-parts` | `17c9d6cdfc60c64f4ee8d306f9bc0b4ccb51481e` (2026-07-01) | `17c9d6cdfc60c64f4ee8d306f9bc0b4ccb51481e` (2026-07-01) | 未变 |
| `mango/flake-parts/nixpkgs-lib` | `db3f255737b94216eb71cce308e2912cf6bc2d7c` (2026-06-28) | `db3f255737b94216eb71cce308e2912cf6bc2d7c` (2026-06-28) | 未变 |
| `mango/nixpkgs` | `f205b5574fd0cb7da5b702a2da51507b7f4fdd1b` (2026-07-05) | `f205b5574fd0cb7da5b702a2da51507b7f4fdd1b` (2026-07-05) | 未变 |
| `mango/scenefx` | `37ccd723bef49e6891156ffafce8f549f01446cc` (2026-06-28) | `37ccd723bef49e6891156ffafce8f549f01446cc` (2026-06-28) | 未变 |
| `mango/scenefx/flake-utils` | `11707dc2f618dd54ca8739b309ec4fc024de578b` (2024-11-13) | `11707dc2f618dd54ca8739b309ec4fc024de578b` (2024-11-13) | 未变 |
| `mango/scenefx/systems` | `31732fcf5e8fea42e59c2488ad31a0e651500f68` (2023-07-14) | `31732fcf5e8fea42e59c2488ad31a0e651500f68` (2023-07-14) | 未变 |
| `mark-shot` | `a682fce199c731eb737e1b306c1f6dbe45987319` (2026-10-12) | `fd481ed87902a26600b872ed33a9e951dd637423` (2026-10-18) | 更新 |
| `mark-shot/flake-utils` | `11707dc2f618dd54ca8739b309ec4fc024de578b` (2024-11-13) | `11707dc2f618dd54ca8739b309ec4fc024de578b` (2024-11-13) | 未变 |
| `mark-shot/flake-utils/systems` | `da67096a3b9bf56a91d16901293e51ba5b49a27e` (2023-04-09) | `da67096a3b9bf56a91d16901293e51ba5b49a27e` (2023-04-09) | 未变 |
| `mark-shot/nixpkgs` | `e73de5be04e0eff4190a1432b946d469c794e7b4` (2026-06-26) | `e73de5be04e0eff4190a1432b946d469c794e7b4` (2026-06-26) | 未变 |
| `nix-index-database` | `9a2dd40780eeab8543aa97c59c26f11267025616` (2026-10-11) | `1b4d1758fa6053c5d6284254a793134fa602fbff` (2026-10-18) | 更新 |
| `nixpkgs` | `7993f34ee47e28a3d607a525aadc6c94b73be728` (2026-10-12) | `da6dc0e7b26060f2f71ce3ef7088fb56ee44fa36` (2026-10-21) | 更新 |
| `nixpkgs-unstable` | `7fd4004d0511991fff3a0524856a9be09e28c5f0` (2026-10-11) | `02c087f3fe673c9e317f206a627cb6b910336dbe` (2026-10-20) | 更新 |
| `noctalia` | `fc2af27c0e616006bf858cad3b7c9711a028e501` (2026-10-14) | `5f864d472676c77e5310881b243f15cc371bb223` (2026-10-24) | 更新 |
| `noctalia-greeter` | `05fc8e3763de7940233358b5e0b1a5ae1967bcf1` (2026-10-12) | `8cc00abfdce3d8c1e68709a44eb0efc055932ada` (2026-10-23) | 更新 |
| `noctalia-greeter/nixpkgs` | `6510408d147d8c5e6d76043e899e9251756f6a75` (2026-10-10) | `fe13242281a67641c0102cdb1087f0ebe586c7df` (2026-10-15) | 更新 |
| `noctalia-plugins-community` | `7691612a091ac903cab79ffa5b3f740a04808ef1` (2026-10-13) | `e9dec7443b8a70ab606dc72669fb122a9d668bce` (2026-10-23) | 更新 |
| `noctalia-plugins-official` | `9aec34181e46789b281263942092ac552f661d1a` (2026-10-12) | `e1eac19947d4dbb7adb5a22c1de41ec348c4ca3d` (2026-10-23) | 更新 |
| `sops-nix` | `ee48786c6f9160d2c1a084aac841f68195b8420c` (2026-10-11) | `442449fa7b1fe6c692d0103ac9fc8f9e82931cf3` (2026-10-24) | 更新 |
| `treefmt-nix` | `0d6d739a833ba9a9c93034862e4a7b061a062a1c` (2026-10-13) | `0d6d739a833ba9a9c93034862e4a7b061a062a1c` (2026-10-13) | 未变 |
| `treefmt-nix/nixpkgs` | `8825bebf6324e0579d012936eff73379af284b6d` (2026-09-23) | follows nixpkgs | 更新 |
| `wayscrollshot` | `e42f3b9e68f0018809ff9d8390ce9d3424c79cf3` (2026-07-15) | `703474ad7b94a504306d7a93d21668ee162ebf1c` (2026-10-15) | 更新 |
| `wayscrollshot/flake-parts` | `0678d8986be1661af6bb555f3489f2fdfc31f6ff` (2026-05-05) | `0678d8986be1661af6bb555f3489f2fdfc31f6ff` (2026-05-05) | 未变 |
| `wayscrollshot/flake-parts/nixpkgs-lib` | `f5901329dade4a6ea039af1433fb087bd9c1fe14` (2026-04-26) | `f5901329dade4a6ea039af1433fb087bd9c1fe14` (2026-04-26) | 未变 |
| `wayscrollshot/nixpkgs` | `549bd84d6279f9852cae6225e372cc67fb91a4c1` (2026-05-05) | `549bd84d6279f9852cae6225e372cc67fb91a4c1` (2026-05-05) | 未变 |
| `wayscrollshot/rust-overlay` | `bc83d66023d19fb301ee98772643b24b6129ef48` (2026-05-08) | `bc83d66023d19fb301ee98772643b24b6129ef48` (2026-05-08) | 未变 |

### 验证与构建

本轮按要求依次执行；下列成功命令均返回 0。首次 toplevel 失败单列说明，
修复后重新执行格式、求值、treefmt、相关 checks 与 toplevel；未回退任何输入。

1. `git diff --check`；`nix fmt`；再查看 diff：通过，formatter 没有改写内容。
2. `nix flake check --no-build --no-write-lock-file`：求值通过，包括全部 18 个 checks
   的 derivation 和真实主机配置。存在 `unknown flake output 'denful'` 警告，退出码为 0。
   这一步不证明 checks 已构建。
3. `nix build --no-link --no-write-lock-file .#checks.x86_64-linux.treefmt`：构建通过。
4. `nix eval --json --no-write-lock-file .#checks.x86_64-linux --apply builtins.attrNames`
   列出 18 个 checks。以下 10 个 `embedded-*` / `*-composition` 全部构建通过，
   并补充构建 `project-workbench`、`interactive-session-config`；DSH 修复后 12 项一起重跑通过：

   ```sh
   nix build --no-link --no-write-lock-file \
     .#checks.x86_64-linux.desktop-composition \
     .#checks.x86_64-linux.editing-composition \
     .#checks.x86_64-linux.embedded-composition \
     .#checks.x86_64-linux.embedded-home \
     .#checks.x86_64-linux.embedded-tools \
     .#checks.x86_64-linux.embedded-udev \
     .#checks.x86_64-linux.local-services-composition \
     .#checks.x86_64-linux.protocols-composition \
     .#checks.x86_64-linux.remote-workspace-composition \
     .#checks.x86_64-linux.workspace-composition \
     .#checks.x86_64-linux.project-workbench \
     .#checks.x86_64-linux.interactive-session-config
   ```

5. 完整系统：

   ```sh
   nix build --no-link --no-write-lock-file .#nixosConfigurations.nixos-btw.config.system.build.toplevel --print-out-paths
   ```

   首次返回 1，唯一根因是 DSH 重复补丁的 `substituteInPlace --replace-fail`；
   读取 `nix log /nix/store/v2s54dp28v5nb6majzk5bza2q3hk8acj-dsh-0.2.1-rc.3.drv`
   及 `nix derivation show` 定位后修复。重跑返回 0，新产物为：

   ```text
   /nix/store/m94847gja6hic2r8sr2ygcjq7xhwzyn3-nixos-system-nixos-btw-26.05.20261021.da6dc0e
   ```

6. `nix store diff-closures /run/current-system /nix/store/m94847gja6hic2r8sr2ygcjq7xhwzyn3-nixos-system-nixos-btw-26.05.20261021.da6dc0e`：
   返回 0；摘要见下节。`nix path-info --json --closure-size` 和
   `nix path-info --recursive` 补充核验总大小及未变版本。
7. 真实 host 求值检查：`plugdevMembers = []`，所有主组或附加组使用 plugdev 的
   账号集合 `plugdevUsers = []`；mayon 的附加组仍为
   `libvirtd, kvm, gamemode, dialout, input, wheel, networkmanager`。
8. Nix 构建沙箱中的 DSH CLI 启动检查返回 0：使用真实 Home Manager 的 `dsh` wrapper，
   为 HOME/XDG 目录分配构建临时目录，执行 `dsh --version`、`dsh --help`、
   `dsh headless --help`。输出保存在
   `/nix/store/l7lrxjdp5bpnnpr8xsxpykfhkv7w4rqd-dsh-startup-check`。
   没有使用个人 Harness 配置、凭据或发送模型请求；不据此宣称 GUI/服务端端到端通过。
9. 文档相对链接、全仓库跟踪文件当前态引用与最终 `git diff --check` 通过。
   新历史文件按任务要求新增且未 stage；Git flake 不包含该未跟踪文件，已单独检查其链接与内容。
   treefmt 当前仅配置 Nix/Lua 等 formatter，不承担 Markdown 排版验证。

### Closure 摘要

对比基线运行系统 `dp8v8fdxa3hsjzl733442dpgmrdpagsy` 与新构建，
这只是产物比较，不代表运行内核或桌面已经更新。

| 项目 | 旧 → 新 |
|---|---|
| 内核 | linux-zen 7.2.9 → 7.2.11 |
| NVIDIA | 驱动仍为 595.104.02；open 模块从匹配 7.2.9 改为匹配 7.2.11 |
| Mesa | 主 Mesa 仍为 26.1.8；closure 中 mesa-libgbm 26.0.3/26.1.3 仍在，26.1.3 的 store 路径由 1 份增至 2 份 |
| Mango | nightly，rev `1cfb497eea7b18a2fb8372321b7927629208436a` → `900b8d7e06c396a20b6d4e56f242c4e240a69dfa` |
| Noctalia / greeter | 5.2.1 → 5.3.0 / 1.6.0 → 1.7.0 |
| Firefox | 157.0.1 → 158.0.1 |
| 总 closure（NAR 大小） | 64,511,171,856 → 65,747,263,928 字节；60.08 → 61.23 GiB，增加 1.15 GiB（1.92%） |

以上内核与驱动属于本轮历史产物；后续源码已改为 stable 默认 LTS 和同源 NVIDIA，
并启用 scx_lavd，见[第四轮记录](#第四轮lts-内核stable-nvidia-与-sched-ext)。构建和实际启动状态分别记录。

显著增加项：DSH +248.1 MiB，Python 汇总 +137.1 MiB（新增 3.14.8 路径）、
Perl 汇总 +55.2 MiB；此外有多份运行库因不同输入 pin 并存。
这些是 diff-closures 按名称汇总的 store 产物大小差，不是独立软件的完整依赖 closure。
NewNuclear 的 tmuxp JSON 与 desktop entry 均从新 closure 移除。

### 应用与实机验收

待主代理应用。构建不会激活系统；本轮未执行 sudo 或任何 nixos-rebuild。
udev 日志噪声是否消失、USB 设备访问、桌面与更新软件的实际运行表现，均待主代理应用后验证。

---

## 第二轮：开机体验与冷色调壁纸

2026-10-24，第二轮。主代理和用户已确认“完整无闪屏开机”与“冷色调轮换，默认 005”。
开始时工作树干净。本轮只修改仓库配置与文档，不应用配置、不修改运行态、不删除素材或应用数据，
不 stage、提交或推送；`flake.lock` 保持不变。本文按任务明确要求新增，未 stage，
因此不属于 Git flake 的输入；单独检查本文内容与链接。

### 实现与归属

- `aspects/system/legion-laptop/boot.nix`：systemd-boot timeout 从默认 5 改为 1 秒，
  `consoleMode = "max"`，`editor = false`；选择 systemd initrd、`verbose = false`、
  early i915 KMS 与 Plymouth `bgrt`。原有 `dm_mod` 保留，NVIDIA 留在 stage 2。
  `console.earlySetup = true`，Terminus `ter-v32n`（16×32 像素字格，内屏约 160×50）
  与 `console.packages = [ pkgs.terminus_font ]` 也属于该笔记本的启动/高分屏策略。
- `aspects/interactive-session/host/fonts.nix`：TTY 16 色消费宿主外观输入与公开
  `appearance/ansi.nix`，仅去掉 `#`。与 Kitty/Neovim 及桌面设计的 ANSI 顺序一致，
  不复制颜色值，也不让硬件 aspect 读取外观实现。外观 README 同步消费者。
- `aspects/system/maintenance/nix.nix`：journald `SystemMaxUse=1G`；只声明滚动上限，
  未手动 vacuum 或删除日志。现有 `maintenance/nh.nix` 已启用 nh 自动清理，锁定模块
  将其实现为每周 `nh clean all --keep 5 --keep-since 14d`，timer 为 Persistent；
  `nix.gc.automatic = false`。保留该现状，没有新增清理任务；用户仍可用 `nc` 手动清理。
- `aspects/interactive-session/noctalia.nix`：用 linkFarm 派生目录限定
  `002/005/008/009/011` 五张 PNG，`recursive = false`；默认路径 `005`，
  automation 为 enabled、random、86400 秒。全部原素材保留。
  Greeter、Xorg 桌面及 Xorg 锁屏固定为 `005`；Wayland 锁屏继续跟随当前壁纸。
  Xorg 检查和 desktop-design、xorg-desktop-execution、dwm-visual-design 同步。
- `aspects/interactive-session/checks.nix` 验证真实 host 的 loader/initrd/Plymouth/TTY、
  NVIDIA 不进入 initrd、greetd VT/顺序、派生目录恰有五个有效链接与默认/greeter 同图。
  `tests/composition/desktop.nix` 同时检查 reducedMotion 关闭启动转场且保留自动轮换。

### 锁定源码核对

本轮 nixpkgs 为 `da6dc0e7b26060f2f71ce3ef7088fb56ee44fa36`：

- `nixos/modules/system/boot/plymouth.nix` 的默认主题就是 `bgrt`，
  `themePackages` 仅对 breeze 默认补包；bgrt 由 Plymouth 包自带。
  模块自动复制 DejaVuSans 字体、默认 NixOS logo 和 bgrt 依赖的 spinner 资源到 initrd，
  不需额外 themePackages/font/logo 配置。固件 logo 是否可用取决于本机 BGRT，需重启验收；
  主题不等于能保证固件至 greeter 的所有画面都无闪屏。
- Plymouth 模块自动追加 `splash`，本地不重复。保留 `quiet`、`udev.log_level=3`、
  `loglevel=3`、`split_lock_detect=off`，仅补充 `systemd.show_status=auto`。
  锁定 systemd 260.5 源码 `src/udev/udev-config.c:462` 与
  `src/basic/proc-cmdline.c:165–179` 表明 udev 不带前缀的参数在两阶段都生效，
  因而不加重复的 `rd.udev.log_level=3`。`src/core/main.c:364–372,2886–2887`
  使用 flags=0 解析且只匹配 `systemd.show_status`，不会剥除 rd 前缀；因此
  `rd.systemd.show_status=auto` 无效，不添加。无前缀的 show_status 同时作用于两阶段。
  同版本 `systemd.1` 手册确认 quiet 默认是 error，auto 平时静默、明显延迟时显示状态，
  与 quiet 的默认值不重复。
  `boot.initrd.verbose` 主要控制旧 stage-1 脚本消息；systemd initrd 的状态策略由上述参数控制。
- `nixos/modules/services/display-managers/greetd.nix` 固定 VT1，旧 `services.greetd.vt`
  已移除。`greeterManagesPlymouth` 默认 false，自动令 greetd 排在
  `plymouth-quit-wait.service` 后；Noctalia greeter 当前模块未覆写该值。
  保留模块自带交接，不添加未经支持的 VT 或 quit 覆盖。
- Noctalia 当前锁定的是 `5f864d472676c77e5310881b243f15cc371bb223`（5.3.0），
  桌面设计早期引用的 `fc2af27c…` 是旧 pin。当前
  `docs/user/desktop/wallpaper.mdx:32–36,77–87`、
  `src/config/schema/config_schema.cpp:891–900`、
  `src/shell/wallpaper/wallpaper.cpp:938–943,994–1001` 确认字段名、目录/recursive 与轮换语义：
  shell 启动时先随机选一张，之后每 86400 秒随机选图，并同步应用到已连接输出；
  不是固定日历时刻任务，也不保证登录第一张为 `005`。
  `wallpaper.cpp:589–593,612–627` 表明手动/IPC 换图会重置该计时；
  `src/app/application_ui.cpp:342` 与 `wallpaper.cpp:912–914,1037–1046` 表明锁屏期间
  不执行轮换，wall clock 仍继续，解锁时若间隔已到期可立即换图。
  `reducedMotion = true` 通过本仓库已有适配设置 `transition_on_startup = false`、
  `transition = []`，轮换继续，切换无转场。未修改用户状态中原来的 `006`；
  应用后由主代理通过已核验的 IPC 处理，不清空 Noctalia state。

### 验证与构建

实际执行以下命令。静默参数按当前 systemd 源码精简后，重新完成格式检查、flake 求值、
最终配置求值、全部 checks 和 toplevel 构建；以下证据对应最终配置。

1. `git diff --check`：通过。`nix fmt`：通过，首次格式化仅改写了 Noctalia linkFarm
   的排版；最终一轮 0 changed。之后查看 `git diff` 并复查空白，通过。
2. `nix flake check --no-build --no-write-lock-file`：返回 0，全部 checks derivation
   与真实 host 求值通过；存在既有 `unknown flake output 'denful'` 警告。
3. `nix eval --json --no-write-lock-file .#checks.x86_64-linux --apply builtins.attrNames`：
   返回 0，共 18 项。用 Python 将该列表转换成 installable 参数，实际批量运行：

   ```sh
   nix build --no-link --no-write-lock-file \
     .#checks.x86_64-linux.command-line-runtime \
     .#checks.x86_64-linux.desktop-composition \
     .#checks.x86_64-linux.editing-composition \
     .#checks.x86_64-linux.embedded-composition \
     .#checks.x86_64-linux.embedded-home \
     .#checks.x86_64-linux.embedded-tools \
     .#checks.x86_64-linux.embedded-udev \
     .#checks.x86_64-linux.interactive-session-config \
     .#checks.x86_64-linux.local-services-composition \
     .#checks.x86_64-linux.neovim \
     .#checks.x86_64-linux.project-workbench \
     .#checks.x86_64-linux.protocols-composition \
     .#checks.x86_64-linux.remote-workspace-composition \
     .#checks.x86_64-linux.rime-technical-runtime \
     .#checks.x86_64-linux.system-boundaries \
     .#checks.x86_64-linux.treefmt \
     .#checks.x86_64-linux.workspace-composition \
     .#checks.x86_64-linux.xorg-session-runtime
   ```

   返回 0，全部 18 项构建成功，包含 treefmt、真实 host 配置、reducedMotion 分支、
   Xorg 运行检查及 Neovim 检查；部分复用此前已成功构建的相同产物。
   这些运行检查在构建沙箱执行，不代表真实桌面或开机验证。
4. `nix build --no-link --no-write-lock-file .#nixosConfigurations.nixos-btw.config.system.build.toplevel --print-out-paths`：
   返回 0，产物如下。构建使用模块自带 bgrt/spinner、DejaVu 字体与 Terminus，
   未额外配置主题包。并行求值时出现 Nix eval-cache SQLite busy 的 ignored 提示，未阻断构建。

   ```text
   /nix/store/5xipwrgs2rpdkn9x0bbf2kifv3ij5g7z-nixos-system-nixos-btw-26.05.20261021.da6dc0e
   ```

5. 实际打印最终值：

   ```sh
   nix eval --json --no-write-lock-file .#nixosConfigurations.nixos-btw.config --apply 'c: { timeout = c.boot.loader.timeout; kernelParams = c.boot.kernelParams; initrdModules = c.boot.initrd.kernelModules; plymouthTheme = c.boot.plymouth.theme; consoleFont = c.console.font; wallpaper = c.home-manager.users.mayon.programs.noctalia.settings.wallpaper; }'
   nix eval --json --no-write-lock-file .#nixosConfigurations.nixos-btw.config.home-manager.users.mayon.programs.noctalia.settings.wallpaper.directory --apply builtins.readDir
   ```

   两条均返回 0。timeout=1，initrdModules=`["dm_mod","i915"]`，theme=bgrt，
   consoleFont=ter-v32n。kernelParams 的完整输出：

   ```text
   quiet
   udev.log_level=3
   systemd.show_status=auto
   split_lock_detect=off
   root=fstab
   splash
   loglevel=3
   lsm=landlock,yama,bpf
   vt.default_red=0x0e,0xe5,0x8e,0xe2,0x4f,0xbf,0x48,0xa0,0x53,0xe5,0x8e,0xe2,0x4f,0xbf,0x48,0xd1
   vt.default_grn=0x10,0x55,0xbd,0xb8,0xa6,0x68,0xb0,0xa8,0x59,0x55,0xbd,0xb8,0xa6,0x68,0xb0,0xd5
   vt.default_blu=0x13,0x61,0x6b,0x6b,0xed,0xd9,0xbd,0xb7,0x65,0x61,0x6b,0x6b,0xed,0xd9,0xbd,0xde
   ```

   壁纸目录为 `/nix/store/shl9fh0mqv840192hich73a0fl12a7g9-noctalia-cool-wallpapers`，
   `builtins.readDir` 输出恰为五个 symlink：`wallpaper-002.png`、`wallpaper-005.png`、
   `wallpaper-008.png`、`wallpaper-009.png`、`wallpaper-011.png`；构建检查进一步验证链接目标存在。
   默认路径为 `/nix/store/q4rjlxsx98ahl40zj56b30piy4vv94ai-wallpaper-005.png`。
   同时求值确认 `initrdSystemd=true`、`initrdVerbose=false`、`themePackages=[]`、
   console 16 色、greetd VT1/After 和 nh weekly 策略。
6. `nix build --no-link --no-write-lock-file .#nixosConfigurations.nixos-btw.config.systemd.package.src --print-out-paths`：
   返回 0，仅为核对锁定 systemd 260.5 的参数解析源码；产物为
   `/nix/store/s8lxzd3r71kn8f8gfj9vq4ghdzvlna7f-source`。
   读取已构建 bgrt 主题确认 `UseFirmwareBackground=true` 与 spinner ImageDir；
   Terminus 包确认存在 `share/consolefonts/ter-v32n.psf.gz`。
7. Python 校验 6 个修改/新增 Markdown 文件中的 47 个相对链接：通过；
   新 history 单独检查行尾空白。`git diff --exit-code -- flake.lock` 返回 0。
   新文件的 `git diff --no-index --check /dev/null docs/history/boot-wallpaper-2026-10-24.md`
   无空白错误输出，返回 1 表示两输入存在差异；不把该退出码写成构建失败或成功码。
   Git flake 不包含这份未跟踪历史文件；treefmt 也不承担 Markdown 版式检查。
8. 独立 reviewer 只读核对跨模块接线、Noctalia 语义与最终 systemd 参数，未发现阻断缺陷。
   审核没有应用配置，不代替实机测试。

### 应用与待验收

本轮未执行 sudo 或任何 nixos-rebuild，也未改仓库外配置、登录状态和壁纸素材。
待主代理/用户应用后重启：确认固件 logo、early KMS、Plymouth 转圈、greeter 交接及错误场景；
检查启动菜单与 TTY 字号、颜色和字体。仍需实机检查壁纸随机启动/每日轮换、reducedMotion
无转场、greeter 与 Xorg/锁屏裁切。未重新测量启动耗时、功耗或显卡 runtime 行为。

---

## 第三轮：字体、图标与 Atuin

本轮只修改声明、文档并做隔离构建检查，没有应用配置、导入历史或删除用户数据。
开始时工作树干净；按用户明确要求新增本记录，未执行 stage/commit/push。

### 实现与归属

- `aspects/appearance/onedark-darker.nix` 与 `contract.nix`：公共字体分为 sans（Inter）、
  cjk（Noto 简中无衬线）、mono（Maple NF CN）、serif；增加文件夹颜色字段 blue，
  光标改为 Modern Classic、尺寸仍为 24。外观只拥有数据。
- `aspects/interactive-session/host/fonts.nix`：安装 `maple-mono.NF-CN`、`inter`，
  移除不再有消费者的旧等宽字体包；保留独立 Symbols Nerd Font Mono 回退包。
  fontconfig sans-serif 为 Inter 然后 Noto 简中，monospace 跟随公共 mono。
- `aspects/interactive-session/input-method.nix`、`aspects/media/mpv.nix`：候选与中文
  字幕消费 cjk，OSD 消费 mono；无 palette 时用通用 fontconfig 家族，不硬编码外观选择。
  `aspects/documents/zathura.nix` 的无外观界面回退同样使用 sans-serif。
- `aspects/interactive-session/gtk.nix`、`xorg/appearance.nix` 各自将
  `papirus-icon-theme.override { color = palette.iconFolderColor; }` 交给消费者，
  `xorg/default.nix` 的 Dunst XDG 路径也指向同一变体。主题名仍为 Papirus-Dark。
  blue 对应当前蓝色焦点；本轮未另选 bluegrey。
- `aspects/interactive-session/greeter.nix` 增加可在登录前访问的 Inter 包；字体与
  Bibata 光标仍消费 host palette。GTK、Mango/XCURSOR、Xorg 与 greeter 的指针均跟随公共字段。
- `aspects/interactive-session/xorg/dwm/package.nix`、`configure.py` 将 mono/cjk 作为
  参数传入，取消私有字体硬编码；保留 9.5 pt。dmenu、Dunst 和 Xorg 锁屏原有公共字段继续生效。
- `aspects/interactive-session/qt.nix`：除了新配置 seed，增加旧完整字体默认序列的有界
  迁移，仅在 Fonts 段精确匹配时替换。跳过 symlink，保留自定义字体和其他 GUI 键；没有运行激活。
- `aspects/command-line/default.nix`、`zsh.nix` 通过 Home Manager 启用 Atuin：
  `--disable-up-arrow`、`auto_sync = false`、`update_check = false`、compact、20 行、
  `enter_accept = false`、默认 global、shell up filter 为 session。主题由本应用从 palette
  生成到 `atuin/themes/onedark-darker.toml`，配置引用同名主题；无 palette 的纯 CLI 组合
  不生成主题，但仍可使用本地历史搜索。数据库归运行时用户数据，不自动 import。
- `aspects/command-line/checks.nix` 检查最终 Ctrl+R / Ctrl+T / Alt+C / 上箭头和配置主题；
  `aspects/interactive-session/checks.nix` 检查字体选择；`xorg/checks.nix` 更新隔离字体和
  图标包；`tests/composition/desktop.nix`、`protocols.nix` 覆盖字体字段类型、消费关系、
  Qt 旧值迁移、自定义保留和幂等。
- 文档：`docs/desktop-design.md`、`workflow-design.md`、`config-ownership.md`、
  `README.md` 与本记录同步。

Kitty、Noctalia 面板时钟、Qt fixed、mpv OSD 与 dwm 均消费 mono；终端 tmux/Neovim
没有单独 GUI 字体，继承 Kitty。Kitty 保持 11 pt：内屏 2560×1600 / 1.5 约有 1707×1067
逻辑空间，仅换家族不能决定缩字号，需真实窗口比较行宽/行距。原配置没有 symbol_map，
Maple 自带 Nerd/CJK 字形，不新增覆盖；另保留独立 Symbols 字体给其他消费者回退。

Inter 用于面板、控制中心、GTK、Qt、greeter、锁屏、Mango 装饰、图片信息与文档应用 UI；
Fcitx 候选和 mpv 中文字幕继续使用完整中文家族，避免中文正文依赖混合字体度量。

### 锁定源码与字体证据

锁定 nixpkgs 为 `da6dc0e7b26060f2f71ce3ef7088fb56ee44fa36`。
Noctalia `fc2af27c0e616006bf858cad3b7c9711a028e501` 已采用 C++，
`src/render/text/cairo_text_renderer.cpp` 调用 `FcInit`、`pango_cairo_font_map_new`、
`pango_font_description_set_family`、`pango_layout_set_text`，没有关闭 Pango 缺字回退。
因此 Inter 的家族请求可以对中文回退；不能沿用旧 Quickshell/QML 实现的假设。
隔离字体检查使用真实 host 的生成 fontconfig 规则，仍需真实混合文字视觉验收。

锁定 Home Manager `24f2190` 的 `modules/programs/atuin.nix` 支持 themes、Zsh flags 和集成；
`fzf.nix` 以 `mkOrder 910` 提前初始化，为 Atuin 接管 Ctrl+R 让出顺序，其他 fzf 按键保留。
Atuin 18.15.2 支持本轮设置和主题颜色角色；主题色来自公共 palette，没有增加外观对应用的依赖。

字体独立构建实际成功：

```sh
nix build --impure --no-link --no-write-lock-file --print-out-paths --expr \
  'let f = builtins.getFlake (toString ./.); p = import f.inputs.nixpkgs {system="x86_64-linux";}; in [ p.maple-mono.NF-CN p.inter ]'
fc-scan --format '%{family}; %{style}\n' /nix/store/6h0dvbxmjk96hq5yqnq4j9kp8b9z3hyr-MapleMono-NF-CN-7.9/share/fonts/truetype/MapleMono-NF-CN-Regular.ttf
fc-scan --format '%{family}; %{style}\n' /nix/store/2cksf1q8lqpgvcllipn5p56q7njbj9ly-inter-4.1/share/fonts/truetype/Inter.ttc
```

Maple 常规 face 返回 `Maple Mono NF CN; Regular`，Inter TTC 首 face 返回 `Inter; Regular`，
与配置完全一致。Inter 的两个 variable TTF 名为 Inter Variable，但同时安装的 TTC 提供 Inter，
所以不能只扫描 TTF 就断言名称不匹配。另实际用 `fc-query` 读取 charset，并检查 U+4E2D、
U+F07B、U+E0B0 均存在，证明中文、Nerd 文件夹与 Powerline 字形可用。

### 验证结果

实际执行并通过：

1. `git diff --check`；`nix fmt`；格式化后再次 `git diff --check`。
2. `nix flake check --no-build --no-write-lock-file`，最终退出 0、all checks passed。
   保留已有 `unknown flake output 'denful'` 警告；这是求值证据，不是系统应用证据。
3. 下列脚本实际执行，枚举当前全部 18 项 checks，加上真实 host 的 toplevel 构建，最终退出 0：

```python
import json, os, subprocess
checks = json.loads(subprocess.check_output([
    "nix", "eval", "--json", "--no-write-lock-file",
    ".#checks.x86_64-linux", "--apply", "builtins.attrNames"
], text=True))
os.execvp("nix", ["nix", "build", "--no-link", "--no-write-lock-file", "--print-out-paths"]
          + [".#checks.x86_64-linux." + name for name in checks]
          + [".#nixosConfigurations.nixos-btw.config.system.build.toplevel"])
```

18 项为 command-line-runtime、desktop-composition、editing-composition、embedded-composition、
embedded-home、embedded-tools、embedded-udev、interactive-session-config、local-services-composition、
neovim、project-workbench、protocols-composition、remote-workspace-composition、
rime-technical-runtime、system-boundaries、treefmt、workspace-composition、xorg-session-runtime。
包含构建沙箱内的 Xvfb/Xorg 行为检查，不等同于笔记本桌面验收。

新系统输出：

```text
/nix/store/7znxsgz6hldwy7n3521lhcim4991jsz1-nixos-system-nixos-btw-26.05.20261021.da6dc0e
```

构建产物已读回：

- `/nix/store/axjki8yx2chaaib1a9br2apcffzymbc1-interactive-session-config/` 的
  sans-family.txt、mono-family.txt、cjk-fallback.txt 分别是 Inter、Maple Mono NF CN、Noto 简中。
- `/nix/store/b1h8ihyjx7ziwjkp4ir6xrl9qrxs0wdj-den-interactive-session-composition/`
  保存 Qt 迁移、保留自定义字体及现有 palette 的结果。
- `/nix/store/i47w9g92ch31xy58710mxhji8cp7jdng-command-line-runtime/`
  的 zsh-ctrl-r 为 atuin-search，zsh-fzf-bindings 包含 fzf-file-widget、fzf-cd-widget、
  up-line-or-beginning-search。测试将生成 zshrc 的绝对 home/秘密文件路径重定向至隔离 HOME；
  不导入或读取真实历史。
- Papirus 构建包 `/nix/store/5vm57z2rc9dcywhmq3bxyjd9av2xj7d5-papirus-icon-theme-20250501`
  下 Papirus 与 Papirus-Dark 的 `48x48/places/folder.svg`，实际 `readlink` 都返回 folder-blue.svg。

初次求值曾暴露纯 CLI fixture 的 null palette 主题错误，修正可选主题后全量重跑通过。
独立 reviewer 还发现 Qt seed 不更新旧配置，补上有界迁移并通过组合检查；最终复核无未解决阻断。
改动文档的本地链接已用 Python 逐个检查目标存在，README/desktop/workflow/ownership 分别有
29/17/15/11 个本地链接。本记录按用户明确请求新增且未 stage，因此不在 Git flake 源快照内；
本轮配置与检查均是已跟踪文件，以上构建已包含，未使用 `path:.` 扩大源范围。

### 名称残留逐条核对

实际运行用户指定三个名称的递归 grep（排除 Git 元数据），结果如下。
旧鼠标主题名无匹配；旧等宽名字仅存在于 Qt 迁移匹配与其测试输入，不再作为当前字体选择。

| 文件与行 | 保留原因 |
|---|---|
| `aspects/appearance/onedark-darker.nix:8` | 中文专用公共字段，是保留的中文字体选择 |
| `aspects/interactive-session/qt.nix:113` | 只用于识别旧 UI 默认值，输出来自当前 palette |
| `aspects/interactive-session/qt.nix:114` | 只用于识别旧 fixed 默认值，输出来自当前 palette |
| `tests/composition/desktop.nix:355` | 旧 UI 字体迁移的测试输入 |
| `tests/composition/desktop.nix:356` | 旧 fixed 字体迁移的测试输入 |
| `aspects/editing/host.nix:10` | IDE 自带原生库的兼容原因，与字体无关 |
| `aspects/editing/jetbrains.nix:3` | IDE 包 RPATH workaround 原因，与字体无关 |
| `docs/desktop-design.md:75` | 记录界面中文回退规则 |
| `docs/desktop-design.md:138` | IDE 项目 launcher provider，与字体无关 |
| `docs/desktop-design.md:180` | 记录中文公共字段的准确 family |
| `docs/desktop-design.md:187` | 记录 sans-serif 回退顺序 |
| `docs/desktop-design.md:192` | 记录旧字体包已移除，不是安装声明 |
| `docs/desktop-design.md:199` | 记录中文字体选择检查的预期结果 |
| `docs/config-ownership.md:21` | 记录 Qt 旧默认值有界迁移的范围 |
| `docs/config-ownership.md:27` | IDE/编辑器配置与用户数据归属 |
| `docs/application-review.md:87` | 保留 IDE 功能的源码入口 |
| `docs/application-review.md:200` | 保留 IDE 项目 provider 的评估 |
| `docs/history/refactor-plan.md:144` | 历史 IDE 保留选择 |
| `docs/history/refactor-plan.md:153` | 历史 launcher 插件清单 |
| `docs/history/refactor-plan.md:238` | 历史 IDE 精简章节标题 |
| `docs/history/refactor-plan.md:268` | 历史软件取舍决定 |
| `docs/history/refactor-plan.md:329` | 历史应用/会话入口清单 |
| `docs/history/refactor-plan.md:353` | 历史 provider 保留决定 |
| `docs/history/refactor-plan.md:364` | 历史 provider 与工具依赖边界 |
| `docs/history/den-execution.md:41` | 历史编辑器功能迁移证据 |
| `docs/history/execution-handoff.md:85` | 历史完整编辑器/语言批次交接 |

### 应用后的实机待验

- Kitty 11 pt 的宽度、连字、Nerd/CJK 混排行距，tmux/Neovim 和 mpv OSD。
- Noctalia 面板、中文 launcher/控制中心、锁屏及 greeter 的缺字回退、裁切和数字宽度。
- GTK/Qt 字体、Qt 旧配置迁移后 GUI 保存与重启读回，Papirus 蓝色文件夹，以及 Mango/Xorg/
  XWayland/greeter 的 Classic 24 指针；混合 DPI/外屏仍待取得真实输出事实。
- 新 shell 的 Atuin Ctrl+R、Enter 仅返回编辑、上箭头原生搜索、fzf Ctrl+T/Alt+C 和主题。
  需要旧历史导入时由主代理应用配置后显式执行，保留原历史及 Atuin 数据库。

---

## 第四轮：LTS 内核、stable NVIDIA 与 sched-ext

日期：2026-10-24。范围：`nixos-btw` 的 legion-laptop 硬件策略、组合检查和文档。
本轮只构建，不激活配置；没有执行 sudo、nixos-rebuild 或 Git stage/commit/push。

### 背景与依据

原声明使用 linux-zen 7.2.11。stable NVIDIA 595.71.05 的内核源码使用已在 Linux 7.2
移除的 `strncpy`，因此先前借用 nixpkgs-unstable 的 nvidia-x11 配方（595.104.02），
再用本机内核和 stable 依赖构建。社区同类报错见
[Nixpkgs #554125](https://github.com/NixOS/nixpkgs/issues/554125)。

锁定 stable nixpkgs 为 `da6dc0e`（完整 revision 见 `flake.lock`）：默认
`linuxPackages` 为 6.18.57，`nvidiaPackages.stable` 为 595.71.05；
`lenovo-legion-module` 可用，scx Rust schedulers 为 1.1.2。
配置依据锁定源码 `nixos/modules/services/scheduling/scx.nix` 和
`pkgs/os-specific/linux/scx/scx_rustscheds.nix`，没有更新 lock。

[Nixpkgs #555996](https://github.com/NixOS/nixpkgs/issues/555996) 将 lavd 卡顿/冻结回归
定位到 1.1.3，并记录回退至 1.1.2；[上游 #3750](https://github.com/sched-ext/scx/issues/3750)
也有 1.1.3 卡顿、1.1.2 正常的用户报告。
[PR #574970](https://github.com/NixOS/nixpkgs/pull/574970) 将 1.1.2 升至 1.1.4，
称后者修复该回归。因此已报告的这次 1.1.3 回归不涵盖当前锁定的 1.1.2；
这不证明 1.1.2 没有其他问题，也不代替本机运行验证。

[OmerFarukOruc/nixos-config #208](https://github.com/OmerFarukOruc/nixos-config/pull/208)
在另一台 AMD ROG / KWin 机器上报告：power-saver 下使用 `--autopower`，
合成器线程最坏唤醒延迟约 101 ms，固定 performance 时约 0.9 ms。
该短时单机测量支持规避 autopower；不能推断 Intel/NVIDIA + Mango 的本机延迟或收益。

### 决定与实现

- `aspects/system/legion-laptop/boot.nix` 改为 `pkgs.linuxPackages`，
  NVIDIA 使用 `config.boot.kernelPackages.nvidiaPackages.stable`；清除跨 channel 配方
  和不再使用的 `inputs` 参数。保留 open、persistenced、PRIME offload 和 Mango profile。
- stable 内核与驱动来自同一 package set，减少 API 不匹配；sched_ext 自 6.12 起可用，
  本轮由 scx 提供调度策略，不再选择 zen。保留 legion 模块、`split_lock_detect=off`、
  i915 early KMS、systemd initrd 和 Plymouth bgrt。
- `aspects/system/legion-laptop/power.nix` 启用 `services.scx`，scheduler 为
  `scx_lavd`，`extraArgs = []`。实际构建出的 1.1.2 `--help` 确认：无参数默认
  **autopilot**，按负载选择 performance/powersave/balanced，并非固定 balanced；
  `--autopower` 则跟随电源 profile。本轮保留无参数默认，不启用 autopower，
  也不固定 performance/powersave/balanced。
- 官方模块把 scx 包加入系统，unit 随 `multi-user.target` 启动，以
  `/sys/kernel/sched_ext` 目录为条件，`Restart=on-failure`，30 秒最多启动 2 次；
  `SCX_SCHEDULER=scx_lavd`、`SCX_FLAGS` 为空。构建不会启动该服务。
- `tests/composition/system.nix` 与 `nix/checks.nix` 验证真实 host 的内核 derivation
  等于 stable 默认内核、NVIDIA 等于同一 kernelPackages 的 stable 包，且 lavd 启用、
  参数不含 autopower；无头 fixture 同时断言不启用 scx，防止硬件策略泄漏。

### 验证

参数依据命令（实际运行，退出 0；帮助输出写入 stderr，故合并后截取）：

```sh
/nix/store/72q6ba4s23gn8d89kizdy146izbhyzdp-scx_full-1.1.2/bin/scx_lavd --help 2>&1 | head -60
```

`nix eval --json --no-write-lock-file .#nixosConfigurations.nixos-btw.config --apply
'c: { kernel = c.boot.kernelPackages.kernel.version; nvidia = c.hardware.nvidia.package.version;
scheduler = c.services.scx.scheduler; extraArgs = c.services.scx.extraArgs;
extraModulePackages = map (p: p.name) c.boot.extraModulePackages; }'` 实际返回：

```json
{"kernel":"6.18.57","nvidia":"595.71.05","scheduler":"scx_lavd","extraArgs":[],"extraModulePackages":["lenovo-legion-module-0.0.20-unstable-2025-07-11","nvidia-open-595.71.05-6.18.57"]}
```

实际验证命令及结果：

1. `git diff --check`、`nix fmt` 后再次 `git diff --check`：退出 0。
2. `nix flake check --no-build --no-write-lock-file`：退出 0，全部求值通过。
   仅有既有 `unknown flake output 'denful'` 警告；求值本身不证明构建或运行成功。
3. 构建全部 `checks.x86_64-linux` 和 toplevel，以下命令退出 0 并打印 19 个输出路径
   （18 项 checks + 系统）：

   ```sh
   nix build --no-link --no-write-lock-file --print-out-paths --impure --expr \
     'let f = builtins.getFlake (toString ./.); in builtins.attrValues f.checks.x86_64-linux ++ [ f.nixosConfigurations.nixos-btw.config.system.build.toplevel ]'
   ```

   其中 `system-boundaries` 的 `stableDefaultKernel`、`matchingStableNvidia`、
   `lavdWithoutAutopower` 均为 true，产物为
   `/nix/store/5kfnhm0w5bk36r6q82793mzj0ix16f4z-den-system-boundaries.json`。
   内核、legion 和 NVIDIA 模块使用二进制缓存，系统模块集合、initrd 和 toplevel
   成功构建；没有把缓存取得描述为本机源码重新编译。
4. 再以真实 Git flake 入口执行
   `nix build --no-link --no-write-lock-file --print-out-paths .#nixosConfigurations.nixos-btw.config.system.build.toplevel`，
   退出 0，路径与上述结果一致：

   ```text
   /nix/store/b62ckg0pnj6s2fd6bf4fmf9iwwnr6l24-nixos-system-nixos-btw-26.05.20261021.da6dc0e
   ```

5. `nix build --no-link --no-write-lock-file --print-out-paths .#nixosConfigurations.nixos-btw.config.boot.kernelPackages.kernel.configfile`：
   退出 0。产物
   `/nix/store/6p7i4nkc80krhk9f4a4cz7prqji5a3lb-linux-config-6.18.57`
   确认 `CONFIG_SCHED_CLASS_EXT=y`、`CONFIG_DEBUG_INFO_BTF=y`，
   `CONFIG_DRM_I915=m`、`CONFIG_IWLWIFI=m`、`CONFIG_IWLMVM=m`。
   `modinfo -F vermagic` 对 legion-laptop.ko 与 nvidia.ko.xz 均返回
   `6.18.57 SMP preempt mod_unload`。求值确认 initrd 模块为 `dm_mod`、`i915`，
   保留 `split_lock_detect=off` 与 Plymouth；实际 initrd 构建成功。
   以上证明配置和构建产物兼容，不证明真实硬件已加载或启动成功。
6. 检查新 toplevel 的 `etc/systemd/system/scx.service`，确认 scheduler、空参数、
   目录条件、重启策略和 multi-user wants 与锁定模块一致。
7. 修改文档的本地相对链接检查通过；独立 reviewer 只读复核未发现阻断问题。
   本文件按任务要求新增并保持未 stage；Git flake 不包含该未跟踪文档，
   本文件链接与内容单独核验。另以 `git status --short --ignored` 确认未发现忽略文件，
   没有使用 `path:.` 或引入运行时秘密。

### Closure 摘要

`nix store diff-closures /run/current-system /nix/store/b62ckg0pnj6s2fd6bf4fmf9iwwnr6l24-nixos-system-nixos-btw-26.05.20261021.da6dc0e`
实际退出 0。对比基线为
`/nix/store/7znxsgz6hldwy7n3521lhcim4991jsz1-nixos-system-nixos-btw-26.05.20261021.da6dc0e`，
这是运行系统的 closure，不据此推断当前正在运行的内核版本。

| 项目 | 基线 → 新产物 |
|---|---|
| 内核 / initrd | linux-zen 7.2.11 → linux 6.18.57 |
| NVIDIA open 模块 | 595.104.02-7.2.11 → 595.71.05-6.18.57 |
| NVIDIA 用户态 / persistenced / settings | 595.104.02 → 595.71.05 |
| scx | 新增 scx_full / scx_rustscheds 1.1.2、scx_cscheds 0-unstable-2026-01-13、unit-scx.service |
| 总 closure NAR 大小 | 65,890,199,504 → 66,123,743,664 字节；增加 233,544,160 字节，约 222.7 MiB |

总大小由 `nix path-info --json --closure-size` 核验。diff-closures 显示 Rust schedulers
新增约 212.8 MiB、C schedulers 约 6.1 MiB；完整 scx 包是锁定 NixOS 模块的默认选择。
这些是 store 产物变化，不是运行时内存或性能测量。

### 回退与实机验收

若后续应用并重启后出现启动、驱动或调度问题，可在开机 systemd-boot 菜单选择上一代。
当前菜单超时 1 秒，可在启动时按住 Space 显示菜单；不清理旧 generation。
源码回退可恢复 `boot.kernelPackages = pkgs.linuxPackages_zen`，并同时在 nvidia.nix
恢复 `inputs` 参数及下面的旧配方，然后重新求值、构建，再由有授权者应用：

```nix
package =
  (config.boot.kernelPackages.callPackage (
    inputs.nixpkgs-unstable + "/pkgs/os-specific/linux/nvidia-x11"
  ) { }).stable;
```

若只需撤回 sched-ext，可关闭 `services.scx.enable`；回退源码时还须同步调整本轮新增的
策略断言，避免预期不同而失败。以上是回退方法，本轮没有执行应用或回退操作。

重启后待验：`uname -r`、`nvidia-smi` 与 PRIME offload、`legion_laptop` 模块加载、
CNVi Wi-Fi/以太网、i915/Plymouth 启动画面、`systemctl status scx`、
`cat /sys/kernel/sched_ext/state` 与当前调度器名称，以及不同供电/profile 下的指针、
窗口交互和休眠恢复。尚无同条件性能/续航测量，不宣称交互或功耗已经改善。

### 重启后实机验证（2026-10-24 18:11 启动）

- `uname -r` = 6.18.57；`nvidia-smi` 识别 RTX 4060 Laptop，驱动 595.71.05。
- `/sys/kernel/sched_ext/state` = enabled，ops = `lavd_1.1.2`；`scx.service` active；legion 模块已加载；Wi-Fi 已连接。
- Plymouth 启动服务已运行；无失败的系统/用户单元。
- loader 阶段仍为 5.7s：EFI 变量 `LoaderConfigTimeout` = 5 覆盖了 `loader.conf` 的 `timeout 1`。已用 `bootctl set-timeout ''` 清除，下次启动生效（未再次重启验证）。

---

## 第五轮：仓库整理、登录加速与头像

2026-10-24。基线 `e580c6d66da17f3b36d05eaacc1cfd9772d7b857`，开始时工作树干净。
本轮只修改仓库源码、文档并构建；没有执行 sudo、任何 nixos-rebuild 子命令、
git add/commit/push/stash/reset、flake update 或用户数据清理。

### 仓库整理与字节等价

- `aspects/interactive-session/mango.nix` 的 `defaultBinds` 至 `helpText` 原表达式
  原样移至私有 `mango/keybinds.nix`，显式接收 `lib`、`pkgs`、`display`。
  主文件保留 HM 接线、绑定中帮助命令的展开、规则及外观设置；顺便修正旧路径注释。
- 修改前先求值并构建两个 HM 文件，记录基线 flake source
  `/nix/store/bh859c1s06mv9n662badsl8x4azb18xh-source`。
  拆分后重新求值与构建，两个生成文件的 store 路径均与基线相同。
  实际执行两次 `cmp`，均返回 0；独立 reviewer 另确认搬移表达式源字节一致。

| 文件 | 拆分前、后相同 store 路径 | SHA256 |
| --- | --- | --- |
| `~/.config/mango/config.conf` | `/nix/store/bvpckzjyw4b16xanwaxkbsf8naww1y7l-mango-config.conf` | `5bfb6282e9e86f4caa15f4f659a64823490346471ed182c282f71c38356fed36` |
| `~/.local/share/mango/keybindings.txt` | `/nix/store/n30hky22s4zb39887lydn0yacdbwhj4d-hm_mangokeybindings.txt` | `a7c56b2e9ede87648a0131da7dd668418e1dcc4360e3888cd77b0f4c01a3d3e1` |

基线命令（修改前执行）；改后以 `path:.#` 替代 `.#` 重新执行：

```sh
nix eval --raw --no-write-lock-file '.#nixosConfigurations.nixos-btw.config.home-manager.users.mayon.xdg.configFile."mango/config.conf".source'
nix eval --raw --no-write-lock-file '.#nixosConfigurations.nixos-btw.config.home-manager.users.mayon.xdg.dataFile."mango/keybindings.txt".source'
nix build --no-link --no-write-lock-file --print-out-paths '.#nixosConfigurations.nixos-btw.config.home-manager.users.mayon.xdg.configFile."mango/config.conf".source' '.#nixosConfigurations.nixos-btw.config.home-manager.users.mayon.xdg.dataFile."mango/keybindings.txt".source'
```

- 当天第一至四轮完整并入本文件，轮内标题降一级，保留全部事实、命令、链接和验证结论；
  删除被合并的三份历史记录，修复全仓引用及 `docs/README.md` 索引。
  对照 Git HEAD 的原正文与非空行核验，除标题层级及迁移后的链接外均保留。
- 当前态文档按源码清扫：LTS 6.18.57、同源 stable NVIDIA 595.71.05、Inter / Maple、
  Classic 指针、005 默认壁纸、声明的一秒 bootloader timeout。第四轮实测的 EFI timeout
  覆盖仍是当时的事实；清除覆盖后的启动耗时没有重新测量。
  补充核对当前 pin：Noctalia Mango 模板现在确实输出 tab bar 颜色，修正了旧说明；
  早期设计 pin 标为历史证据，另列当前 lock 表，避免混淆。
- 引用审计未发现可安全删除的 Nix 文件、helper 或非壁纸资源，未为缩减文件数删除源码。
  `aspects/default.nix` 显式登记，配方由功能入口显式引用；`lib/java.nix` 由
  PrismLauncher/Java 工具/devShell 消费，`toolchains.nix` 由 Python/Lua/CPP 消费，
  `session-environment.nix` 由 Mango/Noctalia 消费，`seed-file.nix` 由 Qt/Zathura 消费。
  OCR 配方、Rime smoke 源码、reconcile 测试及 Firefox helpers 均有构建或运行消费者。
  未发现断言引用缺失资源；这是静态引用审计，加上后述求值/构建证据，未声称遍历全部运行分支。
  全部 12 张壁纸素材保留，当前轮换集合仍为 002/005/008/009/011。

### 登录关键路径与优化

输入测量由主代理在本次开机实机核验：HM system service 1.81s，位于
`graphical.target ← greetd ← plymouth-quit-wait ← systemd-user-sessions ← home-manager-mayon`。
其中 `checkLinkTargets` 0.24s、`linkGeneration` 0.43s、`batCache` 0.39s、
`migrateQt6ctFonts` 0.36s。这是修改前测量，本轮未应用或重启，没有修改后的耗时数据。

- 锁定 HM `24f2190587513b9c2f73db112a17844ae912d965` 的
  [bat 模块](https://github.com/nix-community/home-manager/blob/24f2190587513b9c2f73db112a17844ae912d965/modules/programs/bat.nix)
  在 bat 启用时每次 activation 都运行 cache builder，与主题/语法内容是否变化无关。
  仓库求值的 `themes = {}`、`syntaxes = {}`，主题为 bat 内置 `base16`。
  `tools.nix` 仅在这两个集合均空时把该 DAG 项置空；将来添加自定义资源会恢复上游行为。
  既有用户缓存不删除，主题与 style 不改。
- bat 配置修改前后仍为
  `/nix/store/7w60b73i6ikd4225w1za7dcxld81dvrw-hm_batconfig`，`cmp` 通过。
  内容仍为 `--style=numbers,changes,header` 与 `--theme=base16`；bat 0.26.1
  `--list-themes` 含 `base16`。配置驱动的带色样例前后 SHA256 均为
  `7df82c0b89f7ce726d97b45b3645f08a0b2e400ec3c50c1158b79f984772a1a3`。

```sh
batpkg=$(nix eval --raw --no-write-lock-file 'path:.#nixosConfigurations.nixos-btw.config.home-manager.users.mayon.programs.bat.package')
printf 'theme sample\n    configured before\n' | "$batpkg/bin/bat" --config-file /nix/store/7w60b73i6ikd4225w1za7dcxld81dvrw-hm_batconfig --color=always | sha256sum
```

- Qt activation 先用 shell 的文件/软链检查与 `grep -Fq` 查旧字体文本，只有命中才调用
  原 Python。刻意使用子串预筛选，保留 CRLF/CR-only 等换行场景；可能多调用一次 Python，
  但不会因整行 grep 漏掉原脚本能处理的旧值。Python 仍只改 `[Fonts]` 的完整旧默认行。
  改前后调用同一 `/nix/store/js77ibpvn7jqa96lfqc1j53qcyl0l4g0-qt6ct-migrate-fonts.py`。
  Nix sandbox differential fixture 使用基线算法与当前实际 activation 对照：LF、CRLF、
  CR-only、无末换行、非 Fonts 的旧行、重复 Fonts、自定义 metrics、不匹配、软链、缺失文件
  均最终字节一致；后四类 Python 调用为 0。测试只写 builder TMPDIR/store。
  产物 `/nix/store/5cvvc01s22qx040kbfznndlll5cz13ir-qt6ct-migration-equivalence`，
  可用 `nix log /nix/store/k4g0sm5q75nq99v3d3nd8kyz331lqwg5-qt6ct-migration-equivalence.drv`
  查看各 fixture 的 identical 与调用次数。
- 保留 `checkLinkTargets` 与 `linkGeneration`：它们承担已有文件冲突检查与 generation
  链接切换，未找到可证明无损的跳过办法。没有修改缺乏分段测量证据的其他步骤。
- 只评估 HM 排序：锁定 [NixOS 模块](https://github.com/nix-community/home-manager/blob/24f2190587513b9c2f73db112a17844ae912d965/nixos/default.nix)
  默认 system-service 模式排在 `systemd-user-sessions.service` 前，确保登录前完成用户环境。
  user-service 模式在该版本仍标为实验性；本机 Mango/Noctalia 直接消费 HM generation 文件。
  移除此边界会允许登录与链接切换竞争，不能在当前证据下证明等价，因此完全保留排序。

### 头像生成、读取路径与已有状态保护

唯一配方位于 `inventory/hosts/nixos-btw/accounts.nix`，HM 消费 `user.appearance`，
真实 host aspect 消费 `host.appearance`；当前二者相同，输出同一 derivation。
使用 librsvg、隔离 Fontconfig 中的 Inter，构建 512×512 RGBA PNG：palette.blue 圆角方形，
palette.black 的 Inter 700 字母 M。Fontconfig 验证 `Inter:style=Bold` 命中 Inter Bold，
PNG IHDR 为 512×512，主代理已目视检查。

PNG：`/nix/store/h2c3zyz29y8gdj0zfsjmwiwdydm3n7gs-mayon-avatar.png`。

- HM 管理 `~/.local/share/nix-dotfiles/mayon-avatar.png`，仅在 `.face` 缺失时 seed 指向它；
  `run` 支持 HM DRY_RUN。已有普通文件、软链或悬空软链一律保留。
- 系统管理 `/etc/nix-dotfiles/mayon-avatar.png`；NixOS activation 在 `users`、`etc`
  后，仅对缺失的 `/var/lib/AccountsService/icons/mayon` 创建指向此稳定路径的软链。
  两个稳定目标随 generation 切换更新，避免凭 store 文件名猜测已有头像归属。
- AccountsService `users/mayon` 缺失则 seed `[User]`/`Icon=`；存在时只补该节中缺失/空白
  的 Icon，保留非空自定义 Icon 的原文件字节，以及其他设置和文件 owner/mode。
  不写穿 metadata 软链或 AccountsService/icons/users 目录软链。
  不把只读探测无权限当作文件不存在；本轮未能读取现有系统 metadata 内容，不需要此内容才能
  验证上述保护逻辑。未对真实系统或用户目录执行这些 activation。
- 锁定 Noctalia 的
  [头像解析器](https://github.com/noctalia-dev/noctalia-shell/blob/5f864d472676c77e5310881b243f15cc371bb223/src/shell/profile/avatar_path.cpp)
  优先 `shell.avatar_path`，否则读取 AccountsService IconFile；launcher 与控制中心消费它。
  本轮不强制该 override，以保留运行时头像选择。
  [greeter](https://github.com/noctalia-dev/noctalia-greeter/blob/8cc00abfdce3d8c1e68709a44eb0efc055932ada/src/accounts/accounts_icon.cpp)
  同样读取 AccountsService IconFile。
- 当前锁屏 login box 无直接头像 consumer；使用锁定源码支持的原生
  [sticker widget](https://github.com/noctalia-dev/noctalia-shell/blob/5f864d472676c77e5310881b243f15cc371bb223/docs/user/desktop/widgets.mdx)，
  由 [lockscreen controller](https://github.com/noctalia-dev/noctalia-shell/blob/5f864d472676c77e5310881b243f15cc371bb223/src/shell/lockscreen/lockscreen_widgets_controller.cpp)
  共用该 widget 类型。只在 mayon 绑定中声明，读取绝对 `/home/mayon/.face`，内屏中心 x=1/2、
  y=13%、80×80 逻辑像素；不改变原 clock/date/login 坐标。独立 reviewer 按真实逻辑高度
  1066.67 核对头像区间 98.67–178.67、clock 201–311，避开日期及认证状态卡。
  这证明布局声明和源码几何，不证明实际画面。
- `interactive-session/checks.nix` 持久回归测试使用实际生成的两个 activation 脚本，
  在 Nix sandbox 替换目标前缀后覆盖：缺失 seed、重复幂等、稳定目标更新、DRY_RUN、
  自定义普通文件/软链/悬空软链、多个 metadata section、缺失/空白/带空格非空 Icon、
  无末换行 custom 文件字节不变、metadata 与各父目录软链，以及 HM/系统 PNG 同源和锁屏配置。

### 最终验证

- `git diff --check` 返回 0。
- `nix fmt` 返回 0；另执行 `nix fmt -- --walk filesystem` 覆盖新增的未跟踪源码，返回 0。
  Git walker 对三份已删除历史文件的提示符合本轮删除操作；最后一次格式化为 0 changed。
- 按要求实际运行 `nix flake check --no-build --no-write-lock-file`：失败，原因为 Git flake
  不含新增且未 stage 的 `mango/keybinds.nix`，不是模块求值失败。遵守禁止 git add 的范围，
  新文件保持未跟踪，交付时必须一并纳入源码，不能只拿现有 Git diff 的 tracked 部分。
- 使用 `path:.` 前执行 `git ls-files --others --ignored --exclude-standard`，无忽略文件；
  `git ls-files --others --exclude-standard` 唯一新增源为 `mango/keybinds.nix`。
  没有把运行时用户数据或秘密纳入源。`nix flake check --no-build --no-write-lock-file path:.`
  返回 0；仅保留仓库原有的 unknown output `denful` 提示。
- 用 `nix eval --json --no-write-lock-file path:.#checks.x86_64-linux --apply builtins.attrNames`
  取得全部 18 个 check 名称，然后一次运行
  `nix build --no-link --no-write-lock-file --print-out-paths path:.#checks.x86_64-linux.<name> …`，
  18 项全部构建成功并输出路径，包括 treefmt、Neovim、CLI、全部组合、Rime/Xorg 和
  interactive-session-config。交互会话检查输出为
  `/nix/store/ibn7r9y89dcjhqshff0gvjfwssnwv1bp-interactive-session-config`，包含 Noctalia/Mango
  原生 parser、fontconfig、所有权与新增头像 activation fixture；返回 0。
  并发求值期间 Nix 曾提示 eval-cache SQLite busy（ignored），所有最终命令均正常结束。
- `nix build --no-link --no-write-lock-file --print-out-paths path:.#nixosConfigurations.nixos-btw.config.system.build.toplevel`
  构建成功，新 toplevel：
  `/nix/store/0kpgi9sqg8a5vbqy6d746xy3044k4s7d-nixos-system-nixos-btw-26.05.20261021.da6dc0e`。
- 最终重新求值两个 Mango 文件和 bat 配置，再以修改前记录的 store 路径为基线执行 `cmp`，
  三项均返回 0；头像 PNG 另以 HM source 输出直接构建，路径如上。
- 文档检查扫描 37 个仓库 Markdown 文件，230 个相对目标（包含 Markdown 锚点）全部通过；
  修正合并后的第四轮锚点，并修正 workflow 指向已重命名 Neovim 标题的旧锚点。
  当前态 21 份文档的 `rg -n` 过时模式扫描无命中：`linuxPackages_zen`、zen 内核、
  unstable NVIDIA 配方、旧 Ice 指针、默认 009/006、`fonts.sans = "Noto…"`、
  五秒启动等待与 `timeout = 5`。Noto 的 CJK 回退及 Qt 迁移匹配值仍是真实当前事实。
  全仓旧历史文件名搜索只剩第二轮真实执行的 `git diff --no-index --check /dev/null …`
  历史命令，按“保留全部命令”要求原样保留；已不存在指向被删除文件的 Markdown 引用。

本轮独立 reviewer 复核了跨模块结论、搬移源、历史正文保留、activation/metadata 保护与
锁屏几何；反馈的 HM dry-run 和原头像位置可能遮挡认证卡问题均已修复。

待实机：由有授权者应用后，再测同条件 HM activation 各分段和 greetd 关键路径；核实
bat 在真实 shell 中配色、Qt 旧默认迁移/GUI 自定义保存；核实 AccountsService IconFile、
launcher/控制中心/greeter 与冷登录的头像加载，以及锁屏 sticker 尺寸、裁切、认证错误卡
和混合缩放下的显示。当前未应用、未重启、未执行真实用户文件迁移，不宣称登录已加速或
GUI 已生效，也不将旧记录中的应用授权延伸到本轮。

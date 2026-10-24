# 项目入口、udev 与输入更新

2026-10-24。基线为 `85010b2`，开始时工作树干净。审核由主代理完成，本轮按确认任务执行；
只修改仓库配置与文档，不应用配置、不删除应用数据，不提交或推送。

## 审核发现与改动

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

## 输入更新

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

## 验证与构建

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

## Closure 摘要

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
并启用 scx_lavd，见[第四轮记录](kernel-scx-2026-10-24.md)。构建和实际启动状态分别记录。

显著增加项：DSH +248.1 MiB，Python 汇总 +137.1 MiB（新增 3.14.8 路径）、
Perl 汇总 +55.2 MiB；此外有多份运行库因不同输入 pin 并存。
这些是 diff-closures 按名称汇总的 store 产物大小差，不是独立软件的完整依赖 closure。
NewNuclear 的 tmuxp JSON 与 desktop entry 均从新 closure 移除。

## 应用与实机验收

待主代理应用。构建不会激活系统；本轮未执行 sudo 或任何 nixos-rebuild。
udev 日志噪声是否消失、USB 设备访问、桌面与更新软件的实际运行表现，均待主代理应用后验证。


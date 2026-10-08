# 共享接口与关键配置索引

编辑 `lib/`、`flake/`、`pkgs/` 或跨模块共享的配置前读本文；它回答"这个值应该改哪里、
改完怎么验证"。领域细节仍看对应技能。

## lib/ 抽象接口

| 文件 | 作用 | 消费者 | 怎么改 |
|---|---|---|---|
| `import-dir.nix` | 递归导入目录下所有 `.nix` | `flake/system.nix`、`hosts/nixos-btw/default.nix` | 不改；无排除机制，非模块 `.nix` 不能放 `modules/` 下 |
| `java.nix` | Temurin JDK 集合：`default` + `jdks`（8/17/21/25/26，26 来自 unstable） | `dev/java.nix`（包与 `javaNN` 包装器）、`games/prismlauncher.nix`（JDK 检测路径）、`base/session-vars.nix`（`JAVA*_HOME`）、`shell/zsh.nix`（`use-javaNN`） | 增删版本只动 `jdks` 一行；换默认版本改 `default` |
| `toolchains.nix` | 语言版本集合：`llvm`（clang/lld/clang-tools）、`python`（含 `<python>.pkgs`）、`lua` + `luaPackages` | `dev/llvm.nix`、`dev/toolchain.nix`、`dev/python.nix`、`dev/lua.nix` | 换 LLVM/Python 改一行；Lua 的 `lua` 与 `luaPackages` 必须一起换（nixpkgs 包集按版本命名） |
| `desktop.nix` | 跨 NixOS/HM 的桌面常量：`cursor`、`primaryOutput`、`repoPath`、`iconTheme` | `home/base/gtk.nix`、`home/base/qt.nix`、`system/desktop/greetd.nix`、`wm/mango/config.nix`、`wm/mango/noctalia.nix`、`system/desktop/xdg.nix`、`system/programs/nh.nix` | 换光标、显示器名、仓库路径或图标主题只改这里；`repoPath` 必须保持可变真实路径，不能换成 store 路径 |
| `graphical-service.nix` | 图形会话 systemd 用户单元模板（Unit/Install 固定，只填 `description` 与 `service`） | `home/services/cliphist.nix`、`home/services/clipboard.nix`、`home/base/xresources.nix` | 新增随会话启停的服务时用它；`Type`/`Restart` 等仍写在调用处 |
| `seed-file.nix` | 激活脚本里"缺失才创建"的可变文件（应用自己会重写） | `home/base/qt.nix`（qt6ct/qt5ct.conf）、`home/programs/terminal/kitty.nix`（noctalia 主题）、`home/programs/apps/zathura.nix`（noctaliarc） | `mkActivation` 生成独立 activation；要嵌进别的脚本用 `mkScript`；永远不覆盖已有文件 |

规则：**≥2 个消费者才进 `lib/`**；单文件内的重复用文件内 `let`。`lib/default.nix` 仍只导出
`importDir`，模块按相对路径取具体文件（如 `../../../lib/desktop.nix`）。

## 关键配置文件

| 文件 | 职责 | 改动要点 |
|---|---|---|
| `flake.nix` | 输入、`pkgs` overlay、`pkgs-unstable` 唯一定义（`_module.args.pkgs-unstable`） | 改输入/overlay 读 [输入与包来源](inputs.md)；不要另起第二个 unstable import |
| `flake/system.nix` | `nixosConfigurations.nixos-btw`；`system` 与 `extraArgs`（`inputs` + `pkgs-unstable`）经 `specialArgs`/`extraSpecialArgs` 下发 | 两个 arg 必须同时给 NixOS 与 HM |
| `modules/home/base/session-vars.nix` | 非秘密会话变量唯一来源，同时写 `systemd.user.sessionVariables` 与 `home.sessionVariables`；`sessionPath` 放默认 JDK 与 `~/.local/bin` | 新增共享变量加进 `shared`；只对交互 shell 生效的放 HM 一侧（如 `EDITOR`） |
| `modules/home/programs/dev/toolchain.nix` | nvim 启动的 server/formatter/linter 唯一来源；nixvim 里只用裸命令 | 加编辑器工具加这里，别写进 nixvim 闭包；语言编译器仍回各语言模块 |
| `modules/home/packages.nix` | 用户级 CLI/应用清单 | unstable 单包要注释原因，并同步 `inputs.md` 例外清单 |
| `nixvim/packages.nix` | nvim 闭包取舍（remote host 关闭、dependencies 只留 fd）；共享键位 helper 在 `nixvim/lib/keymaps.nix` | 改依赖前读 `dev-toolchain` 的闭包参考与文件内测量注释 |
| `pkgs/*.nix` | 不在 nixpkgs 的包表达式（matlab、libtexprintf、diffview-plus、tesseract-ocr） | 放仓库根 `pkgs/`，用 `callPackage`；放 `modules/` 会被 importDir 当模块 |
| `modules/home/wm/mango/noctalia.nix` | Noctalia settings/templates/plugins/hooks 与 firefox 主题 post_hook | 模板路径、插件清单、hooks 都在这；插件外部依赖要同步 `home.packages` |
| `hosts/nixos-btw/hardware.nix` | nixos-generate-config 产物 | 保持生成状态，手改会被下次扫描覆盖；例外见 `host-hardware` 技能 |

## 变更速查

| 想做的事 | 改哪里 | 验证 |
|---|---|---|
| 增/删/换默认 JDK | `lib/java.nix` | `nix flake check --no-build`；构建后 `java -version`、`use-javaNN` |
| 换光标主题/大小 | `lib/desktop.nix` | 构建后查 greetd 配置与 HM `home.pointerCursor` 的值 |
| 换显示器名 | `lib/desktop.nix` | mango `config.conf` 的 monitorrule/sleep/wakeup、xdg screencast、noctalia monitor |
| 换 LLVM/Python/Lua 版本 | `lib/toolchains.nix` | `nix eval` 对比 `clang` 与 `clang-tools` 的 drvPath 是否同源 |
| 加 nvim server/formatter | `modules/home/programs/dev/toolchain.nix`（nixvim 里声明裸命令） | 构建后 `command -v <tool>`；`:checkhealth` |
| 加随图形会话的服务 | `lib/graphical-service.nix` + 调用模块 | 构建后查 `home-files/.config/systemd/user/<unit>.service` |
| 让应用首次生成可变配置 | `lib/seed-file.nix` + 调用模块 | 检查生成脚本含 `! -e` 守卫；构建后跑 activation |
| 新增自定义包 | `pkgs/<name>.nix` + `callPackage` | `nix build` 该包 |
| 新增模块 | 丢进 `modules/home/` 或 `modules/system/`（自动导入） | `nix flake check --no-build`；新文件先 `git add` |
| 新增不稳定单包 | 调用处 `pkgs-unstable.<attr>` 并注释原因 | 同步 `inputs.md` 的例外清单 |

## 相关文档

- 输入、通道与 unstable 例外：[inputs.md](inputs.md)
- 编辑器工具与闭包边界：`dev-toolchain` 技能及其 references
- 秘密增删与传递：`sops-secrets` 技能
- 桌面/会话运行时行为：`desktop-mango`、`shell-terminal` 技能

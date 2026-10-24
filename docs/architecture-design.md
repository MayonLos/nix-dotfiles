# 仓库架构规范 v2.1

状态：规范性文档，2026-10-24 起生效，取代旧版设计说明（旧文全文见 [architecture-design-v1](history/architecture-design-v1.md)）。
本版由主代理起草，经 Codex（GPT）、Claude Fable、Claude Sonnet 三方独立审阅后修订；依据为锁定 Den v0.19.0
（rev 37eb88c）源码、仓库现状与实测（求值剖析、移动文件的 drv 对照实验）。

规则分两级：**[硬]** 必须遵守，能自动检查的由 `checks.architecture` 在**求值期**强制，不能自动检查的由审阅与语义测试强制；
**[建议]** 审阅提示，不阻断。“没有自动检查”不降低硬规则的效力。

---

## 1. 原则

1. **功能内聚**：一个功能的系统侧、用户侧、账号侧声明集中在一个目录；移除其选择与登记后，它不再贡献任何专属声明，
   共享支持在最后一个消费者退出后消失，用户数据保留。
2. **事实与实现分离**：inventory 只描述有什么、谁选择什么；实现全部在功能里。
3. **只依赖公开接口**：功能之间只经 §4 列出的通道与 §5 的公开入口交换数据。
4. **保留 Den，保持身份稳定**：实体、aspect、includes、class 分发由 Den 负责。剖析显示求值 16s 中 Home Manager 占 63%、
   nixpkgs-unstable 19%、noctalia-greeter 自带 nixpkgs 12%，Den 本身可忽略；性能工作不针对组合机制。
5. **规则可执行**：能静态判断的规则自动检查；其余写成语义测试。

## 2. 顶层布局

```text
flake.nix                 # inputs 与 mkFlake ./nix；follows 策略注释在此
nix/                      # flake 管线，无业务配置
  default.nix             # 导入下列文件
  pkgs.nix                # 每个 system 一组 stable 与 unstable 实例；overlay（见 §8）
  hosts.nix               # den.schema.host 默认：instantiate、Home Manager 全局接线（见 §6）
  den.nix                 # Den 导入、schema 类注册、quirk 注册
  outputs.nix             # flake packages（如 neovim）、apps
  checks.nix              # 显式登记表收集各功能 checks + tests + architecture
  dev.nix                 # devShells、treefmt
aspects/<领域>/<功能>/    # 功能（§3）
bundles/                  # 只含 includes 的用途组合（§7）
inventory/                # 实体、事实、绑定（§6）
lib/                      # 跨功能 helper（§8.4）
tests/                    # 跨功能组合与负例（§10）
secrets/                  # sops 加密文件
docs/                     # 现行文档；history/ 只追加
```

## 3. 功能

### 3.1 领域（仅用于导航）

领域目录是**导航分类，不是依赖层级**；aspect ID 与目录路径解耦，迁移目录不改 aspect ID。

| 领域 | 内容 |
|---|---|
| `system/` | nix 设置与维护、locale、sudo/安全策略、账号公共策略 |
| `hardware/` | 机型驱动与策略（legion-laptop：NVIDIA PRIME、电源、启动、gamemode GPU、mpv 硬解等，由 facts 参数化） |
| `appearance/` | 外观契约、主题数据（onedark-darker、ansi、壁纸、头像生成） |
| `desktop/` | `session-support`（输入法、GTK/Qt、字体、portal、音频 socket、session targets）、`mango-session`（Mango+Noctalia+剪贴板+截图）、`xorg-session`、`greeter` |
| `cli/` | shell、terminal、git、tmux、yazi、系统信息、CLI 工具 |
| `dev/` | 编辑器（neovim、vscode、jetbrains）、languages（契约+各语言）、embedded、containers、virtual-machines、ai-agents |
| `apps/` | firefox、communication、documents、media、file-manager、gaming |
| `network/` | 网络管理、代理、远程访问/SSH 策略 |
| `workspace/` | workspace-task、project-workbench（CLI 与桌面共用） |

桌面不再细拆成每个维度一个功能：拆分会制造只有一个消费者的伪契约。只有出现真实复用或替换需求时才拆。

### 3.2 功能目录文件角色

```text
default.nix     # [硬] 唯一 flake-parts 入口：注册 den.aspects（一个入口可注册多个紧密相关 aspect）；允许短实现
nixos.nix       # [建议] 主机侧 class 内容（经具名 -host aspect 投递，见 §4.3）
home.nix        # [建议] homeManager class 内容
user.nix        # [建议] user class（账号属性/授权，见 §4.5）
contract.nix    # 公开接口（三种形态见 §5.2）
package.nix     # 私有配方或声明过的公开包工厂
resources/      # 静态资源、脚本、模板
checks.nix      # 本功能检查，签名见 §10.1
README.md       # [硬] 有契约、有主机侧内容、拥有用户状态或配置文件的功能必需；其余用 aspect 的 description
```

允许 `home/`、`host/` 子目录。单文件超过 400 行为 **[建议]** 拆分（存量白名单；`package.nix` 与生成数据豁免）。

### 3.3 class 文件写法 [硬]

Den 只对**函数值**注入上下文，路径字面量原样交给模块系统（`nix/lib/aspects/fx/class-module.nix`）。因此：

- 需要 `host`/`user` 的 class 文件写成偏应用：`homeManager = import ./home.nix { inherit host user; };`
  或直接以函数值赋给 class；**禁止** `homeManager.imports = [ ./home.nix ]` 依赖 `host`/`user` 参数。
- aspect 函数与 class 函数的**参数形状是语义**（Den 按参数分派与生成实例身份）。增删 `{ host, user, … }` 参数视为行为改动。

## 4. 跨功能通道

### 4.1 允许的五种通道 [硬]

| 通道 | 用途 | 例 |
|---|---|---|
| `includes` | **选择与组合** aspect；不承载数据 | bundles、绑定 |
| 实体 schema 属性 | 实体输入（由 `den.schema.{host,user}.imports` 的契约定义） | `host.appearance`、`user.defaultTools`、`user.workspaceProjects`、`host.facts` |
| quirks（必要时 pipes） | 已选功能向消费者**贡献数据** | `editorLanguages`、`noctaliaIntegrations` |
| 公开模块选项 | 同一模块系统内的合并接线 | `nixDotfiles.graphicalSessionTargets` |
| 公开包工厂 | 带参数的包 | dwm 配方（palette、DPI） |

其他方式（读取其他功能私有文件、通过全局变量、跨功能 `imports` 私有模块）一律禁止。

### 4.2 quirk 规则 [硬]

- 每个 quirk 只有一个声明者（在其契约所属功能的 `default.nix` 注册），名称不得与 class 同名（Den `modules/options.nix` 会 throw）。
- Den 不校验 quirk payload 类型：**消费者必须经契约的 collector/validator（`lib.evalModules` 或断言）校验**后使用。
- user 作用域的 quirk 不会自动进入 host；需要跨作用域时显式使用 pipe，并在契约中写明方向。
- 未选择的功能不贡献数据；收到数据不隐式安装或启用任何功能。

### 4.3 主机侧投递 [硬]

- 被用户绑定选择的功能，其主机侧内容只能放进具名 `<功能>-host` aspect，经 `provides.${host.name}.includes` 投递。
- **禁止**在用户作用域写裸 `nixos`（Den #694 隔离缺陷，`where-config-lands` 文档）。
- `-host` aspect 只消费主机级输入（facts、host 实体属性），不得捕获某个用户的偏好；多个绑定引用同一 `-host` aspect 时由 Den 按 scope+identity 去重。
- 禁止 `den.aspects.<host>.<user>` 子 aspect（会落到每个用户）；定向投递用 `provides`。

### 4.4 默认值与合并 [硬]

- 优先级三层：功能默认 `mkDefault` → 绑定/实例普通赋值 → 有理由的例外 `mkForce`（每处注释 `# force: <原因>`）。
- 相同优先级的单值冲突必须报错；argv 等有序值整体替换、不拼接；有序列表的顺序是语义；按 ID 合并的贡献同 ID 不兼容即报错。
- 默认值只影响已选择的功能。
- `den.default` 只放所有实体都必须有的管线，**不得**承载业务配置。

### 4.5 授权分界 [硬]

- 功能运行所需的组（dialout、input、gamemode、libvirtd、kvm 等）放该功能的 `user` class。
- 管理特权（wheel、`nix.settings.trusted-users`、sops owner）放绑定。
- 主机共享能力（portal、PAM、udev、uaccess）不是按用户访问控制；USB uaccess 仍按活动 seat。

## 5. 公开入口与契约

### 5.1 公开入口 [硬]

其他功能、bundles、inventory、tests、`nix/` 只能引用：功能的 `default.nix`、`contract.nix`、在 README 中声明为公开的包工厂/数据导出（例如外观数据、neovim 包工厂、checks 测试钩子）。其余文件私有。

### 5.2 契约的三种形态

1. **实体 schema 模块**：`den.schema.{host,user}.imports` 引入，定义类型化实体属性（appearance、default-tools、workspaceProjects、facts）。
2. **collector/validator 函数库**：`{ lib }: { collect = …; }`，对 quirk 贡献做类型校验与合并（languages）。
3. **quirk 声明**：在契约所属功能注册，附带对应 validator。

### 5.3 当前契约表

| 契约 | 归属 | 形态 | 提供者 → 消费者 |
|---|---|---|---|
| appearance | `appearance/appearance` | schema（host、user） | 绑定选择 onedark-darker → 所有外观适配 |
| default-tools | `system/default-tools` | schema（user） | 绑定 → 快捷键、MIME、启动器 |
| workspace-projects | `workspace/project-workbench` | schema（user） | 绑定 → 项目工作台 |
| facts | `hardware/` 下契约 | schema（host） | inventory facts → hardware、desktop、greeter |
| languages | `dev/languages` | quirk `editorLanguages` + collector | 各语言 → neovim（已实现）；vscode（计划） |
| desktop-integrations | `desktop/mango-session` | quirk `noctaliaIntegrations` + validator | 选用的应用 → Noctalia 模板 |
| session-targets | `desktop/session-support` | 公开模块选项 `nixDotfiles.graphicalSessionTargets` | 会话 → 输入法、Xresources、音频 socket 等 |

## 6. inventory [硬]

```text
inventory/
  users/<user>.nix              # 跨主机身份：姓名、邮箱、git 身份等纯数据；实体 aspect `<user>`
  hosts/<host>/
    default.nix                 # den.hosts 声明；主机实体 aspect `<host>`：选择 system/hardware/network 功能、hostName、stateVersion
    facts.nix                   # 硬件事实（纯数据）
    hardware-configuration.nix  # 扫描工件（唯一允许的原生模块）
    secrets.nix                 # sops 声明：秘密名、路径、owner、mode、template（无秘密内容）
    users/<user>.nix            # 绑定 `<user>@<host>`：选择 bundles/功能、默认工具、外观、workspaceProjects、管理特权、flakePath 等数据
```

- inventory 中**不得出现** `pkgs`、`runCommand`、`writeText`、`writeShellScript*`、`toFile`、activation、脚本、`imports` 实现模块（hardware-configuration 与 sops 模块导入除外）。
- 实体 aspect 名（主机名、用户名、`user@host`）是**保留名**，只在 inventory 定义；功能、bundle 不得同名。
- `instantiate`、Home Manager 全局设置（`useGlobalPkgs`、`useUserPackages`、`backupFileExtension`、`extraSpecialArgs`）属于管线：在 `nix/hosts.nix` 经 `den.schema.host` 以 `mkDefault` 提供，按当前主机的 system/facts 参数化，不闭包捕获某台机器的 facts。
- 绝对路径（flake 目录等）只作为绑定数据字段声明一次，消费者读字段。

## 7. bundles [硬]

`bundles/default.nix` 只含 `den.aspects.<bundle>.includes = [ … ]`；bundle 名不得与功能或实体同名；不得循环。

## 8. 包与输入

### 8.1 nixpkgs 实例 [硬]

- 每个 system 只在 `nix/pkgs.nix` 实例化一组 stable 与一组 unstable（参数：`inherit system; config.allowUnfree = true;`）。
  除此之外**禁止** `import inputs.nixpkgs*`；新增实例或新增自带 nixpkgs 的输入必须记录求值代价。
- 实例经 `nixosSystem { inherit pkgs; }` 传入；**禁止**在任何模块使用 `nixpkgs.overlays`/`nixpkgs.config`（HM `useGlobalPkgs` 下亦禁用）。

### 8.2 overlay [硬]

- `pkgs.unstable`：一个**白名单 attrset**，每项来自同一 unstable 实例并写明理由，例如
  `unstable = { qq = u.qq; /* 理由 */ jdk26 = u.javaPackages.compiler.temurin-bin.jdk-26; … };`。
  功能只能访问 `pkgs.unstable.<白名单名>`；检查比对用法与白名单。
- 包替换 overlay（如 `xdg-desktop-portal-wlr` 取 unstable）保留原位置与顺序，并注释理由。
- `pkgs.local.<名>`：第三方 flake 包只做**别名** `inputs.<x>.packages.${system}.<y>`，不得用上游 overlay 或以本仓库 nixpkgs 重新 callPackage（会改 drv 并丢缓存）。HM/NixOS 模块形式的输入（如 mango 的 HM 模块）照常导入。

### 8.3 配方位置

- 私有配方留在功能目录；带参数的配方以**包工厂**公开（不要固定成全局单例）。
- 只有被 ≥2 个功能使用的无参配方才放 `packages/`（目前可为空，不预建）。
- flake 对外导出（如 `.#neovim`）由 `nix/outputs.nix` 调用功能的公开包工厂并显式传入默认数据。

### 8.4 lib [硬]

- `lib/` 放被 **≥2 个功能目录**使用的 helper（可接收 `pkgs`，须确定性、无隐藏状态）。
- 零消费者即失败；单消费者为审阅提示（应迁回消费者附近）。

### 8.5 输入管理 [硬]

- `flake.nix` 中每个输入注明 follows 策略与理由；`mango`、`noctalia-greeter`、`mark-shot`、`wayscrollshot`、`llm-agents` **不加 follows**（源码依赖组合或预构建缓存依赖其 pin）。
- 架构重构期间冻结 `flake.lock`、`stateVersion`、包版本与依赖组合。
- 更新输入后必须：构建 toplevel、`nix store diff-closures` 摘要、对照 workaround 原因复核。

## 9. 秘密、状态与服务 [硬]

- **秘密**：声明在 `inventory/hosts/<h>/secrets.nix`；消费者只用 `config.sops.secrets.<n>.path` 或 `config.sops.templates.<n>.path` / placeholder；
  禁止求值期读取明文、写入 Nix 字符串/store/日志，禁止硬编码 `/run/secrets/...`。
- **用户状态**：功能停用或迁移不清理历史、认证、模型、项目、容器卷、VM 镜像；seed/迁移必须幂等，明确对软链与用户自定义值的处理。
- **写入归属**：每个声明式输出或可变字段有唯一权威写入者；seed、迁移、运行时交接（如 Noctalia sidecar、Qt seed/GUI、mark-shot 字段补丁）在 `docs/config-ownership.md` 单列。
- **服务**：system/user/session 生命周期、`WantedBy`/`PartOf`/`After`、socket/D-Bus 激活按 `docs/service-policy.md`；客户端与 daemon 分开选择。

## 10. 测试与检查

### 10.1 功能检查签名

`checks.nix` 为 `{ pkgs, lib, system, nixos, home, appearance }: { <名> = drv; }`（按需取用；`nixos` 为真实主机 config，`home` 为该用户 HM config）。
`nix/checks.nix` 用**显式登记表**收集，复用 `config.flake.nixosConfigurations` 的结果，不重复实例化真实主机。

### 10.2 语义测试 [硬，tests/]

保留并维持通过：两主机两账号路由隔离；双用户共享主机支持去重而授权分离；冲突负例（单值、同 ID）；无桌面组合不激活图形会话；
外观数据被 ≥2 个消费者正确渲染且单写入者；语言贡献只被选中的编辑器消费；移除功能后无残留声明且用户状态保留；客户端不启动 daemon。
tests 只能经 §5.1 公开入口组合功能。

### 10.3 `checks.architecture` [硬]

**求值期执行**（`builtins.readDir` + `readFile` + 检查，失败即 `throw`），保证 `nix flake check --no-build` 也会触发；扫描范围为 Git 跟踪源码，排除 `.work/`、`result*`。

1. 跨功能引用非公开入口（静态解析路径字面量与 `${…}` 插值；例外显式登记）。
2. inventory 违禁项（§6）。
3. `pkgs.unstable` 访问名不在白名单；`pkgs-unstable` 旧参数残留；`mkForce`/`mkOverride` 缺 `# force:` 注释。
4. 功能目录与 `aspects/` 登记表、Den aspect 名不一致；实体保留名被功能占用。
5. 应有 README 的功能缺 README。
6. `lib/` 文件零消费者。

扫描器自带**会失败的 fixture**，证明每条规则确实能报错。

### 10.4 质量门 [硬]

treefmt（nixfmt、stylua）；**deadnix 必须带 `--no-lambda-pattern-names`**（Den 按参数形状分派，自动删除未用 lambda 参数会静默改变语义）；
statix 只检查不自动修复 aspect 文件。

### 10.5 性能预算 [建议]

toplevel 求值 ≤ 20s（`NIX_SHOW_STATS=1`，记录 Nix 版本、lock、缓存状态、3 次样本）；新增 nixpkgs 实例或重型输入需附剖析。

## 11. 重构规程（纯重构必须遵守）[硬]

1. 在**冻结的干净提交**上取基线：toplevel outPath、`.#packages.*`、`.#devShells.*`、`.#formatter.*` 的 drvPath、checks 名单。
2. 每一批只做一类变动（目录移动 / 文件拆分 / overlay / aspect 改名 / 文档），批后立即比对；
   **toplevel outPath 必须严格相等**——不相等就修正直到相等，差异分析只用于定位，不作为接受理由。功能变化另立轮次。
3. 已验证安全：注释改动、移动 Nix 模块文件（含声明选项的模块）不改变 toplevel drv（2026-10-24 对照实验）。
4. 已知危险：资源文件/目录**改名**（basename 进入 store 名）、往被整体插值的目录加文件、改变 `includes`/`imports`/列表顺序、
   改变 `writeText`/activation/unit/脚本名称或文本缩进、增删 class/aspect 函数参数、把第三方包改为重新构建。
5. 新文件需主代理 stage 后再用 Git flake 求值；`path:.` 只用于临时诊断并检查源范围。

## 12. 文档

- 现行文档保持原文件名以免 history 断链：`architecture-design.md`（本规范）、`config-ownership.md`、`service-policy.md`、`desktop-design.md`、`workflow-design.md`、`operations.md`（新增：重建、清理、回滚、验证层级）。
- 功能细节写在功能 README；`docs/history/` 只追加。当前文档与源码矛盾时以源码为准并修正文档。

## 13. 验证层级

求值 < 构建 < 应用 < 实机验证；报告必须写明达到哪一层，不把前者写成后者。

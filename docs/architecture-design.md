# Den 架构设计：实体、选择与完整功能

状态：Den v0.19.0 已锁入根 flake，真实 `nixos-btw`/`mayon` 已完成逐功能迁移。本文规定架构边界；当前接线见 `nix/`、`aspects/default.nix`、`bundles/default.nix` 和 inventory。各批实现与重新执行的检查见 [实施记录](history/den-execution.md)。Den 初轮没有应用；其后应用与运行证据按 [交接记录](history/execution-handoff.md) 链接的各轮状态，不能把初轮限制当作当前运行状态。
最近的目录/依赖整理见 [整理记录](history/repository-organization.md)。

## 设计结论

实体说明存在什么，绑定说明谁在什么机器上需要什么，完整功能负责实现这个结果。用途组合只是普通 aspect 的 `includes`。

| 职责 | 所有者与内容 |
|---|---|
| 主机事实 | 目标平台、设备地址、磁盘/显示器标识等真实实例信息 |
| 个人身份 | 只保存跨机器语义相同的身份与偏好；没有复用价值时无需单独拆文件 |
| 主机—账号绑定 | 账号是否存在、home/UID、HM stateVersion、授权、用途与默认应用选择 |
| 主机策略选择 | 内核/驱动/电源策略、启动方案、实际系统服务；与硬件事实分开 |
| 用途组合 | 日常工作、工程开发、远程工作等经常一起选择的功能；不复制实现 |
| 完整功能 | 自己的系统/用户/账号配置、依赖、资源、包配方、必要适配与功能测试 |

PCI 地址是事实，选择省电策略是意图，驱动与 PRIME 配置是实现。生成的硬件扫描模块可作为实例工件显式引用，不把每个 NixOS 原生选项再包装成自制 facts 字段。

这是 Den 实体、aspect 与关系机制上的仓库设计，不新增角色解释器或实体类型。参考：[核心原则](https://den.denful.dev/explanation/core-principles/)、[实体与 schema](https://den.denful.dev/reference/schema/)。

## 一次选择完整功能

公共调用界面不再要求用户配对选择 workstation 的系统半边和 desktop 的用户半边，也不要求分别选择嵌入式工具、设备规则和串口权限。

```text
某账号在某主机上选择一个完整功能
  ├── 用户配置        → 该账号的 Home Manager
  ├── 账号属性/授权   → 该主机上的该账号
  └── 主机共享支持    → 该主机，按真实资源合并
```

例如 `embedded-workbench` 拥有工具、探针规则、当前账号权限的完整配套；`interactive-session` 组合 Mango/Noctalia 与 `graphical-session-support`，`xorg-session` 组合同一公共支持与 dwm/Xorg。公共支持只包含实际共用的输入、GTK/Qt、音频、字体和基础 portal；Xorg 不再隐式选择 Mango。另一个账号不会仅因存在于该主机上就得到相同的个人环境。

“一次选择”不等于多个 class 会自动投递到正确位置。功能内部必须使用所锁版本的 `user` class、Home Manager 和定向宿主提供机制。用户作用域的裸 `nixos` 不能作为路由保证。原生机制与落点依据：[机制选择](https://den.denful.dev/explanation/choosing-a-mechanism/)、[配置落点](https://den.denful.dev/explanation/where-config-lands/)。

不同用户可有不同默认终端、编辑器或会话；多个桌面会话也可以共存。只对真实互斥资源检查冲突，例如同一监听端口或同一目标文件，不把所有实现都当成 host 单例。远程客户端与本地 daemon 有独立用途时，分别成为可选择功能。

## 组合与实现

功能意图和具体选型要分清，但不为每个应用强制建立 interface/backend 两层。固定选择直接由功能实现；出现真实替换需求和稳定消费者后再提取共同接口。

- `personal-desktop` 组合交互会话、命令行、日用功能与默认工具。
- `engineering-workbench` 组合编辑、语言支持和已经确认需要的专业工具。
- `remote-workspace` 组合命令行、编辑和实际需要的语言；这是组合示意，不是提前部署的服务器。
- 桌面内部，会话实现与桌面 shell 是不同选择维度；更换其中一项时，其余消费者不应引用旧应用私有配置。
- 安装多个编辑器是有效选择；默认编辑器是另一项单值选择。

这些名称描述用途，均是普通 Den aspect。具体软件已按既定保留决定逐项接入，组合变化不自动成为删软件的理由。

## 当前结构

```text
.
├── flake.nix / flake.lock             # 锁定输入与薄 flake-parts 入口
├── nix/                              # Den、包集合、devShell、Neovim 输出和 checks
├── inventory/
│   ├── users/mayon.nix                # 跨主机身份
│   └── hosts/nixos-btw/               # 唯一部署实例
│       ├── default.nix                # 实体、选择和实际主机策略
│       ├── facts.nix                  # 平台/PCI/显示器/键盘公开事实
│       ├── accounts.nix               # 本机账号与运行时凭据读取授权
│       ├── credentials.nix            # sops runtime owner/mode/template
│       └── discovered.nix             # 未改磁盘/交换的扫描工件
├── aspects/
│   ├── default.nix                    # 显式 registry；登记不代表启用
│   ├── system/                        # 维护、实际笔记本设备策略与本地网络策略
│   ├── command-line/                  # 完整 CLI 与独立 terminal
│   ├── workspace-task/                # CLI 与桌面共用的显式长任务命令
│   ├── editing/neovim/                # 丰富 Lua、包/插件/parser 与专项测试
│   ├── languages/                     # 工具与有序编辑器贡献
│   ├── appearance/ / default-tools/   # 公开数据协议
│   ├── interactive-session/           # Mango/Noctalia 与实际共用的会话支持
│   │   └── xorg/                     # dwm/Xorg 模块、配方、脚本和 tests
│   ├── embedded-workbench/            # 工具、共享规则及 binding 授权
│   ├── local-containers/ / local-virtual-machines/
│   └── firefox/ / communication/ / documents/ / media/ / file-manager/ / ai-workbench/ / gaming/ / remote-access/
├── bundles/default.nix                # personal-desktop / engineering-workbench / remote-workspace
├── lib/                              # 有实际共享价值的小函数
├── tests/composition/                 # 生产模块组合、不导出部署 fixture
├── secrets/                          # 仅加密输入
└── docs/
```

旧递归模块树、兼容包入口及测试子 flake 已退出；所有检查使用根输入锁。专项检查靠近功能，跨功能隔离、冲突和授权检查放 `tests/composition/`。构建不执行 activation，设备与桌面行为另做运行验收。

资源、配置脚本、包配方与专项测试优先靠近其功能。没有跨功能复用价值时，不为了沿用旧布局强制拆到顶层 `config/`、`pkgs/` 或公共 helpers。

采用显式入口登记：只加载功能的公开入口，功能内部再引用私有文件。不会对整棵新树递归导入每个 `.nix`，从而允许 `package.nix`、原始 class 模块和 helper 靠近消费者。登记定义与启用功能仍是两个步骤；一个入口文件可以注册多个紧密相关的 aspect，无需每个函数再建文件。

本次不为 policies、schema 生成器、provider registry 或每种实现预建目录。只有实际出现重复的关系规则才提取 policy；只有真实共享才提升协议或纯函数。Den 自己负责实体、aspect 组合与 class 分发。

## 少量公开数据协议

先确定数据含义、所有者和合并规则，再选择 Den 传输机制。schema 适合类型化实体输入；quirks 适合所选功能贡献数据；确实跨作用域时才使用 pipes。Aspect Settings 是官方提供的用户实现 pattern，并非开箱即用的内建功能，本方案不先复制它的全树生成器。参考：[schema](https://den.denful.dev/reference/schema/)、[Aspect Settings](https://den.denful.dev/guides/aspect-settings/)。

| 协议 | 所有者与消费者 | 基本规则 |
|---|---|---|
| 外观 | 一个有效外观选择；各应用适配消费相同语义色、字体等真实共享字段 | 同一用户/绑定明确选择；宿主 greeter 有自己的选择；不跨账号隐式继承 |
| 默认工具 | 绑定选择默认 terminal/editor/browser/fileManager；启动入口、快捷键、MIME 消费 | 安装与设默认分开；参数用结构化 argv；仅建立实际消费者需要的字段 |
| Noctalia 模板请求 | 所选应用贡献 `noctaliaIntegrations` 标记；会话中的唯一 Noctalia renderer 消费 | 只启用实际选中应用的模板；不隐式安装应用，不写 Kitty/Mango |
| 语言支持 | 所选语言贡献稳定 ID、包和命令描述；所选编辑器消费 | 编辑器只解释自己支持的贡献；专属设置/扩展保留明确命名，不伪造通用编辑器配置语言 |

One Dark Darker、具体终端和编辑器属于这些接口的实际选择，不决定架构层次。语言到编辑器的数据贡献可借鉴官方 [Quirk Recipes](https://den.denful.dev/guides/quirk-recipes/)；本仓库的字段、类型和冲突检查仍需自行明确。

公开 `contract.nix` 是该功能允许其他功能引用的稳定边界，私有实现不作为外部 API。共享数据不收集 token、解密内容或隐式授权。

### 合并、覆盖与写入者

- 每个字段明确作用域和类型；可共享的事实与可调的默认值分开声明。
- 默认值只影响已经选择的功能。未选功能不贡献有效数据；收到数据也不自动启用功能或安装软件。
- 单值在相同优先级下不接受不同结果；包集合可明确去重，argv 与 formatter 顺序不能作为普通集合拼接。
- 带 ID 的贡献可以按不同 ID 合并；同一 ID 的不兼容定义必须报错或显式覆盖。quirk 登记本身不等于完成类型检查，消费者需验证。
- 实例覆盖走公开输入；`mkForce` 只用于有依据、有范围的例外，不是处理接口冲突的常规手段。实际 Nix option/quirk 合并行为要用测试验证。
- 一个最终文件/配置树有一个写入者；多个模块可向 Nix 选项贡献数据，最终仍由一个 renderer/HM 模块序列化。
- 声明式主题文件、应用运行时偏好、历史/缓存/模型等数据分别明确所有者。例如 Nix 写 Kitty 主题时，桌面模板不能同时改写同一路径。

同作用域 quirks 收集与跨作用域传播是不同问题；跨主机、跨账号传播必须有明确边界。依据：[Quirks & Pipes](https://den.denful.dev/explanation/quirks-and-pipes/)。

## 功能的公共边界

一个完整功能应能回答：从哪里选择、需要什么输入、向哪些 class/实体输出、拥有哪些文件、贡献哪些数据，以及移除后还留下什么用户状态。

功能自身负责正确路由；库存中的绑定负责谁获得该功能。系统共享资源按 host 合并，账号授权按 binding 生成。不会为了去重系统支持而扩大到所有账号，也不会让一个账号的默认应用变成整台机器的强制单例。

具体实现未支持某个平台时给出明确约束；不同 CPU 平台复用配置与配方，不意味着共享同一二进制。项目 flake 继续拥有项目依赖，仓库开发组合不悄悄接管项目版本。

## 两种组合示意

```text
个人笔记本
  事实：真实平台、磁盘、GPU 地址、显示器
  主机选择：系统维护、启动/图形/电源策略
  mayon 绑定：
    personal-desktop + engineering-workbench
    + 本地容器/虚拟机 + 嵌入式工作台 + 游戏
    + 该机明确授权与默认工具

未来无头机器（概念样本）
  事实：它自己的平台、存储、网络
  主机选择：系统维护、实际服务、明确远程访问策略
  人类账号绑定：
    remote-workspace + 实际需要的语言支持
    + 该机明确授权
```

不按 machine 标签暗中安装整套软件，不创建虚构的可部署服务器。既定保留软件以后逐一适配；当前命名与目录不是未来抽象的约束。

## 架构成立的验收条件

先做纵向最小样本，再迁移现有配置。入口和协议需要能证明以下行为：

1. 两主机、两账号样本中，一个绑定选择功能后，只有目标账号和其宿主得到对应配置。
2. 两个账号选择同一系统支持时，不重复创建资源；权限仍只授予所选账号。
3. 真正互斥的资源或单值选择冲突明确失败；正常可共存的会话和应用不误判冲突。
4. 无桌面组合的实例不激活图形会话；默认工具的缺省值不反向启动桌面。
5. 同一外观输入能被至少两个已选消费者正确渲染，目标文件只有一个写入者。
6. 一项语言贡献能被所选编辑器消费；未选择的语言/编辑器不因协议存在而启用。
7. 移除功能会移除它拥有的声明与输出，保留不应由配置删除的用户状态。

实施顺序：锁定 Den 并保存基线 → 先以完整 shell 功能证明账号/宿主/HM 路由 → 再以嵌入式功能证明系统资源和权限 → 建立小型外观/默认工具/语言接口样本 → 逐项适配当前功能 → 清理旧入口。首批只验证一至两条纵向路径，不先生成大批空目录。

每个可审查的设计决策、纵向验证闭环或功能迁移及时提交。允许推翻已有抽象与实现；发现边界不成立时直接修正，不为保持旧目录或减少 diff 保留错误设计。提交前完成该阶段必要核验，保留清晰的回退点。

## 实现证据与限制

架构与桌面规格来自先前主代理和实际 Astra 设计；本轮实现没有重新设计视觉。Den 的共享 host 支持使用具名 aspect，账号授权仍在 binding，避免多个账号重复输出同一文本。根组合检查覆盖命令行、丰富编辑器/语言、桌面、容器/VM、嵌入式及无头工作台；负例检查有序数据冲突与系统边界。实际包和程序检查见 [tests/README](../tests/README.md) 与 [实施记录](history/den-execution.md)。

同宿主的 portal、PAM/keyring、polkit、udev 等是共享系统能力，不是账号级访问控制。串口组、input/libvirtd/kvm/gamemode 授权按绑定；USB uaccess 仍按活动 seat。PipeWire 自动 socket wants 与本地 Docker daemon 自动启动均不再套到所有用户。

当前只有真实笔记本部署输出。ARM 无头 fixture 验证到求值，未做 ARM closure 构建、跨架构运行或服务器部署。本次目录与依赖整理没有切换系统、执行真实数据迁移、停止旧服务或清理用户状态。历轮 GUI/设备运行证据见对应执行记录；新整理的构建证据不替代实机行为。

# 桌面与窗口优化实施记录

执行日期：2026-10-18。用户授权参考 Mango、niri、Hyprland 社区方案，由实际 Astra
负责视觉和窗口设计并实施，主代理集成，Luna 核对窄范围事实，独立 reviewer 复核。
本轮 goal 到实现、文档和构建为止；视觉手感由用户应用后验收。

## 起点与边界

起始 HEAD 为 `0dfd637`，工作树和索引干净。该提交是完整 Den 重构的可回退基线，
其历史验证见 [Den 实施记录](den-execution.md)，不能代替本轮重新验证。

保留 Mango + Noctalia、固定 One Dark Darker、Kitty/tmux、丰富原生 Lua Neovim 和
已确认的软件选择。社区方案用于窗口组织、浮层层级与动效设计，不运行第三方安装脚本。
不升级输入，不新增虚构输出或服务器，不改变驱动/电源 workaround 来追求未经测量的收益。

不执行 switch/test、注销、服务重启、进程终止、清理或数据迁移。另有 mod 任务运行，
构建串行并限制并行度，不使用 GPU 采样。凭据、项目、历史、模型、容器卷和 VM 镜像保留。

## 已实现的声明

- 1 开发 tile、2 资料 scroller、4/6/8 标签式 monocle，其余普通工作区保留 tile；Tag 0
  采用 scroller 工具层。只设默认布局，不按应用强制搬窗口，原有按键和手势保留。
- `Super+Alt+E` 呼出 Yazi，`Super+Alt+M` 呼出 btop，`Super+Shift+Enter` 保留临时终端。
  三个 named scratchpad 使用独立 app-id、明确尺寸及 store 命令，F1 显示友好名称。
  `Super+Ctrl+S` 静默停放 Tag 0；`Super+Ctrl+G` / `Super+Alt+G` 分别切换 global / overlay。
- 已知设置窗、portal、图片与重命名窗使用精确身份规则；Firefox 英文 PiP 为 480×270、
  靠右下、跨 tag、安静打开，不默认 overlay。保留应用 size hints、父窗与模态处理。
- 主窗轻 zoom、工具 fade、Steam 游戏窗无动画；概览扩大间距。Noctalia 已知 layer
  禁止重复的合成器动画/阴影，截图选区额外禁 blur；不假设支持 fork 专属特效。
- 固定 One Dark Darker；桌面默认和 greeter 共用原有森林壁纸 009，所有素材保留。
  锁屏采用明确 fade/550 ms，时钟位置由逻辑显示尺寸计算。Swayimg 字体和状态色统一。
- 新增声明式 `appearance.reducedMotion`，默认 false；true 时关闭 Mango 动画、Noctalia
  shell/壁纸/锁屏转场、天气效果和媒体滚字，移除面板猫/频谱，Kitty 停止光标闪烁。
  不删除插件 state，不增加运行中的切换 daemon，不承诺关闭其他应用内部动画。

## 注释、复核与验证

Luna 定点审查后修正 Blender/boot 的旧 NVIDIA 路径、嵌入式工具归属、MATLAB LSP 来源，
并给迁移过渡记录补上阶段限定。Astra 修正 Mango layer 支持、Kitty 不透明度、greeter
缩放、F1、旧 mutable theme 等现状描述。日期限定的历史证据和已说明原因的 workaround 保留；
未跟踪的本地任务资料不参与清理。主代理按锁定 GDB 配方进一步修正“host GDB 不能调
Cortex-M”的旧判断：默认 `hostCpuOnly=false`，启用全部 target；交叉 GDB 工作流仍保留。

独立 reviewer 核实锁定源码及真实 diff，发现 named 临时终端不会自动采用全局 scratchpad
比例，已补明确宽高。另核实窗口比例基于完整输出 `mon->m`、offset 为剩余空间百分比、
Tag 0 slot、PiP 焦点与层级、减少动画后的 widget 生命周期，以及空转场池的实际含义。
保留插件配置不会自行实例化已从面板移除的猫/频谱；不扩大用户 state 接管范围。

主代理修复 store 命令字符串在帮助文本中的 Nix context 属性查找错误：仅展示文本丢弃
context，真实绑定保留 executable 闭包。独立追加复核确认两项集成修正无新增缺陷。

已重新执行并通过：

```sh
nix flake check --no-build --no-write-lock-file --max-jobs 1 --cores 2
nix flake check --no-write-lock-file --max-jobs 1 --cores 2
nix build --no-link --no-write-lock-file --max-jobs 1 --cores 2 \
  .#nixosConfigurations.nixos-btw.config.system.build.toplevel
```

全部 15 项根 checks 通过，包括 treefmt、Mango/Noctalia 默认配置、Kitty/Zsh/tmux、丰富
Neovim、协议/语言/桌面/服务/嵌入式及无头边界。新增同宿主两用户不同动效偏好隔离、
Kitty 光标偏好、非 bool 拒绝与默认值检查；减少动画分支另用锁定 Mango 和 Noctalia
真实 parser 验证，而非只比较生成字段。Noctalia 两分支均零 warning，Mango 无键冲突。
完整真实主机 toplevel 构建通过，未执行 activation。

主代理直接比对基线与新声明，default/common/hardware/resize 四组原有动作无缺项；
本地 Markdown 链接与 `git diff --check` 通过。根 `flake.lock` 相对基线完全不变。

本地回退点：`40492c4` 记录 clean 基线；`e005501` 修正迁移后注释；`da453a0` 包含
Astra 视觉/窗口实现、协议与组合验证。最后的记录提交补齐此页、入口链接及 GDB 注释，
没有推送。构建与检查日志位于本机 `/tmp/codex-desktop-polish-*.log`，不包含用户秘密。

## 应用后验收（本轮均未执行）

| 项目 | 现场检查 |
|---|---|
| 默认场景 | 009 壁纸实际裁切、玻璃亮部对比、greeter/锁屏字体和认证框位置；既有可变壁纸选择可能继续优先于默认值 |
| 窗口与工具 | 每 tag 布局、三个工具首次尺寸/反复呼出、用户手调尺寸、Tag 0 停放/取回、F1 和 resize 模式退出 |
| 对话框与 PiP | 实际 app-id/本地化标题、首次标题时机、父窗/模态、PiP 不抢焦点和全屏遮挡、手动 global/overlay |
| 多屏 | 真实外屏与混合 DPI、跨屏召回尺寸、拔插后浮层/认证框回到可见区域 |
| 动效与负载 | 连续工作区切换、截图选区、锁屏转场、减少动画偏好、mod/游戏同负载帧时间与资源对比 |
| 原有能力 | IME、剪贴板、portal/共享、设备、游戏/休眠及配置文件交接，继续按专项文档验收 |

没有实机测量，不声称更快、更省电或视觉验收通过。系统应用会涉及配置归属交接和会话边界，
本轮不为获得截图而中断任务；仍需后续明确的应用执行安排。

本轮设计依据与操作入口分别见 [桌面设计](../desktop-design.md) 和
[操作方式](../workflow-design.md)。文件接管、会话退出与应用边界仍遵循
[写入归属](../config-ownership.md) 和 [服务策略](../service-policy.md)。

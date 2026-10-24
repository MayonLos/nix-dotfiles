# 求值期架构检查

`default.nix` 是供 `nix/checks.nix` 导入的纯求值检查。调用方传入 `lib`、仓库源码根路径、unstable 白名单、显式公开文件路径和实体保留名；成功返回 `true`，失败抛出包含规则名、文件路径和诊断的错误。默认会先运行内置负例；`returnErrors = true` 与 `sources` 仅用于这些 fixture，便于确认每条检测都能拒绝违规输入。

检查覆盖 feature 之间及其他源码区域对 feature 私有文件的相对路径引用、inventory 实现内容、旧 `pkgs-unstable` 参数、`pkgs.unstable` 白名单（只接受显式点号属性访问）、带理由的 override、feature 目录登记和入口、重复 aspect ID、aspect ID 与实体重名、必需 README、零消费者的 `lib/` Nix 文件，以及现行文本文件中的旧 palette 色值。palette 检查读取 Nix/Markdown 和其他非二进制文本，跳过 `docs/history/` 与 `ONEDARK-LICENSE`；二进制按常见图片、音视频、字体、归档及编译产物扩展名排除。feature 目录从 `aspects/<domain>/<feature>/` 下的全部文件推导，因此没有 `default.nix` 的孤立目录也会报错。跨功能引用只放行目标 `default.nix`、`contract.nix` 和调用方登记的公开文件。inventory 的 `default.nix` 可以登记 inventory 文件；硬件扫描工件和 sops 声明也保留各自导入例外。

扫描器使用 `builtins.readDir` 和 `builtins.readFile`，忽略 `.git`、临时工作目录、`result*` 和自身目录；palette 检查也会扫描隐藏目录中的文本配置。常见二进制扩展名在读取前排除，Nix/Markdown 文件复用架构扫描已读内容，避免重复载入。Nix flake 以 Git 源码构造时，未跟踪文件通常不进入源码快照；实际扫描范围仍由调用方传入的 `root` 决定。它不调用 Git，也不尝试重建 Git 的 tracked 状态。`nix/checks.nix` 另接线 `palette-contrast` 构建检查，从当前 appearance palette 读取颜色，以 WCAG sRGB 相对亮度计算正文、次级文字、选中态、语法色、8%/12% diff 混色和 98% 白底覆盖组合；任何低于设计门槛的组合都会失败并输出逐项比值，报告文本保留在 check 的 `$out` 中。

这是保守的静态检查器，不是完整 Nix 语法树解析器：相对路径按字面路径解析，支持 `./`、`../` 和 `${...}` 中的路径及插值后的字面后缀；不会求值动态拼接路径。feature 注册通过解析 `aspects/default.nix` 中的相对路径完成。aspect ID 重复检查识别字面 `den.aspects.<name> =`、`den.aspects.<name>.<class> =` 声明；静态 attrset 中的保留名也会检查。动态生成的属性名应由调用方传入 `evaluatedAspectIds`，用于实体保留名比较。`lib/` 消费者按相对路径导入识别。内置 fixture 对每条规则检查拒绝行为，并验证合法 inventory 登记导入、白名单点号访问和相邻 `# force:` 注释不会误报。动态结构和例外路径仍需语义审阅补足。

`unstableInspectors` 显式登记管线内对白名单自身的 introspection；当前只有 `nix/checks.nix` 用 `attrNames pkgs.unstable` 获取真实白名单，功能仍必须逐项点号访问。

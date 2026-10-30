# Study / 学习

`study-mayon`（别名 `study`）是中国大学生使用的本地 Rust TUI + CLI。
独立 Cargo workspace 与 lockfile，复用只读的 `mayon-ui` 外观/终端守卫。
公开 Nix 工厂是 `default.nix { pkgs }`，由 `pkgs.studyMayon` 暴露，
安装归属为 `aspects/workspace/study`，桌面快捷键与窗口规则由桌面维护者接入。

## 学习

使用 [fsrs-rs 6.6.2](https://github.com/open-spaced-repetition/fsrs-rs)
（BSD-3-Clause，FSRS 6，21 个参数），不是近似实现。保存 stability、difficulty、
到期时间与逐次复习日志。`z/x/c/v` 为重来/困难/良好/简单；重来有 60 秒重学步骤，
其余用 FSRS 秒级间隔。优先处理到期复习，再加入新词；上限按本地自然日的评分次数计算，
重学也消耗复习上限。`study optimize` 用历史训练参数，至少需要 400 条含历史的样本；
优化可能占 CPU，用户显式运行，缺样本保留默认参数。JSON 可修改 retention 与参数。

模式：认识与否、看中文释义拼写、听音拼写、选择题。翻面后显示中文/英文释义、
遮词例句与词根/词形信息；导入例句、词根可以补充数据。错词本为曾评分「重来」的词，
仍遵守到期与每日上限；词书页 w 可以浏览全部历史错词。统计包含每日量、回想成功率、模型估计当前留存、连续天数、
早/午/晚时段次数、学习用时、12 周热力图和未来 7 天**已排期**复习量。
成功率是评分 > 重来的比例，模型留存是 FSRS 估计；不混称长期实测留存。
用时为每张卡可见到评分的墙钟秒数（每卡至多一小时），不是后台专注追踪。

词书来自固定提交的 [ECDICT](https://github.com/skywind3000/ECDICT)（上游 MIT）：
CET-4、CET-6、考研、IELTS、TOEFL、GRE。Nix 固定 URL + SHA-256，构建期 Python
生成 SQLite，原始 CSV 不装入用户目录；只有显式选择词书才把词加入个人数据库。
标签来自 ECDICT，不等同各考试机构完整或最新官方词表。
源、许可、hash、字段和词根/例句限制见 [data/README.md](data/README.md)。
内置数据含音标、释义和词形变化；**没有可靠词源词根、例句时显示缺失**，不合成释义。
TUI 演示的四条例句为本项目自编，仅 `--demo --data-dir <隔离目录>` 加入。

支持 UTF-8 CSV、纯文本（每行单词，可用 Tab 附释义）、手动添加、
Anki 兼容旧版 `collection.anki2` apkg。Anki 导入剥 HTML/音频标记；不导入媒体、
卡片调度历史或复杂模板；现代 `anki21/anki21b` 明确拒绝，请在 Anki 导出旧版兼容包或 CSV。
CSV 可往返全部单词字段；apkg 导出是基础双字段卡，不含本地调度。
不覆盖已存在的导出目标。导入文件及 apkg 解压数据库各限 64 MiB。
CSV 表头：`word,phonetic,meaning,definition,example,roots,book`；中文表头也可。

`a` 只在按键时运行 `wl-paste` 读取当前选中的单个英文词，不读剪贴板历史。
发音在后台线程运行，默认 `espeak-ng` 离线英语（音质较机械、无需模型、网络、认证）。
可设置 `audio: "youdao"`：请求 `https://dict.youdao.com/dictvoice?audio=...&type=2`，
按需缓存不超过 1 MiB 的单词音频、mpv 播放；错误回退 espeak，超时 8 秒。
该入口无公开稳定契约，不批量下载、无可用性或音频再分发承诺，使用者自选。
[有道官方 TTS](https://ai.youdao.com/DOCSIRMA/html/tts/api/yyhc/index.html)是另需认证的服务；
本项目不读取凭据。[Cambridge API](https://dictionary-api.cambridge.org/api/about)
需要申请 key/许可，因此不抓网页音频。Piper 需要另外授权/下载的语音模型，未集成；
当前离线替代为 espeak。真实网络发音和声卡尚需现场核对。

## 课表

学期开学日所在的周一为第 1 周，按本地日期自动算周，支持显式周次和单双周。
TUI `n/e` 表单填写课程、教师、教室、星期、节次、周次、单双周；`d` 删除选中课程。
周视图今天蓝色、当前节次淡底、课程使用 One Dark 蓝/绿/青/黄；左右键切周。
今日和 `next --json` 仅返回今天的上课中/下一课，今日无课或结束时返回 `null`。

导入能力与边界：

- WakeUp：支持社区观察到的五行 `.wakeup_schedule`（课程名/day/startNode/step/stepWeekList/type），
  同时导入 startDate 与 timeList；不完整元数据报错。普通 `{courses:[...]}` JSON 也可。
  [官方文档](https://wakeup.fun/doc/)只承诺 App 的文件/在线分享流程，没有公开稳定 API/schema。
  结构参考[社区格式记录](https://github.com/VincentZyuApps/koishi-plugin-course-schedule/blob/main/docs/formats/wakeup-schedule.md)，
  未知版本拒绝。分享码/口令不能直接解析，请先在 WakeUp App 导出备份。
- ICS：支持本地浮动时间、单次/基本每周规则及完整节次对齐。UTC Z、TZID、BYDAY、
  其他递归规则、EXDATE/RDATE 明确拒绝，避免时区或例外课程被静默丢弃。
  导出逐 occurrence 写 VEVENT（含 VALARM），保留不连续周和冬夏切换。
- Excel：calamine 读取 xls/xlsx/xlsb/ods，尽力识别第一张表的通用中英文列头。
  正方/强智学校常有合并单元格、自定义网格，**不承诺解析所有原始教务网格**；
  不识别时返回模板列名，`study template` 输出可整理后另存的 CSV 示例。
  课表 CSV 需先整理为 Excel 列模板，词表 CSV 则直接导入。

`study timetable` 输出完整 JSON；修改后 `study timetable timetable.json` 原子校验保存。
`winter/summer.periods` 可编辑每节 start/end，`summer_from` 指定夏令作息启用日期，
也可令 `semester.kind` 为 `summer` 固定用夏令。默认冬夏相同，学校作息需用户设置。
导入追加去重，不删除已有课程；WakeUp 元数据会整体更新开学日期与冬夏时间表，
若与已有课程冲突则整次拒绝。

```console
study today
study next --json
study add resilient --meaning '有韧性的'
study books cet4
study import words.csv
study import timetable.wakeup_schedule
study export vocabulary.csv --format csv
study export cards.apkg --format apkg
study export semester.ics --format ics
study settings > settings.json
study settings settings.json
study timetable > timetable.json
study timetable timetable.json
```

`next --json` 结构（无课为 JSON null）：

```json
{"course":"高等数学","room":"A302","start_time":"2026-10-30T08:00:00+08:00","remaining_minutes":7,"status":"next","end_time":"2026-10-30T09:40:00+08:00"}
```

remaining_minutes 向上取整，上课中为 0，status 为 `in_class`。
CLI 不启动音频、通知或后台轮询。Noctalia 应用公开接口即可；建议 30–60 秒读取一次，
点击执行 `kitty --class study-mayon --title 学习 -e study-mayon tui --page 4`。

## 提醒与状态归属

feature 安装一个登录后/每日零点 bootstrap user timer。`study plan` 计算最近一次
背词时间/上课提前时间，用 `systemd-run --user --on-calendar` 安排精确 transient timer；
回调检查当前数据、去重、安排下一次。没有每分钟唤醒或常驻守护进程，也不设置 WakeSystem、
linger 或睡眠 inhibitor。登录/零点也检查 90 秒内的到点通知。课程和设置修改后重新安排，已有旧期限在触发时读取新数据再决定。
与固定每分钟 timer 相比减少空唤醒；实际耗电未测量。timer AccuracySec=1 秒，
超过期限 90 秒的旧提醒不补发（例如长时间休眠），重登/零点重新计划。
背词时刻由 `settings.reminder` 配置；课前分钟由 `before_minutes` 配置。
通知 action 等待最多 30 秒，点开独立 user service 中的 Kitty 浮窗（不随通知进程退出）；依赖通知服务器支持 action。

启用标记 `~/.config/study/reminders-enabled` 由 HM feature 独占（store symlink），
标记内容为当前公开二进制路径，升级后的旧 timer 会失效；unit 名带路径 hash。
用户也可在非 Nix 安装中显式写入 `enabled` 再 `study plan`。没有标记则 plan/remind 无操作。
移除 feature 撤回此标记、desktop entry 与受管 timer；残留 transient timer 最多再到点一次，
回调看到无标记即退出，不发通知或续约。不会删除数据库、缓存、词书、导出或历史。
包 wrapper 设置公开 `STUDY_EXECUTABLE`，timer 不绕过 wrapper，保留工具路径和词书入口。

默认 `~/.local/share/study/`（尊重 XDG_DATA_HOME），内含 `study.sqlite3` 与 `audio/`。
程序独占 SQLite、复习记录、设置/学期 JSON、通知去重；没有第二个配置 writer。
根目录 0700，数据库 0600，进程 umask 0077，SQLite journal/缓存/导出均为用户私有。
导入的临时数据库用 tempfile RAII，拒绝数据库 symlink。配置可用 CLI 查看和修改，
HM 不写 mutable settings。备份时退出学习并复制整个数据目录。

## 键位与验证

顶部 `1–5`、Tab 切页；`?` 帮助，`/` 过滤，`q` 退出；鼠标点击页签/滚轮选中。
背词 Space 翻面、z/x/c/v 评分、m 换模式、w 错词；普通模式 p 发音，拼写模式 Alt+p，
Esc 先退出输入再 q 退出。拼写 Enter 核对，选择题上下键后 Enter 核对。
n 新增、a 当前剪贴板词；课表左右切周、j/k 选课、e 编辑；词书 j/k + Enter、
s 设置、i 导入。表单 Tab/Shift+Tab 换字段、Enter 保存、Esc 取消。

```sh
CARGO_BUILD_JOBS=6 cargo test --locked
CARGO_BUILD_JOBS=6 cargo clippy --locked --all-targets -- -D warnings
cargo fmt --all --check
```

Nix `checks.study-mayon` 构建包，运行上述测试、clippy、rustfmt；不操作用户 session。
单元测试覆盖 FSRS、上限、各导入 fixture、周次/单双周、ICS 往返及提醒计算。
真实桌面/音频/通知与学校导出格式应在应用后另行核对，构建不等同激活。

测试中的 APKG/XLSX fixture 以 Base64 文本入库，在测试中解码；避免仓库文本架构扫描读取二进制。
重复导入只补全已有单词的空白词典字段，不改学习状态或覆盖已有释义。

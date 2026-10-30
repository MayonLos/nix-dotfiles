# 与 study-mayon 的交换契约

状态：离线 JSON v1 规范可实施；二维码与 LAN 仍是协议草案，未与 r50-study 代理集成验证。本 worktree 不写电脑端。

## v1 文件和二维码

唯一事实载荷是 [format.md](format.md) 的 UTF-8 `timetable.json`，一文件一学期。电脑端与 Android 必须保留 semester/course ID，周次为排序后的显式集合，日期是本地日期、作息是本地时间、星期 ISO 1–7。导入是暂存→schema 校验→差异预览→确认→原子替换；格式未知、版本过高或字段无效必须拒绝，不能丢字段后成功。保留原文件，设备级提醒不跨端覆盖。

二维码不装 URL，不触发网络。文本帧草案：`mayon-tt:1:<transferId>:<index>/<count>:<sha256>:<base64url>`。整个 JSON UTF-8 经 gzip 压缩后分片，每帧 decoded chunk 不超过 600 bytes，总帧数 <=128，总压缩大小 <=76800 bytes，解压上限 2 MiB；hash 是完整未压缩 JSON 的 SHA-256，小写 hex。transferId 是随机 128bit hex，index 从 1 开始；重复帧幂等，不同内容同序号拒绝，混合 transferId 不合并。扫描器显示已收 x/y，可手动取消，10 分钟未完成则清空临时缓冲，集齐后校验再进入普通文件导入预览。二维码不加密，分享时旁人可读；需要秘密传输时用可信文件渠道，不把隐私伪装成“离线=加密”。

## 后续 LAN v1 草案（默认关闭）

只在用户打开“临时局域网同步”后的 5 分钟内监听随机端口，只绑定用户选择的私有网卡。桌面显示带地址、证书 SHA256 pin、128bit 一次性 token 的配对二维码；TLS 1.3、固定 pin，无云发现、中继、mDNS 自动广播或后台联网。用户两端比对短认证码后才接收。`GET /v1/capabilities` 返回协议/格式版本/最大包大小；`POST /v1/transfers` 上传 JSON 和 `If-Match` 基线 hash；`GET /v1/transfers/<id>` 查询待确认状态。token 只放 Authorization，不进 URL/log。最大请求 2 MiB、每分钟 <=10 次、5 次鉴权失败关闭 listener。

收到只写暂存区，界面显示来源、学期、增删改课程数量；用户确认后原子提交并返回新 hash。409 表示基线过期，要求导出对比；第一版不做 last-write-wins、不自动删课、不按设备墙上时钟判新旧。关闭界面/超时后销毁 token 和监听 socket。上述网络、TLS、QR 扫描均未在本阶段实现。

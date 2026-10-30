# 离线二维码互传

二维码承载 `docs/format.md` 定义的 UTF-8 JSON，不包含 URL，不会启动网络请求。传输前 GZIP 压缩，再按 600 字节分片；最多 128 帧、压缩后最多 76,800 字节、解压后最多 2 MiB。每帧包含 128 位随机传输 ID、从 1 开始的序号、帧总数、完整未压缩文档的 SHA-256 和无填充 Base64URL 分片：

```text
mayon-tt:1:<transferId>:<index>/<count>:<sha256>:<base64url>
```

接收器只保存一个进行中的传输。相同序号、相同分片可重复扫描；同一序号不同数据、不同传输 ID 或不一致的 hash/总数都会拒绝。收到全部帧后，接收器先限制 GZIP 解压输出，再验证 SHA-256 与 UTF-8。上层仍须调用 `TimetableJson.decode` 完成 schema 验证，再进入导入预览。超过 10 分钟的未完成传输会在下次收到帧时清空；调用方可随时 `reset()`。

## Kotlin API

- `QrTransfer.encode(json, transferId?)` 生成帧列表；省略 ID 时使用 `SecureRandom` 生成 128 位随机值。
- `QrTransfer.newReceiver(clock?)` 建立接收状态。
- `QrTransferReceiver.accept(frame)` 返回 `QrTransferProgress`。完整且校验通过时，`resultJson` 非空；校验错误抛出 `IllegalArgumentException`。
- `QrShareScreen(json, onBack)` 以可左右滑动的方式展示全部帧。
- `decodeQr(bitmap)` 对系统选取的图片做离线单帧识别，无法识别时返回 `null`。调用者将结果交给接收器；相册/系统选图由 app 层负责。

Android 层依赖 ZXing `com.google.zxing:core`，不使用相机权限、Google Mobile Services 或网络。一个帧只是一段可见文本，二维码没有加密；旁人可读取它。接收时的 schema/导入确认仍是上层责任，二维码校验不能代替用户确认。

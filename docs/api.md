# 「踩点」的两个可选服务端接口

这两个接口都**不是必需的**。不配地址时对应功能就不出现，App 照常是纯本地的。
服务端由你自己实现，本仓库只有客户端。

所有接口都建议走 **https**——账号密码和标记数据都会经过它。

---

## 一、检查更新

设置页 →「更新」→「检查更新地址」。

### 请求

```
GET {你配置的地址}?version=1.0.0&build=1&platform=android
```

| 参数 | 含义 |
| --- | --- |
| `version` | App 当前的版本名，即 `pubspec.yaml` 里 `version:` 加号前那截 |
| `build` | 当前的版本号（整数），加号后面那截 |
| `platform` | 固定 `android` |

如果你配置的地址本身带查询串（`?token=xxx`），这三个参数会**合并**进去，
不会把原来的冲掉。

### 响应

HTTP 200，body 是一个 JSON 对象：

```json
{
  "version": "1.1.0",
  "versionCode": 2,
  "url": "https://example.com/dist/app-release-1.1.0.apk",
  "note": "修好了选点页面板挡住图钉的问题",
  "force": false
}
```

| 字段 | 必需 | 说明 |
| --- | --- | --- |
| `version` | 是 | 最新版本名 |
| `versionCode` | 建议 | 最新版本号（整数）。**有它就优先用它比**，整数比对不会有「1.10 和 1.9 谁大」的歧义 |
| `url` | 是 | APK 的直链。没有它就算版本号更新也不会提示 |
| `note` | 否 | 更新说明，显示在确认弹窗里 |
| `force` | 否 | `true` 时弹窗不给「以后再说」 |

字段名有容错：`version` 也认 `versionName` / `latest`；
`url` 也认 `downloadUrl` / `apk` / `apkUrl`；
`note` 也认 `releaseNote` / `changelog` / `description`；
`versionCode` 也认 `build` / `buildNumber`。

### 客户端怎么判断要不要升级

**不信任服务端自报的字段**，本地自己算一遍：

- 给了 `versionCode` → 比 `versionCode > 当前 build`
- 没给 → 按点分段比 `version` 字符串（`1.2` 等于 `1.2.0`）
- 两者都拿不到，或者 `url` 为空 → 不提示升级

### 最简实现

一个静态 JSON 文件就够了（忽略查询参数，永远返回最新版信息）——
客户端自己会判断是不是真的更新了。

---

## 二、云端同步

设置页 →「云端存储」。需要同时配**地址、手机号、密码**三项才会启用。

同一个地址，用 body 里的 `action` 区分动作。

### 1. 拉取

```jsonc
POST {地址}
{ "action": "pull", "account": "13800000000", "password": "..." }
```

响应：

```jsonc
{ "ok": true, "markers": [ /* 见下面的记录格式 */ ] }
```

### 2. 覆盖保存

```jsonc
POST {地址}
{ "action": "push", "account": "...", "password": "...",
  "markers": [ /* 完整的一份，服务端整体替换这个账号的数据 */ ] }
```

响应：`{ "ok": true, "count": 12 }`

### 3. 问哪些媒体文件还没上传

```jsonc
POST {地址}
{ "action": "missing", "account": "...", "password": "...",
  "hashes": ["<sha256>", "<sha256>", ...] }
```

响应：只回**服务端还没有的**那些：

```jsonc
{ "ok": true, "missing": ["<sha256>", ...] }
```

### 4. 上传一个媒体文件

```
POST {地址}?action=upload
Content-Type: multipart/form-data
```

字段：`account`、`password`、`sha256`、`file`。

响应：`{ "ok": true, "url": "https://example.com/files/<sha256>" }`

### 5. 下载媒体文件

直接 `GET` 服务端在 `pull` 里给出的 `url`，不需要额外参数（或者你自己在
url 里带签名）。

### 出错时

任何一步返回非 200，或者 body 里 `ok` 为 `false`，都会把 `message`
字段的内容直接显示给用户，所以那里写人话。

### 记录格式

```jsonc
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "老张家的面馆",
  "latitude": 39.908722,
  "longitude": 116.397499,
  "placeName": "中铁吉盛物流大厦",
  "address": "北京市大兴区天河北路5号",
  "accuracy": 12.5,
  "note": "二楼，牛肉面加蛋",
  "transcript": "语音备注转出来的文字",
  "tags": ["美食", "打卡"],
  "waveform": [0.4, 0.9, 0.3],
  "audioDurationMs": 12000,
  "createdAt": 1758000000000,
  "updatedAt": 1758000000000,
  "photos": [
    { "sha256": "...", "name": "a1b2.jpg", "url": "https://..." }
  ],
  "audio": { "sha256": "...", "name": "c3d4.wav", "url": "https://..." }
}
```

- `id` 是客户端生成的 UUID v4，**全局唯一、就是同步的主键**。
  服务端按它做 upsert 即可，不要自己另编 id。
- 时间戳是毫秒。`updatedAt` 在「合并」策略下用来决定同一条记录以谁为准。
- `photos` / `audio` 的 `url` 由服务端在 `pull` 时填；客户端 `push` 时
  只保证 `sha256` 和 `name` 有值。
- 媒体按 `sha256` 内容寻址：同一张图不管被多少条记录引用、传多少次，
  服务端只需要存一份。
- 录音现在是 WAV（16 位单声道）；老版本录的 `.m4a` 还在库里，两种都可能出现。
  服务端不必关心格式，按 `name` 里的扩展名原样存取即可。

### 同步时客户端做什么

1. `pull` 拿到服务端全量；
2. 按 `id` 比对出「只有本地有」「只有服务端有」「两边都有」三类；
3. 让用户选策略，三种的提示措辞不同：
   - **以服务端为主** —— 本地新增 N 条、删除 M 条
   - **以本地为主** —— 云端新增 M 条、删除 N 条
   - **合并** —— 双方各自新增，不删除任何数据；同 `id` 取 `updatedAt` 新的
4. 需要上传媒体时先 `missing` 问一遍，只传服务端没有的，再 `push`。

---

## 安全上要知道的

- 密码以**明文**存在手机本地的 SQLite 里。这是自用 App 的常见做法，
  但意味着：别用你其它账号的密码。
- 客户端不校验服务端证书之外的任何东西。地址一定要用 https，
  否则账号密码在链路上是裸的。

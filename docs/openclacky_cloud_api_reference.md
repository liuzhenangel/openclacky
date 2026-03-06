# OpenClacky License API — 接口文档

**Base URL**: `https://your-platform.com`
**Content-Type**: `application/json`
**协议说明**: License Key **全程不通过网络传输**，所有认证均基于 HMAC-SHA256 知识证明。

---

## 接口目录

| # | 接口名称 | 方法 | 路径 | 说明 |
|---|---------|------|------|------|
| 1 | [激活 License](#1-激活-license) | POST | `/api/v1/licenses/activate` | 首次激活，绑定设备 |
| 2 | [获取 Skills 列表](#2-获取-skills-列表) | POST | `/api/v1/licenses/skills` | 查询许可范围内的 Skill |
| 3 | [心跳检测](#4-心跳检测) | POST | `/api/v1/licenses/heartbeat` | 定期验证许可有效性 |

---

## 通用错误码

所有接口均使用统一的错误响应格式：

```json
{
  "status": "error",
  "code": "<错误码>"
}
```

| HTTP 状态码 | code | 说明 |
|------------|------|------|
| 400 | `missing_params` | 缺少必填参数 |
| 401 | `invalid_proof` | 激活证明验证失败 |
| 401 | `invalid_signature` | 请求签名验证失败 |
| 401 | `nonce_replayed` | Nonce 重放攻击，请求已被拒绝 |
| 401 | `timestamp_expired` | 时间戳超出允许范围（±5 分钟） |
| 401 | `user_id_mismatch` | user_id 与 License 不匹配 |
| 401 | `device_revoked` | 设备已被撤销（heartbeat 专用） |
| 403 | `license_revoked` | License 已被撤销 |
| 403 | `license_expired` | License 已过期 |
| 403 | `device_revoked` | 设备已被撤销 |
| 403 | `device_limit_reached` | 已达到设备数量上限 |
| 403 | `invalid_status` | License 状态不允许操作 |
| 404 | `invalid_license` | License 不存在 |
| 404 | `device_not_found` | 设备未激活，请先调用激活接口 |
| 429 | `rate_limited` | 请求过于频繁，请稍后重试 |

---

## 1. 激活 License

**POST** `/api/v1/licenses/activate`

首次在设备上激活 License。使用 HMAC 知识证明，License Key 本身不发送到服务器。
激活成功后，服务器返回许可范围内的 Skills 列表及有效期。

> 同一设备重复激活幂等安全（不会消耗新的设备配额）。

### 请求参数

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `key_hash` | string | 是 | `SHA256(license_key)` 的 hex 字符串（64 字符），用于服务器查找 License |
| `user_id` | string | 是 | 从 License Key 结构中提取的用户 ID（十进制字符串） |
| `device_id` | string | 是 | 设备唯一标识符（建议 32 字符 hex，参见设备 ID 算法） |
| `timestamp` | string | 是 | 当前 Unix 时间戳（秒，字符串格式），需与服务器时间误差 ≤ 5 分钟 |
| `nonce` | string | 是 | 32 字符随机 hex，每次请求必须唯一，10 分钟内不可重用 |
| `proof` | string | 是 | HMAC-SHA256 激活证明（64 字符 hex），计算方式见下方 |
| `device_info` | object | 否 | 设备元数据（如 OS、版本号等），仅用于管理展示 |

**proof 计算方式：**

```
message = "activate:{key_hash}:{user_id}:{device_id}:{timestamp}:{nonce}"
proof   = HMAC-SHA256(license_key, message)  // hex 编码
```

### 响应参数（成功 200）

```json
{
  "status": "success",
  "data": {
    "status": "active",
    "expires_at": "2027-01-01T00:00:00Z",
    "device_id": "a1b2c3d4...",
    "device_limit": 3,
    "activated_devices": 1,
    "skills": [
      {
        "id": 42,
        "name": "Code Review Bot",
        "version": "1.2.0",
        "encrypted": false,
        "checksum": "sha256hex..."
      }
    ]
  }
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `data.status` | string | License 状态：`active` / `assigned` |
| `data.expires_at` | string | ISO 8601 过期时间，null 表示永久有效 |
| `data.device_id` | string | 当前设备 ID（回显） |
| `data.device_limit` | integer | 最大可激活设备数 |
| `data.activated_devices` | integer | 当前已激活设备数 |
| `data.skills` | array | License 授权的 Skill 列表（简要信息） |
| `data.skills[].id` | integer | Skill ID |
| `data.skills[].name` | string | Skill 名称 |
| `data.skills[].version` | string | 当前版本号 |
| `data.skills[].encrypted` | boolean | 是否加密 |
| `data.skills[].checksum` | string | 最新版本校验码 |

### curl 示例

```bash
# 1. 本地计算（伪代码，实际由 SDK 完成）
KEY="0000002A-00000007-DEADBEEF-CAFEBABE-A1B2C3D4"
KEY_HASH=$(echo -n "$KEY" | sha256sum | awk '{print $1}')
DEVICE_ID="a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"
TS=$(date +%s)
NONCE=$(openssl rand -hex 16)
MSG="activate:${KEY_HASH}:42:${DEVICE_ID}:${TS}:${NONCE}"
PROOF=$(echo -n "$MSG" | openssl dgst -sha256 -hmac "$KEY" | awk '{print $2}')

# 2. 发起请求
curl -s -X POST https://your-platform.com/api/v1/licenses/activate \
  -H "Content-Type: application/json" \
  -d "{
    \"key_hash\":    \"${KEY_HASH}\",
    \"user_id\":     \"42\",
    \"device_id\":   \"${DEVICE_ID}\",
    \"timestamp\":   \"${TS}\",
    \"nonce\":       \"${NONCE}\",
    \"proof\":       \"${PROOF}\",
    \"device_info\": {\"os\": \"macOS\", \"version\": \"14.0\", \"app_version\": \"1.0.0\"}
  }"
```

**成功响应示例：**
```json
{
  "status": "success",
  "data": {
    "status": "active",
    "expires_at": "2027-03-06T10:00:00Z",
    "device_id": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6",
    "device_limit": 3,
    "activated_devices": 1,
    "skills": [
      { "id": 42, "name": "Code Review Bot", "version": "1.2.0",
        "encrypted": false, "checksum": "abcdef1234..." }
    ]
  }
}
```

---

## 2. 获取 Skills 列表

**POST** `/api/v1/licenses/skills`

获取当前 License 授权范围内的全部 Skill，包含版本信息和下载地址。
支持按可见性（公开/私有）和关键词过滤。

### 请求参数

**认证参数（必填，同 heartbeat / check_version）：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `user_id` | string | 是 | 从 License Key 提取的用户 ID（十进制字符串） |
| `device_id` | string | 是 | 已激活的设备 ID |
| `timestamp` | string | 是 | 当前 Unix 时间戳（秒），与服务器误差 ≤ 5 分钟 |
| `nonce` | string | 是 | 32 字符随机 hex，每次请求唯一 |
| `signature` | string | 是 | HMAC-SHA256 请求签名（64 字符 hex），计算方式见下方 |

**signature 计算方式：**

```
message   = "{user_id}:{device_id}:{timestamp}:{nonce}"
signature = HMAC-SHA256(license_key, message)  // hex 编码
```

**过滤参数（可选）：**

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `visibility` | string | `all` | `public`（公开）/ `private`（私有）/ `all`（全部） |
| `keyword` | string | — | 关键词，匹配 Skill 的 name 或 description（不区分大小写） |

### 响应参数（成功 200）

```json
{
  "status": "success",
  "total": 2,
  "expires_at": "2027-01-01T00:00:00Z",
  "skills": [
    {
      "id": 42,
      "name": "Code Review Bot",
      "slug": "code-review-bot",
      "description": "Automated code review using AI",
      "visibility": "public",
      "version": "1.2.0",
      "encrypted": false,
      "emoji": null,
      "download_count": 1024,
      "latest_version": {
        "version": "1.2.0",
        "checksum": "a3f8b2c1d4e5...",
        "release_notes": "Fix edge case in Python parsing",
        "published_at": "2026-03-01T00:00:00Z",
        "download_url": "https://bucket.s3.region.amazonaws.com/skills/abc.zip"
      }
    }
  ]
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `total` | integer | 符合条件的 Skill 总数 |
| `expires_at` | string | License 过期时间（ISO 8601） |
| `skills[].id` | integer | Skill ID |
| `skills[].name` | string | Skill 名称 |
| `skills[].slug` | string | URL 友好标识符 |
| `skills[].description` | string | Skill 描述 |
| `skills[].visibility` | string | `public` / `private` |
| `skills[].version` | string | 当前版本号（SemVer） |
| `skills[].encrypted` | boolean | 是否加密 |
| `skills[].emoji` | string/null | 图标 Emoji |
| `skills[].download_count` | integer | 累计下载次数 |
| `skills[].latest_version` | object/null | 最新版本详情，无版本时为 null |
| `skills[].latest_version.version` | string | 版本号 |
| `skills[].latest_version.checksum` | string | 文件 SHA256 校验码 |
| `skills[].latest_version.release_notes` | string | 更新说明 |
| `skills[].latest_version.published_at` | string | 发布时间（ISO 8601） |
| `skills[].latest_version.download_url` | string/null | 文件下载直链（S3 公开 URL，无过期时间） |

### curl 示例

```bash
TS=$(date +%s)
NONCE=$(openssl rand -hex 16)
USER_ID="42"
DEVICE_ID="a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"
KEY="0000002A-00000007-DEADBEEF-CAFEBABE-A1B2C3D4"
MSG="${USER_ID}:${DEVICE_ID}:${TS}:${NONCE}"
SIG=$(echo -n "$MSG" | openssl dgst -sha256 -hmac "$KEY" | awk '{print $2}')

# 获取全部 Skills
curl -s -X POST https://your-platform.com/api/v1/licenses/skills \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\":   \"${USER_ID}\",
    \"device_id\": \"${DEVICE_ID}\",
    \"timestamp\": \"${TS}\",
    \"nonce\":     \"${NONCE}\",
    \"signature\": \"${SIG}\"
  }"

# 只看公开 Skills，且名称包含 "code"
curl -s -X POST https://your-platform.com/api/v1/licenses/skills \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\":    \"${USER_ID}\",
    \"device_id\":  \"${DEVICE_ID}\",
    \"timestamp\":  \"${TS}\",
    \"nonce\":      \"${NONCE}\",
    \"signature\":  \"${SIG}\",
    \"visibility\": \"public\",
    \"keyword\":    \"code\"
  }"
```

---

## 3. 心跳检测

**POST** `/api/v1/licenses/heartbeat`

轻量级 License 有效性确认，建议每 1 天调用一次（或使用 SDK `start_heartbeat!` 自动化）。
服务器同步更新设备的 `last_seen_at` 时间。

### 请求参数

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `user_id` | string | 是 | 用户 ID |
| `device_id` | string | 是 | 设备 ID |
| `timestamp` | string | 是 | Unix 时间戳 |
| `nonce` | string | 是 | 随机 hex，每次唯一 |
| `signature` | string | 是 | HMAC-SHA256 签名 |

### 响应参数（成功 200）

```json
{
  "status": "ok",
  "expires_at": "2027-01-01T00:00:00Z"
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `status` | string | 固定为 `ok` |
| `expires_at` | string | License 过期时间（ISO 8601） |

### curl 示例

```bash
TS=$(date +%s)
NONCE=$(openssl rand -hex 16)
USER_ID="42"
DEVICE_ID="a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"
KEY="0000002A-00000007-DEADBEEF-CAFEBABE-A1B2C3D4"
MSG="${USER_ID}:${DEVICE_ID}:${TS}:${NONCE}"
SIG=$(echo -n "$MSG" | openssl dgst -sha256 -hmac "$KEY" | awk '{print $2}')

curl -s -X POST https://your-platform.com/api/v1/licenses/heartbeat \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\":   \"${USER_ID}\",
    \"device_id\": \"${DEVICE_ID}\",
    \"timestamp\": \"${TS}\",
    \"nonce\":     \"${NONCE}\",
    \"signature\": \"${SIG}\"
  }"
```

**响应示例：**
```json
{ "status": "ok", "expires_at": "2027-03-06T10:00:00Z" }
```

---

## License 算法与验证说明

### 一、License Key 格式

License Key 是一个 **40 个 hex 字符、5 组 8 字符**的字符串：

```
UUUUUUUU - PPPPPPPP - RRRRRRRR - RRRRRRRR - CCCCCCCC
│           │           │                   │
user_id     plan_id     random（8字节熵）    HMAC校验位
（uint32）  （uint32）  64-bit 随机数       （前4字节）
```

**示例：**
```
0000002A-00000007-DEADBEEF-CAFEBABE-A1B2C3D4
│         │         │                 │
user=42   plan=7    随机 8 字节         HMAC checksum
```

**字段说明：**

| 段 | 长度 | 说明 |
|----|------|------|
| `UUUUUUUU` | 8 hex | `user_id` 大端序 uint32，客户端本地可直接解析 |
| `PPPPPPPP` | 8 hex | `plan_id` 大端序 uint32，标识许可计划 |
| `RRRRRRRR-RRRRRRRR` | 16 hex | 8 字节 SecureRandom，保证每个 Key 全局唯一 |
| `CCCCCCCC` | 8 hex | `HMAC-SHA256(LICENSE_SECRET, U+P+R)[0..3]` 的 hex，4 字节完整性校验 |

---

### 二、Key 生成算法（服务端）

```ruby
# 服务端生成（app/models/license.rb）
def generate_key
  u = [user_id].pack('N').unpack1('H*').upcase   # uint32 → 8 hex
  p = [plan_id].pack('N').unpack1('H*').upcase   # uint32 → 8 hex
  r = SecureRandom.bytes(8).unpack1('H*').upcase # 8 字节随机 → 16 hex

  payload  = u + p + r                           # 32 hex = 16 字节
  checksum = HMAC-SHA256(LICENSE_SECRET, payload)[0, 4]  # 取前 4 字节
  checksum = checksum.unpack1('H*').upcase       # → 8 hex

  key      = "#{u}-#{p}-#{r[0..7]}-#{r[8..15]}-#{checksum}"
  key_hash = SHA256(key)                         # 用于激活时的查找索引
end
```

**安全属性：**
- `user_id`/`plan_id` 明文嵌入，客户端无需联网即可解析
- `random` 8 字节（64-bit 熵）保证唯一性，碰撞概率 ≈ 2^(-32) 在 40 亿次生成前
- `HMAC checksum` 使用独立密钥 `LICENSE_SECRET`，篡改任意字符均使校验失败
- `key_hash = SHA256(key)` 存储在数据库，作为激活时的查找索引（无法反推 key）

---

### 三、客户端本地解析（无需联网）

```ruby
# 客户端本地解析（sdk/openclacky_license_client.rb）
hex      = key.delete('-').upcase  # 去掉分隔符
user_id  = hex[0..7].to_i(16)     # 前 8 hex → integer
plan_id  = hex[8..15].to_i(16)    # 次 8 hex → integer
key_hash = SHA256(key)             # 64 字符 hex
```

---

### 四、激活流程：HMAC 知识证明

激活阶段的核心问题：**如何向服务器证明持有 license_key，但又不发送 license_key？**

**解决方案：HMAC 知识证明（Zero-Transmission Proof）**

```
┌─ 客户端 ──────────────────────────────────────────────────┐
│                                                            │
│  1. 本地解析：                                             │
│     user_id  = key[0..7].to_i(16)                        │
│     key_hash = SHA256(license_key)                        │
│                                                            │
│  2. 构造证明消息：                                         │
│     message = "activate:{key_hash}:{user_id}:             │
│                {device_id}:{timestamp}:{nonce}"           │
│                                                            │
│  3. 计算 HMAC 证明：                                       │
│     proof = HMAC-SHA256(license_key, message)             │
│                                                            │
│  4. 发送（不含 license_key）：                             │
│     { key_hash, user_id, device_id, timestamp,           │
│       nonce, proof, device_info }                         │
└───────────────────────────────────────────────────────────┘
         │  HTTP POST  │
         ▼             ▼
┌─ 服务端 ──────────────────────────────────────────────────┐
│                                                            │
│  1. 通过 key_hash 查找 License（O(1) 索引）               │
│  2. 验证时间戳（±5 分钟）                                  │
│  3. 验证 nonce（10 分钟 TTL，防重放）                     │
│  4. 重建 message，使用数据库中存储的 license.key 计算：   │
│     expected = HMAC-SHA256(license.key, message)          │
│  5. 常量时间比较：expected == proof                        │
│  6. 验证通过 → 绑定设备，记录激活时间                     │
│                                                            │
└───────────────────────────────────────────────────────────┘
```

**为什么安全？**
- 只有持有 `license_key` 的客户端才能计算出正确的 `proof`
- `key_hash = SHA256(key)` 是单向函数，服务器无法从 `key_hash` 反推 `key`
- `nonce` 一次性使用，攻击者截获请求后无法重放（10 分钟缓存过期）
- `timestamp` ±5 分钟窗口，进一步限制重放时间窗口

---

### 五、后续请求：签名认证

激活后的所有 API 调用（`skills`、`heartbeat`）使用简化的请求签名：

```
┌─ 客户端 ───────────────────────────────────────┐
│                                                 │
│  message   = "{user_id}:{device_id}:           │
│               {timestamp}:{nonce}"             │
│  signature = HMAC-SHA256(license_key, message) │
│                                                 │
│  发送：{ user_id, device_id, timestamp,        │
│          nonce, signature, ...业务参数 }        │
└─────────────────────────────────────────────────┘
         │
         ▼
┌─ 服务端 ───────────────────────────────────────┐
│                                                 │
│  1. 通过 (device_id + user_id) 查找设备/License│
│  2. 验证时间戳（±5 分钟）                       │
│  3. 验证 nonce（防重放）                        │
│  4. Cross-check：                              │
│     params.user_id == license_plan.user_id     │
│  5. 重算签名并比较                              │
│  6. 更新 last_seen_at                          │
│                                                 │
└─────────────────────────────────────────────────┘
```

**Cross-check 的意义：**
攻击者即使猜到了别人的 `device_id`，也无法伪造请求——因为必须同时满足：
1. `user_id` 与 License 绑定的 `user_id` 一致
2. HMAC 签名正确（需要持有 `license_key`）

---

### 六、稳定设备 ID 算法

SDK 提供 `LicenseClient.stable_device_id` 方法，基于机器指纹生成稳定的 32 字符 hex 设备 ID：

```ruby
# 优先级：/etc/machine-id → /var/lib/dbus/machine-id → hostname
sources = ['/etc/machine-id', '/var/lib/dbus/machine-id']
content = sources.find { |f| File.exist?(f) }
            &.then { |f| File.read(f).strip }

device_id = if content
  SHA256(content)[0, 32]
else
  SHA256("#{Socket.gethostname}-openclacky")[0, 32]
end
```

**特性：**
- 同一机器每次调用返回相同值（幂等）
- 重新安装 App 不影响设备 ID（基于硬件标识）
- 不含任何可识别个人身份的信息

---

### 七、安全防御矩阵

| 威胁 | 防御机制 |
|------|----------|
| License Key 网络截获 | Key 全程不传输；激活用 `key_hash + HMAC proof` |
| 激活 proof 重放 | `timestamp ±5min` + `nonce` 唯一性（Cache TTL 10min） |
| 伪造请求（不持有 key） | HMAC-SHA256 签名，key 作为签名密钥 |
| Device ID 碰撞伪冒 | 每次请求 cross-check `user_id == license_plan.user_id` |
| 伪造 License Key 格式 | Key 含 `HMAC(LICENSE_SECRET, payload)` 校验位，服务端快速拒绝 |
| SHA256(key) 碰撞攻击 | 碰撞空间 2^256，实际不可行 |
| 撤销不传播 | 每次请求查询 `device.revoked_at` + `license.status` |
| 暴力枚举 key_hash | `rack-attack`：激活 10 次/小时/IP，API 120 次/小时/设备 |
| 时序攻击（签名比较） | `ActiveSupport::SecurityUtils.secure_compare` 常量时间 |
| 多设备超限 | `device_limit = license_plan.seats`，激活时强制检查 |

---

### 八、速率限制

| 规则 | 限制 | 周期 | 维度 |
|------|------|------|------|
| 激活接口 | 10 次 | 1 小时 | 客户端 IP |
| 所有 License API | 120 次 | 1 小时 | device_id |

触发限制时响应：
```json
HTTP 429
{ "status": "error", "code": "rate_limited", "message": "Rate limit exceeded. Please try again later." }
```

响应头包含 `Retry-After: <seconds>`。

---

### 九、SDK 快速接入（Ruby）

```ruby
require_relative 'sdk/openclacky_license_client'

# 初始化（仅需一次）
client = OpenClacky::LicenseClient.new(
  base_url:    "https://your-platform.com",
  device_info: { os: RUBY_PLATFORM, app_version: "1.0.0" },
  store:       OpenClacky::LicenseStore.new("~/.myapp/license.json")
)
client.load_license("0000002A-00000007-DEADBEEF-CAFEBABE-A1B2C3D4")

# 激活（首次运行）
license_info = client.activate!

# 获取 Skills 列表
result = client.list_skills                          # 全部
result = client.list_skills(visibility: 'public')   # 仅公开
result = client.list_skills(keyword: 'code review') # 关键词搜索

# 下载 Skill（获取直链后自行下载）
skill = result['skills'].first
download_url = skill['latest_version']['download_url']

# 启动后台心跳（每 10 分钟自动检测）
client.start_heartbeat!(
  on_revoked: ->(e) { puts "License 已撤销：#{e.message}"; exit 1 },
  on_expired: ->(e) { puts "License 已过期，请续费" },
  on_error:   ->(e) { puts "心跳失败（将自动重试）：#{e.message}" }
)
```

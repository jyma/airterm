# 通信协议

## 概述

AirTerm 使用 WebSocket 进行实时双向通信，支持**内网直连（LAN）和外网中继（WAN）**双通道。所有业务消息经端到端加密后传输，无论走哪条通道，安全性完全一致。

## 连接建立

### WAN: Mac → 中继服务器

```
WSS wss://server.com/ws/mac
Headers:
  Authorization: Bearer <jwt>
  X-Device-Id: <mac-device-id>
```

### WAN: 手机 → 中继服务器

```
WSS wss://server.com/ws/phone
Headers:
  Authorization: Bearer <jwt>
  X-Device-Id: <phone-device-id>
```

### LAN: 手机 → Mac 直连

```
WS ws://<mac-lan-ip>:<port>/ws
无 TLS (E2EE 已保证密文安全)
连接后需完成 Challenge-Response 认证 (见下方)
```

### LAN 认证握手 (Challenge-Response)

手机连接 Mac 内网 WebSocket 后，需在 3 秒内完成认证：

```
1. Mac → Phone (明文):
   { "type": "challenge", "nonce": "<random-32-bytes-hex>" }

2. Phone 计算:
   response = HMAC-SHA256(sharedSecret, nonce)

3. Phone → Mac (明文):
   { "type": "auth", "deviceId": "<phone-device-id>", "response": "<hmac-hex>" }

4. Mac 验证:
   - deviceId 在已配对列表中
   - HMAC 与本地计算一致 (证明对方持有共享密钥)
   - 通过 → 连接激活，后续消息走 E2EE 信封
   - 失败 → 立即断开 + 记录告警
```

防护措施：
- 认证超时: 3 秒内未完成认证则断开
- 失败封禁: 同一 IP 连续 5 次认证失败后封禁 10 分钟
- 连接数限制: 最多 5 个并发连接（含未认证）

### 连接优先级

手机打开页面时，**并行**尝试两条通道 (Happy Eyeballs)：

```
T=0ms    并行发起:
         ├── LAN: ws://<mac-lan-ip>:<port>/ws + challenge-response
         └── WAN: wss://<relay-server>/ws/phone + JWT

T<2s     LAN 先通 → active, WAN 继续连接 → standby
T>2s     LAN 超时 → WAN 为 active, 后台持续探测 LAN
```

## 消息格式

### 信封格式（明文，服务器/LAN 可见）

```json
{
  "type": "relay",
  "from": "<device-id>",
  "to": "<device-id>",
  "ts": 1711900000000,
  "payload": "<base64-encoded-encrypted-data>"
}
```

WAN 路径: 服务器只读 `type`、`from`、`to` 用于路由，不接触 `payload`。
LAN 路径: Mac 直接收发，`from`/`to` 仍填写 device ID（格式统一），Mac 验证 `from` 为已配对设备。

### 业务消息（加密后的 payload 解密内容）

所有业务消息包含 `seq` 和 `ack` 字段，用于消息确认和重传：

```json
{
  "seq": 42,
  "ack": 41,
  "kind": "...",
  ...
}
```

- `seq`: 发送方的递增序列号（每个方向独立递增，与传输通道无关）
- `ack`: 发送方已收到对方的最大连续序列号

序列号规则：
- `seq == expected` → 正常处理，推进 expected
- `seq < expected` → 重复消息，丢弃
- `seq > expected` → 乱序，缓存等待（最多 2 秒后放弃空洞）
- 通道切换时：未收到 ack 的消息通过新通道重发

#### 会话列表更新

Mac → 手机，当会话列表变化时推送：

```json
{
  "kind": "sessions",
  "sessions": [
    {
      "id": "sess_abc123",
      "name": "auth 重构",
      "cwd": "~/projects/myapp",
      "terminal": "iTerm2",
      "status": "active",
      "lastOutput": "正在编辑 auth.ts...",
      "needsApproval": false
    }
  ]
}
```

#### 终端输出更新

Mac → 手机，终端内容变化时推送：

```json
{
  "kind": "output",
  "sessionId": "sess_abc123",
  "events": [
    {
      "type": "message",
      "text": "发现 auth.ts 有 3 个安全问题"
    },
    {
      "type": "diff",
      "file": "src/auth.ts",
      "hunks": [
        {
          "oldStart": 42,
          "lines": [
            { "op": "remove", "text": "const token = \"hardcoded\"" },
            { "op": "add", "text": "const token = process.env.AUTH_TOKEN" }
          ]
        }
      ]
    },
    {
      "type": "approval",
      "tool": "Bash",
      "command": "npm test",
      "prompt": "Allow Bash: npm test?"
    }
  ]
}
```

#### 发送输入

手机 → Mac：

```json
{
  "kind": "input",
  "sessionId": "sess_abc123",
  "text": "帮我把错误处理也加上"
}
```

#### 确认操作

手机 → Mac：

```json
{
  "kind": "approval",
  "sessionId": "sess_abc123",
  "action": "allow"
}
```

`action` 可选值: `"allow"` | `"deny"`

#### 快捷指令

手机 → Mac：

```json
{
  "kind": "shortcut",
  "sessionId": "sess_abc123",
  "command": "/commit"
}
```

#### 安全拦截通知

Mac → 手机，当远程指令被安全检查拦截时：

```json
{
  "kind": "blocked",
  "sessionId": "sess_abc123",
  "reason": "包含高危命令: rm -rf",
  "original": "rm -rf node_modules && npm install",
  "requiresMacConfirm": true
}
```

#### 心跳

双向，频率取决于通道角色：

| 通道状态 | 频率 | 说明 |
|---------|------|------|
| LAN active | 5 秒 | 主通道，快速检测断连 |
| WAN active | 30 秒 | 外网主通道 |
| WAN standby | 60 秒 | 热备保活，低开销 |
| LAN reconnecting | 30 秒探测 | 后台尝试恢复 |

```json
{
  "seq": 43,
  "ack": 42,
  "kind": "ping"
}
```

响应：

```json
{
  "seq": 44,
  "ack": 43,
  "kind": "pong"
}
```

心跳也携带 seq/ack，用于通道健康检测和消息确认同步。连续 2 次心跳无响应即判定通道不可用。

#### LAN 地址通知

Mac → 手机 (通过 WAN 信道发送，E2EE 加密)：

当 Mac 内网 IP 变化或首次配对完成后推送：

```json
{
  "seq": 5,
  "ack": 4,
  "kind": "lan_info",
  "addresses": ["192.168.1.100", "10.0.0.5"],
  "port": 48921,
  "ts": 1711900000000
}
```

手机收到后缓存到 IndexedDB，下次打开时优先尝试这些地址。

## 服务器控制消息（明文，不经 E2EE）

### 配对请求

手机 → 服务器：

```
POST /api/pair
Content-Type: application/json

{
  "pairCode": "A3X92K",
  "phonePubKey": "base64...",
  "phoneDeviceId": "uuid",
  "phoneName": "My iPhone"
}
```

响应：

```json
{
  "token": "jwt...",
  "macPubKey": "base64...",
  "macDeviceId": "uuid"
}
```

### 配对完成后的 LAN 信息交换

配对成功 + SAS 验证通过后，Mac 通过已建立的 E2EE WAN 信道发送：

```json
{
  "kind": "lan_info",
  "addresses": ["192.168.1.100"],
  "port": 48921,
  "ts": 1711900000000
}
```

手机缓存此信息后立即尝试 LAN 连接。成功则切换为主通道。

二维码内容也扩展了 LAN 信息（用于首次配对时快速建立 LAN）：

```json
{
  "server": "https://your-server.com",
  "pairCode": "A3X92K",
  "macPubKey": "base64...",
  "macDeviceId": "uuid",
  "frontend_hash": "sha256...",
  "lan": {
    "addresses": ["192.168.1.100", "10.0.0.5"],
    "port": 48921
  }
}
```

### 设备列表

Mac → 服务器：

```
GET /api/devices
Authorization: Bearer <jwt>
```

### 撤销设备

Mac → 服务器：

```
DELETE /api/devices/:deviceId
Authorization: Bearer <jwt>
```

## 错误码

| 代码 | 含义 |
|------|------|
| 4001 | 认证失败 (JWT 无效或过期) |
| 4002 | 设备未配对 |
| 4003 | 配对码无效或已过期 |
| 4004 | 目标设备离线 |
| 4005 | 会话不存在 |
| 4006 | 指令被安全策略拦截 |

## 重连策略

### WAN 重连（中继服务器）

```
断线后自动重连:
  第 1 次: 立即重试
  第 2 次: 1 秒后
  第 3 次: 3 秒后
  第 4 次: 10 秒后
  后续: 每 30 秒重试，最多重试 100 次
  全部失败: Mac 菜单栏显示离线状态
```

### LAN 重连（内网直连）

```
LAN 断开后:
  第 1 次: 5 秒后
  第 2 次: 10 秒后
  第 3 次: 30 秒后
  后续: 每 60 秒探测一次
  持续探测直到 LAN 恢复或 App 关闭
```

### 故障转移

```
LAN → WAN 故障转移:
  触发: LAN 连续 2 次心跳无响应 (~10 秒)
  动作: active 切到 WAN (已 standby 保活)
  重传: 发送队列中未 ack 消息通过 WAN 重发
  延迟: < 1 秒 (WAN 无需重新握手)

WAN → LAN 升级:
  触发: 后台 LAN 探测成功 + challenge-response 认证通过
  动作: 序列号同步后 active 切到 LAN
  WAN: 降为 standby，心跳降频至 60 秒
```

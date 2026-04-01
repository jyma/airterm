# 通信协议

## 概述

Herald 使用 WebSocket 进行实时双向通信。所有业务消息经端到端加密后传输，服务器仅看到密文。

## 连接建立

### Mac → 服务器

```
WSS wss://server.com/ws/mac
Headers:
  Authorization: Bearer <jwt>
  X-Device-Id: <mac-device-id>
```

### 手机 → 服务器

```
WSS wss://server.com/ws/phone
Headers:
  Authorization: Bearer <jwt>
  X-Device-Id: <phone-device-id>
```

## 消息格式

### 信封格式（明文，服务器可见）

```json
{
  "type": "relay",
  "from": "<device-id>",
  "to": "<device-id>",
  "ts": 1711900000000,
  "payload": "<base64-encoded-encrypted-data>"
}
```

服务器只读 `type`、`from`、`to` 用于路由，不接触 `payload`。

### 业务消息（加密后的 payload 解密内容）

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

双向，每 30 秒：

```json
{
  "kind": "ping"
}
```

响应：

```json
{
  "kind": "pong"
}
```

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

```
断线后自动重连:
  第 1 次: 立即重试
  第 2 次: 1 秒后
  第 3 次: 3 秒后
  第 4 次: 10 秒后
  后续: 每 30 秒重试，最多重试 100 次
  全部失败: Mac 菜单栏显示离线状态
```

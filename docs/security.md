# 安全方案

## 威胁模型

AirTerm 具有远程终端控制能力，安全必须作为一等公民对待。

### 攻击面分析

| 威胁         | 风险等级 | 攻击场景                                 |
| ------------ | -------- | ---------------------------------------- |
| 服务器被入侵 | 高       | 攻击者控制中继服务器，尝试窃听或注入指令 |
| 通信被截获   | 中       | 中间人攻击，网络嗅探                     |
| 手机丢失     | 中       | 未授权者通过已配对手机控制 Mac           |
| 配对码泄露   | 低       | 配对过程中被偷窥                         |
| 重放攻击     | 低       | 截获加密消息后重放                       |

## 七层安全防护

### L0: 传输通道安全

AirTerm 支持两条通信路径，安全策略有所不同：

```
WAN 路径: 手机 ──WSS (TLS 1.3)──► 中继服务器 ──WSS (TLS 1.3)──► Mac
LAN 路径: 手机 ──WS (无 TLS)──► Mac (内网直连)
```

**WAN (外网中继):**

- 强制 TLS 1.3，服务器 Let's Encrypt 自动续签
- Mac 客户端验证服务器证书
- 禁用 TLS 1.2 及以下

**LAN (内网直连):**

- 使用 `ws://` 而非 `wss://`（无 TLS）
- **不使用 TLS 的理由：**
  1. 自签名证书会触发浏览器安全告警，用户体验极差
  2. 域名证书对内网 IP 地址无效
  3. E2EE (L2) 已保证所有 payload 为密文，裸 WebSocket 只传输密文
  4. 认证由应用层 Challenge-Response (L1) 保证
- **安全等级对比：**
  - WAN: TLS (传输加密) + E2EE (应用加密) = 双重加密
  - LAN: E2EE (应用加密) = 单重加密，但密文同样不可破

### L1: LAN 接入认证

内网 WebSocket 服务器通过 Challenge-Response 认证，防止未配对设备连接：

```
认证流程:
1. Mac → Phone: { "type": "challenge", "nonce": "<random-32-bytes>" }
2. Phone 计算:  response = HMAC-SHA256(sharedSecret, nonce)
3. Phone → Mac: { "type": "auth", "deviceId": "...", "response": "<hmac>" }
4. Mac 验证:
   - deviceId 在已配对列表中
   - HMAC 与本地计算一致
   - 通过 → 连接激活
   - 失败 → 立即断开 + 告警日志
```

`sharedSecret` 是配对时通过 X25519 协商的共享密钥，只有成功配对的设备才拥有。

**防护措施：**

- 认证超时: 连接后 3 秒内未完成认证则断开
- 失败封禁: 同一 IP 连续 5 次认证失败后封禁 10 分钟
- 连接数限制: 最多 5 个并发连接（含未认证的）
- 端口随机: 每次启动使用随机端口，不使用固定端口

### L2: 传输加密（WAN）

WAN 路径强制使用 TLS 1.3：

### L3: 端到端加密

**核心安全保证：即使中继服务器被完全控制，攻击者也无法读取通信内容。**

加密方案：

```
算法: X25519 密钥交换 + ChaCha20-Poly1305 AEAD
密钥长度: 256-bit
Nonce: 96-bit 随机数，每条消息唯一
```

加密流程：

```
配对阶段:
  Mac 生成 X25519 密钥对 (macPriv, macPub)
  Phone 生成 X25519 密钥对 (phonPriv, phonPub)
  通过二维码交换公钥
  双方独立计算: sharedSecret = X25519(myPriv, peerPub)

通信阶段:
  发送方:
    nonce = randomBytes(12)
    ciphertext = ChaCha20Poly1305.encrypt(sharedSecret, nonce, plaintext)
    send(nonce || ciphertext)

  接收方:
    nonce = data[0:12]
    ciphertext = data[12:]
    plaintext = ChaCha20Poly1305.decrypt(sharedSecret, nonce, ciphertext)
```

**服务器看到的全部是密文，无法解密。**

### L4: 设备认证

#### 配对流程

```
1. Mac App 生成:
   - X25519 密钥对
   - 6 位配对码 (字母数字混合)
   - 配对码有效期: 5 分钟

2. Mac 屏幕显示二维码，编码内容:
   {
     "server": "https://your-server.com",
     "pairCode": "A3X92K",
     "macPubKey": "base64...",
     "macDeviceId": "uuid"
   }

3. 手机扫码:
   - 生成自己的 X25519 密钥对
   - 携带 pairCode + phonePubKey 请求服务器

4. 服务器验证:
   - 校验 pairCode 有效且未过期
   - 绑定 Mac 设备 ↔ 手机设备
   - 签发 JWT (有效期 30 天，可续签)
   - 立即销毁 pairCode（一次性使用）

5. 配对完成:
   - 双方用共享密钥通信
   - JWT 用于后续 WebSocket 认证
```

#### 设备管理

```
Mac App 维护已配对设备列表:
- 设备名称、配对时间、最后活跃时间
- 可随时撤销任一设备
- 撤销后服务器立即断开该设备连接，删除绑定关系
```

### L5: 操作权限控制

#### 危险命令拦截

Mac 端在执行远程输入前进行安全检查：

```
高危命令 (拦截 + Mac 端弹窗确认):
- rm -rf / rm -r
- sudo
- curl | sh, wget | sh
- chmod 777
- > /etc/, > ~/.ssh/
- git push --force
- DROP TABLE, DELETE FROM (无 WHERE)
- 包含密钥/token 的命令

中危命令 (Mac 菜单栏通知，不阻断):
- git push
- npm publish
- docker rm
- kill, pkill

低危命令 (直接放行):
- 普通文本输入
- y/n 确认
- /commit, /review 等 Claude Code 命令
```

#### 确认机制

高危指令触发 Mac 端原生弹窗：

```
┌────────────────────────────────┐
│ AirTerm: 远程指令需要确认          │
│                                │
│ 来自: iPhone (已配对)            │
│ 会话: auth 重构 (~/proj-a)      │
│                                │
│ 指令内容:                       │
│ git push --force origin main   │
│                                │
│ ⚠️ 该命令被标记为高危操作         │
│                                │
│      [拒绝]        [允许]       │
└────────────────────────────────┘
```

不操作自动拒绝（超时 60 秒）。

### L6: 会话安全

| 措施     | 说明                                            |
| -------- | ----------------------------------------------- |
| 自动锁定 | 手机端 30 分钟无操作需重新验证                  |
| 会话超时 | WebSocket 空闲 10 分钟自动断开，需重连          |
| JWT 续签 | Token 有效期 30 天，每次活跃时续签              |
| 操作日志 | 所有远程操作记录在 Mac 本地，含时间戳和来源设备 |
| 密钥轮换 | 支持手动重新配对以更换密钥                      |

### L7: 数据库加密

所有持久化数据使用 SQLCipher (AES-256-CBC) 加密。详见 [privacy.md](privacy.md)。

- Mac 端：加密密钥存储在 macOS Keychain，级别为 `WhenUnlockedThisDeviceOnly`
- 服务器端：加密密钥通过环境变量注入，不入库
- 手机端：使用 Web Crypto API，私钥设为 `non-extractable`

## 安全架构总览

```
┌──────────────────────────────────────────────────────────┐
│                      安全分层 (8 层)                       │
│                                                          │
│  L7  数据库加密    SQLCipher + Keychain + WebCrypto       │
│  L6  会话安全      自动锁定 / 操作日志 / 密钥轮换           │
│  L5  权限控制      危险命令拦截 + Mac 弹窗确认              │
│  L4  设备认证      X25519 密钥交换 + 一次性配对码 + SAS    │
│  L3  端到端加密    ChaCha20-Poly1305 + seq/ack 防重放     │
│  L2  传输加密      WAN: 全链路 WSS (TLS 1.3)             │
│  L1  LAN 接入认证  Challenge-Response (HMAC-SHA256)      │
│  L0  通道安全      LAN ws:// + WAN wss:// 混合           │
└──────────────────────────────────────────────────────────┘
```

## 安全检查清单

部署前确认：

- [ ] 服务器已启用 HTTPS，证书有效
- [ ] 禁用 HTTP 明文访问（301 重定向到 HTTPS）
- [ ] JWT 密钥已更换为随机生成值（非默认值）
- [ ] 配对码有效期设置为 5 分钟
- [ ] 高危命令拦截列表已启用
- [ ] 操作日志已启用
- [ ] 服务器未存储任何消息明文
- [ ] 防火墙仅开放 443 端口
- [ ] SQLCipher 加密已启用（用普通 sqlite3 打开应报错）
- [ ] Keychain 使用 WhenUnlockedThisDeviceOnly 级别
- [ ] Web 前端 CSP 头部已配置
- [ ] 速率限制已启用
- [ ] CORS 仅允许指定域名

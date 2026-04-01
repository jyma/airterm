# 隐私与数据安全

## 核心原则：零知识架构

AirTerm 采用零知识（Zero-Knowledge）设计 — 除用户本人外，任何第三方（包括中继服务器运营者）都无法获取用户数据。

```
┌─────────────────────────────────────────────────────────┐
│                    数据可见性矩阵                          │
│                                                         │
│  数据类型          Mac App   中继服务器   手机 Web         │
│  ─────────────────────────────────────────────────       │
│  终端输出内容        ✅        ❌ 密文     ✅              │
│  代码/文件内容       ✅        ❌ 密文     ✅              │
│  输入的指令          ✅        ❌ 密文     ✅              │
│  会话名称           ✅        ❌ 密文     ✅              │
│  项目路径           ✅        ❌ 密文     ✅              │
│  设备 ID           ✅        ✅ 路由用    ✅              │
│  设备公钥           ✅        ✅ 存储     ✅              │
│  消息时间戳         ✅        ✅ 日志     ✅              │
│  IP 地址           ✅        ✅ 连接层    ✅              │
│  E2E 私钥          ✅        ❌          ✅              │
└─────────────────────────────────────────────────────────┘
```

**服务器永远无法看到：你的代码、终端输出、输入的任何指令、项目名称和路径。**

## 数据分类与处理

### 第一类：敏感数据（代码、终端内容、指令）

- 全程端到端加密，服务器只看到密文
- 不在任何位置持久化存储（内存中处理，用完即弃）
- Mac 端操作日志仅记录"操作类型 + 时间"，不记录具体内容

### 第二类：设备元数据（设备 ID、公钥、配对关系）

- 服务器端存储于加密数据库（详见下文）
- 用于消息路由和设备认证
- 用户撤销设备后立即删除

### 第三类：连接元数据（IP、连接时间）

- 服务器访问日志保留 7 天后自动清除
- 不与用户身份关联
- 可配置完全关闭访问日志

## 数据库安全

### Mac 端本地存储

使用 macOS Keychain 和加密 SQLite：

```
┌─────────────────────────────────────────────┐
│              Mac 端存储架构                    │
│                                             │
│  macOS Keychain (系统级加密)                  │
│  ├── E2E 私钥 (X25519)                      │
│  ├── JWT Token                              │
│  └── 数据库加密密钥                            │
│                                             │
│  SQLite + SQLCipher (AES-256-CBC 加密)       │
│  ├── 已配对设备列表                            │
│  ├── 会话历史摘要 (不含终端内容)                │
│  └── 操作审计日志                              │
│                                             │
│  内存中 (不持久化)                             │
│  ├── 终端输出内容                              │
│  ├── 解析后的结构化事件                         │
│  └── 当前活跃会话状态                           │
└─────────────────────────────────────────────┘
```

```swift
// macOS Keychain 存储私钥
import Security

func savePrivateKey(_ key: Data, label: String) throws {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.airterm.e2e",
        kSecAttrAccount as String: label,
        kSecValueData as String: key,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
        throw KeychainError.saveFailed(status)
    }
}

// kSecAttrAccessibleWhenUnlockedThisDeviceOnly:
// - 仅设备解锁时可访问
// - 不会被 iCloud 备份同步
// - 不可迁移到其他设备
```

```swift
// SQLCipher 加密数据库
import SQLCipher

func openDatabase() throws -> OpaquePointer {
    var db: OpaquePointer?
    sqlite3_open(dbPath, &db)

    // 从 Keychain 读取数据库加密密钥
    let dbKey = try loadFromKeychain("db-encryption-key")

    // 设置加密密钥
    sqlite3_key(db, dbKey, Int32(dbKey.count))

    // 加密配置
    sqlite3_exec(db, "PRAGMA cipher_page_size = 4096", nil, nil, nil)
    sqlite3_exec(db, "PRAGMA kdf_iter = 256000", nil, nil, nil)
    sqlite3_exec(db, "PRAGMA cipher_hmac_algorithm = HMAC_SHA512", nil, nil, nil)
    sqlite3_exec(db, "PRAGMA cipher_kdf_algorithm = PBKDF2_HMAC_SHA512", nil, nil, nil)

    return db!
}
```

### 中继服务器存储

服务器存储的数据量极少，但同样需要加密：

```
┌─────────────────────────────────────────────┐
│              服务器存储架构                     │
│                                             │
│  环境变量 (不入库)                             │
│  ├── JWT_SECRET                             │
│  └── DB_ENCRYPTION_KEY                      │
│                                             │
│  SQLite + SQLCipher                         │
│  ├── devices 表                              │
│  │   ├── device_id     TEXT PRIMARY KEY     │
│  │   ├── device_name   TEXT (加密)           │
│  │   ├── public_key    TEXT                 │
│  │   ├── device_type   TEXT (mac|phone)     │
│  │   ├── created_at    INTEGER              │
│  │   └── last_seen_at  INTEGER              │
│  │                                          │
│  ├── pairings 表                             │
│  │   ├── mac_device_id   TEXT               │
│  │   ├── phone_device_id TEXT               │
│  │   ├── created_at      INTEGER            │
│  │   └── revoked_at      INTEGER NULL       │
│  │                                          │
│  └── pending_pairs 表                        │
│      ├── pair_code     TEXT PRIMARY KEY      │
│      ├── mac_device_id TEXT                  │
│      ├── mac_pub_key   TEXT                  │
│      └── expires_at    INTEGER               │
│                                             │
│  不存储的内容:                                 │
│  ├── ❌ 消息内容 (密文也不存储，仅内存转发)       │
│  ├── ❌ E2E 私钥                              │
│  ├── ❌ 终端输出                               │
│  └── ❌ 用户指令                               │
└─────────────────────────────────────────────┘
```

```typescript
// 服务器数据库初始化
import Database from "better-sqlite3"

function initDatabase(dbPath: string, encryptionKey: string): Database.Database {
  const db = new Database(dbPath)

  // SQLCipher 加密
  db.pragma(`key = '${encryptionKey}'`)
  db.pragma("cipher_page_size = 4096")
  db.pragma("kdf_iter = 256000")
  db.pragma("journal_mode = WAL")

  // 建表
  db.exec(`
    CREATE TABLE IF NOT EXISTS devices (
      device_id   TEXT PRIMARY KEY,
      device_name TEXT NOT NULL,
      public_key  TEXT NOT NULL,
      device_type TEXT NOT NULL CHECK (device_type IN ('mac', 'phone')),
      created_at  INTEGER NOT NULL DEFAULT (unixepoch()),
      last_seen_at INTEGER NOT NULL DEFAULT (unixepoch())
    );

    CREATE TABLE IF NOT EXISTS pairings (
      mac_device_id   TEXT NOT NULL REFERENCES devices(device_id),
      phone_device_id TEXT NOT NULL REFERENCES devices(device_id),
      created_at      INTEGER NOT NULL DEFAULT (unixepoch()),
      revoked_at      INTEGER,
      PRIMARY KEY (mac_device_id, phone_device_id)
    );

    CREATE TABLE IF NOT EXISTS pending_pairs (
      pair_code     TEXT PRIMARY KEY,
      mac_device_id TEXT NOT NULL,
      mac_pub_key   TEXT NOT NULL,
      expires_at    INTEGER NOT NULL
    );
  `)

  // 定时清理过期配对码
  db.exec(`
    DELETE FROM pending_pairs WHERE expires_at < unixepoch();
  `)

  return db
}
```

### 手机端 Web 存储

```
┌─────────────────────────────────────────────┐
│              手机 Web 存储                     │
│                                             │
│  IndexedDB (浏览器加密沙箱)                   │
│  ├── E2E 私钥 (CryptoKey, non-extractable)  │
│  └── JWT Token                              │
│                                             │
│  内存中 (标签页关闭即清除)                      │
│  ├── 解密后的消息内容                           │
│  ├── 会话状态                                 │
│  └── 共享密钥 (derived)                       │
│                                             │
│  不使用的存储:                                 │
│  ├── ❌ localStorage (可被 JS 读取)           │
│  ├── ❌ Cookie                               │
│  └── ❌ sessionStorage                       │
└─────────────────────────────────────────────┘
```

```typescript
// Web Crypto API — 私钥不可导出
async function generateKeyPair(): Promise<CryptoKeyPair> {
  return crypto.subtle.generateKey(
    { name: "X25519" },
    false,  // extractable = false，私钥永远无法被 JS 读取
    ["deriveKey", "deriveBits"]
  )
}

// 存储到 IndexedDB
async function saveKeyPair(keyPair: CryptoKeyPair): Promise<void> {
  const db = await openDB("airterm", 1, {
    upgrade(db) {
      db.createObjectStore("keys")
    }
  })
  // 私钥以 CryptoKey 对象存储，non-extractable
  // 即使 XSS 攻击也无法导出私钥原始值
  await db.put("keys", keyPair.privateKey, "e2e-private")
  await db.put("keys", keyPair.publicKey, "e2e-public")
}
```

## 数据生命周期

```
配对阶段:
  配对码 ──► 5 分钟后自动销毁
  公钥   ──► 永久存储（撤销设备时删除）
  私钥   ──► 永久存储在本地 Keychain/IndexedDB

使用阶段:
  终端输出 ──► 内存中加密传输 ──► 手机解密显示 ──► 不存储
  用户指令 ──► 内存中加密传输 ──► Mac 解密执行 ──► 不存储
  操作日志 ──► Mac 本地加密存储 ──► 90 天后自动清理

撤销阶段:
  撤销设备 ──► 服务器立即删除配对关系
           ──► 断开 WebSocket 连接
           ──► Mac 端删除该设备的本地记录
           ──► 手机端清除 IndexedDB

卸载阶段:
  卸载 Mac App ──► 提示是否清除 Keychain 数据
  清除浏览器数据 ──► IndexedDB 自动清除
```

## 防攻击措施

### 服务器端

```typescript
// 速率限制
const rateLimiter = {
  // 配对请求: 每 IP 每分钟最多 5 次
  pair: rateLimit({ windowMs: 60_000, max: 5 }),

  // WebSocket 消息: 每连接每秒最多 50 条
  wsMessage: rateLimit({ windowMs: 1_000, max: 50 }),

  // API 请求: 每 Token 每分钟最多 100 次
  api: rateLimit({ windowMs: 60_000, max: 100 }),
}

// 配对码暴力破解防护
// 6 位字母数字 = 36^6 = 21 亿种组合
// 限速 5次/分钟 → 暴力破解需要 ~800 年
// 加上 5 分钟过期 → 最多尝试 25 次 → 概率 0.0000012%
```

### 中间人攻击防护

```
传输层: TLS 1.3 证书验证
应用层: E2E 加密，密钥通过二维码线下交换
双重保障: 即使 TLS 被破解，E2E 层依然安全
```

### XSS 防护（Web 前端）

```typescript
// 所有来自终端的内容在渲染前进行转义
function sanitizeTerminalOutput(raw: string): string {
  return raw
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;")
}

// CSP 头部配置
// Content-Security-Policy:
//   default-src 'self';
//   script-src 'self';
//   style-src 'self' 'unsafe-inline';
//   connect-src 'self' wss://your-server.com;
//   img-src 'self' data:;
```

## 合规考虑

| 要求 | AirTerm 的做法 |
|------|-----------------|
| 数据最小化 | 服务器仅存储路由所需的最少元数据 |
| 数据本地化 | 所有敏感数据仅存在于用户设备上 |
| 用户控制权 | 用户可随时撤销设备、删除数据 |
| 透明性 | 开源，可自部署，可审计 |
| 知情同意 | 首次使用说明数据处理方式 |

## 安全审计清单

部署前额外确认：

- [ ] SQLCipher 加密已启用（尝试用普通 sqlite3 打开应报错）
- [ ] Keychain 存储使用 `WhenUnlockedThisDeviceOnly` 级别
- [ ] Web 前端 CSP 头部已配置
- [ ] 服务器无任何消息内容日志
- [ ] 速率限制已启用
- [ ] 过期配对码自动清理已启用
- [ ] 操作日志 90 天自动清理已启用
- [ ] CORS 仅允许指定域名

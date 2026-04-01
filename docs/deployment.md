# 部署指南

## 默认方式：使用公共中继实例（零配置）

AirTerm 默认使用官方公共中继实例 `relay.airterm.dev`，**无需自行部署任何服务器**。

安装 Mac App 后即可扫码配对使用。服务器采用零知识架构（E2E 加密），即使是官方实例也无法读取任何通信内容。

如果你需要自主可控或有特殊网络需求，可选择自部署。

---

## 高级选项：自部署中继服务器

### 方式一：Docker（推荐）

#### 1. 准备服务器

最低配置：1 核 CPU、512MB 内存、10GB 磁盘。

AirTerm 服务器只做消息转发，资源消耗极低。

#### 2. 部署

```bash
# 克隆项目
git clone https://github.com/your-org/airterm.git
cd airterm/apps/server

# 配置环境变量
cp .env.example .env
```

编辑 `.env`：

```bash
# 服务器域名
DOMAIN=airterm.your-domain.com

# JWT 密钥（必须更换为随机值）
JWT_SECRET=your-random-secret-at-least-32-chars

# 端口
PORT=3000

# 配对码有效期（秒）
PAIR_CODE_TTL=300

# SQLite 数据库路径
DB_PATH=/data/airterm.db
```

```bash
# 启动
docker compose up -d

# 查看日志
docker compose logs -f
```

#### 3. 配置 HTTPS

使用 Caddy 作为反向代理（自动获取 Let's Encrypt 证书）：

```bash
# Caddyfile
airterm.your-domain.com {
    reverse_proxy localhost:3000
}
```

```bash
# 安装并启动 Caddy
sudo apt install caddy
sudo systemctl enable caddy
sudo systemctl start caddy
```

或使用 Nginx + Certbot：

```nginx
server {
    listen 443 ssl;
    server_name airterm.your-domain.com;

    ssl_certificate /etc/letsencrypt/live/airterm.your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/airterm.your-domain.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400;  # WebSocket 长连接
    }
}
```

### 方式二：直接运行

```bash
cd apps/server
pnpm install
pnpm build
node dist/index.js
```

使用 PM2 保持进程：

```bash
npm install -g pm2
pm2 start dist/index.js --name airterm
pm2 save
pm2 startup  # 开机自启
```

## Docker Compose 配置

```yaml
# apps/server/docker-compose.yml
services:
  airterm:
    build: .
    ports:
      - '3000:3000'
    volumes:
      - airterm-data:/data
    environment:
      - JWT_SECRET=${JWT_SECRET}
      - DB_PATH=/data/airterm.db
      - PAIR_CODE_TTL=300
    restart: unless-stopped
    healthcheck:
      test: ['CMD', 'curl', '-f', 'http://localhost:3000/health']
      interval: 30s
      timeout: 5s
      retries: 3

volumes:
  airterm-data:
```

```dockerfile
# apps/server/Dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN npm install -g pnpm && pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./

EXPOSE 3000
CMD ["node", "dist/index.js"]
```

## Mac 应用安装

### Homebrew（推荐）

```bash
brew install --cask airterm
```

安装后在菜单栏点击 AirTerm 图标 → "配对新设备" → 手机扫码即可使用。无需配置服务器地址（默认使用公共实例）。

### 直接下载

从 GitHub Releases 下载 `AirTerm.dmg`，拖到 /Applications。

### 开发阶段

```bash
cd apps/mac
open AirTerm.xcodeproj
# Xcode 中 Build & Run
```

## 验证部署

### 1. 检查服务器

```bash
# 健康检查
curl https://airterm.your-domain.com/health
# 应返回: {"status":"ok"}

# WebSocket 连接测试
wscat -c wss://airterm.your-domain.com/ws/mac
```

### 2. 检查 Mac 应用

- 菜单栏出现 AirTerm 图标
- 点击图标打开面板，可新建终端会话
- 在内置终端中输入 `claude`，正常启动
- 状态显示「已连接服务器」（默认 `relay.airterm.dev`）
- 可选: 设置中授予辅助功能权限后，可看到外部终端中的 claude 会话

### 3. 检查手机访问

- 扫描配对二维码
- Web 页面正常加载
- 能看到会话列表

## 监控

### 服务器日志

```bash
# Docker
docker compose logs -f airterm

# PM2
pm2 logs airterm
```

### 关键指标

| 指标             | 正常范围 | 告警阈值           |
| ---------------- | -------- | ------------------ |
| WebSocket 连接数 | 1-10     | > 100 (可能被攻击) |
| 内存使用         | < 50MB   | > 200MB            |
| CPU 使用         | < 5%     | > 50%              |
| 消息转发延迟     | < 50ms   | > 500ms            |

## 备份

仅需备份 SQLite 数据库（设备配对信息）：

```bash
# 定时备份
0 3 * * * cp /data/airterm.db /backup/airterm-$(date +%Y%m%d).db
```

消息不存储，无需备份。

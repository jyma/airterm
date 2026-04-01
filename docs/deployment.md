# 部署指南

## 中继服务器部署

### 方式一：Docker（推荐）

#### 1. 准备服务器

最低配置：1 核 CPU、512MB 内存、10GB 磁盘。

Herald 服务器只做消息转发，资源消耗极低。

#### 2. 部署

```bash
# 克隆项目
git clone https://github.com/your-org/herald.git
cd herald/apps/server

# 配置环境变量
cp .env.example .env
```

编辑 `.env`：

```bash
# 服务器域名
DOMAIN=herald.your-domain.com

# JWT 密钥（必须更换为随机值）
JWT_SECRET=your-random-secret-at-least-32-chars

# 端口
PORT=3000

# 配对码有效期（秒）
PAIR_CODE_TTL=300

# SQLite 数据库路径
DB_PATH=/data/herald.db
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
herald.your-domain.com {
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
    server_name herald.your-domain.com;

    ssl_certificate /etc/letsencrypt/live/herald.your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/herald.your-domain.com/privkey.pem;

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
pm2 start dist/index.js --name herald
pm2 save
pm2 startup  # 开机自启
```

## Docker Compose 配置

```yaml
# apps/server/docker-compose.yml
services:
  herald:
    build: .
    ports:
      - "3000:3000"
    volumes:
      - herald-data:/data
    environment:
      - JWT_SECRET=${JWT_SECRET}
      - DB_PATH=/data/herald.db
      - PAIR_CODE_TTL=300
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 5s
      retries: 3

volumes:
  herald-data:
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

## Mac 应用分发

### 开发阶段

Xcode 直接 Build & Run 即可。

### 正式分发

两种方式：

#### 1. 直接分发 `.app`

```bash
# Xcode 中: Product → Archive → Distribute App → Copy App
# 生成 Herald.app，拷贝到 /Applications
```

#### 2. Homebrew Cask（未来）

```bash
brew install --cask herald
```

## 验证部署

### 1. 检查服务器

```bash
# 健康检查
curl https://herald.your-domain.com/health
# 应返回: {"status":"ok"}

# WebSocket 连接测试
wscat -c wss://herald.your-domain.com/ws/mac
```

### 2. 检查 Mac 应用

- 菜单栏出现 Herald 图标
- 点击图标能看到已发现的 claude 进程
- 状态显示「已连接服务器」

### 3. 检查手机访问

- 扫描配对二维码
- Web 页面正常加载
- 能看到会话列表

## 监控

### 服务器日志

```bash
# Docker
docker compose logs -f herald

# PM2
pm2 logs herald
```

### 关键指标

| 指标 | 正常范围 | 告警阈值 |
|------|---------|---------|
| WebSocket 连接数 | 1-10 | > 100 (可能被攻击) |
| 内存使用 | < 50MB | > 200MB |
| CPU 使用 | < 5% | > 50% |
| 消息转发延迟 | < 50ms | > 500ms |

## 备份

仅需备份 SQLite 数据库（设备配对信息）：

```bash
# 定时备份
0 3 * * * cp /data/herald.db /backup/herald-$(date +%Y%m%d).db
```

消息不存储，无需备份。

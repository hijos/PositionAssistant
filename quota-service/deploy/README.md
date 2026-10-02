# 额度子服务 Docker 部署

这个部署包运行公开 GHCR 镜像中的独立额度服务。服务器只需要安装 Docker Engine 和 Docker Compose plugin，不需要安装 Node.js。镜像目标平台为 `linux/amd64`。

## 首次部署

在服务器上进入本目录，复制环境变量模板：

```bash
cp .env.example .env
```

编辑 `.env`：

- `QUOTA_IMAGE` 改成 GitHub Actions 推送的公开镜像地址；
- `QUOTA_ADMIN_PASSWORD` 设置至少 8 个字符的管理员密码；
- `QUOTA_IP_HASH_SALT` 设置随机字符串；
- `QUOTA_BIND_HOST` 默认是 `127.0.0.1`，适合由本机反向代理转发；需要直接对外监听时再改成 `0.0.0.0`；
- `QUOTA_CORS_ORIGIN` 按实际 Web 来源配置，纯 Android 客户端可以按部署方式设置。

启动并检查健康状态：

```bash
docker compose pull
docker compose up -d
docker compose ps
curl http://127.0.0.1:4100/health
```

健康检查返回类似以下内容时，服务已经启动：

```json
{"ok":true,"service":"quota-service","version":75}
```

公开 GHCR 镜像不需要服务器登录。若 GitHub Packages 中首次发布的包仍显示为私有，请在包的设置中把可见性改为 Public。

## 数据持久化

额度和费率的初始数据已经打进镜像。容器第一次启动时，会把镜像中的种子复制到 `/app/data/db.json`；Compose 的 `quota_data` named volume 会持久化这个文件。

之后的管理员修改、用户纠错、审计和撤销都会写入这个卷。重新拉取镜像或重建容器不会覆盖已有数据。

备份当前运行数据：

```bash
docker compose exec -T quota-service sh -c 'cat /app/data/db.json' > quota-db-backup-$(date +%F).json
```

不要使用 `docker compose down -v`，它会删除 `quota_data` 及其中的额度数据。需要重新使用镜像种子初始化时，先备份数据，再明确删除 named volume：

```bash
docker compose down
docker volume ls | grep quota_data
docker volume rm <实际的_quota_data_卷名>
docker compose up -d
```

## 更新镜像

GitHub Actions 会在代码推送到默认分支或手动触发时生成新镜像。更新服务器上的版本：

```bash
docker compose pull
docker compose up -d
docker compose ps
```

如果使用固定版本标签，先修改 `.env` 中的 `QUOTA_IMAGE`，再执行上述命令。已有 `quota_data` 卷会继续使用，镜像里的种子只对新的空卷生效。

## 访问管理页面

服务管理页面位于：

```text
http://服务器地址:4100/
```

生产环境的域名、HTTPS 和反向代理由部署方配置。反向代理与服务在同一台服务器时，保持 `QUOTA_BIND_HOST=127.0.0.1` 即可。

## 初始种子更新

开发工作区仍保留原始数据文件时，可以重新生成不含历史纠错和审计的种子：

```bash
npm run quota:seed
npm run quota:seed:check
```

提交 `quota-service/seed.json` 后，GitHub Actions 会把它打进下一版镜像。已有服务器卷不会自动替换；需要更新现有数据时，应先备份并按业务需要通过管理页面修改或执行受控的数据迁移。

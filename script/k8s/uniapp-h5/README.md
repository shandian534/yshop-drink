# YShop UniApp H5 部署指南

## 概述

本目录包含 YShop UniApp 项目 H5 版本的 K8s 部署配置和脚本。

## 目录结构

```
script/k8s/
├── uniapp-h5/              # UniApp H5 构建配置
│   ├── Dockerfile         # Docker 构建文件
│   ├── nginx.conf         # Nginx 配置
│   ├── vite.config.js     # Vite 构建配置
│   ├── package.json       # 构建依赖
│   └── .dockerignore      # Docker 忽略文件
├── deploy-uniapp-h5.sh    # 部署脚本
├── 10-uniapp-h5.yaml      # K8s 部署配置
└── 08-ingress.yaml        # Ingress 配置（已更新）
```

## 前置要求

- Docker 运行环境
- kubectl 命令行工具
- 可访问的 K8s 集群
- Harbor 镜像仓库访问权限

## 快速开始

### 1. 完整部署（推荐）

```bash
cd script/k8s

# 自动查找并构建 UniApp 项目，然后部署到 K8s
./deploy-uniapp-h5.sh full
```

### 2. 仅构建镜像

```bash
# 仅构建并推送镜像到 Harbor
./deploy-uniapp-h5.sh build
```

### 3. 仅部署

```bash
# 使用已有镜像部署到 K8s
./deploy-uniapp-h5.sh deploy
```

## 配置说明

### 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `NAMESPACE` | K8s 命名空间 | `yshop` |
| `UNIAPP_IMAGE_TAG` | 镜像标签 | 自动生成时间戳 |
| `HARBOR_ADDRESS` | Harbor 地址 | `192.168.2.254:30002` |
| `HARBOR_ACCOUNT` | Harbor 账号 | `admin` |
| `UNIAPP_PROJECT_PATH` | UniApp 项目路径 | 自动查找 |

### 使用示例

```bash
# 使用自定义镜像标签
UNIAPP_IMAGE_TAG=v1.0.0 ./deploy-uniapp-h5.sh full

# 指定 UniApp 项目路径
UNIAPP_PROJECT_PATH=/path/to/uniapp ./deploy-uniapp-h5.sh full

# 使用自定义 Harbor 配置
HARBOR_ADDRESS=your-harbor.com \
HARBOR_ACCOUNT=your-account \
HARBOR_PASSWORD=your-password \
./deploy-uniapp-h5.sh full
```

## 访问方式

部署完成后，可以通过以下方式访问 UniApp H5：

### 方式 1: Ingress（需要配置 hosts）

```bash
# 添加 hosts 记录
echo "192.168.x.x h5.yshop.local" >> /etc/hosts

# 访问
http://h5.yshop.local
```

### 方式 2: PortForward

```bash
kubectl port-forward svc/yshop-uniapp-h5 8080:80 -n yshop

# 访问
http://localhost:8080/h5/
```

### 方式 3: 查看状态

```bash
# 查看 Pod 状态
kubectl get pods -n yshop -l app=yshop-uniapp-h5

# 查看日志
kubectl logs -f -l app=yshop-uniapp-h5 -n yshop

# 查看部署状态
./deploy-uniapp-h5.sh status
```

## 路由配置

UniApp H5 的路由基础路径配置为 `/h5/`（在 `manifest.json` 中配置）：

```json
{
  "h5": {
    "router": {
      "base": "/h5/"
    }
  }
}
```

因此，访问路径需要包含 `/h5/` 前缀：
- Ingress: `http://h5.yshop.local/h5/`
- PortForward: `http://localhost:8080/h5/`

如需修改，请同步更新：
1. `yshop-drink-uniapp-vue3/manifest.json`
2. `script/k8s/uniapp-h5/nginx.conf`

## 常见问题

### 1. 构建失败

**问题**: 构建过程中出现依赖安装错误

**解决**:
- 检查网络连接，确保可以访问 npm 镜像源
- 尝试手动安装依赖: `cd yshop-drink-uniapp-vue3 && pnpm install`

### 2. Pod 无法启动

**问题**: Pod 状态为 CrashLoopBackOff

**解决**:
```bash
# 查看 Pod 日志
kubectl logs -f <pod-name> -n yshop

# 检查镜像是否成功推送
docker images | grep yshop-uniapp-h5
```

### 3. 访问 404

**问题**: 访问 H5 页面返回 404

**解决**:
- 确认访问路径包含 `/h5/` 前缀
- 检查 nginx 配置中的路由规则
- 验证 manifest.json 中的路由配置

## 手动构建

如果需要手动构建而不使用脚本：

```bash
# 1. 进入 UniApp 项目目录
cd yshop-drink-uniapp-vue3

# 2. 安装依赖（如果还没有）
pnpm install

# 3. 构建 H5 版本
pnpm build:h5

# 4. 构建产物在 dist/build/h5 目录

# 5. 使用 Dockerfile 构建镜像
cd script/k8s/uniapp-h5
docker build -t yshop-uniapp-h5:latest .
```

## 相关文件

- [UniApp H5 官方文档](https://uniapp.dcloud.net.cn/tutorial/h5.html)
- [Vite 构建配置](https://vitejs.dev/)
- [Nginx 配置参考](https://nginx.org/en/docs/)

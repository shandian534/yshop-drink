# YShop K8s 部署指南

本文档说明如何使用K8s部署YShop系统。

## 目录结构

```
script/k8s/
├── 00-namespace.yaml              # 命名空间配置
├── 01-mysql-secret.yaml           # MySQL密钥配置
├── 02-mysql-pvc.yaml              # MySQL持久化存储
├── 03-mysql.yaml                  # MySQL部署和服务
├── 04-redis-pvc.yaml              # Redis持久化存储
├── 05-redis.yaml                  # Redis部署和服务
├── 06-server-configmap.yaml       # 后端服务配置
├── 07-server.yaml                 # 后端服务部署
├── 08-ingress.yaml                # Ingress配置（外部访问）
├── build-and-push.sh              # 镜像构建和推送脚本
├── deploy.sh                      # K8s部署脚本
└── README.md                      # 本文档
```

## 前置要求

1. **K8s集群**: 已配置并可访问的Kubernetes集群
2. **kubectl**: 已安装并配置好kubeconfig
3. **Docker**: 已安装并运行
4. **容器镜像仓库**: 可选，默认使用本地私有仓库

## 快速开始

### 1. 准备镜像仓库

#### 选项A: 使用本地私有仓库（默认）

```bash
# 启动本地私有仓库
docker run -d -p 5000:5000 --name registry registry:2

# 配置Docker允许http（仅用于开发环境）
# 编辑 /etc/docker/daemon.json 添加:
# { "insecure-registries": ["localhost:5000"] }

# 重启Docker
sudo systemctl restart docker  # Linux
# 或在Docker Desktop中重启
```

#### 选项B: 使用云端镜像仓库

```bash
# 使用阿里云、腾讯云、Harbor等
export REGISTRY="your-registry.com"
export IMAGE_NAME="yshop-server"
export IMAGE_TAG="v1.0.0"
```

### 2. 构建和推送镜像

```bash
# 在项目根目录执行
./script/k8s/build-and-push.sh

# 或指定自定义仓库
REGISTRY=myregistry.com IMAGE_TAG=v1.0.0 ./script/k8s/build-and-push.sh
```

### 3. 部署到K8s

```bash
# 完整部署（推荐）
./script/k8s/deploy.sh all

# 或分步部署
./script/k8s/deploy.sh infra    # 仅基础设施（MySQL、Redis）
./script/k8s/deploy.sh server   # 仅后端服务
./script/k8s/deploy.sh ingress  # 仅Ingress
```

### 4. 验证部署

```bash
# 查看部署状态
./script/k8s/deploy.sh status

# 查看服务日志
./script/k8s/deploy.sh logs

# 或使用kubectl
kubectl get pods -n yshop
kubectl get svc -n yshop
kubectl logs -f -l app=yshop-server -n yshop
```

## 配置说明

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| NAMESPACE | yshop | K8s命名空间 |
| REGISTRY | localhost:5000 | 镜像仓库地址 |
| IMAGE_NAME | yshop-server | 镜像名称 |
| IMAGE_TAG | latest | 镜像标签 |

### 访问服务

#### 方式1: Ingress（推荐）

```bash
# 配置hosts或DNS
echo "<K8s节点IP> api.yshop.local" | sudo tee -a /etc/hosts

# 访问API
curl http://api.yshop.local
```

#### 方式2: NodePort

```bash
# 修改Service类型为NodePort
kubectl patch svc yshop-server -n yshop -p '{"spec":{"type":"NodePort"}}'

# 查看端口
kubectl get svc yshop-server -n yshop

# 访问
curl http://<节点IP>:<NodePort>
```

#### 方式3: Port Forward

```bash
# 本地转发
kubectl port-forward svc/yshop-server 48080:48080 -n yshop

# 访问
curl http://localhost:48080
```

## 资源配置

默认资源配置可根据实际需求调整：

| 组件 | 内存请求 | 内存限制 | CPU请求 | CPU限制 |
|------|----------|----------|---------|---------|
| MySQL | 512Mi | 1Gi | 250m | 500m |
| Redis | 128Mi | 256Mi | 100m | 200m |
| Server | 512Mi | 1Gi | 250m | 500m |

## 持久化存储

- **MySQL**: 10Gi PVC，可调整
- **Redis**: 2Gi PVC，可调整

根据集群配置，可能需要配置StorageClass。

## 故障排查

### Pod无法启动

```bash
# 查看Pod状态
kubectl get pods -n yshop

# 查看事件
kubectl describe pod <pod-name> -n yshop

# 查看日志
kubectl logs <pod-name> -n yshop
```

### 镜像拉取失败

```bash
# 确认镜像已推送
docker images | grep yshop-server

# 检查镜像拉取密钥（如果使用私有仓库）
kubectl create secret docker-registry regcred \
  --docker-server=<registry> \
  --docker-username=<username> \
  --docker-password=<password> \
  -n yshop
```

### 数据库连接失败

```bash
# 检查MySQL是否就绪
kubectl get pods -l app=mysql -n yshop

# 进入Pod测试连接
kubectl exec -it <mysql-pod> -n yshop -- mysql -uroot -p123456
```

## 清理资源

```bash
# 完全清理
./script/k8s/deploy.sh cleanup

# 或手动清理
kubectl delete namespace yshop
```

## 生产环境建议

1. **镜像仓库**: 使用稳定的私有镜像仓库
2. **密钥管理**: 使用外部密钥管理系统（如Vault、KMS）
3. **数据库**: 使用托管数据库服务（RDS、云数据库）
4. **监控**: 部署Prometheus+Grafana监控
5. **日志**: 使用ELK或Loki收集日志
6. **备份**: 配置数据库定期备份
7. **高可用**: 增加副本数，配置Pod反亲和性
8. **安全策略**: 配置NetworkPolicy、PodSecurityPolicy
9. **证书**: 使用cert-manager管理HTTPS证书

## 常见问题

**Q: 如何更新应用？**
```bash
# 构建新镜像
./script/k8s/build-and-push.sh

# 更新部署
kubectl set image deployment/yshop-server yshop-server=<new-image> -n yshop

# 或重新部署
./script/k8s/deploy.sh server
```

**Q: 如何扩缩容？**
```bash
# 扩容到3个副本
kubectl scale deployment yshop-server --replicas=3 -n yshop
```

**Q: 如何回滚？**
```bash
# 查看历史
kubectl rollout history deployment/yshop-server -n yshop

# 回滚到上一版本
kubectl rollout undo deployment/yshop-server -n yshop

# 回滚到指定版本
kubectl rollout undo deployment/yshop-server --to-revision=2 -n yshop
```

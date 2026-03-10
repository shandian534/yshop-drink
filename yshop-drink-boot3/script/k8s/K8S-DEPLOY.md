# YShop K8s 一键部署指南

## 🚀 快速开始

### 方式一：在服务器上直接执行

```bash
# 1. 上传项目到服务器（在本地执行）
scp -r yshop-drink-boot3 root@192.168.2.254:/root/

# 2. 登录服务器并执行一键部署（在服务器上执行）
ssh root@192.168.2.254
cd /root/yshop-drink-boot3
./deploy-to-k8s.sh
```

### 方式二：从本地执行远程部署

```bash
# 在本地执行（需要配置SSH免密登录）
ssh root@192.168.2.254 'bash -s' < yshop-drink-boot3/deploy-to-k8s.sh
```

---

## ⚙️ 自定义配置

### 使用环境变量覆盖默认配置

```bash
# 自定义镜像标签
IMAGE_TAG=v1.0.0 ./deploy-to-k8s.sh

# 自定义命名空间
NAMESPACE=production ./deploy-to-k8s.sh

# 完整自定义
HARBOR_ADDRESS=192.168.2.254:30002 \
HARBOR_ACCOUNT=admin \
HARBOR_PASSWORD=your-password \
HARBOR_PROJECT_NAME=ruoyi-vue-pro \
NAMESPACE=yshop \
IMAGE_NAME=yshop-server \
IMAGE_TAG=v1.0.0 \
./deploy-to-k8s.sh
```

---

## 📋 部署流程说明

脚本会自动执行以下步骤：

| 步骤 | 操作 | 说明 |
|------|------|------|
| 1 | 环境检查 | 检查Docker、kubectl、项目文件 |
| 2 | 登录Harbor | 使用配置的账号登录Harbor镜像仓库 |
| 3 | 构建JAR包 | 使用Maven Docker容器构建项目 |
| 4 | 构建镜像 | 构建Docker镜像并推送到Harbor |
| 5 | 创建命名空间 | 创建K8s命名空间（如不存在） |
| 6 | 创建拉取密钥 | 创建Harbor镜像拉取Secret |
| 7 | 部署MySQL | 部署MySQL数据库 |
| 8 | 部署Redis | 部署Redis缓存 |
| 9 | 部署后端服务 | 部署yshop-server应用 |
| 10 | 部署Ingress | 配置外部访问 |
| 11 | 验证部署 | 显示部署状态和访问方式 |

---

## 🔍 验证部署

部署完成后，使用以下命令验证：

```bash
# 查看Pod状态
kubectl get pods -n yshop

# 查看服务状态
kubectl get svc -n yshop

# 查看日志
kubectl logs -f -l app=yshop-server -n yshop

# 查看Ingress
kubectl get ingress -n yshop
```

---

## 🌐 访问应用

### 方式1: Ingress（推荐）

```bash
# 配置hosts
echo "192.168.2.254 api.yshop.local" >> /etc/hosts

# 访问
curl http://api.yshop.local
```

### 方式2: Port Forward

```bash
# 端口转发
kubectl port-forward svc/yshop-server 48081:48081 -n yshop

# 访问
curl http://localhost:48081
```

### 方式3: NodePort

```bash
# 修改Service类型
kubectl patch svc yshop-server -n yshop -p '{"spec":{"type":"NodePort"}}'

# 查看端口
kubectl get svc yshop-server -n yshop

# 访问
curl http://192.168.2.254:<NodePort>
```

---

## 🔧 常用运维命令

```bash
# 重新部署
kubectl rollout restart deployment/yshop-server -n yshop

# 扩容
kubectl scale deployment yshop-server --replicas=3 -n yshop

# 查看历史版本
kubectl rollout history deployment/yshop-server -n yshop

# 回滚到上一版本
kubectl rollout undo deployment/yshop-server -n yshop

# 进入Pod
kubectl exec -it <pod-name> -n yshop -- /bin/bash

# 查看事件
kubectl get events -n yshop --sort-by='.lastTimestamp'
```

---

## 🧹 清理资源

```bash
# 删除命名空间（清理所有资源）
kubectl delete namespace yshop

# 仅删除应用
kubectl delete deployment yshop-server -n yshop
```

---

## ⚠️ 故障排查

### Pod无法启动

```bash
# 查看Pod详情
kubectl describe pod <pod-name> -n yshop

# 查看日志
kubectl logs <pod-name> -n yshop
```

### 镜像拉取失败

```bash
# 检查Secret是否存在
kubectl get secret harbor-registry -n yshop

# 检查镜像是否存在
docker images | grep yshop-server
```

### 健康检查失败

```bash
# 检查应用是否启用actuator端点
# 在application.yml中添加:
# management:
#   endpoints:
#     web:
#       exposure:
#         include: health,readiness
```

---

## 📊 配置文件位置

```
script/k8s/
├── 00-namespace.yaml              # 命名空间
├── 01-mysql-secret.yaml           # MySQL密钥
├── 02-mysql-pvc.yaml              # MySQL存储
├── 03-mysql.yaml                  # MySQL部署
├── 04-redis-pvc.yaml              # Redis存储
├── 05-redis.yaml                  # Redis部署
├── 06-server-configmap.yaml       # 后端配置
├── 07-server.yaml                 # 后端服务
├── 08-ingress.yaml                # Ingress配置
├── 00-setup-harbor-secret.sh      # Harbor密钥配置
├── build-and-push.sh              # 镜像构建脚本
├── deploy.sh                      # 部署脚本
└── README.md                      # 详细文档
```

---

## 📝 注意事项

1. **首次部署**：确保Harbor中已创建 `ruoyi-vue-pro` 项目
2. **网络访问**：确保K8s节点能访问Harbor地址
3. **存储类**：根据集群配置调整StorageClass
4. **健康检查**：确保应用启用了actuator端点
5. **资源限制**：根据实际需求调整CPU和内存配置

---

## 🎯 默认配置

| 配置项 | 默认值 |
|--------|--------|
| Harbor地址 | 192.168.2.254:30002 |
| Harbor账号 | admin |
| Harbor项目 | ruoyi-vue-pro |
| 命名空间 | yshop |
| 镜像名称 | yshop-server |
| 镜像标签 | latest |

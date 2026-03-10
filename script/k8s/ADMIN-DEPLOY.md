# 前端管理界面部署指南

## 概述

YShop系统包含前端管理界面（Vue3），需要单独构建和部署。

---

## 📋 前置条件

### 方式一：使用已有前端镜像

如果您已经构建了前端镜像，可以直接修改配置文件：

```bash
# 编辑前端部署配置
vi yshop-drink/script/k8s/09-admin.yaml

# 修改镜像地址
image: 192.168.2.254:30002/ruoyi-vue-pro/yshop-admin:latest
```

### 方式二：从源码构建

需要前端项目源码（通常是独立仓库）。

---

## 🚀 部署方式

### 方式一：使用已构建的镜像（推荐）

1. **准备前端镜像**
   ```bash
   # 推送前端镜像到Harbor
   docker tag yshop-admin:latest 192.168.2.254:30002/ruoyi-vue-pro/yshop-admin:latest
   docker push 192.168.2.254:30002/ruoyi-vue-pro/yshop-admin:latest
   ```

2. **部署前端**
   ```bash
   cd /root/yshop-drink/script/k8s
   kubectl apply -f 09-admin.yaml
   ```

3. **验证部署**
   ```bash
   kubectl get pods -n yshop | grep admin
   kubectl get svc -n yshop | grep admin
   ```

### 方式二：从源码构建

如果前端项目在独立仓库：

1. **克隆前端项目**
   ```bash
   cd /root
   git clone <前端仓库地址> yshop-ui-admin
   ```

2. **构建前端**
   ```bash
   cd yshop-ui-admin

   # 安装依赖
   npm install

   # 构建生产版本
   npm run build

   # 构建Docker镜像
   docker build -t 192.168.2.254:30002/ruoyi-vue-pro/yshop-admin:latest .

   # 推送到Harbor
   docker push 192.168.2.254:30002/ruoyi-vue-pro/yshop-admin:latest
   ```

3. **部署到K8s**
   ```bash
   cd /root/yshop-drink/script/k8s
   kubectl apply -f 09-admin.yaml
   ```

---

## 🌐 访问前端

### 方式1: Ingress（推荐）

```bash
# 配置hosts
echo "192.168.2.254 admin.yshop.local" >> /etc/hosts

# 访问
浏览器打开: http://admin.yshop.local
```

### 方式2: Port Forward

```bash
# 端口转发
kubectl port-forward svc/yshop-admin 8080:80 -n yshop

# 访问
浏览器打开: http://localhost:8080
```

### 方式3: NodePort

```bash
# 修改Service类型
kubectl patch svc yshop-admin -n yshop -p '{"spec":{"type":"NodePort"}}'

# 查看端口
kubectl get svc yshop-admin -n yshop

# 访问
浏览器打开: http://192.168.2.254:<NodePort>
```

---

## ⚙️ 前端配置

前端需要配置后端API地址，通常在构建时设置：

### 环境变量配置

构建时传入环境变量：

```bash
# 构建时设置API地址
npm run build -- --base-api=/prod-api
```

### Dockerfile示例

```dockerfile
# 构建阶段
FROM node:18-alpine as builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

# 运行阶段
FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

### nginx.conf示例

```nginx
server {
    listen 80;
    server_name localhost;
    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # API代理到后端
    location /prod-api/ {
        proxy_pass http://yshop-server.yshop.svc.cluster.local:48081/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

---

## 📝 注意事项

1. **API地址配置**：确保前端能正确访问后端API
   - Ingress环境：使用 `http://api.yshop.local`
   - 集群内部：使用 `http://yshop-server.yshop.svc.cluster.local:48081`

2. **跨域问题**：前后端分离需要配置CORS或使用nginx代理

3. **镜像拉取**：确保K8s节点能访问Harbor仓库

4. **健康检查**：确保前端服务正常响应 `/` 路径

---

## 🔧 故障排查

### Pod无法启动

```bash
# 查看Pod状态
kubectl get pods -n yshop | grep admin

# 查看日志
kubectl logs <pod-name> -n yshop

# 查看事件
kubectl describe pod <pod-name> -n yshop
```

### 无法访问后端API

1. 检查前端配置的API地址是否正确
2. 检查后端Service是否正常
3. 检查网络策略是否允许访问

---

## 📦 完整部署示例

```bash
# 1. 构建并推送前端镜像
cd yshop-ui-admin
docker build -t 192.168.2.254:30002/ruoyi-vue-pro/yshop-admin:v1.0.0 .
docker push 192.168.2.254:30002/ruoyi-vue-pro/yshop-admin:v1.0.0

# 2. 更新K8s配置中的镜像版本
cd /root/yshop-drink/script/k8s
kubectl set image deployment/yshop-admin \
  yshop-admin=192.168.2.254:30002/ruoyi-vue-pro/yshop-admin:v1.0.0 \
  -n yshop

# 3. 验证部署
kubectl get pods -n yshop -w
```

---

## 🎯 默认配置

| 配置项 | 默认值 |
|--------|--------|
| 镜像 | 192.168.2.254:30002/ruoyi-vue-pro/yshop-admin:latest |
| 副本数 | 1 |
| 内存限制 | 256Mi |
| CPU限制 | 200m |
| 访问地址 | http://admin.yshop.local |

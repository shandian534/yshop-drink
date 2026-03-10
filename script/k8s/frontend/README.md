# 前端管理界面构建指南

本目录包含YShop前端管理界面的Docker构建模板。

---

## 📁 文件说明

| 文件 | 说明 |
|------|------|
| `Dockerfile` | 多阶段构建配置（Node构建 + Nginx运行） |
| `nginx.conf` | Nginx配置文件 |
| `.dockerignore` | Docker构建忽略文件 |
| `build.sh` | 镜像构建和推送脚本 |

---

## 🚀 快速开始

### 方式一：使用build.sh脚本（推荐）

```bash
# 在前端项目根目录执行
FRONTEND_PATH=/path/to/yshop-ui-admin \
IMAGE_TAG=v1.0.0 \
/path/to/script/k8s/frontend/build.sh
```

### 方式二：手动构建

```bash
# 1. 复制文件到前端项目目录
cp Dockerfile nginx.conf .dockerignore /path/to/yshop-ui-admin/

# 2. 进入前端项目目录
cd /path/to/yshop-ui-admin

# 3. 构建镜像
docker build -t 192.168.2.254:30002/ruoyi-vue-pro/yshop-admin:latest .

# 4. 推送镜像
docker login 192.168.2.254:30002
docker push 192.168.2.254:30002/ruoyi-vue-pro/yshop-admin:latest
```

---

## ⚙️ 配置说明

### 构建参数

可以通过 `--build-arg` 传递构建参数：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| NODE_ENV | production | 运行环境 |
| PUBLIC_PATH | / | 公共路径 |
| VUE_APP_TITLE | 意象商城管理系统 | 应用标题 |
| VUE_APP_BASE_API | /prod-api | API基础路径 |
| VUE_APP_TENANT_ENABLE | true | 是否启用租户 |
| VUE_APP_CAPTCHA_ENABLE | true | 是否启用验证码 |
| VUE_APP_DOC_ENABLE | true | 是否启用文档 |

**示例：**

```bash
docker build \
  --build-arg VUE_APP_TITLE="我的商城" \
  --build-arg VUE_APP_BASE_API="/api" \
  -t yshop-admin:latest .
```

### Nginx配置

`nginx.conf` 中的关键配置：

1. **前端路由**：支持Vue Router history模式
2. **API代理**：将 `/prod-api/` 请求代理到后端服务
3. **静态资源缓存**：js/css等资源缓存1年
4. **Gzip压缩**：启用响应压缩

---

## 📦 部署到K8s

构建完成后，使用部署脚本部署：

```bash
# 使用默认镜像部署
cd /root/yshop-drink-boot3/script/k8s
./deploy-admin-only.sh

# 或指定镜像
./deploy-admin-only.sh --image 192.168.2.254:30002/ruoyi-vue-pro/yshop-admin:v1.0.0
```

---

## 🔧 常见问题

### Q: 如何修改后端API地址？

**方式1：构建时指定**
```bash
docker build --build-arg VUE_APP_BASE_API="http://api.example.com" -t yshop-admin .
```

**方式2：修改nginx.conf的proxy_pass**
```nginx
location /prod-api/ {
    proxy_pass http://your-backend-server:48081/;
    ...
}
```

### Q: 如何本地测试构建？

```bash
# 构建镜像
docker build -t yshop-admin:test .

# 运行容器
docker run -d -p 8080:80 --name yshop-admin-test yshop-admin:test

# 访问
open http://localhost:8080
```

### Q: 如何调试构建问题？

```bash
# 进入构建阶段容器
docker run --rm -it --entrypoint sh node:18-alpine

# 查看构建日志
docker build --no-cache --progress=plain -t yshop-admin .
```

---

## 📝 注意事项

1. **Node版本**：默认使用Node 18，根据项目需要修改Dockerfile
2. **npm镜像**：已配置国内镜像加速，如需修改请编辑Dockerfile
3. **构建缓存**：首次构建较慢，后续构建会利用缓存
4. **镜像大小**：使用alpine基础镜像，最终镜像约50MB

---

## 🎯 完整示例

```bash
# 1. 克隆前端项目（如果需要）
git clone <frontend-repo> yshop-ui-admin
cd yshop-ui-admin

# 2. 复制构建文件
cp /root/yshop-drink/script/k8s/frontend/Dockerfile .
cp /root/yshop-drink/script/k8s/frontend/nginx.conf .
cp /root/yshop-drink/script/k8s/frontend/.dockerignore .

# 3. 构建并推送
docker build -t 192.168.2.254:30002/ruoyi-vue-pro/yshop-admin:v1.0.0 .
docker push 192.168.2.254:30002/ruoyi-vue-pro/yshop-admin:v1.0.0

# 4. 部署到K8s
cd /root/yshop-drink/script/k8s
./deploy-admin-only.sh --image 192.168.2.254:30002/ruoyi-vue-pro/yshop-admin:v1.0.0

# 5. 配置hosts并访问
echo "192.168.2.254 admin.yshop.local" >> /etc/hosts
# 浏览器打开 http://admin.yshop.local
```

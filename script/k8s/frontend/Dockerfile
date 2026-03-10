# ===========================================
# 构建阶段 - 使用 Node.js 镜像
# ===========================================
FROM node:21.5-alpine AS builder

# 设置工作目录
WORKDIR /app

# 安装 pnpm
RUN npm install -g pnpm

# 设置npm镜像（使用淘宝镜像）
RUN pnpm config set registry https://registry.npmmirror.com

# 设置网络重试和超时
RUN pnpm config set fetch-retries 5 && \
    pnpm config set fetch-timeout 120000

# 复制 package.json 和 pnpm-lock.yaml
COPY package.json pnpm-lock.yaml* ./

# 安装依赖（使用 shamefully-hoist 解决模块解析问题）
RUN pnpm install --shamefully-hoist

# 复制源代码
COPY . .

# 设置构建参数（可在docker build时通过ARG传入）
ARG BUILD_MODE=prod
ARG NODE_ENV=production
ARG PUBLIC_PATH=/
ARG VUE_APP_TITLE=意象商城管理系统
ARG VUE_APP_BASE_API=/prod-api
ARG VUE_APP_APP_NAME=/
ARG VUE_APP_TENANT_ENABLE=true
ARG VUE_APP_CAPTCHA_ENABLE=true
ARG VUE_APP_DOC_ENABLE=true
ARG VUE_APP_BAIDU_CODE=fadc1bd5db1a1d6f581df60a1807f8ab

# 设置环境变量
ENV NODE_ENV=${NODE_ENV}
ENV PUBLIC_PATH=${PUBLIC_PATH}
ENV VUE_APP_TITLE=${VUE_APP_TITLE}
ENV VUE_APP_BASE_API=${VUE_APP_BASE_API}
ENV VUE_APP_APP_NAME=${VUE_APP_APP_NAME}
ENV VUE_APP_TENANT_ENABLE=${VUE_APP_TENANT_ENABLE}
ENV VUE_APP_CAPTCHA_ENABLE=${VUE_APP_CAPTCHA_ENABLE}
ENV VUE_APP_DOC_ENABLE=${VUE_APP_DOC_ENABLE}
ENV VUE_APP_BAIDU_CODE=${VUE_APP_BAIDU_CODE}

# 构建项目（根据 BUILD_MODE 选择构建脚本：local/dev/test/stage/prod）
RUN pnpm build:${BUILD_MODE}

# ===========================================
# 运行阶段 - 使用 Nginx 镜像
# ===========================================
FROM nginx:alpine

# 设置时区
ENV TZ=Asia/Shanghai

# 安装基础工具（可选，用于调试）
RUN apk add --no-cache curl tzdata && \
    cp /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo "${TZ}" > /etc/timezone && \
    apk del tzdata

# 从构建阶段复制构建产物
COPY --from=builder /app/dist /usr/share/nginx/html

# 复制 nginx 配置
COPY nginx.conf /etc/nginx/conf.d/default.conf

# 暴露端口
EXPOSE 80

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

# 启动 nginx
CMD ["nginx", "-g", "daemon off;"]

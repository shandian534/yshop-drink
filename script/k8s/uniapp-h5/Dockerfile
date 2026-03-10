# ===========================================
# 构建阶段 - 使用 Node.js 镜像
# ===========================================
FROM node:21.5-alpine AS builder

# 安装 pnpm
RUN npm install -g pnpm

# 设置npm镜像（使用华为云镜像）
RUN pnpm config set registry https://mirrors.huaweicloud.com/repository/npm/

# 设置网络重试和超时
RUN pnpm config set fetch-retries 5 && \
    pnpm config set fetch-timeout 120000

# 设置工作目录
WORKDIR /app

# 复制 uniapp 项目文件
COPY ./source ./

# 复制构建配置（如果项目中没有的话）
COPY vite.config.js ./

# 安装依赖
RUN pnpm install

# 构建 H5 版本
RUN pnpm build:h5

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
COPY --from=builder /app/dist/build/h5 /usr/share/nginx/html

# 复制 nginx 配置
COPY nginx.conf /etc/nginx/conf.d/default.conf

# 暴露端口
EXPOSE 80

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

# 启动 nginx
CMD ["nginx", "-g", "daemon off;"]

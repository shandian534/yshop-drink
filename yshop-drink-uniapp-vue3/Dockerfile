# yshop-drink H5 Dockerfile
# 基于 Nginx Alpine 镜像构建轻量级容器
FROM nginx:alpine

# 将 uni-app H5 构建产物复制到 Nginx 目录
COPY dist/build/h5 /usr/share/nginx/html/h5

# 复制自定义 Nginx 配置
COPY nginx.conf /etc/nginx/conf.d/default.conf

# 暴露 80 端口
EXPOSE 80

# Nginx 默认启动命令
CMD ["nginx", "-g", "daemon off;"]

#!/bin/bash
# K8s 镜像构建和推送脚本

set -e

# Harbor配置（可覆盖）
HARBOR_ADDRESS=${HARBOR_ADDRESS:-"192.168.2.254:30002"}
HARBOR_ACCOUNT=${HARBOR_ACCOUNT:-"admin"}
HARBOR_PASSWORD=${HARBOR_PASSWORD:-"Lpg_98534"}
HARBOR_PROJECT_NAME=${HARBOR_PROJECT_NAME:-"ruoyi-vue-pro"}

# 镜像配置
REGISTRY=${REGISTRY:-"${HARBOR_ADDRESS}/${HARBOR_PROJECT_NAME}"}
IMAGE_NAME=${IMAGE_NAME:-"yshop-server"}
IMAGE_TAG=${IMAGE_TAG:-"latest"}
FULL_IMAGE_NAME="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查Docker是否运行
check_docker() {
    if ! docker info > /dev/null 2>&1; then
        log_error "Docker未运行，请先启动Docker"
        exit 1
    fi
    log_info "Docker运行正常"
}

# 登录Harbor镜像仓库
login_harbor() {
    log_info "登录Harbor镜像仓库: ${HARBOR_ADDRESS}"

    echo "${HARBOR_PASSWORD}" | docker login "${HARBOR_ADDRESS}" \
        --username="${HARBOR_ACCOUNT}" \
        --password-stdin

    if [ $? -eq 0 ]; then
        log_info "Harbor登录成功"
    else
        log_error "Harbor登录失败"
        exit 1
    fi
}

# 构建JAR包
build_jar() {
    log_info "开始构建JAR包..."

    if [ ! -f "pom.xml" ]; then
        log_error "未找到pom.xml文件，请在项目根目录下执行此脚本"
        exit 1
    fi

    # 创建maven缓存volume（如果不存在）
    docker volume create yshop-maven-repo 2>/dev/null || true

    # 使用Docker运行Maven构建
    docker run -it --rm --name yshop-maven \
        -v yshop-maven-repo:/root/.m2 \
        -v "$PWD":/usr/src/mymaven \
        -w /usr/src/mymaven \
        maven:3.9-eclipse-temurin-21 \
        mvn clean install package -Dmaven.test.skip=true

    if [ ! -f "yshop-server/target/yshop-server.jar" ]; then
        log_error "JAR包构建失败，未找到目标文件"
        exit 1
    fi

    log_info "JAR包构建完成"
}

# 构建Docker镜像
build_image() {
    log_info "开始构建Docker镜像: ${FULL_IMAGE_NAME}"

    # 确保在正确的目录
    cd yshop-server

    docker build -t "${FULL_IMAGE_NAME}" .

    cd ..

    log_info "Docker镜像构建完成"
}

# 推送镜像
push_image() {
    log_info "推送镜像到仓库: ${FULL_IMAGE_NAME}"

    docker push "${FULL_IMAGE_NAME}"

    log_info "镜像推送完成"
}

# 主函数
main() {
    log_info "========== 开始构建和推送流程 =========="
    log_info "镜像名称: ${FULL_IMAGE_NAME}"
    log_info "Harbor地址: ${HARBOR_ADDRESS}"
    log_info "Harbor项目: ${HARBOR_PROJECT_NAME}"

    check_docker
    login_harbor
    build_jar
    build_image
    push_image

    log_info "========== 构建和推送流程完成 =========="
    log_info "镜像: ${FULL_IMAGE_NAME}"
    log_info "执行以下命令部署到K8s:"
    log_info "  cd script/k8s && ./deploy.sh"
}

# 执行主函数
main "$@"

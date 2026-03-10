#!/bin/bash
# 前端镜像构建脚本

set -e

# ==================== 配置区域 ====================

# Harbor配置
HARBOR_ADDRESS=${HARBOR_ADDRESS:-"192.168.2.254:30002"}
HARBOR_ACCOUNT=${HARBOR_ACCOUNT:-"admin"}
HARBOR_PASSWORD=${HARBOR_PASSWORD:-"Lpg_98534"}
HARBOR_PROJECT_NAME=${HARBOR_PROJECT_NAME:-"ruoyi-vue-pro"}

# 镜像配置
IMAGE_NAME=${IMAGE_NAME:-"yshop-admin"}
IMAGE_TAG=${IMAGE_TAG:-"latest"}
FULL_IMAGE_NAME="${HARBOR_ADDRESS}/${HARBOR_PROJECT_NAME}/${IMAGE_NAME}:${IMAGE_TAG}"

# 前端项目路径
FRONTEND_PATH=${FRONTEND_PATH:-"."}

# ==================== 颜色输出 ====================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# ==================== 主函数 ====================

main() {
    log_info "========== 前端镜像构建 =========="
    log_info "镜像名称: ${FULL_IMAGE_NAME}"
    log_info "项目路径: ${FRONTEND_PATH}"
    echo ""

    # 检查项目路径
    if [ ! -d "${FRONTEND_PATH}" ]; then
        log_error "项目路径不存在: ${FRONTEND_PATH}"
        exit 1
    fi

    # 检查必需文件
    cd "${FRONTEND_PATH}"
    if [ ! -f "package.json" ]; then
        log_error "未找到 package.json，请确认这是前端项目目录"
        exit 1
    fi

    # 检查Dockerfile
    if [ ! -f "Dockerfile" ]; then
        log_warn "未找到 Dockerfile"
        log_info "将从模板复制 Dockerfile..."

        # 假设模板在k8s脚本目录
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        DOCKERFILE_TEMPLATE="${SCRIPT_DIR}/frontend/Dockerfile"

        if [ -f "${DOCKERFILE_TEMPLATE}" ]; then
            cp "${DOCKERFILE_TEMPLATE}" Dockerfile
            log_info "Dockerfile 已创建"
        else
            log_error "Dockerfile 模板不存在: ${DOCKERFILE_TEMPLATE}"
            exit 1
        fi
    fi

    # 构建镜像
    log_step "构建Docker镜像..."
    docker build -t "${FULL_IMAGE_NAME}" .

    log_info "镜像构建完成"

    # 登录Harbor
    log_step "登录Harbor..."
    echo "${HARBOR_PASSWORD}" | docker login "${HARBOR_ADDRESS}" \
        --username="${HARBOR_ACCOUNT}" \
        --password-stdin

    # 推送镜像
    log_step "推送镜像到Harbor..."
    docker push "${FULL_IMAGE_NAME}"

    echo ""
    log_info "========== 构建完成 =========="
    log_info "镜像: ${FULL_IMAGE_NAME}"
    echo ""
    log_info "现在可以部署到K8s:"
    log_info "  ./deploy-admin-only.sh --image ${FULL_IMAGE_NAME}"
}

# 捕获Ctrl+C
trap 'echo -e "\n${RED}构建已中断${NC}"; exit 1' INT

# 执行主函数
main "$@"

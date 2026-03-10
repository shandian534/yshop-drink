#!/bin/bash
# YShop 前端管理界面部署脚本
# 用途: 单独部署前端管理界面到K8s

set -e

# ==================== 配置区域 ====================

# Harbor配置
HARBOR_ADDRESS=${HARBOR_ADDRESS:-"192.168.2.254:30002"}
HARBOR_ACCOUNT=${HARBOR_ACCOUNT:-"admin"}
HARBOR_PASSWORD=${HARBOR_PASSWORD:-"Lpg_98534"}
HARBOR_PROJECT_NAME=${HARBOR_PROJECT_NAME:-"ruoyi-vue-pro"}

# K8s配置
NAMESPACE=${NAMESPACE:-"yshop"}

# 镜像配置
ADMIN_IMAGE_NAME=${ADMIN_IMAGE_NAME:-"yshop-admin"}
ADMIN_IMAGE_TAG=${ADMIN_IMAGE_TAG:-"latest"}
REGISTRY="${HARBOR_ADDRESS}/${HARBOR_PROJECT_NAME}"
FULL_ADMIN_IMAGE="${REGISTRY}/${ADMIN_IMAGE_NAME}:${ADMIN_IMAGE_TAG}"

# 前端项目路径（如果需要构建）
ADMIN_PROJECT_PATH=${ADMIN_PROJECT_PATH:-""}

# ==================== 颜色输出 ====================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

log_success() {
    echo -e "${CYAN}[SUCCESS]${NC} $1"
}

print_banner() {
    cat << "EOF"

 ██   ██  █████   ██████  ███    ███
  ██ ██  ██   ██ ██       ████  ████
   ███   ███████ ██   ███ ██ ████ ██
  ██ ██  ██   ██ ██    ██ ██  ██  ██
 ██   ██ ██   ██  ██████  ██      ██

 ██    ██ ██████  ██████   █████  ████████ ███████
 ██    ██ ██   ██ ██   ██ ██   ██    ██    ██
 ██    ██ ██████  ██   ██ ███████    ██    █████
 ██    ██ ██      ██   ██ ██   ██    ██    ██
  ██████  ██      ██████  ██   ██    ██    ███████

                    📱 FRONTEND ONLY 📱

EOF
}

# ==================== 获取脚本目录 ====================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==================== 检查函数 ====================

check_kubectl() {
    log_step "检查kubectl环境..."
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl未安装"
        exit 1
    fi
    if ! kubectl cluster-info &> /dev/null; then
        log_error "无法连接到K8s集群"
        exit 1
    fi
    log_success "kubectl配置正常"
}

check_docker() {
    if [ "${BUILD_IMAGE}" = "true" ]; then
        log_step "检查Docker环境..."
        if ! docker info > /dev/null 2>&1; then
            log_error "Docker未运行"
            exit 1
        fi
        log_success "Docker运行正常"
    fi
}

# ==================== 镜像构建函数 ====================

build_admin_image() {
    if [ -z "${ADMIN_PROJECT_PATH}" ]; then
        log_error "未指定前端项目路径"
        log_info "请设置环境变量: ADMIN_PROJECT_PATH=/path/to/frontend"
        exit 1
    fi

    if [ ! -d "${ADMIN_PROJECT_PATH}" ]; then
        log_error "前端项目路径不存在: ${ADMIN_PROJECT_PATH}"
        exit 1
    fi

    log_step "构建前端镜像..."
    log_info "项目路径: ${ADMIN_PROJECT_PATH}"
    log_info "镜像名称: ${FULL_ADMIN_IMAGE}"

    cd "${ADMIN_PROJECT_PATH}"

    # 检查是否有Dockerfile
    if [ ! -f "Dockerfile" ]; then
        log_error "未找到Dockerfile"
        exit 1
    fi

    # 构建镜像
    docker build -t "${FULL_ADMIN_IMAGE}" .

    log_success "前端镜像构建完成"

    # 推送镜像
    log_step "推送镜像到Harbor..."
    echo "${HARBOR_PASSWORD}" | docker login "${HARBOR_ADDRESS}" \
        --username="${HARBOR_ACCOUNT}" \
        --password-stdin

    docker push "${FULL_ADMIN_IMAGE}"
    log_success "镜像推送完成"
}

# ==================== K8s部署函数 ====================

create_namespace() {
    log_step "创建命名空间..."
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    log_success "命名空间已就绪"
}

create_harbor_secret() {
    log_step "创建Harbor镜像拉取密钥..."

    if kubectl get secret harbor-registry -n "${NAMESPACE}" &> /dev/null; then
        log_info "密钥已存在，跳过创建"
        return
    fi

    kubectl create secret docker-registry harbor-registry \
        --docker-server="${HARBOR_ADDRESS}" \
        --docker-username="${HARBOR_ACCOUNT}" \
        --docker-password="${HARBOR_PASSWORD}" \
        -n "${NAMESPACE}"

    log_success "Harbor镜像拉取密钥已创建"
}

deploy_admin() {
    log_step "部署前端管理界面..."

    # 检查配置文件
    if [ ! -f "${SCRIPT_DIR}/09-admin.yaml" ]; then
        log_error "前端配置文件不存在: ${SCRIPT_DIR}/09-admin.yaml"
        exit 1
    fi

    # 更新镜像版本（如果需要）
    if [ "${BUILD_IMAGE}" = "true" ]; then
        log_info "更新镜像版本: ${FULL_ADMIN_IMAGE}"
        # 使用sed更新镜像
        sed "s|image:.*yshop-admin.*|image: ${FULL_ADMIN_IMAGE}|g" \
            "${SCRIPT_DIR}/09-admin.yaml" > /tmp/09-admin-updated.yaml
        kubectl apply -f /tmp/09-admin-updated.yaml
        rm -f /tmp/09-admin-updated.yaml
    else
        kubectl apply -f "${SCRIPT_DIR}/09-admin.yaml"
    fi

    # 等待Pod就绪
    log_info "等待前端Pod就绪..."
    kubectl wait --for=condition=ready pod -l app=yshop-admin -n "${NAMESPACE}" --timeout=300s || true

    log_success "前端管理界面部署完成"
}

deploy_ingress() {
    log_step "部署Ingress..."

    if [ ! -f "${SCRIPT_DIR}/08-ingress.yaml" ]; then
        log_warn "Ingress配置文件不存在，跳过Ingress部署"
        log_info "请使用PortForward方式访问: kubectl port-forward svc/yshop-admin 8080:80 -n ${NAMESPACE}"
        return
    fi

    kubectl apply -f "${SCRIPT_DIR}/08-ingress.yaml"
    log_success "Ingress部署完成"
}

# ==================== 验证函数 ====================

show_status() {
    log_step "部署状态:"
    echo ""

    log_info "Pod状态:"
    kubectl get pods -n "${NAMESPACE}" -l app=yshop-admin
    echo ""

    log_info "Service状态:"
    kubectl get svc -n "${NAMESPACE}" -l app=yshop-admin
    echo ""

    if kubectl get ingress -n "${NAMESPACE}" &> /dev/null; then
        log_info "Ingress状态:"
        kubectl get ingress -n "${NAMESPACE}"
        echo ""
    fi

    log_info "访问方式:"
    log_info "  1. Ingress: http://admin.yshop.local (需配置hosts)"
    log_info "     echo '192.168.2.254 admin.yshop.local' >> /etc/hosts"
    echo ""
    log_info "  2. PortForward:"
    log_info "     kubectl port-forward svc/yshop-admin 8080:80 -n ${NAMESPACE}"
    log_info "     然后访问: http://localhost:8080"
    echo ""
    log_info "  3. 查看日志:"
    log_info "     kubectl logs -f -l app=yshop-admin -n ${NAMESPACE}"
}

show_help() {
    cat << EOF
${CYAN}YShop 前端管理界面部署脚本${NC}

用法: $0 [选项]

${GREEN}选项:${NC}
  --build             构建前端镜像并部署
  --image IMAGE       指定前端镜像地址
  --path PATH         指定前端项目路径（构建时需要）
  --tag TAG           指定镜像标签（默认: latest）
  --namespace NS      指定命名空间（默认: yshop）
  help                显示此帮助信息

${GREEN}环境变量:${NC}
  ADMIN_IMAGE_NAME    前端镜像名称（默认: yshop-admin）
  ADMIN_IMAGE_TAG     前端镜像标签（默认: latest）
  ADMIN_PROJECT_PATH  前端项目路径
  NAMESPACE           命名空间（默认: yshop）
  BUILD_IMAGE         是否构建镜像（true/false）

${GREEN}示例:${NC}
  # 使用已有镜像部署
  $0

  # 使用自定义镜像部署
  $0 --image 192.168.2.254:30002/ruoyi-vue-pro/yshop-admin:v1.0.0

  # 构建并部署（需要前端项目）
  ADMIN_PROJECT_PATH=/root/yshop-ui-admin $0 --build

  # 部署到指定命名空间
  $0 --namespace production

${YELLOW}说明:${NC}
  此脚本仅部署前端管理界面，不包含后端API服务。
  确保后端API服务已部署并可访问。

EOF
}

# ==================== 主函数 ====================

main() {
    BUILD_IMAGE=${BUILD_IMAGE:-"false"}

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --build)
                BUILD_IMAGE="true"
                shift
                ;;
            --image)
                FULL_ADMIN_IMAGE="$2"
                shift 2
                ;;
            --path)
                ADMIN_PROJECT_PATH="$2"
                shift 2
                ;;
            --tag)
                ADMIN_IMAGE_TAG="$2"
                FULL_ADMIN_IMAGE="${REGISTRY}/${ADMIN_IMAGE_NAME}:${ADMIN_IMAGE_TAG}"
                shift 2
                ;;
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            help|--help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done

    print_banner

    log_info "========== 前端管理界面部署 =========="
    log_info "命名空间: ${NAMESPACE}"
    log_info "镜像: ${FULL_ADMIN_IMAGE}"
    if [ "${BUILD_IMAGE}" = "true" ]; then
        log_info "构建模式: 是"
    fi
    echo ""

    # 环境检查
    check_kubectl
    check_docker
    echo ""

    # 构建镜像（如果需要）
    if [ "${BUILD_IMAGE}" = "true" ]; then
        log_info "========== 第一步: 构建镜像 =========="
        build_admin_image
        echo ""
    fi

    # K8s部署
    log_info "========== 第二步: 部署到K8s =========="
    create_namespace
    create_harbor_secret
    deploy_admin
    deploy_ingress
    echo ""

    # 验证部署
    log_info "========== 第三步: 验证部署 =========="
    show_status
    echo ""

    log_success "========== 部署完成 =========="
}

# 捕获Ctrl+C
trap 'echo -e "\n${RED}部署已中断${NC}"; exit 1' INT

# 执行主函数
main "$@"

#!/bin/bash
# YShop UniApp H5 部署脚本

set -e

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

# ==================== 自动定位项目目录 ====================

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 获取script目录的父目录（应该是yshop-drink）
YSHOP_ROOT="$(dirname "${SCRIPT_DIR}")"

# 自动查找 uniapp 项目目录
find_uniapp_project() {
    log_info "自动定位 UniApp 项目..."

    # 在yshop-drink根目录下查找
    for dir in "${YSHOP_ROOT}"/*; do
        if [ -d "$dir" ] && [ -f "$dir/manifest.json" ] && [ -f "$dir/pages.json" ]; then
            echo "$dir"
            return 0
        fi
    done

    return 1
}

# ==================== 配置区域 ====================

# Harbor配置
HARBOR_ADDRESS=${HARBOR_ADDRESS:-"192.168.2.254:30002"}
HARBOR_ACCOUNT=${HARBOR_ACCOUNT:-"admin"}
HARBOR_PASSWORD=${HARBOR_PASSWORD:-"Lpg_98534"}
HARBOR_PROJECT_NAME=${HARBOR_PROJECT_NAME:-"ruoyi-vue-pro"}

# K8s配置
NAMESPACE=${NAMESPACE:-"yshop"}

# UniApp H5镜像配置
UNIAPP_IMAGE_NAME=${UNIAPP_IMAGE_NAME:-"yshop-uniapp-h5"}
UNIAPP_IMAGE_TAG=${UNIAPP_IMAGE_TAG:-"latest"}
# 如果未指定标签，自动生成基于时间戳的标签
if [ "${UNIAPP_IMAGE_TAG}" = "latest" ]; then
    UNIAPP_IMAGE_TAG="$(date +%Y%m%d%H%M%S)"
    AUTO_GENERATED_TAG="true"
fi
REGISTRY="${HARBOR_ADDRESS}/${HARBOR_PROJECT_NAME}"
FULL_UNIAPP_IMAGE="${REGISTRY}/${UNIAPP_IMAGE_NAME}:${UNIAPP_IMAGE_TAG}"

# UniApp项目路径（可选，用于构建前端镜像）
UNIAPP_PROJECT_PATH=${UNIAPP_PROJECT_PATH:-""}

# ==================== 检查函数 ====================

check_docker() {
    log_step "检查Docker环境..."
    if ! docker info > /dev/null 2>&1; then
        log_error "Docker未运行或未安装"
        exit 1
    fi
    log_success "Docker运行正常"
}

check_kubectl() {
    log_step "检查kubectl环境..."
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl未安装"
        exit 1
    fi
    if ! kubectl cluster-info &> /dev/null; then
        log_error "无法连接到K8s集群，请检查kubeconfig配置"
        exit 1
    fi
    log_success "kubectl配置正常"
    kubectl cluster-info | head -n 1
}

# ==================== Docker相关函数 ====================

login_harbor() {
    log_step "登录Harbor镜像仓库..."
    log_info "Harbor地址: ${HARBOR_ADDRESS}"
    log_info "Harbor账号: ${HARBOR_ACCOUNT}"

    echo "${HARBOR_PASSWORD}" | docker login "${HARBOR_ADDRESS}" \
        --username="${HARBOR_ACCOUNT}" \
        --password-stdin

    if [ $? -eq 0 ]; then
        log_success "Harbor登录成功"
    else
        log_error "Harbor登录失败"
        exit 1
    fi
}

# ==================== UniApp H5 构建函数 ====================

build_uniapp_h5_image() {
    log_step "构建 UniApp H5 镜像..."

    # 检查 UniApp 项目路径
    if [ -z "${UNIAPP_PROJECT_PATH}" ]; then
        UNIAPP_PROJECT_PATH=$(find_uniapp_project)
        if [ -z "${UNIAPP_PROJECT_PATH}" ]; then
            log_error "未找到 UniApp 项目"
            log_info "请通过 UNIAPP_PROJECT_PATH 指定项目路径"
            exit 1
        fi
        log_info "找到 UniApp 项目: ${UNIAPP_PROJECT_PATH}"
    fi

    if [ ! -d "${UNIAPP_PROJECT_PATH}" ]; then
        log_error "UniApp 项目路径不存在: ${UNIAPP_PROJECT_PATH}"
        exit 1
    fi

    # 检查必需文件
    if [ ! -f "${UNIAPP_PROJECT_PATH}/manifest.json" ]; then
        log_error "未找到 manifest.json，请确认这是 UniApp 项目"
        exit 1
    fi

    log_info "UniApp 项目: ${UNIAPP_PROJECT_PATH}"
    log_info "镜像名称: ${FULL_UNIAPP_IMAGE}"

    # 保存当前目录
    local current_dir
    current_dir="$(pwd)"

    # 创建临时构建目录
    local build_dir
    build_dir="${SCRIPT_DIR}/uniapp-h5-build"
    rm -rf "${build_dir}"
    mkdir -p "${build_dir}"

    # 准备构建环境
    log_info "准备构建环境..."
    cp -r "${SCRIPT_DIR}/uniapp-h5/"* "${build_dir}/"

    # 创建源代码目录软链接
    mkdir -p "${build_dir}/source"
    # 使用 cp 复制项目文件（避免跨设备链接问题）
    cp -r "${UNIAPP_PROJECT_PATH}"/* "${build_dir}/source/"

    # 进入构建目录
    cd "${build_dir}"

    # 构建镜像
    log_info "开始构建 Docker 镜像..."
    docker build -t "${FULL_UNIAPP_IMAGE}" .

    # 清理临时目录
    cd "${current_dir}"
    rm -rf "${build_dir}"

    log_success "UniApp H5 镜像构建完成"
}

push_uniapp_h5_image() {
    log_step "推送 UniApp H5 镜像到 Harbor..."
    docker push "${FULL_UNIAPP_IMAGE}"
    log_success "镜像推送完成"
}

# ==================== K8s相关函数 ====================

create_namespace() {
    log_step "创建命名空间..."
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    log_success "命名空间 ${NAMESPACE} 已就绪"
}

create_harbor_secret() {
    log_step "创建Harbor镜像拉取密钥..."

    # 删除已存在的密钥
    if kubectl get secret harbor-registry -n "${NAMESPACE}" &> /dev/null; then
        kubectl delete secret harbor-registry -n "${NAMESPACE}"
    fi

    # 创建新密钥
    kubectl create secret docker-registry harbor-registry \
        --docker-server="${HARBOR_ADDRESS}" \
        --docker-username="${HARBOR_ACCOUNT}" \
        --docker-password="${HARBOR_PASSWORD}" \
        -n "${NAMESPACE}"

    log_success "Harbor镜像拉取密钥已创建"
}

deploy_uniapp_h5() {
    log_step "部署 UniApp H5..."

    # 检查配置文件是否存在
    if [ ! -f "${SCRIPT_DIR}/10-uniapp-h5.yaml" ]; then
        log_error "UniApp H5 配置文件不存在: ${SCRIPT_DIR}/10-uniapp-h5.yaml"
        exit 1
    fi

    # 更新镜像
    log_info "使用 UniApp H5 镜像: ${FULL_UNIAPP_IMAGE}"
    kubectl set image deployment/yshop-uniapp-h5 \
        yshop-uniapp-h5="${FULL_UNIAPP_IMAGE}" \
        -n "${NAMESPACE}"

    # 等待部署完成
    log_info "等待 UniApp H5 就绪..."
    kubectl wait --for=condition=ready pod -l app=yshop-uniapp-h5 -n "${NAMESPACE}" --timeout=180s || true

    log_success "UniApp H5 部署完成"
}

# ==================== 验证函数 ====================

show_deployment_status() {
    log_step "部署状态:"
    echo ""

    log_info "UniApp H5 Pod状态:"
    kubectl get pods -n "${NAMESPACE}" -l app=yshop-uniapp-h5
    echo ""

    log_info "UniApp H5 Service状态:"
    kubectl get svc -n "${NAMESPACE}" -l app=yshop-uniapp-h5
    echo ""

    log_info "访问方式:"
    log_info "  1. H5 Ingress: http://h5.yshop.local (需配置hosts)"
    log_info "  2. PortForward: kubectl port-forward svc/yshop-uniapp-h5 8080:80 -n ${NAMESPACE}"
    log_info "  3. 查看日志: kubectl logs -f -l app=yshop-uniapp-h5 -n ${NAMESPACE}"
}

# ==================== 帮助信息 ====================

show_help() {
    cat << EOF
${CYAN}YShop UniApp H5 K8s 部署脚本${NC}

用法: $0 [模式]

${GREEN}部署模式:${NC}
  build      仅构建镜像 - 构建 UniApp H5 镜像，不部署
  deploy     仅部署 - 使用已有镜像部署到 K8s
  full       完整部署 - 构建镜像 + 部署到 K8s（默认）
  status     查看状态 - 显示当前部署状态
  help       显示帮助信息

${GREEN}环境变量:${NC}
  NAMESPACE           命名空间 (默认: yshop)
  UNIAPP_IMAGE_TAG    镜像标签 (默认自动生成时间戳)
  HARBOR_ADDRESS      Harbor地址 (默认: 192.168.2.254:30002)
  HARBOR_ACCOUNT      Harbor账号 (默认: admin)
  HARBOR_PASSWORD     Harbor密码 (默认: Lpg_98534)
  UNIAPP_PROJECT_PATH UniApp项目路径 (可选，默认自动查找)

${GREEN}示例:${NC}
  # 完整部署（自动查找 UniApp 项目）
  $0 full

  # 仅构建镜像
  $0 build

  # 仅部署已有镜像
  $0 deploy

  # 使用自定义镜像标签
  UNIAPP_IMAGE_TAG=v1.0.0 $0 full

${YELLOW}UniApp 项目自动查找:${NC}
  脚本会自动在项目根目录查找包含 manifest.json 和 pages.json 的目录

EOF
}

# ==================== 主函数 ====================

main() {
    local mode="${1:-full}"

    # 处理特殊模式
    case "$mode" in
        help|--help|-h)
            show_help
            exit 0
            ;;
        status)
            log_info "========== UniApp H5 部署状态 =========="
            echo ""
            show_deployment_status
            exit 0
            ;;
    esac

    # 显示自动生成的标签
    if [ "${AUTO_GENERATED_TAG}" = "true" ]; then
        log_info "自动生成 UniApp H5 镜像标签: ${UNIAPP_IMAGE_TAG}"
    fi

    # 显示部署信息
    log_info "========== YShop UniApp H5 K8s 部署 =========="
    log_info "部署模式: ${mode}"
    log_info "命名空间: ${NAMESPACE}"
    log_info "UniApp H5 镜像: ${FULL_UNIAPP_IMAGE}"
    if [ -n "${UNIAPP_PROJECT_PATH}" ]; then
        log_info "UniApp 项目: ${UNIAPP_PROJECT_PATH}"
    fi
    echo ""

    # 根据模式执行部署
    case "$mode" in
        build)
            log_info "========== 仅构建镜像模式 =========="
            check_docker
            login_harbor
            build_uniapp_h5_image
            push_uniapp_h5_image
            echo ""
            log_success "========== 镜像构建完成 =========="
            log_info "镜像: ${FULL_UNIAPP_IMAGE}"
            echo ""
            log_info "要部署此镜像，请运行:"
            log_info "  UNIAPP_IMAGE_TAG=${UNIAPP_IMAGE_TAG} $0 deploy"
            ;;
        deploy)
            log_info "========== 仅部署模式 =========="
            check_kubectl
            create_namespace
            create_harbor_secret
            deploy_uniapp_h5
            echo ""
            show_deployment_status
            echo ""
            log_success "========== 部署完成 =========="
            ;;
        full)
            log_info "========== 完整部署模式 =========="

            # 构建镜像
            log_info "========== 第一步: 构建镜像 =========="
            check_docker
            login_harbor
            build_uniapp_h5_image
            push_uniapp_h5_image
            echo ""

            # 部署到K8s
            log_info "========== 第二步: 部署到K8s =========="
            check_kubectl
            create_namespace
            create_harbor_secret
            deploy_uniapp_h5
            echo ""

            # 验证部署
            log_info "========== 第三步: 验证部署 =========="
            show_deployment_status
            echo ""

            log_success "========== 完整部署完成 =========="
            ;;
        *)
            log_error "未知模式: $mode"
            echo ""
            show_help
            exit 1
            ;;
    esac

    # 通用提示信息
    echo ""
    log_info "========== 快捷操作 =========="
    log_info "查看状态:     $0 status"
    log_info "仅构建:       $0 build"
    log_info "仅部署:       $0 deploy"
}

# 捕获Ctrl+C
trap 'echo -e "\n${RED}操作已中断${NC}"; exit 1' INT

# 执行主函数
main "$@"

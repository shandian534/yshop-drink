#!/bin/bash
# K8s 部署脚本

set -e

# Harbor配置（可覆盖）
HARBOR_ADDRESS=${HARBOR_ADDRESS:-"192.168.2.254:30002"}
HARBOR_PROJECT_NAME=${HARBOR_PROJECT_NAME:-"ruoyi-vue-pro"}

# 配置变量
NAMESPACE=${NAMESPACE:-"yshop"}
REGISTRY=${REGISTRY:-"${HARBOR_ADDRESS}/${HARBOR_PROJECT_NAME}"}
IMAGE_NAME=${IMAGE_NAME:-"yshop-server"}
IMAGE_TAG=${IMAGE_TAG:-"latest"}
FULL_IMAGE_NAME="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 检查kubectl
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl未安装，请先安装kubectl"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        log_error "无法连接到K8s集群，请检查kubeconfig配置"
        exit 1
    fi

    log_info "kubectl配置正常，集群信息:"
    kubectl cluster-info
}

# 部署命名空间
deploy_namespace() {
    log_step "部署命名空间..."
    kubectl apply -f 00-namespace.yaml
    log_info "命名空间部署完成"
}

# 部署MySQL
deploy_mysql() {
    log_step "部署MySQL..."
    kubectl apply -f 01-mysql-secret.yaml
    kubectl apply -f 02-mysql-pvc.yaml
    kubectl apply -f 03-mysql.yaml

    # 等待MySQL就绪
    log_info "等待MySQL就绪..."
    kubectl wait --for=condition=ready pod -l app=mysql -n "${NAMESPACE}" --timeout=300s || true

    log_info "MySQL部署完成"
}

# 部署Redis
deploy_redis() {
    log_step "部署Redis..."
    kubectl apply -f 04-redis-pvc.yaml
    kubectl apply -f 05-redis.yaml

    # 等待Redis就绪
    log_info "等待Redis就绪..."
    kubectl wait --for=condition=ready pod -l app=redis -n "${NAMESPACE}" --timeout=180s || true

    log_info "Redis部署完成"
}

# 部署后端服务
deploy_server() {
    log_step "部署后端服务..."

    # 更新镜像名称（使用环境变量中的镜像）
    if [ -n "${FULL_IMAGE_NAME}" ]; then
        # 使用kubectl patch更新镜像
        kubectl set image deployment/yshop-server yshop-server="${FULL_IMAGE_NAME}" -n "${NAMESPACE}" --dry-run=client -o yaml > 07-server-updated.yaml
        kubectl apply -f 07-server-updated.yaml
        rm -f 07-server-updated.yaml
    else
        kubectl apply -f 06-server-configmap.yaml
        kubectl apply -f 07-server.yaml
    fi

    # 等待服务就绪
    log_info "等待后端服务就绪..."
    kubectl wait --for=condition=ready pod -l app=yshop-server -n "${NAMESPACE}" --timeout=300s || true

    log_info "后端服务部署完成"
}

# 部署Ingress
deploy_ingress() {
    log_step "部署Ingress..."
    kubectl apply -f 08-ingress.yaml
    log_info "Ingress部署完成"
}

# 显示部署状态
show_status() {
    log_step "部署状态:"
    echo ""

    log_info "Pod状态:"
    kubectl get pods -n "${NAMESPACE}"

    echo ""
    log_info "Service状态:"
    kubectl get svc -n "${NAMESPACE}"

    echo ""
    log_info "PVC状态:"
    kubectl get pvc -n "${NAMESPACE}"

    if kubectl get ingress -n "${NAMESPACE}" &> /dev/null; then
        echo ""
        log_info "Ingress状态:"
        kubectl get ingress -n "${NAMESPACE}"
    fi

    echo ""
    log_info "访问地址:"
    log_info "  API服务: http://api.yshop.local (需要配置hosts或DNS)"
    log_info "  NodePort方式: 获取节点IP后访问"
    log_info "  镜像仓库: ${HARBOR_ADDRESS}"
}

# 显示日志
show_logs() {
    log_step "查看日志 (Ctrl+C退出)..."
    kubectl logs -f -l app=yshop-server -n "${NAMESPACE}"
}

# 清理部署
cleanup() {
    log_warn "清理部署，删除所有资源..."
    read -p "确认删除命名空间 ${NAMESPACE} 下的所有资源? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl delete namespace "${NAMESPACE}"
        log_info "清理完成"
    else
        log_info "取消清理"
    fi
}

# 帮助信息
show_help() {
    cat << EOF
K8s 部署脚本

用法: $0 [选项]

选项:
    all         完整部署（命名空间、MySQL、Redis、服务、Ingress）
    infra       仅部署基础设施（MySQL、Redis）
    server      仅部署后端服务
    ingress     仅部署Ingress
    status      显示部署状态
    logs        查看服务日志
    cleanup     清理所有资源
    help        显示此帮助信息

环境变量:
    NAMESPACE   命名空间 (默认: yshop)
    REGISTRY    镜像仓库 (默认: localhost:5000)
    IMAGE_NAME  镜像名称 (默认: yshop-server)
    IMAGE_TAG   镜像标签 (默认: latest)

示例:
    # 完整部署
    $0 all

    # 使用自定义镜像部署
    IMAGE_TAG=v1.0.0 REGISTRY=myregistry.com $0 all

    # 仅部署后端服务
    $0 server

    # 查看状态
    $0 status

EOF
}

# 主函数
main() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "${script_dir}" || exit 1

    log_info "========== K8s 部署脚本 =========="
    log_info "命名空间: ${NAMESPACE}"
    log_info "镜像: ${FULL_IMAGE_NAME}"
    log_info "Harbor地址: ${HARBOR_ADDRESS}"
    log_info "Harbor项目: ${HARBOR_PROJECT_NAME}"
    echo ""

    check_kubectl

    case "${1:-all}" in
        all)
            deploy_namespace
            deploy_mysql
            deploy_redis
            deploy_server
            deploy_ingress
            show_status
            ;;
        infra)
            deploy_namespace
            deploy_mysql
            deploy_redis
            show_status
            ;;
        server)
            deploy_server
            show_status
            ;;
        ingress)
            deploy_ingress
            show_status
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs
            ;;
        cleanup)
            cleanup
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac

    log_info "========== 部署脚本完成 =========="
}

# 执行主函数
main "$@"

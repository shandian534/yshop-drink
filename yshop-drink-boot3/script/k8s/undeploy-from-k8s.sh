#!/bin/bash
# YShop K8s 一键卸载脚本
# 用途: 从K8s集群中完全移除YShop系统的所有资源

set -e

# ==================== 配置区域 ====================

# Harbor配置
HARBOR_ADDRESS=${HARBOR_ADDRESS:-"192.168.2.254:30002"}
HARBOR_PROJECT_NAME=${HARBOR_PROJECT_NAME:-"ruoyi-vue-pro"}

# K8s配置
NAMESPACE=${NAMESPACE:-"yshop"}
IMAGE_NAME=${IMAGE_NAME:-"yshop-server"}
REGISTRY="${HARBOR_ADDRESS}/${HARBOR_PROJECT_NAME}"

# ==================== 颜色输出 ====================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
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

log_danger() {
    echo -e "${MAGENTA}[DANGER]${NC} $1"
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

                   ⚠️  UNINSTALL SCRIPT ⚠️

EOF
}

# ==================== 检查函数 ====================

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

# ==================== 确认函数 ====================

confirm_uninstall() {
    clear
    print_banner

    log_danger "========================================"
    log_danger "     即将从K8s集群中卸载YShop系统       "
    log_danger "========================================"
    echo ""
    log_warn "以下资源将被删除："
    echo ""
    echo "  📦 命名空间: ${NAMESPACE}"
    echo "  🗄️  持久化存储 (PVC) - 数据将被清空！"
    echo "  🔐 密钥配置 (Secret)"
    echo "  ⚙️  配置映射 (ConfigMap)"
    echo "  🚀 所有部署和Service"
    echo "  🌐 Ingress配置"
    echo ""
    log_error "⚠️  警告: 此操作不可逆！所有数据将被永久删除！"
    echo ""

    # 二次确认
    echo -n "请输入命名空间 '${NAMESPACE}' 以确认卸载: "
    read -r CONFIRM_INPUT

    if [ "${CONFIRM_INPUT}" != "${NAMESPACE}" ]; then
        log_error "确认失败，卸载已取消"
        exit 0
    fi

    echo ""
    log_warn "正在进行最终确认..."
    echo -n "请输入 'YES' 以继续卸载 (输入其他任何内容取消): "
    read -r FINAL_CONFIRM

    if [ "${FINAL_CONFIRM}" != "YES" ]; then
        log_error "最终确认失败，卸载已取消"
        exit 0
    fi

    echo ""
    log_success "确认完成，开始卸载..."
    echo ""
}

# ==================== 显示资源信息 ====================

show_resources() {
    log_step "当前集群中的YShop资源:"
    echo ""

    # 显示命名空间
    if kubectl get namespace "${NAMESPACE}" &> /dev/null; then
        log_info "✓ 命名空间: ${NAMESPACE}"
        kubectl get namespace "${NAMESPACE}"
    else
        log_warn "✗ 命名空间 ${NAMESPACE} 不存在"
    fi
    echo ""

    # 显示Pod
    if kubectl get pods -n "${NAMESPACE}" &> /dev/null 2>&1; then
        log_info "Pod状态:"
        kubectl get pods -n "${NAMESPACE}" 2>/dev/null || echo "  无Pod"
    fi
    echo ""

    # 显示PVC
    if kubectl get pvc -n "${NAMESPACE}" &> /dev/null 2>&1; then
        log_info "持久化存储(PVC):"
        kubectl get pvc -n "${NAMESPACE}" 2>/dev/null || echo "  无PVC"
    fi
    echo ""
}

# ==================== 清理函数 ====================

cleanup_ingress() {
    log_step "删除Ingress配置..."
    if kubectl get ingress -n "${NAMESPACE}" &> /dev/null 2>&1; then
        kubectl delete ingress yshop-ingress -n "${NAMESPACE}" --ignore-not-found=true
        log_success "Ingress已删除"
    else
        log_info "Ingress不存在或已删除"
    fi
}

cleanup_resources() {
    log_step "删除部署和Service..."

    # 删除部署
    kubectl delete deployment yshop-server -n "${NAMESPACE}" --ignore-not-found=true 2>/dev/null || true

    # 删除Service
    kubectl delete service yshop-server -n "${NAMESPACE}" --ignore-not-found=true 2>/dev/null || true
    kubectl delete service mysql -n "${NAMESPACE}" --ignore-not-found=true 2>/dev/null || true
    kubectl delete service redis -n "${NAMESPACE}" --ignore-not-found=true 2>/dev/null || true

    log_success "部署和Service已删除"
}

cleanup_configs() {
    log_step "删除配置和密钥..."

    # 删除ConfigMap
    kubectl delete configmap server-config -n "${NAMESPACE}" --ignore-not-found=true 2>/dev/null || true

    # 删除Secret
    kubectl delete secret mysql-secret -n "${NAMESPACE}" --ignore-not-found=true 2>/dev/null || true
    kubectl delete secret harbor-registry -n "${NAMESPACE}" --ignore-not-found=true 2>/dev/null || true

    log_success "配置和密钥已删除"
}

cleanup_pvc() {
    log_step "删除持久化存储(PVC)..."

    # 获取PVC列表
    local pvcs
    pvcs=$(kubectl get pvc -n "${NAMESPACE}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$pvcs" ]; then
        log_warn "即将删除以下PVC（数据将永久丢失）:"
        echo "$pvcs" | tr ' ' '\n' | sed 's/^/  - /'
        echo ""

        for pvc in $pvcs; do
            kubectl delete pvc "$pvc" -n "${NAMESPACE}" --ignore-not-found=true 2>/dev/null || true
            log_info "已删除PVC: $pvc"
        done
        log_success "所有PVC已删除"
    else
        log_info "没有找到PVC"
    fi
}

cleanup_namespace() {
    log_step "删除命名空间..."

    if kubectl get namespace "${NAMESPACE}" &> /dev/null; then
        kubectl delete namespace "${NAMESPACE}" --ignore-not-found=true
        log_success "命名空间 ${NAMESPACE} 已删除"
    else
        log_info "命名空间 ${NAMESPACE} 不存在或已删除"
    fi
}

# ==================== 验证清理结果 ====================

verify_cleanup() {
    log_step "验证清理结果..."
    echo ""

    if kubectl get namespace "${NAMESPACE}" &> /dev/null 2>&1; then
        log_warn "⚠️  命名空间 ${NAMESPACE} 仍然存在"
        kubectl get all -n "${NAMESPACE}" 2>/dev/null || true
    else
        log_success "✓ 命名空间 ${NAMESPACE} 已完全删除"
    fi

    echo ""
    log_info "检查孤立的PVC（跨命名空间）..."
    local orphan_pvcs
    orphan_pvcs=$(kubectl get pvc -A -o json | grep -o "\"namespace\": \"${NAMESPACE}\"" 2>/dev/null || echo "")

    if [ -n "$orphan_pvcs" ]; then
        log_warn "发现可能的孤立PVC，请手动检查"
        kubectl get pvc -A | grep "${NAMESPACE}" || true
    else
        log_success "✓ 无孤立资源"
    fi
}

# ==================== 主函数 ====================

main() {
    # 打印横幅
    print_banner

    log_info "========== YShop K8s 卸载脚本 =========="
    log_info "命名空间: ${NAMESPACE}"
    log_info "镜像: ${REGISTRY}/${IMAGE_NAME}"
    echo ""

    # 检查kubectl
    check_kubectl
    echo ""

    # 显示当前资源
    show_resources

    # 确认卸载
    confirm_uninstall

    # 开始清理
    log_info "========== 开始清理资源 =========="
    echo ""

    cleanup_ingress
    cleanup_resources
    cleanup_configs
    cleanup_pvc
    cleanup_namespace

    echo ""

    # 验证清理结果
    log_info "========== 验证清理结果 =========="
    verify_cleanup

    echo ""
    log_success "========== 卸载完成 =========="
    echo ""

    log_info "如需重新部署，请运行:"
    log_info "  ./script/k8s/deploy-to-k8s.sh"
    echo ""
}

# 捕获Ctrl+C
trap 'echo -e "\n${RED}卸载已中断${NC}"; exit 1' INT

# 执行主函数
main "$@"

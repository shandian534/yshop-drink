#!/bin/bash
# Harbor镜像拉取密钥配置脚本

set -e

# Harbor配置
HARBOR_ADDRESS=${HARBOR_ADDRESS:-"192.168.2.254:30002"}
HARBOR_ACCOUNT=${HARBOR_ACCOUNT:-"admin"}
HARBOR_PASSWORD=${HARBOR_PASSWORD:-"Lpg_98534"}
NAMESPACE=${NAMESPACE:-"yshop"}
SECRET_NAME=${SECRET_NAME:-"harbor-registry"}

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# 检查kubectl
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl未安装"
        exit 1
    fi
}

# 创建或更新镜像拉取密钥
create_registry_secret() {
    log_info "创建Harbor镜像拉取密钥..."

    # 删除已存在的密钥
    if kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" &> /dev/null; then
        log_warn "密钥已存在，删除旧密钥..."
        kubectl delete secret "${SECRET_NAME}" -n "${NAMESPACE}"
    fi

    # 创建新密钥
    kubectl create secret docker-registry "${SECRET_NAME}" \
        --docker-server="${HARBOR_ADDRESS}" \
        --docker-username="${HARBOR_ACCOUNT}" \
        --docker-password="${HARBOR_PASSWORD}" \
        -n "${NAMESPACE}"

    log_info "Harbor镜像拉取密钥创建完成"
    log_info "密钥名称: ${SECRET_NAME}"
    log_info "命名空间: ${NAMESPACE}"
}

# 验证密钥
verify_secret() {
    log_info "验证密钥..."
    kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" -o jsonpath='{.data\.dockerconfigjson}' | base64 -d | jq .

    log_info "密钥验证完成"
}

# 主函数
main() {
    log_info "========== Harbor镜像拉取密钥配置 =========="
    log_info "Harbor地址: ${HARBOR_ADDRESS}"
    log_info "Harbor账号: ${HARBOR_ACCOUNT}"
    log_info "命名空间: ${NAMESPACE}"
    echo ""

    check_kubectl
    create_registry_secret
    verify_secret

    echo ""
    log_info "========== 配置完成 =========="
    log_info "密钥已创建，Deployment中需要配置imagePullSecrets"
    log_info "在Deployment的spec.template.spec中添加:"
    log_info "  imagePullSecrets:"
    log_info "  - name: ${SECRET_NAME}"
}

# 执行主函数
main "$@"

#!/bin/bash
# YShop一键部署到K8s脚本
# 用途: 从构建JAR包到完整部署到K8s集群的全流程自动化

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
IMAGE_NAME=${IMAGE_NAME:-"yshop-server"}
IMAGE_TAG=${IMAGE_TAG:-"latest"}
REGISTRY="${HARBOR_ADDRESS}/${HARBOR_PROJECT_NAME}"
FULL_IMAGE_NAME="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

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

EOF
}

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

check_project() {
    log_step "检查项目文件..."
    if [ ! -f "pom.xml" ]; then
        log_error "未找到pom.xml文件，请在项目根目录下执行此脚本"
        exit 1
    fi
    if [ ! -d "yshop-server" ]; then
        log_error "未找到yshop-server目录"
        exit 1
    fi
    if [ ! -f "yshop-server/Dockerfile" ]; then
        log_error "未找到Dockerfile"
        exit 1
    fi
    log_success "项目文件检查通过"
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

build_jar() {
    log_step "构建JAR包..."

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

    log_success "JAR包构建完成"
}

build_image() {
    log_step "构建Docker镜像..."
    log_info "镜像名称: ${FULL_IMAGE_NAME}"

    cd yshop-server
    docker build -t "${FULL_IMAGE_NAME}" .
    cd ..

    log_success "Docker镜像构建完成"
}

push_image() {
    log_step "推送镜像到Harbor..."
    docker push "${FULL_IMAGE_NAME}"
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

deploy_mysql() {
    log_step "部署MySQL..."

    local k8s_dir="script/k8s"

    kubectl apply -f "${k8s_dir}/01-mysql-secret.yaml"
    kubectl apply -f "${k8s_dir}/02-mysql-pvc.yaml"
    kubectl apply -f "${k8s_dir}/03-mysql.yaml"

    log_info "等待MySQL就绪..."
    kubectl wait --for=condition=ready pod -l app=mysql -n "${NAMESPACE}" --timeout=300s || true

    log_success "MySQL部署完成"
}

deploy_redis() {
    log_step "部署Redis..."

    local k8s_dir="script/k8s"

    kubectl apply -f "${k8s_dir}/04-redis-pvc.yaml"
    kubectl apply -f "${k8s_dir}/05-redis.yaml"

    log_info "等待Redis就绪..."
    kubectl wait --for=condition=ready pod -l app=redis -n "${NAMESPACE}" --timeout=180s || true

    log_success "Redis部署完成"
}

deploy_server() {
    log_step "部署后端服务..."

    local k8s_dir="script/k8s"

    # 应用ConfigMap
    kubectl apply -f "${k8s_dir}/06-server-configmap.yaml"

    # 应用Deployment（已包含Harbor镜像地址和imagePullSecrets）
    kubectl apply -f "${k8s_dir}/07-server.yaml"

    log_info "等待后端服务就绪..."
    kubectl wait --for=condition=ready pod -l app=yshop-server -n "${NAMESPACE}" --timeout=300s || true

    log_success "后端服务部署完成"
}

deploy_ingress() {
    log_step "部署Ingress..."

    local k8s_dir="script/k8s"

    kubectl apply -f "${k8s_dir}/08-ingress.yaml"

    log_success "Ingress部署完成"
}

# ==================== 验证函数 ====================

show_deployment_status() {
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
    echo ""

    if kubectl get ingress -n "${NAMESPACE}" &> /dev/null; then
        log_info "Ingress状态:"
        kubectl get ingress -n "${NAMESPACE}"
        echo ""
    fi

    log_info "访问方式:"
    log_info "  1. Ingress: http://api.yshop.local (需配置hosts)"
    log_info "  2. PortForward: kubectl port-forward svc/yshop-server 48080:48080 -n ${NAMESPACE}"
    log_info "  3. 查看日志: kubectl logs -f -l app=yshop-server -n ${NAMESPACE}"
}

show_logs() {
    log_step "查看服务日志 (Ctrl+C退出)..."
    kubectl logs -f -l app=yshop-server -n "${NAMESPACE}"
}

# ==================== 主函数 ====================

main() {
    clear
    print_banner

    log_info "========== YShop K8s 一键部署 =========="
    log_info "命名空间: ${NAMESPACE}"
    log_info "镜像名称: ${FULL_IMAGE_NAME}"
    log_info "Harbor地址: ${HARBOR_ADDRESS}"
    log_info "Harbor项目: ${HARBOR_PROJECT_NAME}"
    echo ""

    # 环境检查
    log_info "========== 第一步: 环境检查 =========="
    check_docker
    check_kubectl
    check_project
    echo ""

    # Docker镜像构建
    log_info "========== 第二步: 构建镜像 =========="
    login_harbor
    build_jar
    build_image
    push_image
    echo ""

    # K8s部署
    log_info "========== 第三步: 部署到K8s =========="
    create_namespace
    create_harbor_secret
    deploy_mysql
    deploy_redis
    deploy_server
    deploy_ingress
    echo ""

    # 验证部署
    log_info "========== 第四步: 验证部署 =========="
    sleep 5
    show_deployment_status
    echo ""

    log_success "========== 部署完成 =========="
    echo ""
    log_info "如需查看日志，请运行:"
    log_info "  kubectl logs -f -l app=yshop-server -n ${NAMESPACE}"
    echo ""
    log_info "如需重新部署，请运行:"
    log_info "  kubectl rollout restart deployment/yshop-server -n ${NAMESPACE}"
}

# 捕获Ctrl+C
trap 'echo -e "\n${RED}部署已中断${NC}"; exit 1' INT

# 执行主函数
main "$@"

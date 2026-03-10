#!/bin/bash
# YShop一键部署到K8s脚本
# 用途: 从构建JAR包到完整部署到K8s集群的全流程自动化

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

# ==================== 自动定位项目根目录 ====================

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 获取script目录的父目录（应该是yshop-drink）
YSHOP_ROOT="$(dirname "${SCRIPT_DIR}")"

# 尝试查找后端项目（包含pom.xml的目录）
PROJECT_ROOT=""
for potential_root in "${YSHOP_ROOT}"/*; do
    if [ -d "$potential_root" ] && [ -f "$potential_root/pom.xml" ]; then
        PROJECT_ROOT="$potential_root"
        break
    fi
done

# 如果没找到，尝试在script目录本身查找（兼容旧结构）
if [ -z "${PROJECT_ROOT}" ]; then
    PROJECT_ROOT="${SCRIPT_DIR}"
    while [ "${PROJECT_ROOT}" != "/" ]; do
        if [ -f "${PROJECT_ROOT}/pom.xml" ]; then
            break
        fi
        PROJECT_ROOT="$(dirname "${PROJECT_ROOT}")"
    done
fi

# 如果没找到pom.xml，尝试使用YSHOP_ROOT作为项目根目录（admin模式可能不需要后端）
if [ ! -f "${PROJECT_ROOT}/pom.xml" ]; then
    # 暂时不报错，可能在admin模式下不需要后端项目
    PROJECT_ROOT="${YSHOP_ROOT}"
fi

# 切换到项目根目录（如果存在pom.xml则切换到后端项目，否则切换到yshop-drink）
if [ -f "${PROJECT_ROOT}/pom.xml" ]; then
    cd "${PROJECT_ROOT}"
else
    cd "${YSHOP_ROOT}"
fi

# 自动定位前端项目目录
find_frontend_project() {
    log_info "自动定位前端项目..."

    # 方式1: 在yshop-drink根目录下查找
    for dir in "${YSHOP_ROOT}"/*; do
        if [ -d "$dir" ] && [ -f "$dir/package.json" ]; then
            # 检查是否是前端项目（包含vue相关或package.json中有vue）
            if grep -q "vue\|vite\|nuxt" "$dir/package.json" 2>/dev/null; then
                echo "$dir"
                return 0
            fi
        fi
    done

    # 方式2: 检查后端项目内部的子目录
    for dir in "${PROJECT_ROOT}"/*; do
        if [ -d "$dir" ] && [ -f "$dir/package.json" ]; then
            if grep -q "vue\|vite\|nuxt" "$dir/package.json" 2>/dev/null; then
                echo "$dir"
                return 0
            fi
        fi
    done

    return 1
}

# 自动设置前端项目路径
if [ -z "${ADMIN_PROJECT_PATH}" ]; then
    ADMIN_PROJECT_PATH=$(find_frontend_project)
    if [ -n "${ADMIN_PROJECT_PATH}" ]; then
        log_info "找到前端项目: ${ADMIN_PROJECT_PATH}"
    else
        log_warn "未找到前端项目"
    fi
fi

# ==================== 配置区域 ====================

# Harbor配置
HARBOR_ADDRESS=${HARBOR_ADDRESS:-"192.168.2.254:30002"}
HARBOR_ACCOUNT=${HARBOR_ACCOUNT:-"admin"}
HARBOR_PASSWORD=${HARBOR_PASSWORD:-"Lpg_98534"}
HARBOR_PROJECT_NAME=${HARBOR_PROJECT_NAME:-"ruoyi-vue-pro"}

# K8s配置
NAMESPACE=${NAMESPACE:-"yshop"}

# 后端镜像配置
IMAGE_NAME=${IMAGE_NAME:-"yshop-server"}
IMAGE_TAG=${IMAGE_TAG:-"latest"}
REGISTRY="${HARBOR_ADDRESS}/${HARBOR_PROJECT_NAME}"
FULL_IMAGE_NAME="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# 前端镜像配置
ADMIN_IMAGE_NAME=${ADMIN_IMAGE_NAME:-"yshop-admin"}
ADMIN_IMAGE_TAG=${ADMIN_IMAGE_TAG:-"latest"}
FULL_ADMIN_IMAGE="${REGISTRY}/${ADMIN_IMAGE_NAME}:${ADMIN_IMAGE_TAG}"

# 前端项目路径（可选，用于构建前端镜像）
ADMIN_PROJECT_PATH=${ADMIN_PROJECT_PATH:-""}

# 是否构建前端镜像
BUILD_ADMIN=${BUILD_ADMIN:-"false"}

# 是否跳过模板文件复制（如果已手动复制）
SKIP_TEMPLATE_COPY=${SKIP_TEMPLATE_COPY:-"false"}

# ==================== 其他函数 ====================

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
    log_info "当前目录: $(pwd)"

    # 如果当前目录不是后端项目（没有pom.xml），则跳过后端检查
    if [ ! -f "pom.xml" ]; then
        log_warn "当前目录不是后端项目，跳过后端项目检查"
        return 0
    fi

    log_info "项目根目录: ${PROJECT_ROOT}"
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

# ==================== 前端构建函数 ====================

build_admin_image() {
    if [ "${BUILD_ADMIN}" != "true" ]; then
        log_info "跳过前端镜像构建（BUILD_ADMIN=false）"
        return 0
    fi

    if [ -z "${ADMIN_PROJECT_PATH}" ]; then
        log_warn "未找到前端项目，跳过前端构建"
        log_info "提示：脚本会自动在同级目录查找前端项目"
        return 0
    fi

    if [ ! -d "${ADMIN_PROJECT_PATH}" ]; then
        log_error "前端项目路径不存在: ${ADMIN_PROJECT_PATH}"
        return 1
    fi

    log_step "准备前端构建文件..."
    log_info "前端项目: ${ADMIN_PROJECT_PATH}"
    log_info "脚本目录: ${SCRIPT_DIR}"

    # 跳过复制（如果用户已手动复制）
    if [ "${SKIP_TEMPLATE_COPY}" = "true" ]; then
        log_info "跳过模板文件复制（SKIP_TEMPLATE_COPY=true）"

        # 验证必需文件是否存在
        if [ ! -f "${ADMIN_PROJECT_PATH}/Dockerfile" ]; then
            log_error "Dockerfile 不存在，请手动复制或设置 SKIP_TEMPLATE_COPY=false"
            return 1
        fi
        if [ ! -f "${ADMIN_PROJECT_PATH}/nginx.conf" ]; then
            log_error "nginx.conf 不存在，请手动复制或设置 SKIP_TEMPLATE_COPY=false"
            return 1
        fi
        log_success "必需文件验证通过"
    else
        # 检查模板目录是否存在
        if [ ! -d "${SCRIPT_DIR}/frontend" ]; then
            log_error "模板目录不存在: ${SCRIPT_DIR}/frontend/"
            log_info "请检查 script/k8s/frontend/ 目录是否存在"
            log_info "或者设置 SKIP_TEMPLATE_COPY=true 并手动复制文件"
            return 1
        fi

        # 列出模板目录内容（调试）
        log_info "模板目录内容:"
        ls -la "${SCRIPT_DIR}/frontend/" || {
            log_error "无法列出模板目录"
            return 1
        }

        # 强制复制模板文件（确保使用最新版本）
        log_info "从模板复制构建文件到 ${ADMIN_PROJECT_PATH}..."
        cp -v "${SCRIPT_DIR}/frontend/Dockerfile" "${ADMIN_PROJECT_PATH}/" || {
            log_error "Dockerfile 复制失败"
            return 1
        }
        cp -v "${SCRIPT_DIR}/frontend/nginx.conf" "${ADMIN_PROJECT_PATH}/" || {
            log_error "nginx.conf 复制失败"
            return 1
        }
        cp -v "${SCRIPT_DIR}/frontend/.dockerignore" "${ADMIN_PROJECT_PATH}/" || {
            log_warn ".dockerignore 复制失败（非致命）"
        }
        log_success "已复制 Dockerfile、nginx.conf、.dockerignore"

        # 验证文件是否复制成功
        log_info "验证前端项目文件..."
        ls -la "${ADMIN_PROJECT_PATH}/" | grep -E "Dockerfile|nginx.conf|\.dockerignore" || {
            log_error "文件复制后验证失败"
            return 1
        }
    fi

    log_step "构建前端Docker镜像..."
    log_info "镜像名称: ${FULL_ADMIN_IMAGE}"

    # 保存当前目录
    local current_dir
    current_dir="$(pwd)"

    # 进入前端项目目录构建
    cd "${ADMIN_PROJECT_PATH}"
    docker build -t "${FULL_ADMIN_IMAGE}" .
    cd "${current_dir}"

    log_success "前端镜像构建完成"
}

push_admin_image() {
    if [ "${BUILD_ADMIN}" != "true" ]; then
        return 0
    fi

    log_step "推送前端镜像到Harbor..."
    docker push "${FULL_ADMIN_IMAGE}"
    log_success "前端镜像推送完成"
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

    kubectl apply -f "${SCRIPT_DIR}/01-mysql-secret.yaml"
    kubectl apply -f "${SCRIPT_DIR}/02-mysql-pvc.yaml"
    kubectl apply -f "${SCRIPT_DIR}/03-mysql.yaml"

    log_info "等待MySQL就绪..."
    kubectl wait --for=condition=ready pod -l app=mysql -n "${NAMESPACE}" --timeout=300s || true

    log_success "MySQL部署完成"
}

deploy_redis() {
    log_step "部署Redis..."

    kubectl apply -f "${SCRIPT_DIR}/04-redis-pvc.yaml"
    kubectl apply -f "${SCRIPT_DIR}/05-redis.yaml"

    log_info "等待Redis就绪..."
    kubectl wait --for=condition=ready pod -l app=redis -n "${NAMESPACE}" --timeout=180s || true

    log_success "Redis部署完成"
}

deploy_server() {
    log_step "部署后端服务..."

    # 应用ConfigMap
    kubectl apply -f "${SCRIPT_DIR}/06-server-configmap.yaml"

    # 应用Deployment（已包含Harbor镜像地址和imagePullSecrets）
    kubectl apply -f "${SCRIPT_DIR}/07-server.yaml"

    log_info "等待后端服务就绪..."
    kubectl wait --for=condition=ready pod -l app=yshop-server -n "${NAMESPACE}" --timeout=300s || true

    log_success "后端服务部署完成"
}

deploy_ingress() {
    log_step "部署Ingress..."

    kubectl apply -f "${SCRIPT_DIR}/08-ingress.yaml"

    log_success "Ingress部署完成"
}

deploy_admin() {
    log_step "部署前端管理界面..."

    # 检查前端配置文件是否存在
    if [ ! -f "${SCRIPT_DIR}/09-admin.yaml" ]; then
        log_warn "前端配置文件不存在，跳过前端部署"
        log_info "如需部署前端，请准备前端镜像或配置"
        return 0
    fi

    # 如果构建了前端镜像，更新部署配置
    if [ "${BUILD_ADMIN}" = "true" ]; then
        log_info "使用自定义前端镜像: ${FULL_ADMIN_IMAGE}"
        kubectl set image deployment/yshop-admin \
            yshop-admin="${FULL_ADMIN_IMAGE}" \
            -n "${NAMESPACE}"
    else
        # 使用配置文件中的默认镜像
        kubectl apply -f "${SCRIPT_DIR}/09-admin.yaml"
    fi

    # 等待前端就绪
    log_info "等待前端服务就绪..."
    kubectl wait --for=condition=ready pod -l app=yshop-admin -n "${NAMESPACE}" --timeout=180s || true

    log_success "前端管理界面部署完成"
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
    log_info "  1. 后端API Ingress: http://api.yshop.local (需配置hosts)"
    log_info "  2. 前端管理界面 Ingress: http://admin.yshop.local (需配置hosts)"
    log_info "  3. 后端PortForward: kubectl port-forward svc/yshop-server 48081:48081 -n ${NAMESPACE}"
    log_info "  4. 前端PortForward: kubectl port-forward svc/yshop-admin 8080:80 -n ${NAMESPACE}"
    log_info "  5. 查看日志: kubectl logs -f -l app=yshop-server -n ${NAMESPACE}"
}

show_logs() {
    log_step "查看服务日志 (Ctrl+C退出)..."
    kubectl logs -f -l app=yshop-server -n "${NAMESPACE}"
}

# ==================== 代码变更检测 ====================

check_code_changes() {
    log_info "检测代码变更..."

    # 检查是否在git仓库中
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_warn "不是git仓库，跳过变更检测"
        return 0
    fi

    # 获取最近的提交时间
    local last_commit
    last_commit=$(git log -1 --format="%ct" 2>/dev/null || echo "0")

    # 获取target目录的最后修改时间
    if [ -f "yshop-server/target/yshop-server.jar" ]; then
        local jar_time
        jar_time=$(stat -c "%Y" yshop-server/target/yshop-server.jar 2>/dev/null || stat -f "%m" yshop-server/target/yshop-server.jar)

        if [ "$jar_time" -lt "$last_commit" ]; then
            log_warn "JAR包比最新提交旧，建议重新构建"
            return 1
        else
            log_info "JAR包是最新的"
            return 0
        fi
    fi

    return 1
}

# ==================== 帮助信息 ====================

show_help() {
    cat << EOF
${CYAN}YShop K8s 部署脚本${NC}

用法: $0 [模式]

${GREEN}部署模式:${NC}
  full       完整部署（默认）- 构建镜像 + 部署所有K8s资源（含前后端）
  backend    后端部署 - 仅部署后端服务（不含前端）
  admin      前端部署 - 仅部署前端管理界面
  code       后端代码更新 - 仅构建JAR、镜像并更新后端应用
  config     配置更新 - 仅更新K8s配置，不重新构建
  restart    重启应用 - 仅重启Pod，使用现有镜像
  image      仅构建镜像 - 构建JAR和Docker镜像，不部署
  status     查看状态 - 显示当前部署状态
  logs       查看日志 - 实时查看应用日志
  help       显示帮助信息

${GREEN}环境变量:${NC}
  NAMESPACE           命名空间 (默认: yshop)
  IMAGE_TAG           后端镜像标签 (默认: latest)
  ADMIN_IMAGE_TAG     前端镜像标签 (默认: latest)
  HARBOR_ADDRESS      Harbor地址 (默认: 192.168.2.254:30002)
  HARBOR_ACCOUNT      Harbor账号 (默认: admin)
  HARBOR_PASSWORD     Harbor密码 (默认: Lpg_98534)
  HARBOR_PROJECT_NAME Harbor项目 (默认: ruoyi-vue-pro)
  BUILD_ADMIN         是否构建前端 (默认: false)
  ADMIN_PROJECT_PATH  前端项目路径 (可选，默认自动查找)

${GREEN}示例:${NC}
  # 完整部署（后端 + 前端，自动查找前端）
  $0 full

  # 完整部署（后端 + 前端，构建前端）
  BUILD_ADMIN=true $0 full

  # 仅部署后端
  $0 backend

  # 仅部署前端（自动查找前端项目）
  $0 admin

  # 仅部署前端（构建前端镜像）
  BUILD_ADMIN=true $0 admin

  # 后端代码快速更新
  $0 code

  # 使用自定义镜像标签
  IMAGE_TAG=v1.0.0 ADMIN_IMAGE_TAG=v1.0.0 $0 full

${YELLOW}代码更新场景说明:${NC}
  1. 修改了Java代码 → 使用 'code' 模式
  2. 修改了前端代码 → 使用 'admin' 模式（设置 BUILD_ADMIN=true）
  3. 修改了配置文件 → 使用 'config' 模式
  4. 只想重启Pod → 使用 'restart' 模式

${YELLOW}前端自动查找说明:${NC}
  脚本会自动在以下位置查找前端项目：
  1. 后端项目的父目录下的 *-vue3 目录
  2. 后端项目的父目录下包含 package.json 且有 vue 依赖的目录
  3. 后端项目内部的子目录

EOF
}

# ==================== 部署模式函数 ====================

deploy_full() {
    log_info "========== 完整部署模式 =========="

    # 环境检查
    log_info "========== 第一步: 环境检查 =========="
    check_docker
    check_kubectl
    check_project
    echo ""

    # Docker镜像构建
    log_info "========== 第二步: 构建镜像 =========="
    login_harbor

    # 构建后端镜像
    build_jar
    build_image
    push_image

    # 构建前端镜像（如果启用）
    if [ "${BUILD_ADMIN}" = "true" ] && [ -n "${ADMIN_PROJECT_PATH}" ]; then
        echo ""
        build_admin_image
        push_admin_image
    fi

    echo ""

    # K8s部署
    log_info "========== 第三步: 部署到K8s =========="
    create_namespace
    create_harbor_secret
    deploy_mysql
    deploy_redis
    deploy_server
    deploy_admin
    deploy_ingress
    echo ""

    # 验证部署
    log_info "========== 第四步: 验证部署 =========="
    sleep 5
    show_deployment_status
    echo ""

    log_success "========== 完整部署完成 =========="
}

deploy_backend_only() {
    log_info "========== 后端部署模式 =========="

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
    show_deployment_status
    echo ""

    log_success "========== 后端部署完成 =========="
}

deploy_code() {
    log_info "========== 代码更新模式 =========="
    log_warn "此模式仅更新应用代码，不修改基础设施配置"
    echo ""

    # 环境检查
    log_info "========== 第一步: 环境检查 =========="
    check_docker
    check_kubectl
    check_project

    # 检查代码变更
    check_code_changes || log_warn "代码可能已变更，将重新构建"
    echo ""

    # 构建镜像
    log_info "========== 第二步: 构建并推送镜像 =========="
    login_harbor
    build_jar
    build_image
    push_image
    echo ""

    # 更新应用
    log_info "========== 第三步: 更新应用 =========="
    log_info "更新Deployment镜像版本..."

    # 使用kubectl set image更新
    kubectl set image deployment/yshop-server \
        yshop-server="${FULL_IMAGE_NAME}" \
        -n "${NAMESPACE}"

    # 等待滚动更新完成
    log_info "等待滚动更新完成..."
    kubectl rollout status deployment/yshop-server -n "${NAMESPACE}" --timeout=300s
    echo ""

    # 验证更新
    log_info "========== 第四步: 验证更新 =========="
    show_deployment_status
    echo ""

    log_success "========== 代码更新完成 =========="
}

deploy_config() {
    log_info "========== 配置更新模式 =========="
    log_warn "此模式仅更新配置，不重新构建镜像"
    echo ""

    check_kubectl

    log_info "========== 更新配置 =========="
    create_harbor_secret

    # 重新应用ConfigMap
    kubectl apply -f "${SCRIPT_DIR}/06-server-configmap.yaml"

    # 重启Pod以应用新配置
    log_info "重启应用以应用新配置..."
    kubectl rollout restart deployment/yshop-server -n "${NAMESPACE}"

    # 等待重启完成
    kubectl rollout status deployment/yshop-server -n "${NAMESPACE}" --timeout=300s
    echo ""

    show_deployment_status
    echo ""

    log_success "========== 配置更新完成 =========="
}

deploy_restart() {
    log_info "========== 重启应用模式 =========="

    check_kubectl

    log_info "重启应用Pod..."
    kubectl rollout restart deployment/yshop-server -n "${NAMESPACE}"

    log_info "等待重启完成..."
    kubectl rollout status deployment/yshop-server -n "${NAMESPACE}" --timeout=300s
    echo ""

    show_deployment_status
    echo ""

    log_success "========== 应用重启完成 =========="
}

deploy_image_only() {
    log_info "========== 仅构建镜像模式 =========="

    check_docker
    check_project

    login_harbor
    build_jar
    build_image
    push_image

    echo ""
    log_success "========== 镜像构建完成 =========="
    log_info "镜像: ${FULL_IMAGE_NAME}"
    echo ""
    log_info "要部署此镜像，请运行:"
    log_info "  IMAGE_TAG=${IMAGE_TAG} $0 code"
}

deploy_admin_only() {
    log_info "========== 前端部署模式 =========="

    # 显示前端项目信息
    if [ -n "${ADMIN_PROJECT_PATH}" ]; then
        log_info "前端项目: ${ADMIN_PROJECT_PATH}"
    fi

    # 检查是否需要构建前端
    if [ "${BUILD_ADMIN}" = "true" ]; then
        if [ -z "${ADMIN_PROJECT_PATH}" ]; then
            log_error "未找到前端项目，无法构建"
            log_info "请确保前端项目与后端项目在同一父目录下"
            return 1
        fi

        log_info "========== 第一步: 构建前端镜像 =========="
        check_docker
        login_harbor
        build_admin_image
        push_admin_image
        echo ""
    else
        log_info "使用已有前端镜像: ${FULL_ADMIN_IMAGE}"
        echo ""
    fi

    # K8s部署
    log_info "========== 第二步: 部署到K8s =========="
    check_kubectl
    create_namespace
    create_harbor_secret
    deploy_admin
    deploy_ingress
    echo ""

    # 验证部署
    log_info "========== 第三步: 验证部署 =========="
    show_deployment_status
    echo ""

    log_success "========== 前端部署完成 =========="
}

# ==================== 主函数 ====================

main() {
    local mode="${1:-full}"

    # 显示横幅
    if [ "$mode" != "status" ] && [ "$mode" != "logs" ] && [ "$mode" != "help" ]; then
        clear
        print_banner
    fi

    # 处理特殊模式
    case "$mode" in
        help|--help|-h)
            show_help
            exit 0
            ;;
        status)
            log_info "========== 部署状态 =========="
            echo ""
            show_deployment_status
            exit 0
            ;;
        logs)
            log_info "========== 应用日志 (Ctrl+C退出) =========="
            echo ""
            kubectl logs -f -l app=yshop-server -n "${NAMESPACE}"
            exit 0
            ;;
    esac

    # 显示部署信息
    log_info "========== YShop K8s 部署 =========="
    log_info "部署模式: ${mode}"
    log_info "命名空间: ${NAMESPACE}"
    log_info "后端镜像: ${FULL_IMAGE_NAME}"
    log_info "前端镜像: ${FULL_ADMIN_IMAGE}"
    log_info "项目根目录: ${PROJECT_ROOT}"
    if [ "${BUILD_ADMIN}" = "true" ]; then
        log_info "前端构建: 是"
    fi
    echo ""

    # 根据模式执行部署
    case "$mode" in
        full)
            deploy_full
            ;;
        backend)
            deploy_backend_only
            ;;
        code)
            deploy_code
            ;;
        config)
            deploy_config
            ;;
        restart)
            deploy_restart
            ;;
        image)
            deploy_image_only
            ;;
        admin)
            deploy_admin_only
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
    log_info "查看日志:     $0 logs"
    log_info "查看状态:     $0 status"
    log_info "后端更新:     $0 code"
    log_info "前端部署:     $0 admin"
    log_info "仅后端:       $0 backend"
    log_info "完整部署:     $0 full"
}

# 捕获Ctrl+C
trap 'echo -e "\n${RED}操作已中断${NC}"; exit 1' INT

# 执行主函数
main "$@"

# 数据库URL配置流程详解

## 配置传递链路

```
ConfigMap/Secret → 环境变量 → ARGS → Java应用
```

## 详细步骤

### 第一步：定义配置源

**ConfigMap** (`06-server-configmap.yaml`) - 存储非敏感配置
```yaml
data:
  MASTER_DATASOURCE_URL: "jdbc:mysql://mysql:3306/yixiang-drink?..."
```

**Secret** (`01-mysql-secret.yaml`) - 存储敏感信息
```yaml
stringData:
  mysql-root-password: "123456"
```

### 第二步：引用配置到环境变量

**Deployment** (`07-server.yaml`) 中的 `env` 部分：

```yaml
env:
# URL来自ConfigMap
- name: MASTER_DATASOURCE_URL
  valueFrom:
    configMapKeyRef:
      name: server-config
      key: MASTER_DATASOURCE_URL

# 密码来自Secret
- name: MASTER_DATASOURCE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: mysql-secret
      key: mysql-root-password
```

### 第三步：通过ARGS传递给Java

```yaml
# 关键：使用 $() 引用其他环境变量
- name: ARGS
  value: >-
    --spring.datasource.dynamic.datasource.master.url=$(MASTER_DATASOURCE_URL)
    --spring.datasource.dynamic.datasource.master.username=$(MASTER_DATASOURCE_USERNAME)
    --spring.datasource.dynamic.datasource.master.password=$(MASTER_DATASOURCE_PASSWORD)
```

### 第四步：Dockerfile接收并启动

**Dockerfile** (`yshop-server/Dockerfile`):
```dockerfile
ENV ARGS=""
CMD java ${JAVA_OPTS} -jar app.jar $ARGS
```

K8s会自动将 `$(MASTER_DATASOURCE_URL)` 等变量展开，最终Java进程收到的命令是：

```bash
java -Xms512m -Xmx512m -jar app.jar \
  --spring.datasource.dynamic.datasource.master.url=jdbc:mysql://mysql:3306/yixiang-drink?... \
  --spring.datasource.dynamic.datasource.master.username=root \
  --spring.datasource.dynamic.datasource.master.password=123456
```

## 配置源对比

| 配置项 | 来源 | 类型 | 说明 |
|--------|------|------|------|
| URL | ConfigMap | 明文 | 连接地址 |
| Username | 硬编码/ConfigMap | 明文 | 数据库用户 |
| Password | Secret | 加密存储 | 敏感信息 |

## 验证配置

```bash
# 1. 查看ConfigMap
kubectl get configmap server-config -n yshop -o yaml

# 2. 查看Secret（已编码）
kubectl get secret mysql-secret -n yshop -o yaml

# 3. 查看Pod实际环境变量
kubectl exec -it <pod-name> -n yshop -- env | grep DATASOURCE

# 4. 查看Java进程启动参数
kubectl exec -it <pod-name> -n yshop -- ps aux | grep java
```

## 常见问题

### Q1: 为什么要用ARGS而不是直接传环境变量？

A: Spring Boot应用通过命令行参数(`--property=value`)覆盖配置文件更可控，且不会污染所有环境变量。

### Q2: $(变量名) 何时展开？

A: K8s在容器启动前展开，Java进程看到的是已替换的值。

### Q3: 如何修改数据库URL？

```bash
# 方式1: 修改ConfigMap后重启Pod
kubectl edit configmap server-config -n yshop
kubectl rollout restart deployment/yshop-server -n yshop

# 方式2: 直接修改deployment的env
kubectl set env deployment/yshop-server MASTER_DATASOURCE_URL="新URL" -n yshop
```

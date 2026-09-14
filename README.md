# sre-series


## 前置环境

- 本地 Kubernetes：`kind`
- 推荐 Kubernetes 版本：`v1.30.x`
- 推荐 kind 节点镜像：`kindest/node:v1.30.8`（可按需替换为同 minor 的更新 patch）
- 监控组件：`prometheus operator (kube-prometheus-stack)`

### 版本选择说明

- 默认优先使用 `v1.30.x`，与 `kube-prometheus-stack` 的兼容性通常更稳。
- 若需要新特性，可尝试 `v1.31.x`，但建议先验证 chart 与 CRD 兼容性。
- 尽量让本地 kind 与目标环境保持相同 minor 版本，降低迁移差异。

## 安装与初始化

> 以下示例基于 Linux（x86_64）。

### 1) 安装 `kubectl`

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
```

### 2) 安装 `kind`

```bash
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
kind --version
```

### 3) 安装 `helm`

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

### 4) 创建 kind 集群（Kubernetes `v1.30.x`）

```bash
kind create cluster --name sre-series --image kindest/node:v1.30.8
kubectl cluster-info --context kind-sre-series
kubectl get nodes
```

### 5) 安装 `kube-prometheus-stack`

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
kubectl create namespace monitoring
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
	--namespace monitoring
```

IdmXAyhl6NJ4B3HaTO4nN5V2I5tHR0g7SBVry2Hn

### 6) 验证安装

```bash
kubectl get pods -n monitoring
kubectl get servicemonitors -n monitoring
```

### 7) 删除 kind 集群

```bash
kind delete cluster --name sre-series
kind get clusters
```

若输出中不再包含 `sre-series`，说明集群已删除。


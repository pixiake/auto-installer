#!/bin/bash

set -x
set -e

# 如果没有传入 K8S_CLUSTER_NAME 退出
if [ -z "$K8S_CLUSTER_NAME" ]; then
  echo "Usage: K8S_CLUSTER_NAME=<cluster-name> ./add-cluster.sh"
  exit 1
fi

# 如果没有传入 IMAGE_REGISTRY 退出
if [ -z "$IMAGE_REGISTRY" ]; then
  echo "Usage: IMAGE_REGISTRY=<image-registry> ./add-cluster.sh"
  exit 1
fi

# 如果没有传入 K8S_CLUSTER_ROLE 退出，K8S_CLUSTER_ROLE 可以是 member、host 或 dmp 之一
if [ -z "$K8S_CLUSTER_ROLE" ]; then
  echo "Usage: K8S_CLUSTER_ROLE=<cluster-role> ./add-cluster.sh"
  exit 1
fi

# 如果没有传入 K8S_CLUSTER_TYPE 退出
if [ -z "$K8S_CLUSTER_TYPE" ]; then
  echo "Usage: K8S_CLUSTER_TYPE=<k8s-cluster-type> ./add-cluster.sh"
  exit 1
fi

# 如果没有传入 CLOUD_ENV 退出
if [ -z "$CLOUD_ENV" ]; then
  echo "Usage: CLOUD_ENV=<k8s-cluster-env> ./add-cluster.sh"
  exit 1
fi

# 设置 KUBECONFIG 为 host 集群的 kubeconfig
if [ "$K8S_CLUSTER_ROLE" == "host" ]; then
   # 设置 KUBECONFIG 为新建集群的 kubeconfig
   export KUBECONFIG=clusters/${K8S_CLUSTER_NAME}/${K8S_CLUSTER_NAME}-kubeconfig.yaml
else
   # 设置 KUBECONFIG 为 host 集群的 kubeconfig
   export KUBECONFIG=clusters/host/host-kubeconfig.yaml
fi

function member_cluster() {
  # 1. 创建 cluster
  config=$(cat <<EOF | base64 -w 0
global:
  imageRegistry: ${IMAGE_REGISTRY}
apiserver:
  image:
    tag: "v4.1.0-20240506-1"
console:
  image:
    tag: "v4.1.0-20240508-1"
controller:
  image:
    tag: "v4.1.0-20240506-1"
upgrade:
  enabled: false
cloud:
  enabled: false
EOF
  )

  cat <<EOF | kubectl apply -f -
apiVersion: cluster.kubesphere.io/v1alpha1
kind: Cluster
metadata:
  annotations:
    kubesphere.io/description: ${K8S_CLUSTER_NAME}
  labels:
    cluster.kubesphere.io/group: ${CLOUD_ENV}
  name: ${K8S_CLUSTER_NAME}
spec:
  config: $config
  connection:
    type: direct
    kubeconfig: $(cat clusters/${K8S_CLUSTER_NAME}/${K8S_CLUSTER_NAME}-kubeconfig.yaml | base64 -w 0)
  joinFederation: true
  provider: ${K8S_CLUSTER_TYPE}
EOF

  # 2. 等待 cluster Ready
  kubectl wait cluster/${K8S_CLUSTER_NAME} --for=condition=Ready --timeout=120s
}

function host_cluster() {
  # 1. 安装 ks-core
  helm upgrade --install ks-core charts/ks-core --namespace kubesphere-system --create-namespace \
       --debug \
       --wait \
       --set hostClusterName=${K8S_CLUSTER_NAME} \
       --set global.imageRegistry=${IMAGE_REGISTRY},extension.imageRegistry=${IMAGE_REGISTRY}

  # 2. 发布扩展组件
  helm template -n kubesphere-system charts/kse-extensions-publish --set museum.enabled=true,global.imageRegistry=${IMAGE_REGISTRY} | kubectl apply -f -

  # 3. 检查并创建 configmap kse-extensions-cluster-record
  if ! kubectl get cm kse-extensions-cluster-record -n kubesphere-system &> /dev/null; then
      # 如果不存在则创建
      kubectl create cm kse-extensions-cluster-record -n kubesphere-system --from-literal=common="" --from-literal=dmp=""
  fi
}

# 如果 K8S_CLUSTER_ROLE 为 member, 则执行 member cluster 任务
if [ "$K8S_CLUSTER_ROLE" == "member" ]; then
  member_cluster
fi

# 如果 K8S_CLUSTER_ROLE 为 host, 则执行 host cluster 任务
if [ "$K8S_CLUSTER_ROLE" == "host" ]; then
  host_cluster
fi

# 更新 Application CRD
#kubectl apply -f crds/application.kubesphere.io_applications.yaml
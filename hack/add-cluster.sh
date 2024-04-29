#!/bin/bash

set -x
set -e

# 如果没有传入 CLUSTER_NAME 退出
if [ -z "$CLUSTER_NAME" ]; then
  echo "Usage: CLUSTER_NAME=<cluster-name> ./add-cluster.sh"
  exit 1
fi

# 如果没有传入 IMAGE_REGISTRY 退出
if [ -z "$IMAGE_REGISTRY" ]; then
  echo "Usage: IMAGE_REGISTRY=<image-registry> ./add-cluster.sh"
  exit 1
fi

# 设置 KUBECONFIG 为 host 集群的 kubeconfig
KUBECONFIG=clusters/host/host-kubeconfig.yaml

current_dir=$(cd $(dirname $0); pwd)

# 1. 创建 cluster
config=$(cat <<EOF | base64 -w 0
global:
  imageRegistry: ${IMAGE_REGISTRY}
EOF
)

cat <<EOF | kubectl apply -f -
apiVersion: cluster.kubesphere.io/v1alpha1
kind: Cluster
metadata:
  name: ${CLUSTER_NAME}
spec:
  config: $config
  connection:
    type: direct
    kubeconfig: $(cat clusters/${CLUSTER_NAME}/${CLUSTER_NAME}-kubeconfig.yaml | base64 -w 0)
EOF

# 2. 等待 cluster Ready
kubectl wait cluster/${CLUSTER_NAME} --for=condition=Ready --timeout=120s
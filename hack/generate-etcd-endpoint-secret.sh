#!/bin/bash

set -x

# 如果没有传入 CLUSTER_NAME 退出
if [ -z "$CLUSTER_NAME" ]; then
  echo "Usage: CLUSTER_NAME=<cluster-name> ./add-cluster.sh"
  exit 1
fi

# 设置 KUBECONFIG 为新建集群的 kubeconfig
KUBECONFIG=clusters/${CLUSTER_NAME}/${CLUSTER_NAME}-kubeconfig.yaml

current_dir=$(cd $(dirname $0); pwd)

# 1. 创建 etcd-endpoint-secret-generator job
kubectl apply -f ${current_dir}/etcd-endpoint-secret-generator.yaml

# 2. 等待 etcd-endpoint-secret-generator job 完成
kubectl wait -n kubesphere-system job/etcd-endpoint-secret-generator --for=condition=complete --timeout=120s
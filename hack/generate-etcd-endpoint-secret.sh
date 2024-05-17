#!/bin/bash

set -x

# 如果没有传入 CLUSTER_NAME 退出
if [ -z "$CLUSTER_NAME" ]; then
  echo "Usage: CLUSTER_NAME=<cluster-name> ./add-cluster.sh"
  exit 1
fi

# 如果没有传入 CLUSTER_ROLE 退出
if [ -z "$CLUSTER_ROLE" ]; then
  echo "Usage: CLUSTER_ROLE=<cluster-role> ./add-cluster.sh"
  exit 1
fi

# 设置 KUBECONFIG 为新建集群的 kubeconfig
export KUBECONFIG=clusters/${CLUSTER_NAME}/${CLUSTER_NAME}-kubeconfig.yaml

# 如果 CLUSTER_ROLE 为 host，则创建 kubesphere-system namespace
if [ "$CLUSTER_ROLE" == "host" ]; then
  kubectl create ns kubesphere-system
fi

# 1. 创建 etcd-endpoint-secret-generator job
kubectl apply -f etcd-endpoint-secret-generator.yaml

# 2. 等待 etcd-endpoint-secret-generator job 完成
kubectl wait -n kubesphere-system job/etcd-endpoint-secret-generator --for=condition=complete --timeout=120s
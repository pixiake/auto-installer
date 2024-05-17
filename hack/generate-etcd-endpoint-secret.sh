#!/bin/bash

set -x

# 如果没有传入 K8S_CLUSTER_NAME 退出
if [ -z "$K8S_CLUSTER_NAME" ]; then
  echo "Usage: K8S_CLUSTER_NAME=<cluster-name> ./generate-etcd-endpoint-secret.sh"
  exit 1
fi

# 如果没有传入 K8S_CLUSTER_ROLE 退出
if [ -z "$K8S_CLUSTER_ROLE" ]; then
  echo "Usage: K8S_CLUSTER_ROLE=<cluster-role> ./generate-etcd-endpoint-secret.sh"
  exit 1
fi

# 设置 KUBECONFIG 为新建集群的 kubeconfig
export KUBECONFIG=clusters/${K8S_CLUSTER_NAME}/${K8S_CLUSTER_NAME}-kubeconfig.yaml

# 如果 K8S_CLUSTER_ROLE 为 host，则创建 kubesphere-system namespace
if [ "$K8S_CLUSTER_ROLE" == "host" ]; then
  kubectl create ns kubesphere-system
fi

# 1. 创建 etcd-endpoint-secret-generator job
kubectl apply -f etcd-endpoint-secret-generator.yaml

# 2. 等待 etcd-endpoint-secret-generator job 完成
kubectl wait -n kubesphere-system job/etcd-endpoint-secret-generator --for=condition=complete --timeout=120s
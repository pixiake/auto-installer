#!/bin/bash

set -x
set -e

# 如果没有传入 K8S_ 退出
if [ -z "$K8S_CLUSTER_NAME" ]; then
  echo "Usage: K8S_CLUSTER_NAME=<cluster-name> ./enable-extensions.sh"
  exit 1
fi

# 如果没有传入 K8S_CLUSTER_ROLE 退出，K8S_CLUSTER_ROLE 可以是 member、host 或 dmp 之一
if [ -z "$K8S_CLUSTER_ROLE" ]; then
  echo "Usage: K8S_CLUSTER_ROLE=<cluster-role> ./enable-extensions.sh"
  exit 1
fi

# 设置 KUBECONFIG 为 host 集群的 kubeconfig
export KUBECONFIG=clusters/host/host-kubeconfig.yaml

# 检查 kse-extensions-cluster-record 是否存在
if ! kubectl get cm kse-extensions-cluster-record -n kubesphere-system &> /dev/null; then
  echo "check configmap kse-extensions-cluster-record failed"
  exit 1
fi

# 获取 kse-extensions-cluster-record
common=$(kubectl get cm kse-extensions-cluster-record -n kubesphere-system -o jsonpath='{.data.common}')
dmp=$(kubectl get cm kse-extensions-cluster-record -n kubesphere-system -o jsonpath='{.data.dmp}')

# 添加 K8S_CLUSTER_NAME 到 common
if [ -z "$common" ]; then
  common=$K8S_CLUSTER_NAME
elif [[ ! $common =~ (^|,)$K8S_CLUSTER_NAME(,|$) ]]; then
  common=$common,$K8S_CLUSTER_NAME
fi

# 如果 K8S_CLUSTER_ROLE 为 dmp, 则添加 dmp
if [ "$K8S_CLUSTER_ROLE" == "dmp" ]; then
  # 添加 K8S_CLUSTER_NAME 到 dmp
  if [ -z "$dmp" ]; then
    dmp=$K8S_CLUSTER_NAME
  elif [[ ! $dmp =~ (^|,)$K8S_CLUSTER_NAME(,|$) ]]; then
    dmp=$dmp,$K8S_CLUSTER_NAME
  fi
fi

# 替换 kse-extensions/kustomization.yaml 中的 REPLACE_ME_COMMON 和 REPLACE_ME_DMP
sed -i "s/REPLACE_ME_COMMON/$common/g" kse-extensions/kustomization.yaml
sed -i "s/REPLACE_ME_DMP/$dmp/g" kse-extensions/kustomization.yaml

# 使用 kustomize 生成 installplan 并应用
kubectl kustomize kse-extensions | kubectl apply -f -

# 根据 annotation （kubesphere.io/installation-mode=Multicluster）以及annotation （app=chart）筛选 installplan
installplans=$(kubectl get installplan -o jsonpath='{.items[?(@.status.clusterSchedulingStatuses.'$K8S_CLUSTER_NAME')].metadata.name}')

# 遍历 installplans，等待所有的 installplan Ready
for installplan in $installplans; do
  kubectl wait --for=jsonpath='{.status.clusterSchedulingStatuses.'$K8S_CLUSTER_NAME'.state}'=Installed --timeout=600s installplan/$installplan
done

# 使用 kubectl patch 更新 kse-extensions-cluster-record
kubectl patch cm kse-extensions-cluster-record -n kubesphere-system --type merge -p "{\"data\":{\"common\":\"$common\",\"dmp\":\"$dmp\"}}"

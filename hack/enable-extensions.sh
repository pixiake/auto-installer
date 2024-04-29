#!/bin/bash

set -x
set -e

# 如果没有传入 CLUSTER_NAME 退出
if [ -z "$CLUSTER_NAME" ]; then
  echo "Usage: CLUSTER_NAME=<cluster-name> ./add-cluster.sh"
  exit 1
fi

# 如果没有传入 ENABLE_DMP 退出
if [ -z "$ENABLE_DMP" ]; then
  echo "Usage: ENABLE_DMP=<enable-dmp> ./add-cluster.sh"
  exit 1
fi

# 设置 KUBECONFIG 为 host 集群的 kubeconfig
export KUBECONFIG=clusters/host/host-kubeconfig.yaml

# 获取 kse-extensions-cluster-record
common=$(kubectl get cm kse-extensions-cluster-record -n kubesphere-system -o jsonpath='{.data.common}')
dmp=$(kubectl get cm kse-extensions-cluster-record -n kubesphere-system -o jsonpath='{.data.dmp}')

# 添加 CLUSTER_NAME 到 common
if [ -z "$common" ]; then
  common=$CLUSTER_NAME
else
  common=$common,$CLUSTER_NAME
fi

# 如果 ENABLE_DMP 为 true, 则添加 dmp
if [ "$ENABLE_DMP" == "true" ]; then
  # 添加 CLUSTER_NAME 到 dmp
  if [ -z "$dmp" ]; then
    dmp=$CLUSTER_NAME
  else
    dmp=$dmp,$CLUSTER_NAME
  fi
fi

# 替换 kse-extensions/kustomization.yaml 中的 REPLACE_ME_COMMON 和 REPLACE_ME_DMP
sed -i "s/REPLACE_ME_COMMON/$common/g" kse-extensions/kustomization.yaml
sed -i "s/REPLACE_ME_DMP/$dmp/g" kse-extensions/kustomization.yaml

# 使用 kustomize build 生成 kse-extensions-installplan.yaml
kustomize build kse-extensions | kubectl apply -f -

# 等待所有的 InstallPlan Ready
kubectl wait --for=condition=Installed --timeout=120s installplan --all

# 使用 kubectl patch 更新 kse-extensions-cluster-record
kubectl patch cm kse-extensions-cluster-record -n kubesphere-system --type merge -p "{\"data\":{\"common\":\"$common\",\"dmp\":\"$dmp\"}}"

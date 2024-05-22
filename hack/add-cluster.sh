#!/bin/bash

set -x
set -e

base_path=$(pwd)

export K8S_CLUSTER_NAME=$cluster_name
export IMAGE_REGISTRY="hub.kubesphere.com.cn"
export K8S_CLUSTER_ROLE=$kse_type
export K8S_CLUSTER_TYPE=$cluster_type
export CLOUD_ENV=$cloud_env
export STORAGE_CLASS=$storage_class

# 如果没有传入 K8S_CLUSTER_NAME 退出
if [ -z "$K8S_CLUSTER_NAME" ]; then
  echo "K8S_CLUSTER_NAME is required"
  exit 1
fi

# 如果没有传入 IMAGE_REGISTRY 退出
if [ -z "$IMAGE_REGISTRY" ]; then
  echo "IMAGE_REGISTRY is required"
  exit 1
fi

# 如果没有传入 K8S_CLUSTER_ROLE 退出，K8S_CLUSTER_ROLE 可以是 member、host 或 dmp 之一
if [ -z "$K8S_CLUSTER_ROLE" ]; then
  echo "K8S_CLUSTER_ROLE is required"
  exit 1
fi

# 如果没有传入 K8S_CLUSTER_TYPE 退出
if [ -z "$K8S_CLUSTER_TYPE" ]; then
  echo "K8S_CLUSTER_TYPE is required"
  exit 1
fi

# 如果没有传入 CLOUD_ENV 退出
if [ -z "$CLOUD_ENV" ]; then
  echo "CLOUD_ENV is required"
  exit 1
fi

# 设置 KUBECONFIG 为 host 集群的 kubeconfig
if [ "$K8S_CLUSTER_ROLE" == "host" ]; then
   # 设置 KUBECONFIG 为新建集群的 kubeconfig
   export KUBECONFIG=$base_path/clusters/${K8S_CLUSTER_NAME}/${K8S_CLUSTER_NAME}-kubeconfig.yaml
else
   # 设置 KUBECONFIG 为 host 集群的 kubeconfig
   export KUBECONFIG=$base_path/clusters/host/host-kubeconfig.yaml
fi

function member_cluster() {
  # 创建 cluster
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

  # 等待 cluster Ready
  kubectl wait cluster/${K8S_CLUSTER_NAME} --for=condition=Ready --timeout=300s
}

function host_cluster() {
  # 安装 ks-core
  helm upgrade --install ks-core $base_path/charts/ks-core --namespace kubesphere-system --create-namespace \
       --debug \
       --wait \
       --set hostClusterName=${K8S_CLUSTER_NAME} \
       --set global.imageRegistry=${IMAGE_REGISTRY},extension.imageRegistry=${IMAGE_REGISTRY}

  # 发布扩展组件
  helm template -n kubesphere-system $base_path/charts/kse-extensions-publish --set museum.enabled=true,global.imageRegistry=${IMAGE_REGISTRY} | kubectl apply -f -

  # 等待 extensions-museum 启动
  kubectl wait --for=condition=available --timeout=600s -n kubesphere-system  deploy/extensions-museum

  # 设置 storage class
  find $base_path/kse-extensions -type f -exec sed -i "s/REPLACE_ME_STORAGE_CLASS/${STORAGE_CLASS}/g" {} \;

  # 安装扩展组件
  kubectl apply -f $base_path/kse-extensions

  # 等待所有扩展组件 Ready
  kubectl wait --for=condition=Installed --timeout=600s installplan --all
}

# 如果 K8S_CLUSTER_ROLE 为 host, 则执行 host cluster 任务
if [ "$K8S_CLUSTER_ROLE" == "host" ]; then
  host_cluster
else
  member_cluster
fi

# 更新 Application CRD
#kubectl apply -f crds/application.kubesphere.io_applications.yaml
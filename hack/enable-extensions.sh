#!/bin/bash

set -x
set -e

base_path=$(pwd)

export K8S_CLUSTER_NAME=$cluster_name
export K8S_CLUSTER_ROLE=$kse_type
export K8S_CLUSTER_TYPE=$cluster_type
export STORAGE_CLASS=$storage_class

# 如果没有传入 K8S_ 退出
if [ -z "$K8S_CLUSTER_NAME" ]; then
  echo "K8S_CLUSTER_NAME is required"
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

# 定义多级群 extensions （该列表中仅包含多级群部署模式的 extensions）
extensions=("gateway" "metrics-server" "network" "vector" "whizard-alerting" "whizard-auditing" "whizard-events" "whizard-logging" "whizard-monitoring" "whizard-telemetry-ruler")
if [ "$K8S_CLUSTER_ROLE" == "host" ]; then
  extensions+=("devops")
elif [ "$K8S_CLUSTER_ROLE" == "dmp member" ]; then
  extensions+=("dmp")
fi

### 设置 KUBECONFIG 为 host 集群的 kubeconfig
export KUBECONFIG=$base_path/clusters/host/host-kubeconfig.yaml

### 创建 devops patch，该 patch 主要用于配置新建集群 devops 的存储类
cat <<EOF > $base_path/devops-patch.yaml
spec:
  clusterScheduling:
    overrides:
      ${K8S_CLUSTER_NAME}: |
        agent:
          jenkins:
            persistence:
              storageClass: ${STORAGE_CLASS}
    placement:
      clusters: REPLACE_ME_CLUSTERS
EOF

### 创建 dmp patch, 该 patch 主要用于配置新建集群 dmp 的存储类
cat <<EOF > $base_path/dmp-patch.yaml
spec:
  clusterScheduling:
    overrides:
      ${K8S_CLUSTER_NAME}: |
        global:
          storageClass: ${STORAGE_CLASS}
    placement:
      clusters: REPLACE_ME_CLUSTERS
EOF

### 设置是否开启 calico exporter
calico_exporter_enabled=false
if [ "$K8S_CLUSTER_TYPE" == "BM1" ]; then
  calico_exporter_enabled=true
fi

### 创建 whizard-monitoring patch
cat <<EOF > $base_path/whizard-monitoring-patch.yaml
spec:
  clusterScheduling:
    overrides:
      ${K8S_CLUSTER_NAME}: |
        kube-prometheus-stack:
          prometheus-node-exporter:
            CalicoExporter:
              enabled: $calico_exporter_enabled
    placement:
      clusters: REPLACE_ME_CLUSTERS
EOF

### 遍历 extensions，根据不同的 extension 创建 patch
for extension in ${extensions[@]}; do
  case $extension in
    "whizard-monitoring")
      new_clusters=$(kubectl get installplan whizard-monitoring -o json | jq -r -c ".spec.clusterScheduling.placement.clusters + [\"$K8S_CLUSTER_NAME\"] | unique")
      sed -i "s/REPLACE_ME_CLUSTERS/$new_clusters/g" $base_path/whizard-monitoring-patch.yaml
      kubectl patch installplan whizard-monitoring --type merge --patch-file $base_path/whizard-monitoring-patch.yaml
      ;;
    "devops")
      new_clusters=$(kubectl get installplan devops -o json | jq -r -c ".spec.clusterScheduling.placement.clusters + [\"$K8S_CLUSTER_NAME\"] | unique")
      sed -i "s/REPLACE_ME_CLUSTERS/$new_clusters/g" $base_path/devops-patch.yaml
      kubectl patch installplan devops --type merge --patch-file $base_path/devops-patch.yaml
      ;;
    "dmp")
      new_clusters=$(kubectl get installplan dmp -o json | jq -r -c ".spec.clusterScheduling.placement.clusters + [\"$K8S_CLUSTER_NAME\"] | unique")
      sed -i "s/REPLACE_ME_CLUSTERS/$new_clusters/g" $base_path/dmp-patch.yaml
      kubectl patch installplan dmp --type merge --patch-file $base_path/dmp-patch.yaml
      ;;
    *)
      ### 创建 common patch
      cat <<EOF > $base_path/$extension-patch.yaml
spec:
  clusterScheduling:
    placement:
      clusters: REPLACE_ME_CLUSTERS
EOF
      new_clusters=$(kubectl get installplan $extension -o json | jq -r -c ".spec.clusterScheduling.placement.clusters + [\"$K8S_CLUSTER_NAME\"] | unique")
      sed -i "s/REPLACE_ME_CLUSTERS/$new_clusters/g" $base_path/$extension-patch.yaml
      kubectl patch installplan $extension --type merge --patch-file $base_path/$extension-patch.yaml
      ;;
  esac
done

### 遍历 extensions，等待所有的 installplan Ready
for extension in ${extensions[@]}; do
  kubectl wait --for=jsonpath='{.status.clusterSchedulingStatuses.'$K8S_CLUSTER_NAME'.state}'=Installed --timeout=600s installplan/$extension
done

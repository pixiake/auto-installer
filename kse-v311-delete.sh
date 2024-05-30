#！/bin/bash
############################################################################################################
# 该脚本用于卸载集群中的 KSE v3.1.1
#
# 注意： 执行该脚本前请确保当前集群已从 host 集群中解绑
############################################################################################################

set -x

# 清除集群所有 namespace 中的 workspace 标签
kubectl get ns -l kubesphere.io/workspace -o name | xargs -I {} bash -c "kubectl label {} kubesphere.io/workspace- && kubectl patch {} -p '{\"metadata\":{\"ownerReferences\":[]}}' --type=merge"

# # 清除集群所有 namespace 中的 kubefed 标签
kubectl get ns -l kubefed.io/managed -o name | xargs -I {} bash -c "kubectl label {} kubefed.io/managed- && kubectl patch {} -p '{\"metadata\":{\"ownerReferences\":[]}}' --type=merge"

# 清除集群中的 workspace 以及 workspacetemplate 资源
kubectl get workspacetemplate -A -o name | xargs -I {} kubectl patch {} -p '{"metadata":{"ownerReferences":[]}}' --type=merge
kubectl get workspace -A -o name | xargs -I {} kubectl patch {} -p '{"metadata":{"ownerReferences":[]}}' --type=merge

kubectl get workspacetemplate -A -o name | xargs -I {} kubectl delete {}
kubectl get workspace -A -o name | xargs -I {} kubectl delete {}

# 删除 clusterroles
delete_cluster_roles() {
  for role in `kubectl get clusterrole -l iam.kubesphere.io/role-template -o jsonpath="{.items[*].metadata.name}"`
  do
    kubectl delete clusterrole $role 2>/dev/null
  done

  for role in `kubectl get clusterroles | grep "kubesphere" | awk '{print $1}'| paste -sd " "`
  do
    kubectl delete clusterrole $role 2>/dev/null
  done
}

delete_cluster_roles

# 删除 clusterrolebindings
delete_cluster_role_bindings() {
  for rolebinding in `kubectl get clusterrolebindings -l iam.kubesphere.io/role-template -o jsonpath="{.items[*].metadata.name}"`
  do
    kubectl delete clusterrolebindings $rolebinding 2>/dev/null
  done

  for rolebinding in `kubectl get clusterrolebindings | grep "kubesphere" | awk '{print $1}'| paste -sd " "`
  do
    kubectl delete clusterrolebindings $rolebinding 2>/dev/null
  done
}
delete_cluster_role_bindings

# 删除 validatingwebhookconfigurations
for webhook in ks-events-admission-validate users.iam.kubesphere.io network.kubesphere.io validating-webhook-configuration resourcesquotas.quota.kubesphere.io
do
  kubectl delete validatingwebhookconfigurations.admissionregistration.k8s.io $webhook 2>/dev/null
done

# 删除 mutatingwebhookconfigurations
for webhook in ks-events-admission-mutate logsidecar-injector-admission-mutate mutating-webhook-configuration
do
  kubectl delete mutatingwebhookconfigurations.admissionregistration.k8s.io $webhook 2>/dev/null
done

# 删除 users
for user in `kubectl get users -o jsonpath="{.items[*].metadata.name}"`
do
  kubectl patch user $user -p '{"metadata":{"finalizers":null}}' --type=merge
done
kubectl delete users --all 2>/dev/null

# 删除 iam 资源
for resource_type in `echo globalrolebinding loginrecord rolebase workspacerole globalrole workspacerolebinding`; do
  for resource_name in `kubectl get ${resource_type}.iam.kubesphere.io -o jsonpath="{.items[*].metadata.name}"`; do
    kubectl patch ${resource_type}.iam.kubesphere.io ${resource_name} -p '{"metadata":{"finalizers":null}}' --type=merge
  done
  kubectl delete ${resource_type}.iam.kubesphere.io --all 2>/dev/null
done

# 卸载 ks-core
helm del -n kubesphere-system ks-redis &> /dev/null || true
kubectl delete pvc -n kubesphere-system -l app=redis-ha --ignore-not-found || true
kubectl delete deploy -n kubesphere-system -l app.kubernetes.io/managed-by!=Helm --field-selector metadata.name=redis --ignore-not-found || true
kubectl delete svc -n kubesphere-system -l app.kubernetes.io/managed-by!=Helm --field-selector metadata.name=redis --ignore-not-found || true
kubectl delete secret -n kubesphere-system -l app.kubernetes.io/managed-by!=Helm --field-selector metadata.name=redis-secret --ignore-not-found || true
kubectl delete cm -n kubesphere-system -l app.kubernetes.io/managed-by!=Helm --field-selector metadata.name=redis-configmap --ignore-not-found || true
kubectl delete pvc -n kubesphere-system -l app.kubernetes.io/managed-by!=Helm --field-selector metadata.name=redis-pvc --ignore-not-found || true

kubectl delete deploy -n kubesphere-system --all --ignore-not-found
kubectl delete svc -n kubesphere-system --all --ignore-not-found
kubectl delete cm -n kubesphere-system --all --ignore-not-found
kubectl delete secret -n kubesphere-system --all --ignore-not-found
kubectl delete sa -n kubesphere-system --all --ignore-not-found

## 卸载 监控组件
# 删除 Prometheus/ALertmanager/ThanosRuler
kubectl -n kubesphere-monitoring-system delete Prometheus  k8s --ignore-not-found
kubectl -n kubesphere-monitoring-system delete secret additional-scrape-configs --ignore-not-found
kubectl -n kubesphere-monitoring-system delete serviceaccount prometheus-k8s --ignore-not-found
kubectl -n kubesphere-monitoring-system delete service prometheus-k8s --ignore-not-found
kubectl -n kubesphere-monitoring-system delete role prometheus-k8s-config --ignore-not-found
kubectl -n kubesphere-monitoring-system delete rolebinging prometheus-k8s-config --ignore-not-found

kubectl -n kubesphere-monitoring-system delete Alertmanager main --ignore-not-found
kubectl -n kubesphere-monitoring-system delete secret alertmanager-main --ignore-not-found
kubectl -n kubesphere-monitoring-system delete service alertmanager-main --ignore-not-found

kubectl -n kubesphere-monitoring-system delete ThanosRuler kubesphere --ignore-not-found

# 删除 ServiceMonitor/PrometheusRules
kubectl -n kubesphere-monitoring-system delete ServiceMonitor alertmanager coredns etcd ks-apiserver  kube-apiserver kube-controller-manager kube-proxy kube-scheduler kube-state-metrics kubelet node-exporter  prometheus prometheus-operator  s2i-operator  thanosruler --ignore-not-found
kubectl -n kubesphere-monitoring-system delete PrometheusRule kubesphere-rules prometheus-k8s-coredns-rules prometheus-k8s-etcd-rules prometheus-k8s-rules --ignore-not-found

# 删除 prometheus-operator
kubectl -n kubesphere-monitoring-system delete deployment prometheus-operator --ignore-not-found
kubectl -n kubesphere-monitoring-system delete service  prometheus-operator --ignore-not-found
kubectl -n kubesphere-monitoring-system delete serviceaccount prometheus-operator --ignore-not-found

# 删除 kube-state-metrics/node-exporter
kubectl -n kubesphere-monitoring-system delete deployment kube-state-metrics --ignore-not-found
kubectl -n kubesphere-monitoring-system delete service  kube-state-metrics --ignore-not-found
kubectl -n kubesphere-monitoring-system delete serviceaccount  kube-state-metrics --ignore-not-found

kubectl -n kubesphere-monitoring-system delete daemonset node-exporter --ignore-not-found
kubectl -n kubesphere-monitoring-system delete service node-exporter --ignore-not-found
kubectl -n kubesphere-monitoring-system delete serviceaccount node-exporter --ignore-not-found

# 删除 Clusterrole/ClusterRoleBinding
kubectl delete clusterrole kubesphere-prometheus-k8s kubesphere-kube-state-metrics kubesphere-node-exporter kubesphere-prometheus-operator
kubectl delete clusterrolebinding kubesphere-prometheus-k8s kubesphere-kube-state-metrics kubesphere-node-exporter kubesphere-prometheus-operator

# 删除 notification-manager
helm delete notification-manager -n kubesphere-monitoring-system

## 卸载 日志组件
# 删除 fluent-bit
kubectl -n kubesphere-logging-system  delete fluentbitconfigs fluent-bit-config --ignore-not-found
kubectl -n kubesphere-logging-system patch fluentbit fluent-bit -p '{"metadata":{"finalizers":null}}' --type=merge
kubectl -n kubesphere-logging-system delete fluentbit fluent-bit --ignore-not-found

# 删除 ks-logging
helm del -n kubesphere-logging-system logsidecar-injector &> /dev/null || true

# 删除 ks-events
helm del -n kubesphere-logging-system ks-events &> /dev/null || true

# 删除 kube-auditing
helm del -n kubesphere-logging-system kube-auditing &> /dev/null || true

# 清理 kubesphere-logging-system
kubectl delete deploy -n kubesphere-logging-system --all --ignore-not-found
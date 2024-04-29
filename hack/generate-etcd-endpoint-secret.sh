#!/bin/bash

set -x

current_dir=$(cd $(dirname $0); pwd)
# 1. 创建 etcd-endpoint-secret-generator job
kubectl apply -f ${current_dir}/etcd-endpoint-secret-generator.yaml

# 2. 等待 etcd-endpoint-secret-generator job 完成
kubectl wait --for=condition=complete --timeout=120s job/etcd-endpoint-secret-generator -n kubesphere-system
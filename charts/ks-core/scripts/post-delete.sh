#!/usr/bin/env bash

# set -x

CRD_NAMES=$1
MAPPING_CONFIG=$2

for extension in `kubectl get extension | grep 'Installed' | awk '{print $1}'`
do
  version=$(kubectl get extension $extension -o=jsonpath='{.status.installedVersion}')
  extensionversion=$extension-$version
  echo "Found extension $extensionversion installed"
  helm status $extension --namespace extension-$extension
  if [ $? -eq 0 ]; then
    helm mapkubeapis $extension --namespace extension-$extension --mapfile $MAPPING_CONFIG
  fi
  helm status $extension-agent --namespace extension-$extension
  if [ $? -eq 0 ]; then
    helm mapkubeapis $extension-agent --namespace extension-$extension --mapfile $MAPPING_CONFIG
  fi
done

# delete crds
for crd in `kubectl get crds -o jsonpath="{.items[*].metadata.name}"`
do
  if [[ ${CRD_NAMES[@]/${crd}/} != ${CRD_NAMES[@]} ]]; then
     scop=$(eval echo $(kubectl get crd ${crd} -o jsonpath="{.spec.scope}"))
     if [[ $scop =~ "Namespaced" ]] ; then
        kubectl get $crd -A --no-headers | awk '{print $1" "$2" ""'$crd'"}' | xargs -n 3 sh -c 'kubectl patch $2 -n $0 $1 -p "{\"metadata\":{\"finalizers\":null}}" --type=merge 2>/dev/null && kubectl delete $2 -n $0 $1 2>/dev/null'
     else
        kubectl get $crd -A --no-headers | awk '{print $1" ""'$crd'"}' | xargs -n 2 sh -c 'kubectl patch $1 $0 -p "{\"metadata\":{\"finalizers\":null}}" --type=merge 2>/dev/null && kubectl delete $1 $0 2>/dev/null'
     fi
     kubectl delete crd $crd 2>/dev/null;
  fi
done


EXTENSION_RELATED_RESOURCES='jobs.batch roles.rbac.authorization.k8s.io rolebindings.rbac.authorization.k8s.io clusterroles.rbac.authorization.k8s.io clusterrolebindings.rbac.authorization.k8s.io'

for resource in $EXTENSION_RELATED_RESOURCES;do
  echo "kubectl delete $resource -l kubesphere.io/extension-ref --all-namespaces"
  kubectl delete $resource -l kubesphere.io/managed=true --all-namespaces
done

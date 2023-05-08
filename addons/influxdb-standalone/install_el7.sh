#!/usr/bin/env bash

# You must be prepared as follows before run install.sh:
#
# 1. INFLUXDB_PWD MUST be set as environment variable, for an example:
#
#        export INFLUXDB_PWD="password"
#
# 2. INFLUXDB_STORAGECLASS_NAME MUST be set as environment variable, for an example:
#
#        export INFLUXDB_STORAGECLASS_NAME=""
#
# 3. INFLUXDB_PVC_SIZE_G MUST be set as environment variable, for an example:
#
#        export INFLUXDB_PVC_SIZE_G="50"
#
# 4. INFLUXDB_NODE_NAMES MUST be set as environment variable, for an example:
#
#        export INFLUXDB_NODE_NAMES="kube-node01"
#

readonly NAMESPACE="influxdb"
readonly CHART="bitnami/influxdb"
readonly RELEASE="influxdb-standalone"
readonly TIME_OUT_SECOND="600s"
readonly RESOURCE_LIMITS_CPU="2"
readonly RESOURCE_LIMITS_MEMORY="4Gi"
readonly RESOURCE_REQUESTS_CPU="2"
readonly RESOURCE_REQUESTS_MEMORY="4Gi"
readonly INFLUXDB_HTTP_PORT="8086"
readonly INFLUXDB_RPC_PORT="8088"

INSTALL_LOG_PATH=""

info() {
  echo "[Info][$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" | tee -a "${INSTALL_LOG_PATH}"
}

error() {
  echo "[Error][$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" | tee -a "${INSTALL_LOG_PATH}"
  exit 1
}

install_kubectl() {
  info "Install kubectl..."
  if ! curl -LOs "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"; then
    error "Fail to get kubectl, please confirm whether the connection to dl.k8s.io is ok?"
  fi
  if ! sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl; then
    error "Install kubectl fail"
  fi
  info "Kubectl install completed"
}

install_helm() {
  info "Install helm..."
  if ! curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3; then
    error "Fail to get helm installed script, please confirm whether the connection to raw.githubusercontent.com is ok?"
  fi
  chmod 700 get_helm.sh
  if ! ./get_helm.sh; then
    error "Fail to get helm when running get_helm.sh"
  fi
  info "Helm install completed"
}

install_mysql() {
  # check if mysql already installed
  if helm status ${RELEASE} -n ${NAMESPACE} &>/dev/null; then
    error "${RELEASE} already installed. Use helm remove it first"
  fi
  info "Install mysql, It might take a long time..."
  helm install ${RELEASE} ${CHART} \
    --debug \
    --namespace ${NAMESPACE} \
    --create-namespace \
    --set auth.admin.password=''"${INFLUXDB_PWD}"'' \
    --set influxdb.resources.limits.cpu=''${RESOURCE_LIMITS_CPU}'' \
    --set influxdb.resources.limits.memory=''${RESOURCE_LIMITS_MEMORY}'' \
    --set influxdb.resources.requests.cpu=''${RESOURCE_REQUESTS_CPU}'' \
    --set influxdb.resources.requests.memory=''${RESOURCE_REQUESTS_MEMORY}'' \
    --set influxdb.containerPorts.http=''"${INFLUXDB_HTTP_PORT}"'' \
    --set influxdb.containerPorts.rpc=''"${INFLUXDB_RPC_PORT}"'' \
    --set influxdb.nodeAffinityPreset.type="hard" \
    --set influxdb.nodeAffinityPreset.key="influxdb\.standalone\.node" \
    --set influxdb.nodeAffinityPreset.values='{enable}' \
    --set persistence.storageClass=''"${INFLUXDB_STORAGECLASS_NAME}"'' \
    --set persistence.size=''"${INFLUXDB_PVC_SIZE_G}Gi"'' \
    --timeout $TIME_OUT_SECOND \
    --wait 2>&1 | grep "\[debug\]" | awk '{$1="[Helm]"; $2=""; print }' | tee -a "${INSTALL_LOG_PATH}" || {
    error "Fail to install ${RELEASE}."
  }

  #TODO: check more resources after install
}

init_helm_repo() {
  info "Start add helm bitnami repo"
  helm repo add bitnami https://charts.bitnami.com/bitnami &>/dev/null || {
    error "Helm add bitnami repo error."
  }

  info "Start update helm bitnami repo"
  helm repo update bitnami 2>/dev/null || {
    error "Helm update bitnami repo error."
  }
}

verify_supported() {
  local HAS_HELM
  HAS_HELM="$(type "helm" &>/dev/null && echo true || echo false)"
  local HAS_KUBECTL
  HAS_KUBECTL="$(type "kubectl" &>/dev/null && echo true || echo false)"
  local HAS_CURL
  HAS_CURL="$(type "curl" &>/dev/null && echo true || echo false)"

  if [[ -z "${INFLUXDB_PWD}" ]]; then
    error "INFLUXDB_PWD MUST set in environment variable."
  fi

  if [[ -z "${INFLUXDB_STORAGECLASS_NAME}" ]]; then
    error "INFLUXDB_STORAGECLASS_NAME MUST set in environment variable."
  fi

  kubectl get storageclasses "${INFLUXDB_STORAGECLASS_NAME}" &>/dev/null || {
    error "storageclass resources not all ready, use kubectl to check reason"
  }

  if [[ -z "${INFLUXDB_PVC_SIZE_G}" ]]; then
    error "INFLUXDB_PVC_SIZE_G MUST set in environment variable."
  fi

  if [[ -z "${INFLUXDB_NODE_NAMES}" ]]; then
    error "INFLUXDB_NODE_NAMES MUST set in environment variable."
  fi

  local db_node_array
  IFS="," read -r -a db_node_array <<<"${INFLUXDB_NODE_NAMES}"
  for node in "${db_node_array[@]}"; do
    kubectl label node "${node}" 'mysql.standalone.node=enable' --overwrite &>/dev/null || {
      error "kubectl label node ${node} 'mysql.standalone.node=enable' failed, use kubectl to check reason"
    }
  done

  if [[ -z "${INFLUXDB_HTTP_PORT}" ]]; then
    error "INFLUXDB_HTTP_PORT MUST set in environment variable."
  fi

  if [[ -z "${INFLUXDB_RPC_PORT}" ]]; then
    error "INFLUXDB_RPC_PORT MUST set in environment variable."
  fi

  if [[ "${HAS_CURL}" != "true" ]]; then
    error "curl is required"
  fi

  if [[ "${HAS_HELM}" != "true" ]]; then
    install_helm
  fi

  if [[ "${HAS_KUBECTL}" != "true" ]]; then
    install_kubectl
  fi
}

init_log() {
  INSTALL_LOG_PATH=/tmp/mysql_install-$(date +'%Y-%m-%d_%H-%M-%S').log
  if ! touch "${INSTALL_LOG_PATH}"; then
    error "Create log file ${INSTALL_LOG_PATH} error"
  fi
  info "Log file create in path ${INSTALL_LOG_PATH}"
}

############################################
# Check if helm release deployment correctly
# Arguments:
#   release
#   namespace
############################################
verify_installed() {
  helm status "${RELEASE}" -n "${NAMESPACE}" | grep deployed &>/dev/null || {
    error "${RELEASE} installed fail, check log use helm and kubectl."
  }

  info "${RELEASE} Deployment Completed!"
}

main() {
  init_log
  verify_supported
  init_helm_repo
  install_mysql
  verify_installed
}

main

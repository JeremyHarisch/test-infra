#!/usr/bin/env bash
set -e

KYMA_PROJECT_DIR="/home/prow/go/src/github.com/kyma-project"
KLM_SOURCES_DIR="$KYMA_PROJECT_DIR/lifecycle-manager/"
#KCP_KUBECONFIG="$KYMA_PROJECT_DIR/kcp.yaml"
#SKR_KUBECONFIG="$KYMA_PROJECT_DIR/skr.yaml"

#shellcheck source=prow/scripts/lib/log.sh
source "$KYMA_PROJECT_DIR/test-infra/prow/scripts/lib/log.sh"
#shellcheck source=prow/scripts/lib/kyma.sh
source "$KYMA_PROJECT_DIR/test-infra/prow/scripts/lib/kyma.sh"
# shellcheck source=prow/scripts/lib/docker.sh
source "$KYMA_PROJECT_DIR/test-infra/prow/scripts/lib/docker.sh"


#REMOVE below if not used
#shellcheck source=prow/scripts/lib/utils.sh
source "$KYMA_PROJECT_DIR/test-infra/prow/scripts/lib/utils.sh"
# shellcheck source=prow/scripts/lib/gardener/gardener.sh
source "$KYMA_PROJECT_DIR/test-infra/prow/scripts/lib/gardener/gardener.sh"



function prereq_install() {
  log::info "Install Kyma CLI"
  kyma::install_cli

  log::info "Install k3d"
  wget -q -O - https://raw.githubusercontent.com/rancher/k3d/main/install.sh | bash

  log::info "Install istioctl"
  export ISTIO_VERSION="1.17.1"
  wget -q "https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istioctl-${ISTIO_VERSION}-linux-amd64.tar.gz"
  tar -C /usr/local/bin -xzf "istioctl-${ISTIO_VERSION}-linux-amd64.tar.gz"
  export PATH=$PATH:/usr/local/bin/istioctl
  istioctl version --remote=false
  export ISTIOCTL_PATH=/usr/local/bin/istioctl


}

function prereq_test() {
  command -v k3d >/dev/null 2>&1 || { echo >&2 "k3d not found"; exit 1; }
  command -v kyma >/dev/null 2>&1 || { echo >&2 "kyma not found"; exit 1; }
  command -v kubectl >/dev/null 2>&1 || { echo >&2 "kubectl not found"; exit 1; }
}

function provision_k3d() {
  log::info "Provisioning k3d cluster"

  k3d version
  kyma provision k3d --name=kcp -p 9080:80@loadbalancer -p 9443:443@loadbalancer --ci
  k3d kubeconfig get kcp > kcp.yaml
  log::success "Kyma K3d cluster provisioned: kcp"

  k3d cluster create skr -p 10080:80@loadbalancer -p 10443:443@loadbalancer
  k3d kubeconfig get skr > skr.yaml
  log::success "Base K3d cluster provisioned: skr"


  FILE=/etc/hosts
  if [ -f "$FILE" ]; then
      echo "127.0.0.1 k3d-registry.localhost" >> my_file.txt
  else
      log::error "$FILE does not exist."
      exit 1
  fi

  log::info "/etc/hosts file patched"
}

function installKcpComponents() {
  export KUBECONFIG=$KCP_KUBECONFIG

  istioctl install --set profile=demo -y

  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.0/cert-manager.yaml
}

prereq_install
prereq_test

docker::start

provision_k3d

installKcpComponents

pwd
cd $KLM_SOURCES_DIR
pwd
make local-deploy-with-watcher IMG=eu.gcr.io/kyma-project/lifecycle-manager:latest


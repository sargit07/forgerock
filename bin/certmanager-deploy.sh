#!/usr/bin/env bash
# Script to deploy Cert-Manager
#
# Run ./certmanager-deploy.sh to deploy with default ca cert.
# Run ./certmanager-deploy.sh -d to delete cert-manager deployment
#
# To be used if namespace gets stuck in 'terminating state'
#kubectl delete apiservice v1beta1.webhook.cert-manager.io
set -oe pipefail

VERSION="v1.6.1"
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
CM_DIR="${CURRENT_DIR}/../cluster/addons/certmanager"

# Print usage message to screen
usage() {
  printf "Usage: $0 [-d] \n\n"
  exit 2
}


helm repo add jetstack https://charts.jetstack.io
helm repo update


# Deploy cert-manager
# Add below arg if you want to cleanup all ssl certificates when deleting the platform.
#  extraArgs:
#  - --enable-certificate-owner-ref=true
deploy() {
    # Install CRDs
    kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/$VERSION/cert-manager.crds.yaml

    # Set the minumum resource limits (these work for GKE autopilot clusters)
    cat >/tmp/cert-manager-values.yaml <<EOF
global:
  leaderElection:
    # Need for GKE autopilot as the kube-system namespace is locked down
    namespace: cert-manager
resources:
  requests:
    cpu: "250m"
    memory: "512Mi"
cainjector:
  resources:
    requests:
      cpu: "250m"
      memory: "512Mi"
webhook:
  resources:
    requests:
      cpu: "250m"
      memory: "512Mi"
EOF

    helm install \
        cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --version $VERSION \
        --values /tmp/cert-manager-values.yaml


    # Install a self signed cluster issuer
    kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: default-issuer
spec:
  selfSigned: {}
EOF

}

# Delete cert-manager and namespace
delete() {
    echo "Deleting cert-manager"
    helm -n cert-manager uninstall cert-manager
    kubectl delete -f https://github.com/jetstack/cert-manager/releases/download/$VERSION/cert-manager.crds.yaml
    exit 0
}

# Validate arguments".
[ $# -gt 0 ] && [[ ! ${1} =~ ^(-d) ]] && usage
[ $# -gt 0 ] && [[ ${1} =~ "-d" ]] && delete

# Deploy cert-manager manifests
deploy

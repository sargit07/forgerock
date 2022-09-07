#!/usr/bin/env bash
# Provision EKS cluster using eksctl
# ./e

set -o errexit
set -o pipefail
set -o nounset


EXTERNAL_SNAPSHOT_VERSION=${EXTERNAL_SNAPSHOT_VERSION:=v5.0.1}
HELM_EBS_CHART_VERSION=${HELM_EBS_CHART_VERSION:=2.6.7}

usage() {
    printf "\nUsage: $0 <config file>\n\n"
    exit 1
}

# Create cluster
create_cluster() {
    eksctl create cluster -f ${file}

    # Who created this cluster.
    CREATOR="${USER:-unknown}"
    # Labels can not contain dots that may be present in the user.name
    CREATOR=$(echo $CREATOR | sed 's/\./_/' | tr "[:upper:]" "[:lower:]")

    kubectl label nodes -l alpha.eksctl.io/nodegroup-name=primary new-label=$CREATOR
    kubectl label nodes -l alpha.eksctl.io/nodegroup-name=ds new-label=$CREATOR
}



# Create IAM role mappings
createIAMMapping() {
    eksctl create iamidentitymapping --cluster $cluster_name $role-arn --group system:masters --group cdm-users
}

createStorageClasses() {
    kubectl create -f - <<EOF
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
    name: fast
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
---
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
    name: standard
provisioner: kubernetes.io/aws-ebs
parameters:
    type: gp2
EOF

    # Set default storage class to 'fast'
    kubectl patch storageclass fast -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

    # Delete gp2 storage class
    kubectl delete storageclass gp2
}


installSnapShots() {
    aws_container_images=$(kubectl get po -n kube-system -l k8s-app=aws-node -o jsonpath='{ .items[].spec.containers[].image }')
    aws_registry=$(tail -n 1 <<<$aws_container_images | cut -f1 -d '/')


    # Install SnapShot CRD
    {
        kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${EXTERNAL_SNAPSHOT_VERSION}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml;
        kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${EXTERNAL_SNAPSHOT_VERSION}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml;
        kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${EXTERNAL_SNAPSHOT_VERSION}/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml;
        echo "CSI Snapshotter CRDs successfully installed."
    } || { echo "Failed to install SnapShot CRDs"; exit 1; }

    # Install SnapShot Controller
    {
        kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${EXTERNAL_SNAPSHOT_VERSION}/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml;
        kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${EXTERNAL_SNAPSHOT_VERSION}/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml;
        echo "CSI Snapshotter controller successfully installed."
    } || { echo "Failed to install External SnapShotterCRDs"; exit 1; }

    if ! helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver;
    then
        echo "Failed to add helm aws-ebs-csi-driver repo"
        exit 1;
    fi

    if ! helm repo update;
    then
        echo "Failed to update helm repos"
        exit 1;
    fi

    if ! helm upgrade --install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
    	--version $HELM_EBS_CHART_VERSION \
    	--namespace kube-system \
    	--set image.repository="${aws_registry}/eks/aws-ebs-csi-driver" \
    	--set enableVolumeResizing=true \
    	--set enableVolumeSnapshot=true \
    	--set controller.serviceAccount.create=true \
    	--set controller.serviceAccount.name=ebs-csi-controller-sa;
        then
            echo "Failed to install ebs csi controller."
            exit 1;
    fi

    kubectl create -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: ds-snapshot-class
driver: ebs.csi.aws.com
deletionPolicy: Delete
EOF

}
if [[ "$#" != 1 ]]; then
    usage
fi

file="$1"
 # Check if yaml file exists
if [ ! -f "$file" ]; then
    printf "\nProvided config file name doesn't exist\n\n"
    usage
fi

# Get values from yaml file
cluster_name=$(grep -A1 '^metadata:$' $file | tail -n1 | awk '{ print $2 }')
region=$(grep -A2 'metadata:' $file | tail -n1 | awk '{ print $2 }')
#####
# Code for ForgeRock staff only
#####
FO_ENV=${FO_ENV:-env}
# Load and enforce tags
cd "$(dirname "$0")" && . ../../bin/lib-entsec-asset-tag-policy.sh
if [[ -f $HOME/.forgeops.${FO_ENV}.sh ]];
then
    . $HOME/.forgeops.${FO_ENV}.sh
fi

IS_FORGEROCK=$(IsForgeRock)
if [ "$IS_FORGEROCK" == "yes" ];
then
    if ! EnforceEntSecTags;
    then
        echo "ForgeRock staff are required to add specific labels to their"
        echo "Kubernetes clusters. Configure $HOME/.forgeops.${FO_ENV}.sh so that"
        echo "these labels are added to your clusters."
        exit 1
    fi
    # Check for template tool
    envsubst_installed=no
    if command -v envsubst &> /dev/null;
    then
        envsubst_installed=yes
    fi
    # Check for tags being set
    tags_set=no
    if ! grep -q '${ES_ZONE}' ${file};
    then
        tags_set=yes
    fi
    # Print message and exit since we can't really help
    if [[ "$tags_set" == "no" ]] && [[ "$envsubst_installed" == "no" ]];
    then
        echo "EntSec tags dont' appear to be configured, please make sure they are set"
        echo "Couldn't find envsubst. Can't generate profile"
        echo "Manually change the config examples are found in the current ${file}";
        exit 1
    fi
    if [[ "$tags_set" == "no" ]] && [[ "$envsubst_installed" == "yes" ]];
    then
        new_conf_name=fr-${file}
        cat "${file}" | envsubst > "${new_conf_name}"
        echo "Found envsubst. Generating EntSec tag profile for you review tag values in ${new_conf_name} and uncomment as required"
        echo "Then run $0 ${new_conf_name}"
        exit 1
    fi
fi
#####
# End code for ForgeRock staff only
#####


AWS_ACCT_ID=$(aws sts get-caller-identity --output text | awk '{ print $1 }')
echo "Creating EKS cluster..."
eksctl create cluster -f ${file}
#echo "Creating identity mappings..."
# createIAMMapping
echo "Creating storage classes..."
createStorageClasses
echo "Creating prod namespace..."
kubectl create ns prod
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.3.6/components.yaml

echo "Installing snapshots"
installSnapShots
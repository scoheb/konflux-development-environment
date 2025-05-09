#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

if [ -z "${CLUSTER_NAME}" ] ; then
  echo "undefined ENV var CLUSTER_NAME"
  exit 1
fi
if [ -z "${CLUSTER_OWNER}" ] ; then
  echo "undefined ENV var CLUSTER_OWNER"
  exit 1
fi
if [ -z "${SLACK_BOT_TOKEN}" ] ; then
  echo "undefined ENV var SLACK_BOT_TOKEN"
  exit 1
fi
if [ -z "${CLUSTER_EXPIRATION_WEEKS}" ] ; then
  echo "undefined ENV var CLUSTER_EXPIRATION_WEEKS"
  exit 1
fi

. ${SCRIPT_DIR}/notify.sh

userTuple=$(getSlackUserID "${CLUSTER_OWNER}")
if [ -z "${userTuple}" ]; then
  echo "Error getting Slack user metadata"
  exit 1
fi

if [ -z "${REGION}" ] ; then
  REGION=us-east-1
fi
if [ -z "${BASE_DOMAIN}" ] ; then
  BASE_DOMAIN=konflux-engineering.com
fi
if [ -z "${RELEASE_IMAGE}" ] ; then
  #RELEASE_IMAGE=quay.io/openshift-release-dev/ocp-release:4.13.5-multi
  #RELEASE_IMAGE=quay.io/openshift-release-dev/ocp-release:4.14.41-multi
  #RELEASE_IMAGE=quay.io/openshift-release-dev/ocp-release:4.16.24-multi #4.16.20-multi
  #RELEASE_IMAGE=4.15.39-multi
  RELEASE_IMAGE=4.16.32-multi
fi
RELEASE_IMAGE_LOCATION=quay.io/openshift-release-dev/ocp-release:${RELEASE_IMAGE}

if [ -z "${PULL_SECRET}" ] ; then
  PULL_SECRET=/home/shebert/Downloads/pull-secret.txt
fi
if [ -z "${NAMESPACE}" ] ; then
  NAMESPACE=stonesoup
fi
# update these via https://github.com/stolostron/hypershift-addon-operator/blob/main/docs/creating_role_sts_aws.md
if [ -z "${STS_CREDS}" ] ; then
  STS_CREDS=sts-creds.json
fi
if [ -z "${ROLE_ARN}" ] ; then
  ROLE_ARN=arn:aws:iam::956541543493:role/hcp-cli-role
fi
if [ -z "${AWS_CREDS}" ] ; then
  AWS_CREDS=.aws/credentials
fi
export AWS_SHARED_CREDENTIALS_FILE="${AWS_CREDS}"

if [ -z "${INSTANCE_TYPE}" ] ; then
  INSTANCE_TYPE=m5.2xlarge #updated Apr 25 was m5.xlarge # default
  #INSTANCE_TYPE=m5.2xlarge #sdouglas
  #INSTANCE_TYPE=m6i.4xlarge
  #INSTANCE_TYPE=t4g.large # for stuart for multi-arch
fi
if [ -z "${NETWORK_TYPE}" ] ; then
  NETWORK_TYPE=OVNKubernetes
  #NETWORK_TYPE=OpenShiftSDN
fi
if [ -z "${NODE_POOL_REPLICAS}" ] ; then
  # changing to 5 ... Apr 28th, 2025
  NODE_POOL_REPLICAS=5
fi

LOG_FILE=creation-log.txt

oc project $NAMESPACE

echo ""
if oc get hostedcluster/${CLUSTER_NAME} -n $NAMESPACE &>/dev/null; then
  echo "Cluster ${CLUSTER_NAME} already exists."
  while true; do
    read -p "Do you wish to delete this cluster? " yn
    case $yn in
        [Yy]* ) hypershift destroy cluster aws --name ${CLUSTER_NAME} --aws-creds ${AWS_CREDS} --namespace ${NAMESPACE}; break;;
        [Nn]* ) echo "hypershift destroy cluster aws --name ${CLUSTER_NAME} --aws-creds ${AWS_CREDS} --namespace ${NAMESPACE}" ; exit 1;;
        * ) echo "Please answer yes or no.";;
    esac
  done

  #echo ""
  #echo "destroy using: hypershift destroy cluster aws --name ${CLUSTER_NAME} --aws-creds ${AWS_CREDS} --namespace ${NAMESPACE}"
  #exit 1
fi

#echo "fyi: use https://github.com/stolostron/hypershift-addon-operator/blob/main/docs/creating_role_sts_aws.md"

echo "Refreshing STS token..."
echo ""
aws sts get-session-token --output json > ${STS_CREDS}

echo ""
echo "Starting provisioning of cluster $CLUSTER_NAME"
echo ""

HYPERSHIFT_CLI=hcp

echo ${HYPERSHIFT_CLI} create cluster aws --name $CLUSTER_NAME --node-pool-replicas=$NODE_POOL_REPLICAS --base-domain $BASE_DOMAIN --pull-secret $PULL_SECRET --sts-creds $STS_CREDS --role-arn $ROLE_ARN --region $REGION --generate-ssh --namespace=$NAMESPACE --release-image $RELEASE_IMAGE_LOCATION --instance-type $INSTANCE_TYPE --network-type $NETWORK_TYPE --control-plane-availability-policy SingleReplica --annotations resource-request-override.hypershift.openshift.io/kube-apiserver.kube-apiserver=memory=4Gi,cpu=800m --endpoint-access=Public --wait

${HYPERSHIFT_CLI} create cluster aws --name $CLUSTER_NAME --node-pool-replicas=$NODE_POOL_REPLICAS --base-domain $BASE_DOMAIN --pull-secret $PULL_SECRET --sts-creds $STS_CREDS --role-arn $ROLE_ARN --region $REGION --generate-ssh --namespace=$NAMESPACE --release-image $RELEASE_IMAGE_LOCATION --instance-type $INSTANCE_TYPE --network-type $NETWORK_TYPE --control-plane-availability-policy SingleReplica --annotations resource-request-override.hypershift.openshift.io/kube-apiserver.kube-apiserver=memory=4Gi,cpu=800m --endpoint-access=Public --wait


echo ""
echo ""
echo -n "Waiting for Cluster init to be completed: "
while ! oc get hostedcluster/${CLUSTER_NAME} -n $NAMESPACE | tail -1 | awk '{print $4}' | grep Completed ; do
  echo -n .
  sleep 1
done

echo ""
echo "Labelling cluster with expiration date and owner:"
expirationDate=$(date -d "+$CLUSTER_EXPIRATION_WEEKS weeks" '+%s')
oc label hostedcluster $CLUSTER_NAME clusterExpirationTimestamp=$expirationDate
oc label hostedcluster $CLUSTER_NAME clusterOwner=$(sed 's/@/__/g' <<< $CLUSTER_OWNER)
echo ""
oc get hostedcluster/$CLUSTER_NAME -ojson | jq -r .metadata.labels.clusterExpirationTimestamp
oc get hostedcluster/$CLUSTER_NAME -ojson | jq -r .metadata.labels.clusterOwner

export KUBEADMIN_PASSWORD=$(oc get secret/${CLUSTER_NAME}-kubeadmin-password -n $NAMESPACE -o json | jq -M .data.password | sed 's/"//g' | base64 -d)

#echo ""
#echo "Details"
#echo "" | tee -a $LOG_FILE
#echo "========================="  | tee -a $LOG_FILE
#echo "" | tee -a $LOG_FILE
#echo "Date:               $(date)" | tee -a $LOG_FILE
#echo "Console URL:        https://console-openshift-console.apps.${CLUSTER_NAME}.${BASE_DOMAIN}/" | tee -a $LOG_FILE
#echo "Kubeadmin password: $KUBEADMIN_PASSWORD" | tee -a $LOG_FILE
#echo "" | tee -a $LOG_FILE
#echo "=========================" | tee -a $LOG_FILE
#echo "" | tee -a $LOG_FILE

title="Cluster Provisioning"
message="
Details

=========================

Date:               $(date)
Console URL:        https://console-openshift-console.apps.${CLUSTER_NAME}.${BASE_DOMAIN}/
Kubeadmin password: $KUBEADMIN_PASSWORD

=========================

"

echo $message | tee -a $LOG_FILE

notifyUser "${CLUSTER_NAME}" "$CLUSTER_OWNER" "$title" "$message"
notifyUser "${CLUSTER_NAME}" "shebert@redhat.com" "$title" "ADMIN: $message"

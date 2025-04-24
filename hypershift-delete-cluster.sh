#!/bin/bash

if [ -z "${CLUSTER_NAME}" ] ; then
  echo "undefined ENV var CLUSTER_NAME"
  exit 1
fi
if [ -z "${NAMESPACE}" ] ; then
  NAMESPACE=stonesoup
fi
if [ -z "${AWS_CREDS}" ] ; then
  AWS_CREDS=.aws/credentials
fi
if [ -z "${ROLE_ARN}" ] ; then
  ROLE_ARN=arn:aws:iam::956541543493:role/hcp-cli-role
fi

echo "${AWS_CREDS}" > /tmp/aws-credentials

export AWS_SHARED_CREDENTIALS_FILE="/tmp/aws-credentials"
export AWS_CONFIG_FILE="/tmp/aws-credentials"

if [ -z "${STS_CREDS}" ] ; then
  STS_CREDS=/tmp/sts-creds.json
fi

echo "Refreshing STS token..."
echo ""
aws sts get-session-token --output json > ${STS_CREDS}

echo ""
if kubectl get hostedcluster/${CLUSTER_NAME} -n $NAMESPACE &>/dev/null; then
  echo ""
  echo "Starting deletion of cluster $CLUSTER_NAME"
  echo ""
  hcp destroy cluster aws --name ${CLUSTER_NAME} --sts-creds ${STS_CREDS} --role-arn ${ROLE_ARN} --namespace ${NAMESPACE}
else
  echo "Cluster does not exist"
  exit 1
fi

echo ""
echo ""
echo "========================="
echo ""
echo "Date:               $(date)"
echo "Cluster:            ${CLUSTER_NAME}"
echo ""
echo "========================="
echo ""

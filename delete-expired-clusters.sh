#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

NAMESPACE="stonesoup"
# cluster notification window in seconds
CLUSTER_EXPIRATION_NOTIFICATION_WINDOW=259200

CLUSTERS=$(kubectl get hostedclusters -n $NAMESPACE --no-headers | awk '{print $1}')

if [ -z "${SLACK_BOT_TOKEN}" ] ; then
  echo "undefined ENV var SLACK_BOT_TOKEN"
  exit 1
fi

. ${SCRIPT_DIR}/notify.sh

for cluster in $CLUSTERS;
do
  echo "*** $cluster"
  # check for expiration label
  hostedCluster=$(kubectl get hostedcluster/$cluster -n $NAMESPACE -ojson)
  clusterExpirationTimestamp=$(jq -r '.metadata.labels.clusterExpirationTimestamp // ""' <<< "${hostedCluster}")
  clusterOwner=$(jq -r '.metadata.labels.clusterOwner // ""' <<< "${hostedCluster}")
  if [ -z ${clusterOwner} ]; then
    clusterOwner="shebert@redhat.com"
  else
    clusterOwner=$(sed 's/__/@/g' <<< ${clusterOwner})
  fi
  if [ -n "${clusterExpirationTimestamp}" ]; then
    currentTimestamp=$(date '+%s')
    echo "current timestamp:    $currentTimestamp"
    echo "expiration timestamp: $clusterExpirationTimestamp"
    if [ $currentTimestamp -gt $clusterExpirationTimestamp ]; then
      echo "marking $cluster for deletion"
      echo ""
      export AWS_CREDS=${AWS_CREDS}
      export ROLE_ARN=${ROLE_ARN}
      export CLUSTER_NAME=$cluster
      hypershift-delete-cluster.sh

      title="Cluster Deletion"
      message="Your cluster $cluster has been deleted since it has expired"
      notifyUser "$cluster" "$clusterOwner" "$title" "$message"
      notifyUser "$cluster" "shebert@redhat.com" "$title" "ADMIN: $message"

    else
      echo "not expired"
      # checking if should be notified
      #
      set -x
      diff=$(($currentTimestamp - $clusterExpirationTimestamp))
      expired=$(($diff - $CLUSTER_EXPIRATION_NOTIFICATION_WINDOW))
      if [ $expired -gt 0 ]; then
        # less than 1 week before expiration
        clusterOwnerNotified=$(jq -r '.metadata.labels.clusterOwnerNotified // ""' <<< "${hostedCluster}")
        if [ -z "${clusterOwnerNotified}" ]; then
          # we can notify
          title="Cluster Expiration"
          expirationString=$(displaytime $diff)
          message="Your cluster $cluster will be deleted in $expirationString"

          notifyUser "$cluster" "$clusterOwner" "$title" "$message"
          notifyUser "$cluster" "shebert@redhat.com" "$title" "ADMIN: $message"
          # mark as notified
          oc label hostedcluster $cluster clusterOwnerNotified=$currentTimestamp -n $NAMESPACE
        else
          echo "already notified $clusterOwnerNotified"
        fi
      else
        echo "outside expiration window. skipping"
      fi
      set +x
    fi
  else
    echo "no clusterExpirationTimestamp label found"
  fi
done

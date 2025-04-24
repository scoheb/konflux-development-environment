#!/bin/bash

NAMESPACE="stonesoup"
# cluster notification window in seconds
CLUSTER_EXPIRATION_NOTIFICATION_WINDOW=259200

CLUSTERS=$(kubectl get hostedclusters -n $NAMESPACE --no-headers | awk '{print $1}')

if [ -z "${SLACK_BOT_TOKEN}" ] ; then
  echo "undefined ENV var SLACK_BOT_TOKEN"
  exit 1
fi

function displaytime {
  local T=$1
  local D=$((T/60/60/24))
  local H=$((T/60/60%24))
  local M=$((T/60%60))
  local S=$((T%60))
  (( $D > 0 )) && printf '%d days ' $D
  (( $H > 0 )) && printf '%d hours ' $H
  (( $M > 0 )) && printf '%d minutes ' $M
  (( $D > 0 || $H > 0 || $M > 0 )) && printf 'and '
  printf '%d seconds\n' $S
}

function send() { # expected args: user_id, user_name, cluster, message
  local userId=$1
  local userName=$2
  local cluster=$3
  local message=$4

  CHANNEL_ID=$(curl -s -X POST https://slack.com/api/conversations.open \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"users\":\"$userId\"}" | jq -r '.channel.id')

  echo $CHANNEL_ID
  cat > "/tmp/messageblocks.json" << EOF
        {
          "channel": "$CHANNEL_ID",
          "link_names": true,
          "blocks": [
            {
              "type": "header",
              "text": {
                "type": "plain_text",
                "text": "Konflux Developer Environment\n",
                "emoji": true
              }
            },
            {
              "type": "divider"
            },
            {
              "type": "rich_text",
              "elements": [
                {
                  "type": "rich_text_section",
                  "elements": [
                    {
                      "type": "text",
                      "text": "Cluster Expiration\n\n",
                      "style": {
                        "bold": true
                      }
                    },
                    {
                      "type": "text",
                      "text": "Your cluster $cluster will be deleted in $message"
                    }
                  ]
                }
              ]
            }
          ]
        }
EOF

curl -X POST https://slack.com/api/chat.postMessage \
  -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary "@/tmp/messageblocks.json"

}

function getUserID () { # expected args: email
  # Make the API call
  response=$(curl -s -X GET "https://slack.com/api/users.lookupByEmail" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -G --data-urlencode "email=$1@redhat.com")

  # Parse the user ID from the response
  user_id=$(echo "$response" | jq -r '.user.id')
  user_name=$(echo "$response" | jq -r '.user.name')

  # Check for errors
  if [[ "$user_id" == "null" ]]; then
    echo "Error: Could not find user or invalid token."
    echo "Response: $response"
    exit
  fi
  echo "$user_id,$user_name"

}

function notify () { # Expected arguments are [cluster, email, expiration]
  userTuple=$(getUserID $2)
  userId=$(echo $userTuple | cut -f1 -d,)
  userName=$(echo $userTuple | cut -f2 -d,)
  expirationString=$(displaytime $3)
  send "$userId" "$userName" "$1" "$expirationString"
}

for cluster in $CLUSTERS;
do
  echo "*** $cluster"
  # check for expiration label
  hostedCluster=$(kubectl get hostedcluster/$cluster -n $NAMESPACE -ojson)
  clusterExpirationTimestamp=$(jq -r '.metadata.labels.clusterExpirationTimestamp // ""' <<< "${hostedCluster}")
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
    else
      echo "not expired"
      # checking if should be notified
      #
      set -x
      diff=$(($currentTimestamp - $clusterExpirationTimestamp))
      expired=$(($diff - $CLUSTER_EXPIRATION_NOTIFICATION_WINDOW))
      if [ $expired -gt 0 ]; then
        # less than 1 week before expiration
        clusterOwner=$(jq -r '.metadata.labels.clusterOwner // "shebert"' <<< "${hostedCluster}")
        clusterOwnerNotified=$(jq -r '.metadata.labels.clusterOwnerNotified // ""' <<< "${hostedCluster}")
        if [ -z "${clusterOwnerNotified}" ]; then
          # we can notify
          notify $cluster $clusterOwner $diff
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

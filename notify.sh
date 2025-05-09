
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

function sendMessageToSlack() { # expected args: user_id, user_name, cluster, title, message
  local userId=$1
  local userName=$2
  local cluster=$3
  local title=$4
  local message=$5

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
                      "text": "$title\n\n",
                      "style": {
                        "bold": true
                      }
                    },
                    {
                      "type": "text",
                      "text": "$message"
                    }
                  ]
                }
              ]
            }
          ]
        }
EOF

#                      "text": "Cluster Expiration\n\n",
#                      "text": "Your cluster $cluster will be deleted in $message"

curl -X POST https://slack.com/api/chat.postMessage \
  -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary "@/tmp/messageblocks.json"

}

function getSlackUserID () { # expected args: email
  # Make the API call
  response=$(curl -s -X GET "https://slack.com/api/users.lookupByEmail" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -G --data-urlencode "email=$1")

  # Parse the user ID from the response
  user_id=$(echo "$response" | jq -r '.user.id')
  user_name=$(echo "$response" | jq -r '.user.name')

  # Check for errors
  if [[ "$user_id" == "null" ]]; then
    echo >&2 "Error: Could not find user or invalid token."
    echo >&2 "Response: $response"
    echo ""
  else
    echo "$user_id,$user_name"
  fi
}

function notifyUser () { # Expected arguments are [cluster, email, title, message]
  cluster=$1
  email=$2
  title=$3
  message=$4

  userTuple=$(getSlackUserID $email)
  if [ -n "${userTuple}" ]; then
    userId=$(echo $userTuple | cut -f1 -d,)
    userName=$(echo $userTuple | cut -f2 -d,)

    sendMessageToSlack "$userId" "$userName" "$cluster" "$title" "$message"
  fi
}

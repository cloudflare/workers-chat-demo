#! /bin/bash
#
# This script uploads the edge chat demo to your Cloudflare Workers account.
#
# This is a temporary hack needed until we add Durable Objects support to Wrangler. Once Wrangler
# support exists, this script can probably go away.
#
# On first run, this script will ask for configuration, create the Durable Object classes bindings,
# and generate metadata.json. On subsequent runs it will just update the script from source code.

set -euo pipefail

if ! which curl >/dev/null; then
  echo "$0: please install curl" >&2
  exit 1
fi

if ! which jq >/dev/null; then
  echo "$0: please install jq" >&2
  exit 1
fi

# If credentials.conf doesn't exist, prompt for the values and generate it.
if [ -e credentials.conf ]; then
  source credentials.conf
else
  echo -n "Cloudflare account ID (32 hex digits): "
  read ACCOUNT_ID
  echo -n "Cloudflare account email: "
  read AUTH_EMAIL
  echo -n "Cloudflare auth key: "
  read AUTH_KEY

  SCRIPT_NAME=edge-chat-demo

  cat > credentials.conf << __EOF__
ACCOUNT_ID=$ACCOUNT_ID
AUTH_EMAIL=$AUTH_EMAIL
AUTH_KEY=$AUTH_KEY
SCRIPT_NAME=$SCRIPT_NAME
__EOF__

  chmod 600 credentials.conf

  echo "Wrote credentials.conf with these values."
fi

# curl_api performs a curl command passing the appropriate authorization headers, and parses the
# JSON response for errors. In case of errors, exit. Otherwise, write just the result part to
# stdout.
curl_api() {
  RESULT=$(curl -s -H "X-Auth-Email: $AUTH_EMAIL" -H "X-Auth-Key: $AUTH_KEY" "$@")
  if [ $(echo "$RESULT" | jq .success) = true ]; then
    echo "$RESULT" | jq .result
    return 0
  else
    echo "API ERROR:" >&2
    echo "$RESULT" >&2
    return 1
  fi
}

# Let's verify the credentials work by listing Workers scripts and Durable Object classes. If
# either of these requests error then we're certainly not going to be able to continue.
echo "Checking credentials..."
curl_api https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/scripts >/dev/null
curl_api https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/durable_objects/classes >/dev/null

# upload_script uploads our Worker code with the appropriate metadata.
upload_script() {
  curl_api https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/scripts/$SCRIPT_NAME \
      -X PUT \
      -F "metadata=@metadata.json;type=application/json" \
      -F "script=@chat.mjs;type=application/javascript+module" \
      -F "html=@chat.html;type=application/octet-stream" > /dev/null
}

# upload_bootstrap_script is a temporary hack to work around a chicken-and-egg problem: in order
# to define a Durable Object class, we must tell it a script and class name. But when we upload our
# script, we need to configure the environment to bind to our durable object classes. This function
# uploads a version of our script with an empty environment (no bindings). The script won't be able
# to run correctly, but this gets us far enough to define the classes, and then we can upload the
# script with full environment later.
#
# This is obviously dumb and we (Cloudflare) will come up with something better soon.
upload_bootstrap_script() {
  echo '{"main_module": "chat.mjs"}' > bootstrap-metadata.json
  curl_api https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/scripts/$SCRIPT_NAME \
      -X PUT \
      -F "metadata=@bootstrap-metadata.json;type=application/json" \
      -F "script=@chat.mjs;type=application/javascript+module" \
      -F "html=@chat.html;type=application/octet-stream" > /dev/null
  rm bootstrap-metadata.json
}

# upsert_class configures a Durable Object class so that instances of it can be created and called
# from other scripts (or from the same script). This function checks if the class already exists,
# creates it if it doesn't, and either way writes the class ID to stdout.
#
# The class ID can be used to configure environment bindings in other scripts (or even the same
# script) such that they can send messages to instances of this class.
upsert_class() {
  # Check if the class exists already.
  EXISTING_ID=$(\
      curl_api https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/durable_objects/classes | \
      jq -r ".[] | select(.script == \"$SCRIPT_NAME\" and .class == \"$1\") | .id")

  if [ "$EXISTING_ID" != "" ]; then
    echo $EXISTING_ID
    return
  fi

  # No. Create it.
  curl_api https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/durable_objects/classes \
      -X POST --data "{\"name\": \"$SCRIPT_NAME-$1\", \"script\": \"$SCRIPT_NAME\", \"class\": \"$1\"}" | \
      jq -r .id
}

if [ ! -e metadata.json ]; then
  # If metadata.json doesn't exist we assume this is first-time setup and we need to create the
  # classes.

  upload_bootstrap_script
  ROOMS_ID=$(upsert_class ChatRoom)
  LIMITERS_ID=$(upsert_class RateLimiter)

  cat > metadata.json << __EOF__
{
  "main_module": "chat.mjs",
  "bindings": [
    {
      "type": "durable_object_class",
      "name": "rooms",
      "class_id": "$ROOMS_ID"
    },
    {
      "type": "durable_object_class",
      "name": "limiters",
      "class_id": "$LIMITERS_ID"
    }
  ]
}
__EOF__
fi

upload_script

echo "App uploaded to your account under the name: $SCRIPT_NAME"
echo "You may deploy it to a specific host in the Cloudflare Dashboard."

#!/bin/bash
set -o pipefail
# get_sa_token.sh - run inside your restricted environment
# Create RS256 JWT claim for a service account
# and get an auth token based on it.
# Not using any external binaries (jq,python).

# Inspired by https://stackoverflow.com/questions/46657001/how-do-you-create-an-rs256-jwt-assertion-with-bash-shell-scripting/46672439#46672439
MASTER_URL="leader.mesos"
svc_account=${SA_NAME:-"default"}
secret=$(echo ${SA_SECRET} | jq -r .private_key)

b64enc() { openssl enc -base64 -A | tr '+/' '-_' | tr -d '='; }
rs_sign() { openssl dgst -binary -sha256 -sign <(printf '%s\n' "$1"); }

# Claim header and payload
header='{"typ":"JWT","alg":"RS256"}'
payload='{"uid":"'${svc_account}'"}'

signed_content="$(printf %s "$header" | b64enc).$(printf %s "$payload" | b64enc)"
sig=$(printf %s "$signed_content" | rs_sign "$secret" | b64enc)
claim=$(printf '%s.%s' "${signed_content}" "${sig}")

echo '{"uid":"'${svc_account}'","token":"'${claim}'"}' > login_token.json
# Request auth token based on the claim
curl --cacert dcos-ca.crt -X POST -H "content-type:application/json" -d @login_token.json  ${MASTER_URL}/acs/api/v1/auth/login > authorization_token.json
# Get just the token part from the json response (no jq)
token=$(cat authorization_token.json | grep "token" | cut -d':' -f2 | tr -d '"' | tr -d [:space:])
echo "${token}" > token

# Cleanup
rm login_token.json authorization_token.json


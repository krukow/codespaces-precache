#!/bin/bash

get_status () {
  local job_id="$1"
  status_data=$(curl "${GITHUB_API_URL}/vscs_internal/codespaces/repository/${GITHUB_REPOSITORY}/prebuild_templates/provisioning_statuses/${job_id}" \
    -H "Content-Type: application/json; charset=utf-8" \
    -H "Authorization: token $GITHUB_TOKEN")
}

poll_status () {
  local job_id="$1"
  local attempt="${2:-1}"

  get_status "$job_id"

  state=$(echo $status_data | jq -r '.state') 

  if [[ "$state" == "succeeded" ]]; then
    return 0
  elif [[ "$state" == "failed" ]]; then
    return 1
  else
    sleep ${POLLING_DELAY:-5}
    poll_status "$job_id" $(($attempt+1))
  fi
}

handle_error() {
  error_message=$(jq -r '.message' response_body.txt)
  >&2 echo "*************************"
  >&2 echo "Error message from server"
  >&2 echo "$error_message"
  >&2 echo "*************************"
  exit 1
}

if [[ -n "$INPUT_TARGET" ]]; then
  target="\"vscs_target\":\"$INPUT_TARGET\","
fi

if [[ -n "$INPUT_TARGET_URL" ]]; then
  target_url="\"vscs_target_url\":\"$INPUT_TARGET_URL\","
fi

for region in $INPUT_REGIONS; do
  body=$(cat <<-JSON
    {
      $target
      $target_url
      "ref": "$GITHUB_REF",
      "location": "$region",
      "sku_name": "$INPUT_SKU_NAME",
      "sha": "$GITHUB_SHA"
    }
JSON
)
  http_code=$(curl -X POST "${GITHUB_API_URL}/vscs_internal/codespaces/repository/${GITHUB_REPOSITORY}/prebuild/templates" \
    -H "Content-Type: application/json; charset=utf-8" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -d "$body" \
    -o response_body.txt \
    -w "%{http_code}")

  if [ $http_code != "200" ]; then
    handle_error
  else
    job_id=$(jq -r '.job_status_id' response_body.txt)
    poll_status $job_id
  fi
done

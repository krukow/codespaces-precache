#!/bin/bash

get_status () {
  local job_id="$1"
  status=$(curl "${GITHUB_API_URL}/vscs_internal/codespaces/repository/${GITHUB_REPOSITORY}/prebuild_templates/provisioning_statuses/${job_id}" \
    -H "Content-Type: application/json; charset=utf-8" \
    -H "Authorization: token $GITHUB_TOKEN")
}

poll_status () {
  local job_id="$1"
  local attempt="${2:-1}"

  get_status "$job_id"

  echo $status

  if [[ "$status" == *complete* ]]; then
    return 0
  elif [[ "$attempt" -ge ${MAX_POLLING_ATTEMPTS:-600} ]]; then
    >&2 echo "Giving up after $attempt attempts to get the provisioning status"
    return 1
  else
    sleep ${POLLING_DELAY:-5}
    poll_status "$job_id" $(($attempt+1))
  fi
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
  response=$(curl -X POST "${GITHUB_API_URL}/vscs_internal/codespaces/repository/${GITHUB_REPOSITORY}/prebuild/templates" \
    -H "Content-Type: application/json; charset=utf-8" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -d "$body")
  job_id=$(echo $response | jq -r '.job_status_id') 
  poll_status $job_id
done

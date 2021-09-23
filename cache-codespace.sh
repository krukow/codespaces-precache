#!/bin/bash

set -x

get_status () {
  local job_id="$1"
  local result=$(curl "${GITHUB_API_URL}/vscs_internal/codespaces/repository/${GITHUB_REPOSITORY}/prebuild_templates/provisioning_statuses/${job_id}" \
    -H "Content-Type: application/json; charset=utf-8" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -s)
  echo $result
}

display_template_failure() {
  local status_data="$1"

  error_logs_available="$(echo $status_data | jq -r '.error_logs_available')"
  message="$(echo $status_data | jq -r '.message')"

  if [[ "$error_logs_available" == "true" ]]; then
    guid="$(echo $status_data | jq -r '.guid')"
    build_logs=$(curl "${GITHUB_API_URL}/vscs_internal/codespaces/repository/${GITHUB_REPOSITORY}/prebuilds/environments/$guid/logs" \
      -H "Content-Type: application/json; charset=utf-8" \
      -H "Authorization: token $GITHUB_TOKEN" \
      -s )
    handle_error_message "$build_logs"
  elif [ "$message" != "null" ]; then
    handle_error_message "$status_data"
  else
    handle_error_message "Something went wrong, please try again. Error Response: ${status_data}"
  fi
}

poll_status () {
  local job_id="$1"
  local attempt="${2:-1}"

  if [[ $attempt == 1 ]]; then 
    echo "codespace caching in progress, this may take a while..."
  else
    echo "still in progress..."
  fi

  local status_data=$(get_status "$job_id")

  state=$(echo $status_data | jq -r '.state')

  if [[ "$state" == "succeeded" ]]; then
    echo "A precached codespace has been created successfully!"
    return 0
  elif [[ "$state" == "failed" ]]; then
    display_template_failure "$status_data"
    return 1
  elif [[ "$state" == "processing" ]]; then 
    sleep ${POLLING_DELAY:-60}
    poll_status "$job_id" $(($attempt+1))
  else
    display_template_failure "$status_data"
    return 1
  fi
}

handle_error_message() {
  local error_message="$1"
  >&2 echo "*************************Error*************************"
  >&2 echo "$error_message"
  >&2 echo "*************************Error*************************"
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

echo "Requesting new codespace to be created & cached..."
  response=$(curl -X POST "${GITHUB_API_URL}/vscs_internal/codespaces/repository/${GITHUB_REPOSITORY}/prebuild/templates" \
    -H "Content-Type: application/json; charset=utf-8" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -d "$body" \
    -s \
    -w "%{http_code}" )
  http_code=${response: -3}
  response_body=$(echo ${response} | head -c-4)
  if [ "$http_code" != "200" ]; then
    handle_error_message "$response_body"
    exit 1
  else
    job_id=$(echo $response_body | jq -r '.job_status_id')
    poll_status $job_id
  fi
done

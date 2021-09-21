#!/bin/bash

get_status () {
  local job_id="$1"
  status_data=$(curl "${GITHUB_API_URL}/vscs_internal/codespaces/repository/${GITHUB_REPOSITORY}/prebuild_templates/provisioning_statuses/${job_id}" \
    -H "Content-Type: application/json; charset=utf-8" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -s)
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
    handle_error_message "$message"
  else
    handle_error_message "Something went wrong, please try again."
  fi
}

poll_status () {
  local job_id="$1"
  local attempt="${2:-1}"

  if [[ $attempt > 10 ]]; then 
    echo "creation in progress, this may take a while..."
  else
    echo "still in progress..."
  fi

  get_status "$job_id"

  state=$(echo $status_data | jq -r '.state')

  if [[ "$state" == "succeeded" ]]; then
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
  response=$(curl -X POST "${GITHUB_API_URL}/vscs_internal/codespaces/repository/${GITHUB_REPOSITORY}/prebuild/templates" \
    -H "Content-Type: application/json; charset=utf-8" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -d "$body" \
    -s \
    -w "%{http_code}" )
  http_code=${response: -3}
  response_body=$(echo ${response} | head -c-4)
  if [ "$http_code" != "200" ]; then
    handle_error_message "$(echo $response_body | jq -r '.message')"
    exit 1
  else
    job_id=$(echo $response_body | jq -r '.job_status_id')
    poll_status $job_id
  fi
done

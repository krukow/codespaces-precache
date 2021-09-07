#!/bin/bash

get_status () {
  local job_id="$1"
  status_data=$(curl "${GITHUB_API_URL}/vscs_internal/codespaces/repository/${GITHUB_REPOSITORY}/prebuild_templates/provisioning_statuses/${job_id}" \
    -H "Content-Type: application/json; charset=utf-8" \
    -H "Authorization: token $GITHUB_TOKEN")
}

display_template_failure() {
  local status_data="$1"

  error_logs_available="$(echo $status_data | jq -r '.error_logs_available')"
  message="$(echo $status_data | jq -r '.message')"

  if [[ "$error_logs_available" == "true" ]]; then
    guid="$(echo $status_data | jq -r '.guid')"
    build_logs=$(curl "${GITHUB_API_URL}/vscs_internal/codespaces/repository/${GITHUB_REPOSITORY}/prebuilds/environments/$guid/logs" \
      -H "Content-Type: application/json; charset=utf-8" \
      -H "Authorization: token $GITHUB_TOKEN")
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

  get_status "$job_id"

  state=$(echo $status_data | jq -r '.state')

  if [[ "$state" == "succeeded" ]]; then
    return 0
  elif [[ "$state" == "failed" ]]; then
    display_template_failure "$status_data"
    return 1
  else
    sleep ${POLLING_DELAY:-5}
    poll_status "$job_id" $(($attempt+1))
  fi
}

handle_error_message() {
  local error_message="$1"
  >&2 echo "*************************"
  >&2 echo "Error message from server"
  >&2 echo "$error_message"
  >&2 echo "*************************"
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
    handle_error_message "$(jq -r '.message' response_body.txt)"
    exit 1
  else
    job_id=$(jq -r '.job_status_id' response_body.txt)
    poll_status $job_id
  fi
done

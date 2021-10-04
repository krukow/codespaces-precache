#!/bin/bash

declare -a RESPONSES=()
declare -a JOB_IDS=()
declare -A JOB_DATA
declare -a IMMEDIATE_FAILURES=()

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
  local job_id="$2"

  local error_logs_available="$(echo $status_data | jq -r '.error_logs_available')"
  local message="$(echo $status_data | jq -r '.message')"

  local guid="$(echo $status_data | jq -r '.guid')"
  if [[ "$error_logs_available" == "true" ]]; then
    build_logs=$(curl "${GITHUB_API_URL}/vscs_internal/codespaces/repository/${GITHUB_REPOSITORY}/prebuilds/environments/$guid/logs" \
      -H "Content-Type: application/json; charset=utf-8" \
      -H "Authorization: token $GITHUB_TOKEN" \
      -s )
    handle_job_error "$build_logs" "${job_id}"
  else
    handle_job_error "Something went wrong, please try again.\n${status_data}" "${job_id}"
  fi
}

poll_status () {
  local -n job_ids="$1"
  local -n job_data="$2"
  local -n immediate_failures="$3"
  local -A job_final_states
  local -A failure_messages
  
  poll_all_statuses "1" "${job_ids[@]}"

  # Print error messages for all failed jobs
  if [ "${#failure_messages[@]}" -ne 0 ]; then
    for job in "${!failure_messages[@]}"; do
      display_template_failure "${failure_messages[$job]}" "${job}"
    done
  fi

  local code=0
  error_count=${#immediate_failures[@]}
  echo "================ACTION STATUS SUMMARY================"
  for job_id in "${!job_data[@]}"; do
    if [[ "${job_final_states[$job_id]}" != "succeeded" ]]; then
      error_count=$(($error_count + 1))
      code=1
    fi
    # Print state for each job
    location=$(echo ${job_data[$job_id]} | jq -r '.location')
    echo -e "job_id: $job_id | status: ${job_final_states[$job_id]} | location: $location"
  done
  echo "Error Count: $error_count"

  # Print immediate failures
  if [ "${#immediate_failures[@]}" -ne 0 ]; then
    handle_error_messages "${immediate_failures[@]}"
    code=1
  fi

  return $code
}

poll_all_statuses () {
  local attempt="$1"
  shift
  local -a job_ids=($@)
  
  local -a jobs_processing=()

  if [[ $attempt == 1 ]]; then 
    echo "codespace caching in progress, this may take a while..."
  else
    echo "still in progress..."
  fi

  for job_id in "${job_ids[@]}"; do

    local status_data=$(get_status "$job_id")

    state=$(echo $status_data | jq -r '.state')

    if [[ "$state" == "succeeded" ]]; then
      job_final_states["$job_id"]+="succeeded"
    elif [[ "$state" == "failed" ]]; then
      failure_messages["$job_id"]+="$status_data"
      job_final_states["$job_id"]+="failed"
    elif [[ "$state" == "processing" ]]; then 
      jobs_processing+=("$job_id")
    else
      failure_messages["$job_id"]+="$status_data"
      job_final_states["$job_id"]+="$state"
    fi
  done

  # Continue to poll only for jobs that are still processing
  if [ ${#jobs_processing[@]} -ne 0 ]; then
    sleep ${POLLING_DELAY:-60}

    poll_all_statuses $(($attempt+1)) "${jobs_processing[@]}"
  fi
}

handle_job_error() {
  local error_message="$1"
  local job_id="$2"
  >&2 echo "*************************Error***********************"
  >&2 echo -e "$error_message"
  >&2 echo "Job ID: ${job_id}"
  >&2 echo "*****************************************************"
}

handle_error_messages() {
  local error_messages=("$@")
  >&2 echo "***********************Errors*************************"
  for error in "${error_messages[@]}"; do
    >&2 echo -e "$error"
    >&2 echo "******************************************************"
  done
}

if [[ -n "$INPUT_TARGET" ]]; then
  target="\"vscs_target\":\"$INPUT_TARGET\","
fi

if [[ -n "$INPUT_TARGET_URL" ]]; then
  target_url="\"vscs_target_url\":\"$INPUT_TARGET_URL\","
fi

echo "Requesting new codespace(s) to be created & cached..."

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
  response="$(curl -X POST "${GITHUB_API_URL}/vscs_internal/codespaces/repository/${GITHUB_REPOSITORY}/prebuild/templates" \
    -H "Content-Type: application/json; charset=utf-8" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -d "$body" \
    -s \
    -w "%{http_code}" )"

  http_code=${response: -3}
  response_body=$(echo ${response} | head -c-4)
  if [ "$http_code" != "200" ]; then
    IMMEDIATE_FAILURES+=("$response_body")
  else
    RESPONSES+=("$response")
  fi
done

for response in "${RESPONSES[@]}"; do
  response_body=$(echo ${response} | head -c-4)
    job_id=$(echo $response_body | jq -r '.job_status_id')
    JOB_IDS+=($job_id)
    JOB_DATA["$job_id"]+="${response_body}"
done

if [ "${#JOB_IDS[@]}" -ne 0 ]; then
  # only poll jobs if at least one job was queued
  poll_status JOB_IDS JOB_DATA IMMEDIATE_FAILURES
else
  # Error immediately if all failed
  echo "Error Count: ${#IMMEDIATE_FAILURES[@]}"
  handle_error_messages "${IMMEDIATE_FAILURES[@]}"
  exit 1
fi
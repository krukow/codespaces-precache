#!/bin/bash

if [[ -n "$INPUT_TARGET" ]]; then
  target="\"vscs_target\":\"$INPUT_TARGET\""
fi

if [[ -n "$INPUT_TARGET_URL" ]]; then
  target_url="\"vscs_target_url\":\"$INPUT_TARGET_URL\""
fi

values=($target_url $target)

for value in "${values[@]}"; do
  if [[ -z "$additional_body" ]]; then
    additional_body=",$value"
  else
    additional_body="$additional_body,$value"
  fi
done

for region in $INPUT_REGIONS; do
  body=$(cat <<-JSON
    {
      "ref": "$GITHUB_REF",
      "location": "$region",
      "sku_name": "$INPUT_SKU_NAME",
      "sha": "$GITHUB_SHA"
      $additional_body
    }
JSON
)
  curl -X POST "${GITHUB_API_URL}/vscs_internal/codespaces/repository/${GITHUB_REPOSITORY}/prebuild/templates" \
    -H "Content-Type: application/json; charset=utf-8" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -d "$body"
done

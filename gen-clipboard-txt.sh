#!/usr/bin/env zsh
#
# gen-clipboard-txt.sh
#   Save clipboard text to a .txt file named via OpenAI.
#
# Requirements: jq, curl, pbpaste, $OPENAI_API_KEY, $OPENAI_ENDPOINT
#
# Usage examples
#   gen-clipboard-txt            # default: o4-mini  (temp forced to 1.0)
#   gen-clipboard-txt gpt-4o     # choose another model (temp 0.3)

function gen-clipboard-txt() {
  ###########################################################################
  # 0. Model & temperature
  ###########################################################################
  local model="${1:-o4-mini}"
  local temperature="0.3"
  [[ "$model" == "o4-mini" ]] && temperature="1.0"   # o4-mini requires 1.0

  ###########################################################################
  # 1. Preconditions
  ###########################################################################
  if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    echo "ERROR: OPENAI_API_KEY is not set." >&2
    return 1
  fi

  if [[ -z "${OPENAI_ENDPOINT:-}" ]]; then
    echo "ERROR: OPENAI_ENDPOINT is not set." >&2
    return 1
  fi

  if ! command -v jq curl pbpaste >/dev/null; then
    echo "ERROR: jq, curl, and pbpaste must be in PATH." >&2
    return 1
  fi

  local clip
  clip="$(pbpaste)"
  if [[ -z "$clip" ]]; then
    echo "Clipboard is empty." >&2
    return 1
  fi

  ###########################################################################
  # 2. Build Chat-Completions request
  ###########################################################################
  local request_json
  request_json="$(jq -n --arg text "$clip" --arg model "$model" --arg temp "$temperature" '
    {
      model:       $model,
      temperature: ($temp | tonumber),
      messages: [
        { role: "system",
          content: "You provide short, lowercase, hyphenated file names summarizing given text. Respond with only the name, no extension." },
        { role: "user",
          content: "Suggest a file name for the following text:\n\n\($text)" }
      ]
    }')"

  ###########################################################################
  # 3. Call OpenAI API – capture body & status
  ###########################################################################
  local end_point="$OPENAI_ENDPOINT"
  local tmp_rsp; tmp_rsp="$(mktemp)"
  local http_code
  http_code="$(
    curl -sS -w '%{http_code}' -o "$tmp_rsp" \
      $end_point \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $OPENAI_API_KEY" \
      -d "$request_json"
  )"

  local response; response="$(<$tmp_rsp)"; rm -f "$tmp_rsp"

  if (( http_code >= 300 )); then
    echo "ERROR: HTTP $http_code returned by OpenAI API." >&2
    echo "$response" | jq -C '.' >&2 || echo "$response" >&2
    return 1
  fi

  ###########################################################################
  # 4. Detect JSON-level errors
  ###########################################################################
  if jq -e '.error' >/dev/null <<<"$response"; then
    echo "ERROR from OpenAI API:" >&2
    echo "$response" | jq -C '.error' >&2
    return 1
  fi

  ###########################################################################
  # 5. Extract assistant file name
  ###########################################################################
  local file_base
  file_base=$(jq -r '.choices[0].message.content' <<<"$response" | tr -d ' "')
  if [[ -z "$file_base" || "$file_base" == "null" ]]; then
    echo "ERROR: Empty or malformed response." >&2
    echo "$response" | jq -C '.' >&2 || echo "$response" >&2
    return 1
  fi

  local file_name="${file_base}.txt"
  local n=1
  while [[ -e "$file_name" ]]; do
    file_name="${file_base}-${n}.txt"
    ((n++))
  done

  ###########################################################################
  # 6. Write file
  ###########################################################################
  echo "$clip" > "$file_name"
  echo "Saved to $file_name"
}


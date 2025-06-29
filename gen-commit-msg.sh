#!/usr/bin/env zsh
#
# gen-commit-msg.sh
#   Generate an English conventional-commit message from the staged diff,
#   print it, and copy it to the clipboard (pbcopy, macOS).
#
# Requirements: jq, curl, pbcopy, $OPENAI_API_KEY
#
# Usage examples
#   git add .
#   gen-commit-msg            # default: o4-mini  (temp forced to 1.0)
#   gen-commit-msg gpt-4o     # choose another model (temp 0.3)

function gen-commit-msg() {
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

  if ! command -v jq curl pbcopy >/dev/null; then
    echo "ERROR: jq, curl, and pbcopy must be in PATH." >&2
    return 1
  fi

  local diff
  diff="$(git diff --cached)"
  if [[ -z "$diff" ]]; then
    echo "No staged changes." >&2
    return 1
  fi

  ###########################################################################
  # 2. Build Chat-Completions request
  ###########################################################################
  local request_json
  request_json="$(jq -n --arg diff "$diff" --arg model "$model" --arg temp "$temperature" '
    {
      model:       $model,
      temperature: ($temp | tonumber),
      messages: [
        { role: "system",
          content: "You are an assistant that writes concise English conventional-commit messages. Format: <type>(<scope>): <subject>\\n\\n<simple-body>" },
        { role: "user",
          content: "Read the following Git diff and propose a commit message:\\n\\n\($diff)" }
      ]
    }')"

  ###########################################################################
  # 3. Call OpenAI API – capture body & status
  ###########################################################################
  local end_point=https://api.openai.com/v1/chat/completions
  local tmp_rsp; tmp_rsp="$(mktemp)"
  local http_code
  http_code="$(
    curl -sS -w '%{http_code}' -o "$tmp_rsp" \
       $end_point \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $OPENAI_API_KEY" \
      -d "$request_json"
  )"

  local response; response="$(<"$tmp_rsp")"; rm -f "$tmp_rsp"

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
  # 5. Extract assistant message (your requested syntax)
  ###########################################################################
  local commit_msg
  commit_msg=$(jq -r '.choices[0].message.content' <<<"$response")

  if [[ -z "$commit_msg" || "$commit_msg" == "null" ]]; then
    echo "ERROR: Empty or malformed response." >&2
    echo "$response" | jq -C '.' >&2 || echo "$response" >&2
    return 1
  fi

  ###########################################################################
  # 6. Output & clipboard
  ###########################################################################
  echo "$commit_msg" | tee >(pbcopy)
}


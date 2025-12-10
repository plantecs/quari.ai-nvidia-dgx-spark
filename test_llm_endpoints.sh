#!/usr/bin/env bash
# Smoke & load tests for DGX Spark LLM stack
# - Verifies HTTPS reachability
# - Checks AnythingLLM UI and /v1 models endpoint
# - Runs timed chat completions at large prompt sizes (50k, 60k, 70k, 79.5k tokens)
#   using the public /v1 OpenAI-compatible endpoint
#
# Requirements: curl, python3; installs tiktoken if missing.

set -euo pipefail

cat <<'BANNER'
 ░▒▓██████▓▒░░▒▓█▓▒░░▒▓█▓▒░░▒▓██████▓▒░░▒▓███████▓▒░░▒▓█▓▒░       ░▒▓██████▓▒░░▒▓█▓▒░ 
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ 
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ 
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓████████▓▒░▒▓███████▓▒░░▒▓█▓▒░      ░▒▓████████▓▒░▒▓█▓▒░ 
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ 
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░▒▓██▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ 
 ░▒▓██████▓▒░ ░▒▓██████▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░▒▓██▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ 
   ░▒▓█▓▒░                                                                            
    ░▒▓██▓▒░
                       quari.ai | plantecs.ai | DGX Spark LLM
BANNER

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_FQDN=${HOST_FQDN:-$(grep -m1 '^HOST_FQDN=' "$ROOT_DIR/.env" 2>/dev/null | cut -d= -f2 || hostname -f)}
BASE_URL="https://${HOST_FQDN}"
LLM_URL="$BASE_URL"
UI_URL="$BASE_URL"
LOCAL_LLM="http://127.0.0.1:7000"
LOCAL_UI="http://127.0.0.1"
TOKEN_FILE="$ROOT_DIR/llm_bearer.txt"
BEARER=$(cat "$TOKEN_FILE" 2>/dev/null || echo "tensorrt_llm")

PROMPTS=(50000 60000 70000 79500)
MAX_TOKENS=200
MODEL="gpt-oss-120b"

say() { echo "[$(date +%H:%M:%S)] $*"; }

ensure_tiktoken() {
  python3 - <<'PY' >/dev/null 2>&1 || { python3 -m pip install --user --quiet tiktoken; }
import tiktoken
PY
}

make_prompt() {
  local target=$1
  python3 - "$target" <<'PY'
import sys
import tiktoken
n = int(sys.argv[1])
enc = tiktoken.get_encoding("cl100k_base")
base_ids = enc.encode(" albatross")  # 1 token with leading space
ids = (base_ids * ((n // len(base_ids)) + 2))[:n]
text = enc.decode(ids)
print(text, end="")
PY
}

check_ssl() {
  say "Checking HTTPS certificate (5s timeout)..."
  if curl -sS --fail --connect-timeout 5 --head "$BASE_URL" >/dev/null; then
    say "HTTPS OK (valid certificate)."
  else
    say "HTTPS check failed; retrying with -k..."
    if curl -sS -k --fail --connect-timeout 5 --head "$BASE_URL" >/dev/null; then
      say "HTTPS reachable with -k (likely self-signed)."
    else
      say "HTTPS unreachable; will fall back to local http for tests."
      LLM_URL="$LOCAL_LLM"
      UI_URL="$LOCAL_UI"
    fi
  fi
}

check_anythingllm() {
  say "Checking AnythingLLM UI (GET /)..."
  curl -sS -k --fail --connect-timeout 5 -o /dev/null "$UI_URL/" && say "AnythingLLM reachable." || say "AnythingLLM unreachable (check nginx/UI)."
}

check_models() {
  say "Checking /v1/models..."
  local code
  code=$(curl -s --connect-timeout 10 -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $BEARER" "$LLM_URL/v1/models")
  if [[ "$code" == "200" ]]; then
    say "/v1/models OK (200)."
  else
    say "WARNING: /v1/models returned $code"
  fi
}

run_test() {
  local target=$1
  local prompt_file="$(mktemp)"
  local body_file="$(mktemp)"
  make_prompt "$target" > "$prompt_file"
  python3 - "$prompt_file" "$body_file" <<'PY'
import json, sys
prompt_path, body_path = sys.argv[1:3]
with open(prompt_path, "r", encoding="utf-8") as f:
    prompt = f.read()
body = {
    "model": "gpt-oss-120b",
    "messages": [{"role": "user", "content": prompt}],
    "max_tokens": 200,
    "temperature": 0.8,
    "top_p": 0.9,
}
with open(body_path, "w", encoding="utf-8") as f:
    json.dump(body, f)
PY
  local start=$(date +%s%3N)
  local http_code
  http_code=$(curl -sS --connect-timeout 15 -o "$body_file.response" -w "%{http_code}" \
    -H "Authorization: Bearer $BEARER" \
    -H "Content-Type: application/json" \
    --data "@${body_file}" \
    "$LLM_URL/v1/chat/completions" || true)
  local end=$(date +%s%3N)
  local dur_ms=$((end - start))
  local summary
  summary=$(python3 - "$body_file.response" <<'PY'
import json, sys
path = sys.argv[1]
try:
    data = json.load(open(path, 'r'))
except Exception as e:
    print(f"parse_error: {e}")
    sys.exit(0)
ptu = data.get("proxy_token_usage", {})
kept = ptu.get("prompt_tokens_kept")
trimmed = ptu.get("prompt_tokens_trimmed")
used = ptu.get("prompt_window_percent_used")
finish = None
choices = data.get("choices")
if choices:
    finish = choices[0].get("finish_reason")
print(f"kept={kept} trimmed={trimmed} used_pct={used} finish={finish}")
PY
)
  echo "target=${target} http=${http_code} time_ms=${dur_ms} ${summary}"
  rm -f "$prompt_file" "$body_file" "$body_file.response"
}

main() {
  ensure_tiktoken
  check_ssl
  check_anythingllm
  check_models
  echo "--- load tests (max_tokens=${MAX_TOKENS}) ---"
  for p in "${PROMPTS[@]}"; do
    run_test "$p"
  done
}

main "$@"

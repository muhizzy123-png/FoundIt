#!/usr/bin/env bash
# End-to-end API test against the deployed Function URL.
#
#   bash scripts/test_api.sh https://<function-url-id>.lambda-url.us-east-1.on.aws
#   bash scripts/test_api.sh            # looks the URL up with the AWS CLI (profile "default")
#
# Creates one throw-away item and deletes it again. Exits non-zero if any check fails.
set -uo pipefail

BASE="${1:-}"
if [[ -z "$BASE" ]]; then
  BASE="$(aws --profile "${LAMBDA_PROFILE:-default}" --region "${AWS_REGION:-us-east-1}" \
    lambda get-function-url-config --function-name "${FUNCTION_NAME:-LostFoundHandler}" \
    --query FunctionUrl --output text)" || { echo "usage: $0 <function-url>" >&2; exit 2; }
fi
BASE="${BASE%/}"

PY=""
for candidate in python python3 py; do
  if command -v "$candidate" >/dev/null 2>&1; then PY="$candidate"; break; fi
done
[[ -n "$PY" ]] || { echo "python not found (used to read JSON)" >&2; exit 2; }

pass=0; fail=0
CODE=""; BODY=""

# req METHOD PATH [JSON_BODY]  -> sets CODE and BODY
req() {
  local method="$1" path="$2" data="${3:-}" out
  if [[ -n "$data" ]]; then
    out="$(curl -s -m 20 -w '\n%{http_code}' -X "$method" -H 'Content-Type: application/json' -d "$data" "$BASE$path")"
  else
    out="$(curl -s -m 20 -w '\n%{http_code}' -X "$method" "$BASE$path")"
  fi
  CODE="${out##*$'\n'}"
  BODY="${out%$'\n'*}"
}

json_get() {  # json_get '<json>' key
  "$PY" -c 'import json,sys; print(json.loads(sys.argv[1]).get(sys.argv[2], ""))' "$1" "$2" 2>/dev/null
}

check() {  # check "label" expected_code
  if [[ "$CODE" == "$2" ]]; then
    printf 'PASS  %-46s HTTP %s\n' "$1" "$CODE"; pass=$((pass + 1))
  else
    printf 'FAIL  %-46s expected %s, got %s\n      %s\n' "$1" "$2" "$CODE" "$BODY"; fail=$((fail + 1))
  fi
}

check_field() {  # check_field "label" '<json>' key expected
  local actual; actual="$(json_get "$2" "$3")"
  if [[ "$actual" == "$4" ]]; then
    printf 'PASS  %-46s %s=%s\n' "$1" "$3" "$actual"; pass=$((pass + 1))
  else
    printf 'FAIL  %-46s %s expected %s, got %s\n' "$1" "$3" "$4" "$actual"; fail=$((fail + 1))
  fi
}

echo "Testing $BASE"
echo

req GET /health;                                                  check "GET /health" 200

req POST /items '{"title":"Dompet hitam","type":"lost","location":"Gedung C","contact":"08123456789","description":"Ada KTM"}'
check "POST /items (valid)" 201
ID="$(json_get "$BODY" itemId)"
check_field "created item starts as open" "$BODY" status open
[[ -n "$ID" ]] || { echo "no itemId returned, stopping"; exit 1; }

req POST /items '{"type":"lost","location":"Gedung C","contact":"08123456789"}'
check "POST /items (missing title)" 400
req POST /items '{"title":"X","type":"stolen","location":"A","contact":"B"}'
check "POST /items (bad type)" 400
req POST /items 'not json';                                       check "POST /items (invalid JSON)" 400

req GET /items;                                                   check "GET /items" 200
req GET '/items?status=open';                                     check "GET /items?status=open" 200
req GET '/items?status=bogus';                                    check "GET /items?status=bogus" 400
req GET "/items/$ID";                                             check "GET /items/{id}" 200

req PUT "/items/$ID" '{"status":"claimed"}';                      check "PUT /items/{id} (claim)" 200
check_field "status is now claimed" "$BODY" status claimed
req PUT "/items/$ID" '{"status":"bogus"}';                        check "PUT /items/{id} (bad status)" 400
req PUT "/items/$ID" '{"itemId":"x"}';                            check "PUT /items/{id} (read-only field)" 400
req GET "/items/$ID";                                             check "GET /items/{id} after update" 200
check_field "update persisted" "$BODY" status claimed

req DELETE "/items/$ID";                                          check "DELETE /items/{id}" 200
req GET "/items/$ID";                                             check "GET /items/{id} after delete" 404
req DELETE "/items/$ID";                                          check "DELETE /items/{id} again" 404
req GET /items/not-a-uuid;                                        check "GET /items/not-a-uuid" 404
req GET /nope;                                                    check "GET /nope" 404
req PATCH /items;                                                 check "PATCH /items" 405

echo
echo "passed: $pass  failed: $fail"
(( fail == 0 ))

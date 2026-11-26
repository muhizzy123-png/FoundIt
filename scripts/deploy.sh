#!/usr/bin/env bash
# Idempotent deploy for Kampus Lost & Found (AWS Learner Lab).
#
#   bash scripts/deploy.sh
#
# Steps (safe to re-run):
#   1. Check both AWS profiles work.
#   2. Create the DynamoDB table LostFoundItems if missing   (IAM user profile).
#   3. Zip lambda/handler.py and create/update the Lambda     (Learner Lab profile, LabRole).
#   4. Create the public Function URL + its two permissions   (Learner Lab profile).
#   5. Print the Function URL and call GET /health.
#
# Why two profiles: in this lab the voclabs role (default) can deploy Lambda but not
# create DynamoDB tables; the IAM user (iam) can create tables but not Lambda functions.
#
# Override with env vars if your profile names differ:
#   LAMBDA_PROFILE=default  DDB_PROFILE=iam  bash scripts/deploy.sh
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
LAMBDA_PROFILE="${LAMBDA_PROFILE:-default}"
DDB_PROFILE="${DDB_PROFILE:-iam}"
TABLE="${TABLE_NAME:-LostFoundItems}"
FUNCTION="${FUNCTION_NAME:-LostFoundHandler}"
ROLE_NAME="LabRole"          # Learner Lab: IAM roles cannot be created, LabRole is used
RUNTIME="python3.12"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

step() { printf '\n==> %s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

lam() { aws --profile "$LAMBDA_PROFILE" --region "$REGION" "$@"; }
ddb() { aws --profile "$DDB_PROFILE" --region "$REGION" "$@"; }

# --- python is only used to build the zip (no zip tool needed in Git Bash) --------------------
PY=""
for candidate in python python3 py; do
  if command -v "$candidate" >/dev/null 2>&1; then PY="$candidate"; break; fi
done
[[ -n "$PY" ]] || fail "python not found (needed to zip lambda/handler.py)"
[[ -f lambda/handler.py ]] || fail "lambda/handler.py not found (run from the repo)"

# --- 1. credentials ---------------------------------------------------------------------------
step "Checking credentials"
lam sts get-caller-identity --query Arn --output text >/dev/null \
  || fail "profile '$LAMBDA_PROFILE' rejected: Start Lab and paste fresh CLI credentials"
ddb sts get-caller-identity --query Arn --output text >/dev/null \
  || fail "profile '$DDB_PROFILE' rejected: check its access key (aws configure --profile $DDB_PROFILE)"
echo "profile $LAMBDA_PROFILE: ok"
echo "profile $DDB_PROFILE: ok"

# --- 2. DynamoDB table -------------------------------------------------------------------------
step "DynamoDB table $TABLE"
if ddb dynamodb describe-table --table-name "$TABLE" >/dev/null 2>&1; then
  echo "table exists"
else
  ddb dynamodb create-table \
    --table-name "$TABLE" \
    --attribute-definitions AttributeName=itemId,AttributeType=S \
    --key-schema AttributeName=itemId,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST >/dev/null
  ddb dynamodb wait table-exists --table-name "$TABLE"
  echo "table created"
fi

# --- 3. Lambda ---------------------------------------------------------------------------------
step "Lambda $FUNCTION"
ROLE_ARN="$(lam iam get-role --role-name "$ROLE_NAME" --query Role.Arn --output text)"
rm -f fn.zip
( cd lambda && "$PY" -m zipfile -c ../fn.zip handler.py )

if lam lambda get-function --function-name "$FUNCTION" >/dev/null 2>&1; then
  lam lambda update-function-code --function-name "$FUNCTION" --zip-file fileb://fn.zip >/dev/null
  lam lambda wait function-updated --function-name "$FUNCTION"
  lam lambda update-function-configuration --function-name "$FUNCTION" \
    --environment "Variables={TABLE_NAME=$TABLE}" >/dev/null
  lam lambda wait function-updated --function-name "$FUNCTION"
  echo "function updated"
else
  lam lambda create-function \
    --function-name "$FUNCTION" \
    --runtime "$RUNTIME" \
    --handler handler.lambda_handler \
    --role "$ROLE_ARN" \
    --timeout 10 \
    --environment "Variables={TABLE_NAME=$TABLE}" \
    --zip-file fileb://fn.zip >/dev/null
  lam lambda wait function-active-v2 --function-name "$FUNCTION" 2>/dev/null \
    || lam lambda wait function-active --function-name "$FUNCTION"
  echo "function created"
fi
rm -f fn.zip

# --- 4. Function URL (public, AuthType NONE) ----------------------------------------------------
step "Function URL"
if ! lam lambda get-function-url-config --function-name "$FUNCTION" >/dev/null 2>&1; then
  lam lambda create-function-url-config --function-name "$FUNCTION" --auth-type NONE >/dev/null
  echo "function url created"
else
  echo "function url exists"
fi

# The two permissions that make the URL callable without credentials.
# A repeat run returns ResourceConflictException, which is fine.
add_permission() {
  local out
  if out="$(lam lambda add-permission --function-name "$FUNCTION" "$@" 2>&1)"; then
    echo "permission added: $2"
  elif grep -q "ResourceConflictException" <<<"$out"; then
    echo "permission exists: $2"
  else
    fail "add-permission failed: $out"
  fi
}
add_permission --statement-id FunctionURLAllowPublicAccess \
  --action lambda:InvokeFunctionUrl --principal "*" --function-url-auth-type NONE
add_permission --statement-id FunctionURLAllowPublicInvoke \
  --action lambda:InvokeFunction --principal "*" --invoked-via-function-url

URL="$(lam lambda get-function-url-config --function-name "$FUNCTION" --query FunctionUrl --output text)"
URL="${URL%/}"

# --- 5. health check ----------------------------------------------------------------------------
step "Health check"
echo "Function URL: $URL"
ok=0
for attempt in 1 2 3 4 5 6; do
  body="$(curl -s -m 15 "$URL/health" || true)"
  if grep -q '"status": *"ok"' <<<"$body"; then ok=1; break; fi
  echo "attempt $attempt: $body"
  sleep 5
done
if (( ok )); then
  echo "OK: $body"
else
  fail "health check did not return ok (a new Function URL can take a few seconds; rerun the script)"
fi

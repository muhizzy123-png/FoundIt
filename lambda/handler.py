"""Lambda handler for the FoundIt API (Lambda Function URL + DynamoDB).

Routes (payload format 2.0 from a Function URL):
    GET    /health        connectivity check (Lambda -> DynamoDB)
    POST   /items         create an item
    GET    /items         list items (optional ?status= and ?type=)
    GET    /items/{id}    get one item
    PUT    /items/{id}    partial update
    DELETE /items/{id}    delete
"""
import base64
import json
import os
import uuid
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

TABLE_NAME = os.environ.get("TABLE_NAME", "LostFoundItems")
table = boto3.resource("dynamodb").Table(TABLE_NAME)

TYPES = {"lost", "found"}
STATUSES = {"open", "claimed"}
MAX_BODY_BYTES = 10_000

# field -> (max length, required on create)
FIELDS = {
    "title": (100, True),
    "type": (None, True),
    "location": (200, True),
    "contact": (100, True),
    "description": (500, False),
    "status": (None, False),
}
UPDATABLE = set(FIELDS)  # itemId, createdAt and updatedAt are server-controlled


class ApiError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status
        self.message = message


def respond(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def utc_now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def valid_id(value):
    try:
        return str(uuid.UUID(value)) == value.lower()
    except (ValueError, AttributeError):
        return False


def parse_body(event):
    raw = event.get("body")
    if not raw:
        raise ApiError(400, "request body is required")
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8", errors="replace")
    if len(raw.encode("utf-8")) > MAX_BODY_BYTES:
        raise ApiError(413, "request body too large")
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        raise ApiError(400, "request body must be valid JSON")
    if not isinstance(data, dict):
        raise ApiError(400, "request body must be a JSON object")
    return data


def validate(data, creating):
    """Return a cleaned dict of fields; raise ApiError(400) with every problem found."""
    errors = []
    unknown = sorted(set(data) - UPDATABLE)
    if unknown:
        errors.append("unknown or read-only field(s): " + ", ".join(unknown))

    clean = {}
    for name, (max_len, required) in FIELDS.items():
        if name not in data:
            if creating and required:
                errors.append(f"{name} is required")
            continue
        value = data[name]
        if not isinstance(value, str):
            errors.append(f"{name} must be a string")
            continue
        value = value.strip()
        if name != "description" and not value:
            errors.append(f"{name} must not be empty")
            continue
        if max_len and len(value) > max_len:
            errors.append(f"{name} must be at most {max_len} characters")
            continue
        if name == "type" and value not in TYPES:
            errors.append("type must be one of: " + ", ".join(sorted(TYPES)))
            continue
        if name == "status" and value not in STATUSES:
            errors.append("status must be one of: " + ", ".join(sorted(STATUSES)))
            continue
        clean[name] = value

    if not creating and not clean and not errors:
        errors.append("no updatable fields provided")
    if errors:
        raise ApiError(400, "; ".join(errors))
    return clean


# --- operations ---------------------------------------------------------------------------

def health():
    try:
        table.load()
        return respond(200, {"status": "ok", "table": TABLE_NAME})
    except Exception as err:  # noqa: BLE001 - report any connectivity problem
        print(f"health check failed: {err!r}")
        return respond(500, {"status": "error"})


def create_item(event):
    fields = validate(parse_body(event), creating=True)
    now = utc_now()
    item = {
        "itemId": str(uuid.uuid4()),
        "description": "",
        "status": "open",
        **fields,
        "createdAt": now,
        "updatedAt": now,
    }
    table.put_item(Item=item, ConditionExpression="attribute_not_exists(itemId)")
    return respond(201, item)


def list_items(event):
    params = event.get("queryStringParameters") or {}
    status, type_ = params.get("status"), params.get("type")
    if status is not None and status not in STATUSES:
        raise ApiError(400, "status must be one of: " + ", ".join(sorted(STATUSES)))
    if type_ is not None and type_ not in TYPES:
        raise ApiError(400, "type must be one of: " + ", ".join(sorted(TYPES)))

    items, kwargs = [], {}
    while True:
        page = table.scan(**kwargs)
        items.extend(page.get("Items", []))
        if "LastEvaluatedKey" not in page:
            break
        kwargs["ExclusiveStartKey"] = page["LastEvaluatedKey"]

    if status:
        items = [i for i in items if i.get("status") == status]
    if type_:
        items = [i for i in items if i.get("type") == type_]
    items.sort(key=lambda i: i.get("createdAt", ""), reverse=True)
    return respond(200, {"count": len(items), "items": items})


def get_item(item_id):
    item = table.get_item(Key={"itemId": item_id}).get("Item") if valid_id(item_id) else None
    if not item:
        raise ApiError(404, "item not found")
    return respond(200, item)


def update_item(item_id, event):
    fields = validate(parse_body(event), creating=False)
    if not valid_id(item_id):
        raise ApiError(404, "item not found")
    fields["updatedAt"] = utc_now()
    names = {f"#{k}": k for k in fields}
    values = {f":{k}": v for k, v in fields.items()}
    expression = "SET " + ", ".join(f"#{k} = :{k}" for k in fields)
    try:
        result = table.update_item(
            Key={"itemId": item_id},
            UpdateExpression=expression,
            ExpressionAttributeNames=names,
            ExpressionAttributeValues=values,
            ConditionExpression="attribute_exists(itemId)",
            ReturnValues="ALL_NEW",
        )
    except ClientError as err:
        if err.response["Error"]["Code"] == "ConditionalCheckFailedException":
            raise ApiError(404, "item not found") from err
        raise
    return respond(200, result["Attributes"])


def delete_item(item_id):
    if not valid_id(item_id):
        raise ApiError(404, "item not found")
    try:
        table.delete_item(Key={"itemId": item_id}, ConditionExpression="attribute_exists(itemId)")
    except ClientError as err:
        if err.response["Error"]["Code"] == "ConditionalCheckFailedException":
            raise ApiError(404, "item not found") from err
        raise
    return respond(200, {"deleted": item_id})


# --- routing --------------------------------------------------------------------------------

def route(event):
    http = event.get("requestContext", {}).get("http", {})
    method = http.get("method", "")
    path = (event.get("rawPath") or "/").rstrip("/") or "/"
    parts = [p for p in path.split("/") if p]

    if parts == ["health"]:
        if method != "GET":
            raise ApiError(405, "method not allowed")
        return health()

    if parts == ["items"]:
        if method == "POST":
            return create_item(event)
        if method == "GET":
            return list_items(event)
        raise ApiError(405, "method not allowed")

    if len(parts) == 2 and parts[0] == "items":
        item_id = parts[1]
        if method == "GET":
            return get_item(item_id)
        if method == "PUT":
            return update_item(item_id, event)
        if method == "DELETE":
            return delete_item(item_id)
        raise ApiError(405, "method not allowed")

    raise ApiError(404, "not found")


def lambda_handler(event, context):
    try:
        return route(event)
    except ApiError as err:
        return respond(err.status, {"error": err.message})
    except Exception as err:  # noqa: BLE001 - never leak internals to a public endpoint
        print(f"unhandled error: {err!r}")
        return respond(500, {"error": "internal server error"})

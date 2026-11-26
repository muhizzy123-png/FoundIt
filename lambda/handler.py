"""Lambda handler for Kampus Lost & Found API.

CRUD logic will be added progressively.
"""
import json
import os

import boto3

TABLE_NAME = os.environ.get("TABLE_NAME", "LostFoundItems")
table = boto3.resource("dynamodb").Table(TABLE_NAME)


def respond(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def lambda_handler(event, context):
    http = event.get("requestContext", {}).get("http", {})
    method, path = http.get("method"), event.get("rawPath", "/")

    if method == "GET" and path == "/health":
        try:
            table.load()
            return respond(200, {"status": "ok", "table": TABLE_NAME})
        except Exception as err:
            return respond(500, {"status": "error", "detail": str(err)})

    return respond(404, {"error": "not found"})
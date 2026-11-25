"""Lambda handler for Kampus Lost & Found API (starter).

CRUD logic will be added progressively.
"""
import json


def lambda_handler(event, context):
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"message": "Kampus Lost & Found API - starter"}),
    }

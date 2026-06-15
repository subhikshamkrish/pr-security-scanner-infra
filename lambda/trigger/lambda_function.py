import base64
import hashlib
import hmac
import json
import os
import re

import boto3
from botocore.exceptions import ClientError


stepfunctions = boto3.client("stepfunctions")
cloudwatch = boto3.client("cloudwatch")
s3 = boto3.client("s3")


def _log(message, **fields):
    print(json.dumps({"message": message, **fields}, default=str))


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body, default=str),
    }


def _put_metric(name, value=1, unit="Count"):
    cloudwatch.put_metric_data(
        Namespace=os.environ.get("METRICS_NAMESPACE", "PRSecurityScanner"),
        MetricData=[
            {
                "MetricName": name,
                "Value": value,
                "Unit": unit,
            }
        ],
    )


def _header(headers, name):
    wanted = name.lower()
    for key, value in (headers or {}).items():
        if key.lower() == wanted:
            return value
    return None


def _verify_signature(raw_body, headers):
    secret = os.environ.get("GITHUB_WEBHOOK_SECRET", "")
    signature = _header(headers, "x-hub-signature-256")

    if not secret:
        raise ValueError("Webhook secret is not configured")
    if not signature:
        raise ValueError("Missing X-Hub-Signature-256 header")

    expected = "sha256=" + hmac.new(
        secret.encode("utf-8"),
        raw_body,
        hashlib.sha256,
    ).hexdigest()

    if not hmac.compare_digest(expected, signature):
        raise ValueError("Invalid webhook signature")


def _object_exists(bucket, key):
    try:
        s3.head_object(Bucket=bucket, Key=key)
        return True
    except ClientError as error:
        if error.response.get("Error", {}).get("Code") in {"404", "NoSuchKey", "NotFound"}:
            return False
        raise


def _repo_slug(full_name):
    return re.sub(r"[^a-z0-9-]", "-", full_name.lower().replace("/", "-"))


def _archive_url(repo_full_name, sha):
    return f"https://github.com/{repo_full_name}/archive/{sha}.zip"


def _build_workflow_payload(webhook_payload, delivery_id):
    pull_request = webhook_payload["pull_request"]
    repo_full_name = webhook_payload["repository"]["full_name"]
    repo_slug = _repo_slug(repo_full_name)
    bucket = os.environ["REPORT_BUCKET"]
    base_sha = pull_request["base"]["sha"]
    pr_sha = pull_request["head"]["sha"]
    base_report_key = f"reports/scans/{repo_slug}/{base_sha}.json"
    pr_report_key = f"reports/scans/{repo_slug}/{pr_sha}.json"

    return {
        "repository": repo_full_name,

        "github_owner": webhook_payload["repository"]["owner"]["login"],
        "github_repo": webhook_payload["repository"]["name"],
        "pr_number": pull_request["number"],

        "pull_request_number": pull_request["number"],
        "execution_id": delivery_id,
        "bucket": bucket,
        "diff_report_key": f"reports/diff/{repo_slug}/{base_sha}..{pr_sha}.json",

        "base": {
            "sha": base_sha,
            "report_key": base_report_key,
            "zip_key": "",
            "source_zip_url": _archive_url(repo_full_name, base_sha),
            "report_exists": _object_exists(bucket, base_report_key),
        },

        "pr": {
            "sha": pr_sha,
            "report_key": pr_report_key,
            "zip_key": "",
            "source_zip_url": _archive_url(repo_full_name, pr_sha),
            "report_exists": _object_exists(bucket, pr_report_key),
        },
    }


def _start_workflow(payload):
    execution_name = re.sub(r"[^A-Za-z0-9_-]", "-", str(payload["execution_id"]))[:80]

    _log(
        "starting_stepfunctions_execution",
        repository=payload["repository"],
        pull_request_number=payload.get("pull_request_number"),
        execution_id=payload["execution_id"],
        execution_name=execution_name,
        base_sha=payload["base"]["sha"],
        pr_sha=payload["pr"]["sha"],
        base_report_exists=payload["base"]["report_exists"],
        pr_report_exists=payload["pr"]["report_exists"],
        diff_report_key=payload["diff_report_key"],
    )

    response = stepfunctions.start_execution(
        stateMachineArn=os.environ["STATE_MACHINE_ARN"],
        name=execution_name,
        input=json.dumps(payload),
    )

    _put_metric("WorkflowStarted")
    _put_metric("BaseScanCacheCheck")

    if payload["base"]["report_exists"]:
        _put_metric("BaseScanCacheHit")

    _log(
        "started_stepfunctions_execution",
        execution_arn=response["executionArn"],
        execution_name=execution_name,
    )

    return response


def handler(event, context):
    headers = event.get("headers") or {}
    event_name = _header(headers, "x-github-event")
    delivery_id = _header(headers, "x-github-delivery") or context.aws_request_id

    raw_body = event.get("body", "")

    if event.get("isBase64Encoded"):
        raw_body_bytes = base64.b64decode(raw_body)
    else:
        raw_body_bytes = raw_body.encode("utf-8")

    # try:
    #     _verify_signature(raw_body_bytes, headers)
    # except ValueError as error:
    #     _log("webhook_signature_rejected", reason=str(error), delivery_id=delivery_id)
    #     return _response(401, {"message": "Unauthorized"})

    webhook_payload = json.loads(raw_body_bytes.decode("utf-8"))

    if event_name == "ping":
        _log("github_webhook_ping", delivery_id=delivery_id)
        return _response(200, {"message": "pong"})

    if event_name != "pull_request":
        _log("github_webhook_ignored_event", event_name=event_name, delivery_id=delivery_id)
        return _response(202, {"message": f"Ignored event: {event_name}"})

    action = webhook_payload.get("action")

    if action not in {"opened", "synchronize", "reopened"}:
        _log("github_webhook_ignored_action", action=action, delivery_id=delivery_id)
        return _response(202, {"message": f"Ignored pull_request action: {action}"})

    payload = _build_workflow_payload(webhook_payload, delivery_id)
    response = _start_workflow(payload)

    return _response(
        202,
        {
            "message": "Workflow execution started",
            "executionArn": response["executionArn"],
            "startDate": response["startDate"].isoformat(),
        },
    )
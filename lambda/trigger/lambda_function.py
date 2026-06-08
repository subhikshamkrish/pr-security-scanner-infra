import json
import os
import re

import boto3


stepfunctions = boto3.client("stepfunctions")


def _log(message, **fields):
    print(json.dumps({"message": message, **fields}, default=str))


def _require(payload, path):
    value = payload
    for part in path.split("."):
        if not isinstance(value, dict) or part not in value:
            raise ValueError(f"Missing required field: {path}")
        value = value[part]
    return value


def handler(event, context):
    state_machine_arn = os.environ["STATE_MACHINE_ARN"]
    payload = event if isinstance(event, dict) else {"raw_event": event}

    for required_path in [
        "repository",
        "execution_id",
        "bucket",
        "diff_report_key",
        "base.sha",
        "base.report_key",
        "base.report_exists",
        "pr.sha",
        "pr.report_key",
        "pr.report_exists",
    ]:
        _require(payload, required_path)

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
        stateMachineArn=state_machine_arn,
        name=execution_name,
        input=json.dumps(payload),
    )

    _log(
        "started_stepfunctions_execution",
        execution_arn=response["executionArn"],
        execution_name=execution_name,
    )

    return {
        "statusCode": 202,
        "body": {
            "message": "Workflow execution started",
            "executionArn": response["executionArn"],
            "startDate": response["startDate"].isoformat(),
        },
    }

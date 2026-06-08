import os
import json

import boto3


s3 = boto3.client("s3")


def _log(message, **fields):
    print(json.dumps({"message": message, **fields}, default=str))


def handler(event, context):
    action = event.get("action", "compare")
    report_bucket = event.get("report_bucket", os.environ.get("REPORT_BUCKET"))

    if action == "github_comment_placeholder":
        _log(
            "github_comment_placeholder",
            repository=event.get("repository"),
            diff_report_key=event.get("diff_report_key"),
        )
        return {
            "action": action,
            "report_bucket": report_bucket,
            "message": "GitHub PR comment step placeholder completed.",
            "would_post_comment": True,
        }

    diff_report = {
        "action": action,
        "report_bucket": report_bucket,
        "repository": event.get("repository"),
        "base_report_key": event.get("base_report_key"),
        "pr_report_key": event.get("pr_report_key"),
        "diff_report_key": event.get("diff_report_key"),
        "message": "Comparison engine placeholder completed.",
        "new_vulnerabilities": [],
        "worsened_vulnerabilities": [],
        "fixed_vulnerabilities": [],
        "unchanged_vulnerabilities": [],
    }

    if report_bucket and event.get("diff_report_key"):
        _log(
            "writing_diff_report",
            repository=event.get("repository"),
            bucket=report_bucket,
            base_report_key=event.get("base_report_key"),
            pr_report_key=event.get("pr_report_key"),
            diff_report_key=event.get("diff_report_key"),
        )
        s3.put_object(
            Bucket=report_bucket,
            Key=event["diff_report_key"],
            Body=json.dumps(diff_report, indent=2).encode("utf-8"),
            ContentType="application/json",
        )

    _log(
        "comparison_completed",
        repository=event.get("repository"),
        diff_report_key=event.get("diff_report_key"),
    )

    return diff_report

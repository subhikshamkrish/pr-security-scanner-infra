import os
import json

import boto3


s3 = boto3.client("s3")


def _log(message, **fields):
    print(json.dumps({"message": message, **fields}, default=str))


def _delete_if_present(bucket, key):
    if not key:
        _log("cleanup_skipped_missing_key")
        return {"key": key, "deleted": False, "reason": "missing_key"}

    _log("deleting_temporary_input", bucket=bucket, key=key)
    s3.delete_object(Bucket=bucket, Key=key)
    return {"key": key, "deleted": True}


def handler(event, context):
    bucket = event.get("bucket") or os.environ["REPORT_BUCKET"]
    deleted = []

    base = event.get("base", {})
    pr = event.get("pr", {})

    if not base.get("report_exists", False):
        deleted.append(_delete_if_present(bucket, base.get("zip_key")))
    else:
        _log("cleanup_skipped_cached_base", key=base.get("zip_key"))

    if not pr.get("report_exists", False):
        deleted.append(_delete_if_present(bucket, pr.get("zip_key")))
    else:
        _log("cleanup_skipped_cached_pr", key=pr.get("zip_key"))

    _log(
        "cleanup_completed",
        bucket=bucket,
        deleted=deleted,
        base_report_exists=base.get("report_exists"),
        pr_report_exists=pr.get("report_exists"),
    )

    return {
        "bucket": bucket,
        "deleted": deleted,
        "message": "Temporary scanner input cleanup completed.",
    }

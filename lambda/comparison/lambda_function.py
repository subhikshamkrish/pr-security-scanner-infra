import os
import json
import boto3
import urllib.request


s3 = boto3.client("s3")

cloudwatch = boto3.client("cloudwatch")

ssm = boto3.client("ssm")


SEVERITY_RANK = {
    "INFO": 0,
    "LOW": 1,
    "WARNING": 2,
    "MEDIUM": 2,
    "ERROR": 3,
    "HIGH": 3,
    "CRITICAL": 4
}


def _log(message, **fields):

    print(json.dumps({
        "message": message,
        **fields
    }, default=str))


def _put_metric(name, value=1, unit="Count"):

    cloudwatch.put_metric_data(

        Namespace=os.environ.get(
            "METRICS_NAMESPACE",
            "PRSecurityScanner"
        ),

        MetricData=[
            {
                "MetricName": name,
                "Value": value,
                "Unit": unit,
            }
        ],
    )


def build_unique_fingerprint(vuln):

    check_id = vuln.get(
        "check_id",
        ""
    )

    raw_path = vuln.get(
        "path",
        ""
    )

    line = str(
        vuln.get(
            "start",
            {}
        ).get(
            "line",
            ""
        )
    )

    normalized_path = raw_path

    if "/source/" in raw_path:

        normalized_path = raw_path.split("/source/")[-1]

        parts = normalized_path.split("/", 1)

        if len(parts) > 1:

            normalized_path = parts[1]

    return (
        f"{check_id}|"
        f"{normalized_path}|"
        f"{line}"
    )


def extract_vulnerabilities(report):

    vulnerabilities = []

    results = report.get(
        "results",
        []
    )

    for vuln in results:

        vulnerabilities.append({

            "fingerprint":
                build_unique_fingerprint(vuln),

            "id":
                vuln.get(
                    "check_id"
                ),

            "file":
                vuln.get(
                    "path"
                ),

            "line":
                vuln.get(
                    "start",
                    {}
                ).get(
                    "line"
                ),

            "severity":
                vuln.get(
                    "extra",
                    {}
                ).get(
                    "severity",
                    "INFO"
                ).upper(),

            "message":
                vuln.get(
                    "extra",
                    {}
                ).get(
                    "message",
                    ""
                ),

            "metadata":
                vuln.get(
                    "extra",
                    {}
                ).get(
                    "metadata",
                    {}
                ),

            "raw":
                vuln
        })

    return vulnerabilities


def compare_reports(base_report, pr_report):

    base_vulns = extract_vulnerabilities(
        base_report
    )

    pr_vulns = extract_vulnerabilities(
        pr_report
    )

    base_map = {
        vuln["fingerprint"]: vuln
        for vuln in base_vulns
    }

    pr_map = {
        vuln["fingerprint"]: vuln
        for vuln in pr_vulns
    }

    new_vulnerabilities = []

    fixed_vulnerabilities = []

    existing_vulnerabilities = []

    worsened_vulnerabilities = []

    improved_vulnerabilities = []

    unchanged_vulnerabilities = []

    for fp, vuln in pr_map.items():

        if fp not in base_map:

            new_vulnerabilities.append(vuln)

        else:

            old_vuln = base_map[fp]

            old_severity = old_vuln.get(
                "severity",
                "INFO"
            )

            new_severity = vuln.get(
                "severity",
                "INFO"
            )

            if (
                SEVERITY_RANK.get(new_severity, 0)
                >
                SEVERITY_RANK.get(old_severity, 0)
            ):

                status = "WORSENED"

            elif (
                SEVERITY_RANK.get(new_severity, 0)
                <
                SEVERITY_RANK.get(old_severity, 0)
            ):

                status = "IMPROVED"

            else:

                status = "UNCHANGED"

            existing_vulnerability = {

                "fingerprint":
                    fp,

                "id":
                    vuln.get(
                        "id"
                    ),

                "file":
                    vuln.get(
                        "file"
                    ),

                "line":
                    vuln.get(
                        "line"
                    ),

                "message":
                    vuln.get(
                        "message"
                    ),

                "old_severity":
                    old_severity,

                "new_severity":
                    new_severity,

                "status":
                    status
            }

            existing_vulnerabilities.append(
                existing_vulnerability
            )

            if status == "WORSENED":

                worsened_vulnerabilities.append(
                    existing_vulnerability
                )

            elif status == "IMPROVED":

                improved_vulnerabilities.append(
                    existing_vulnerability
                )

            elif status == "UNCHANGED":

                unchanged_vulnerabilities.append(
                    existing_vulnerability
                )

    for fp, vuln in base_map.items():

        if fp not in pr_map:

            fixed_vulnerabilities.append(
                vuln
            )

    summary_text = (
        f"Base Scan: {len(base_vulns)} vulnerabilities | "
        f"PR Scan: {len(pr_vulns)} vulnerabilities | "
        f"New: {len(new_vulnerabilities)} | "
        f"Fixed: {len(fixed_vulnerabilities)} | "
        f"Worsened: {len(worsened_vulnerabilities)} | "
        f"Improved: {len(improved_vulnerabilities)} | "
        f"Unchanged: {len(unchanged_vulnerabilities)}"
    )

    return {

        "summary": {

            "base_count":
                len(base_vulns),

            "pr_count":
                len(pr_vulns),

            "new":
                len(new_vulnerabilities),

            "fixed":
                len(fixed_vulnerabilities),

            "existing":
                len(existing_vulnerabilities),

            "worsened":
                len(worsened_vulnerabilities),

            "improved":
                len(improved_vulnerabilities),

            "unchanged":
                len(unchanged_vulnerabilities),

            "summary_text":
                summary_text
        },

        "new_vulnerabilities":
            new_vulnerabilities,

        "fixed_vulnerabilities":
            fixed_vulnerabilities,

        "existing_vulnerabilities":
            existing_vulnerabilities,

        "worsened_vulnerabilities":
            worsened_vulnerabilities,

        "improved_vulnerabilities":
            improved_vulnerabilities,

        "unchanged_vulnerabilities":
            unchanged_vulnerabilities
    }


def read_s3_json(bucket, key):

    response = s3.get_object(
        Bucket=bucket,
        Key=key
    )

    content = response["Body"].read()

    return json.loads(content)


def get_github_pat():

    response = ssm.get_parameter(

        Name="/fcc/github/pat",

        WithDecryption=True
    )

    return response[
        "Parameter"
    ][
        "Value"
    ]


def post_pr_comment(
    owner,
    repo,
    pr_number,
    comment_body
):

    github_token = get_github_pat()

    url = (
        f"https://api.github.com/repos/"
        f"{owner}/{repo}/issues/"
        f"{pr_number}/comments"
    )

    payload = json.dumps({

        "body":
            comment_body

    }).encode("utf-8")

    headers = {

        "Authorization":
            f"Bearer {github_token}",

        "Accept":
            "application/vnd.github+json",

        "Content-Type":
            "application/json"
    }

    request = urllib.request.Request(

        url,

        data=payload,

        headers=headers,

        method="POST"
    )

    with urllib.request.urlopen(
        request
    ) as response:

        response_body = response.read().decode()

        return json.loads(
            response_body
        )


def build_comment_body(comparison_result):

    summary = comparison_result[
        "summary"
    ]

    dashboard_url = os.environ.get(
        "DASHBOARD_URL",
        ""
    )

    comment_body = f"""
## 🔍 Semgrep SAST Comparison Report

| Metric | Count |
|---|---|
| Base Scan | {summary["base_count"]} |
| PR Scan | {summary["pr_count"]} |
| New Vulnerabilities | {summary["new"]} |
| Fixed Vulnerabilities | {summary["fixed"]} |
| Worsened | {summary["worsened"]} |
| Improved | {summary["improved"]} |
| Unchanged | {summary["unchanged"]} |

### 📋 Summary

{summary["summary_text"]}
"""

    if dashboard_url:

        comment_body += f"""

### 📊 Dashboard

{dashboard_url}
"""

    if comparison_result[
        "new_vulnerabilities"
    ]:

        comment_body += "\n\n## 🚨 New Vulnerabilities\n"

        for vuln in comparison_result[
            "new_vulnerabilities"
        ][:10]:

            comment_body += (
                f"\n- `{vuln['severity']}` "
                f"`{vuln['file']}:{vuln['line']}` "
                f"- {vuln['message']}"
            )

    if comparison_result[
        "fixed_vulnerabilities"
    ]:

        comment_body += "\n\n## ✅ Fixed Vulnerabilities\n"

        for vuln in comparison_result[
            "fixed_vulnerabilities"
        ][:10]:

            comment_body += (
                f"\n- `{vuln['severity']}` "
                f"`{vuln['file']}:{vuln['line']}` "
                f"- {vuln['message']}"
            )

    if comparison_result[
        "worsened_vulnerabilities"
    ]:

        comment_body += "\n\n## ⚠️ Worsened Vulnerabilities\n"

        for vuln in comparison_result[
            "worsened_vulnerabilities"
        ][:10]:

            comment_body += (
                f"\n- `{vuln['old_severity']} → "
                f"{vuln['new_severity']}` "
                f"`{vuln['file']}:{vuln['line']}` "
                f"- {vuln['message']}"
            )

    return comment_body


def handler(event, context):

    action = event.get(
        "action",
        "compare"
    )

    report_bucket = event.get(
        "report_bucket",
        os.environ.get("REPORT_BUCKET")
    )

    repository = event.get(
        "repository"
    )

    base_report_key = event.get(
        "base_report_key"
    )

    pr_report_key = event.get(
        "pr_report_key"
    )

    diff_report_key = event.get(
        "diff_report_key"
    )

    github_owner = event.get(
        "github_owner"
    )

    github_repo = event.get(
        "github_repo"
    )

    pr_number = event.get(
        "pr_number"
    )

    if not report_bucket:
        raise Exception(
            "Missing report_bucket"
        )

    if not base_report_key:
        raise Exception(
            "Missing base_report_key"
        )

    if not pr_report_key:
        raise Exception(
            "Missing pr_report_key"
        )

    if not diff_report_key:
        raise Exception(
            "Missing diff_report_key"
        )

    _log(
        "reading_reports",
        repository=repository,
        report_bucket=report_bucket,
        base_report_key=base_report_key,
        pr_report_key=pr_report_key,
    )

    base_report = read_s3_json(
        report_bucket,
        base_report_key
    )

    pr_report = read_s3_json(
        report_bucket,
        pr_report_key
    )

    comparison_result = compare_reports(
        base_report,
        pr_report
    )

    diff_report = {

        "action":
            action,

        "report_bucket":
            report_bucket,

        "repository":
            repository,

        "base_report_key":
            base_report_key,

        "pr_report_key":
            pr_report_key,

        "diff_report_key":
            diff_report_key,

        "message":
            "Comparison completed successfully.",

        **comparison_result
    }

    _put_metric("DiffReportWriteAttempted")

    s3.put_object(

        Bucket=report_bucket,

        Key=diff_report_key,

        Body=json.dumps(
            diff_report,
            indent=2
        ).encode("utf-8"),

        ContentType="application/json",
    )

    _put_metric("DiffReportWriteSucceeded")

    s3.put_object(

        Bucket=report_bucket,

        Key="base_report.json",

        Body=json.dumps(
            base_report,
            indent=2
        ).encode("utf-8"),

        ContentType="application/json",
    )

    s3.put_object(

        Bucket=report_bucket,

        Key="pr_report.json",

        Body=json.dumps(
            pr_report,
            indent=2
        ).encode("utf-8"),

        ContentType="application/json",
    )

    s3.put_object(

        Bucket=report_bucket,

        Key="comparison_report.json",

        Body=json.dumps(
            diff_report,
            indent=2
        ).encode("utf-8"),

        ContentType="application/json",
    )

    _log(
        "latest_dashboard_reports_updated",
        repository=repository
    )

    comment_posted = False

    _log(
        "github_pr_values",
        github_owner=github_owner,
        github_repo=github_repo,
        pr_number=pr_number
    )

    if (
        github_owner
        and github_repo
        and pr_number
    ):

        _put_metric("PRCommentAttempted")

        comment_body = build_comment_body(
            comparison_result
        )

        post_pr_comment(

            github_owner,

            github_repo,

            pr_number,

            comment_body
        )

        comment_posted = True

        _put_metric("PRCommentSucceeded")

    _put_metric("ParallelScanCompleted")

    _log(
        "comparison_completed",
        repository=repository,
        diff_report_key=diff_report_key,
        comment_posted=comment_posted
    )

    return {

        "success":
            True,

        "comparison_report":
            diff_report_key,

        "summary":
            comparison_result[
                "summary"
            ],

        "pr_comment_posted":
            comment_posted
    }
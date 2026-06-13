#!/usr/bin/env sh
set -eu

required_env() {
  name="$1"
  value="$(eval "printf '%s' \"\${$name:-}\"")"
  if [ -z "$value" ]; then
    echo "Missing required environment variable: $name" >&2
    exit 1
  fi
}

required_env REPORT_BUCKET
required_env REPORT_KEY
required_env SCAN_KIND

INPUT_ZIP_KEY="${INPUT_ZIP_KEY:-}"
SOURCE_ZIP_URL="${SOURCE_ZIP_URL:-}"
METRICS_NAMESPACE="${METRICS_NAMESPACE:-PRSecurityScanner}"
PROJECT_NAME="${PROJECT_NAME:-pr-security-scanner}"
start_time="$(date +%s)"

if [ -z "$INPUT_ZIP_KEY" ] && [ -z "$SOURCE_ZIP_URL" ]; then
  echo "Missing source input: set INPUT_ZIP_KEY or SOURCE_ZIP_URL" >&2
  exit 1
fi

log_json() {
  event="$1"
  message="$2"
  printf '{"event":"%s","message":"%s","scan_kind":"%s","bucket":"%s","input_zip_key":"%s","source_zip_url":"%s","report_key":"%s"}\n' \
    "$event" "$message" "$SCAN_KIND" "$REPORT_BUCKET" "$INPUT_ZIP_KEY" "$SOURCE_ZIP_URL" "$REPORT_KEY"
}

put_metric() {
  metric_name="$1"
  value="$2"
  unit="$3"
  aws cloudwatch put-metric-data \
    --namespace "$METRICS_NAMESPACE" \
    --metric-name "$metric_name" \
    --dimensions "Project=${PROJECT_NAME},ScanKind=${SCAN_KIND}" \
    --value "$value" \
    --unit "$unit" >/dev/null 2>&1 || true
}

record_exit_metrics() {
  status="$?"
  end_time="$(date +%s)"
  duration="$((end_time - start_time))"

  put_metric "ScanDurationSeconds" "$duration" "Seconds"

  if [ "$status" -ne 0 ]; then
    log_json "scan_failed" "Scanner task failed"
    put_metric "ScanFailed" 1 "Count"
  fi
}

trap record_exit_metrics EXIT

work_dir="/tmp/scanner-work"
source_zip="${work_dir}/source.zip"
source_dir="${work_dir}/source"
report_file="${work_dir}/report.json"

rm -rf "$work_dir"
mkdir -p "$source_dir"

log_json "scan_started" "Starting Semgrep scan"
put_metric "ScanStarted" 1 "Count"

if [ -n "$INPUT_ZIP_KEY" ]; then
  log_json "download_started" "Downloading source zip from S3"
  put_metric "S3DownloadAttempted" 1 "Count"
  aws s3 cp "s3://${REPORT_BUCKET}/${INPUT_ZIP_KEY}" "$source_zip"
  put_metric "S3DownloadSucceeded" 1 "Count"
else
  log_json "download_started" "Downloading source zip from GitHub archive URL"
  put_metric "SourceDownloadAttempted" 1 "Count"
  python - "$SOURCE_ZIP_URL" "$source_zip" <<'PY'
import sys
import urllib.request

urllib.request.urlretrieve(sys.argv[1], sys.argv[2])
PY
  put_metric "SourceDownloadSucceeded" 1 "Count"
fi

python -m zipfile -e "$source_zip" "$source_dir"

log_json "semgrep_started" "Running Semgrep"
set +e
semgrep scan --quiet --config p/default --json "$source_dir" > "$report_file"
semgrep_exit="$?"
set -e

if [ "$semgrep_exit" -ne 0 ]; then
  log_json "semgrep_nonzero_exit" "Semgrep exited nonzero; uploading report if available"
fi

if [ ! -s "$report_file" ]; then
  printf '{"errors":[{"message":"Semgrep did not produce a report","exit_code":%s}]}\n' "$semgrep_exit" > "$report_file"
fi

log_json "upload_started" "Uploading Semgrep report to S3"
put_metric "S3UploadAttempted" 1 "Count"
aws s3 cp "$report_file" "s3://${REPORT_BUCKET}/${REPORT_KEY}" --content-type application/json
put_metric "S3UploadSucceeded" 1 "Count"

rm -rf "$work_dir"

put_metric "ScanCompleted" 1 "Count"
log_json "scan_completed" "Scan complete"

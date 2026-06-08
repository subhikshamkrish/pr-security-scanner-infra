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
required_env INPUT_ZIP_KEY
required_env REPORT_KEY
required_env SCAN_KIND

log_json() {
  event="$1"
  message="$2"
  printf '{"event":"%s","message":"%s","scan_kind":"%s","bucket":"%s","input_zip_key":"%s","report_key":"%s"}\n' \
    "$event" "$message" "$SCAN_KIND" "$REPORT_BUCKET" "$INPUT_ZIP_KEY" "$REPORT_KEY"
}

work_dir="/tmp/scanner-work"
source_zip="${work_dir}/source.zip"
source_dir="${work_dir}/source"
report_file="${work_dir}/report.json"

rm -rf "$work_dir"
mkdir -p "$source_dir"

log_json "scan_started" "Starting Semgrep scan"
log_json "download_started" "Downloading source zip from S3"
aws s3 cp "s3://${REPORT_BUCKET}/${INPUT_ZIP_KEY}" "$source_zip"

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
aws s3 cp "$report_file" "s3://${REPORT_BUCKET}/${REPORT_KEY}" --content-type application/json

rm -rf "$work_dir"

log_json "scan_completed" "Scan complete"

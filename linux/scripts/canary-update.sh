#!/usr/bin/env bash
set -euo pipefail

canary_file="/srv/ftp/cnc-files/.canary"
timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

mkdir -p "$(dirname "$canary_file")"
printf "canary-updated=%s\n" "$timestamp" > "$canary_file"

#!/usr/bin/env bash
set -euo pipefail

manifest="/var/lib/cnc-ftp/fim-manifest.sha256"
target_dir="/srv/ftp/cnc-files"

if [[ ! -f "$manifest" ]]; then
  echo "Manifest not found: $manifest" >&2
  exit 1
fi

if [[ ! -d "$target_dir" ]]; then
  echo "Target directory not found: $target_dir" >&2
  exit 1
fi

cd "$target_dir"
sha256sum -c "$manifest"

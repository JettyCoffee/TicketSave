#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/test/vision_ticket_ocr.swift"

if [[ ! -f "$SCRIPT" ]]; then
  echo "Missing script: $SCRIPT"
  exit 1
fi

if [[ "$#" -gt 0 ]]; then
  xcrun swift "$SCRIPT" "$@"
else
  xcrun swift "$SCRIPT"
fi

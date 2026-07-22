#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
SERIES_INDEX_FILE="${SERIES_INDEX_FILE:-$ROOT/series-index.txt}"
BACKGROUND_DIR="${BACKGROUND_DIR:-$ROOT/backgrounds}"
OUT_DIR="${OUT_DIR:-$ROOT/icons}"
CREATE_SERIES_SCRIPT="$ROOT/bin/create_series.sh"

usage() {
  echo "Usage: $0 [--series-index <file>] [--background-dir <dir>] [--output-dir <dir>] [--data <file>] [--overlay-dir <dir>] [--font <font.ttf>] [--only-series <id,id,...>]"
  echo ""
  echo "Series index format (whitespace separated):"
  echo "  <id> <background-img>"
  echo ""
  echo "Example lines:"
  echo "  mc grass_block.png"
  echo "  forge anvil.png"
}

resolve_path() {
  local input_path="$1"
  if [[ "$input_path" = /* ]]; then
    echo "$input_path"
  else
    echo "$ROOT/$input_path"
  fi
}

SERIES_FILTER_RAW=""
FORWARD_DATA_FILE=""
FORWARD_OVERLAY_DIR=""
FORWARD_FONT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --series-index)
      SERIES_INDEX_FILE="$2"
      shift 2
      ;;
    --background-dir)
      BACKGROUND_DIR="$2"
      shift 2
      ;;
    --output-dir)
      OUT_DIR="$2"
      shift 2
      ;;
    --data)
      FORWARD_DATA_FILE="$2"
      shift 2
      ;;
    --overlay-dir)
      FORWARD_OVERLAY_DIR="$2"
      shift 2
      ;;
    --font)
      FORWARD_FONT="$2"
      shift 2
      ;;
    --only-series)
      SERIES_FILTER_RAW="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

SERIES_INDEX_FILE="$(resolve_path "$SERIES_INDEX_FILE")"
BACKGROUND_DIR="$(resolve_path "$BACKGROUND_DIR")"
OUT_DIR="$(resolve_path "$OUT_DIR")"

if [[ ! -f "$SERIES_INDEX_FILE" ]]; then
  echo "Series index not found: $SERIES_INDEX_FILE"
  exit 1
fi

if [[ ! -d "$BACKGROUND_DIR" ]]; then
  echo "Background directory not found: $BACKGROUND_DIR"
  exit 1
fi

if [[ ! -x "$CREATE_SERIES_SCRIPT" ]]; then
  echo "create_series.sh missing or not executable: $CREATE_SERIES_SCRIPT"
  exit 1
fi

declare -A SERIES_FILTER_SET
FILTER_ENABLED=0
if [[ -n "$SERIES_FILTER_RAW" ]]; then
  FILTER_ENABLED=1
  IFS=',' read -r -a FILTER_LIST <<< "$SERIES_FILTER_RAW"
  for filter_value in "${FILTER_LIST[@]}"; do
    SERIES_FILTER_SET["$filter_value"]=1
  done
fi

mkdir -p "$OUT_DIR"

series_total=0
series_created=0

while read -r series_id background_img extra_value; do
  [[ -z "${series_id:-}" ]] && continue
  [[ "$series_id" =~ ^# ]] && continue

  if [[ -n "${extra_value:-}" ]]; then
    echo "Skipping malformed line (too many fields): $series_id $background_img $extra_value"
    continue
  fi

  series_total=$((series_total + 1))

  if [[ "$FILTER_ENABLED" -eq 1 ]]; then
    if [[ -z "${SERIES_FILTER_SET[$series_id]+x}" ]]; then
      continue
    fi
  fi

  if [[ -z "${background_img:-}" ]]; then
    echo "Missing background image for series: $series_id"
    exit 1
  fi

  background_path="$BACKGROUND_DIR/$background_img"
  if [[ ! -f "$background_path" ]]; then
    echo "Background not found for series $series_id: $background_path"
    exit 1
  fi

  series_out_dir="$OUT_DIR/$series_id"

  command=(
    "$CREATE_SERIES_SCRIPT"
    --series-id "$series_id"
    --background "$background_path"
    --output-dir "$series_out_dir"
  )

  if [[ -n "$FORWARD_DATA_FILE" ]]; then
    command+=(--data "$FORWARD_DATA_FILE")
  fi

  if [[ -n "$FORWARD_OVERLAY_DIR" ]]; then
    command+=(--overlay-dir "$FORWARD_OVERLAY_DIR")
  fi

  if [[ -n "$FORWARD_FONT" ]]; then
    command+=(--font "$FORWARD_FONT")
  fi

  "${command[@]}"
  series_created=$((series_created + 1))
done < "$SERIES_INDEX_FILE"

echo "Created series: $series_created of $series_total"
echo "Output root: $OUT_DIR"

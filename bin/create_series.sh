#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
DATA_FILE="${DATA_FILE:-$ROOT/version-index.txt}"
OVERLAY_DIR="${OVERLAY_DIR:-$ROOT/overlays}"
OUT_DIR="${OUT_DIR:-$ROOT/icons}"
BACKGROUND_FILE="${BACKGROUND_FILE:-$ROOT/backgrounds/grass_block.png}"
SERIES_ID="${SERIES_ID:-mc}"
CREATE_ICON_SCRIPT="$ROOT/bin/create_icon.sh"

usage() {
  echo "Usage: $0 [--series-id <id>] [--data <file>] [--overlay-dir <dir>] [--output-dir <dir>] [--background <file>] [--font <font.ttf>] [--only <id,id,...>]"
  echo ""
  echo "Data file format (whitespace separated):"
  echo "  <version> <overlay-file> <effect> <version-name>"
  echo ""
  echo "Example line:"
  echo "  1.19 1.19_sculk_sensor.png glow The_Wild_Update"
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name"
    exit 1
  fi
}

resolve_path() {
  local input_path="$1"
  if [[ "$input_path" = /* ]]; then
    echo "$input_path"
  else
    echo "$ROOT/$input_path"
  fi
}

FILTER_RAW=""
FONT_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --series-id|--id)
      SERIES_ID="$2"
      shift 2
      ;;
    --data)
      DATA_FILE="$2"
      shift 2
      ;;
    --overlay-dir)
      OVERLAY_DIR="$2"
      shift 2
      ;;
    --output-dir)
      OUT_DIR="$2"
      shift 2
      ;;
    --background)
      BACKGROUND_FILE="$2"
      shift 2
      ;;
    --font)
      FONT_ARG="$2"
      shift 2
      ;;
    --only)
      FILTER_RAW="$2"
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

require_command magick

if [[ -z "$SERIES_ID" ]]; then
  echo "Series id must not be empty"
  exit 1
fi

DATA_FILE="$(resolve_path "$DATA_FILE")"
OVERLAY_DIR="$(resolve_path "$OVERLAY_DIR")"
OUT_DIR="$(resolve_path "$OUT_DIR")"
BACKGROUND_FILE="$(resolve_path "$BACKGROUND_FILE")"

if [[ ! -f "$DATA_FILE" ]]; then
  echo "Data file not found: $DATA_FILE"
  exit 1
fi

if [[ ! -d "$OVERLAY_DIR" ]]; then
  echo "Overlay directory not found: $OVERLAY_DIR"
  exit 1
fi

if [[ ! -f "$BACKGROUND_FILE" ]]; then
  echo "Background not found: $BACKGROUND_FILE"
  exit 1
fi

if [[ ! -x "$CREATE_ICON_SCRIPT" ]]; then
  echo "create_icon.sh missing or not executable: $CREATE_ICON_SCRIPT"
  exit 1
fi

mkdir -p "$OUT_DIR"

declare -A FILTER_SET
declare -A OUTPUT_NAME_SET
FILTER_ENABLED=0
if [[ -n "$FILTER_RAW" ]]; then
  FILTER_ENABLED=1
  IFS=',' read -r -a FILTER_LIST <<< "$FILTER_RAW"
  for filter_value in "${FILTER_LIST[@]}"; do
    FILTER_SET["$filter_value"]=1
  done
fi

total_count=0
created_count=0

while read -r version_id overlay_file effect_value version_name extra_value; do
  [[ -z "${version_id:-}" ]] && continue
  [[ "$version_id" =~ ^# ]] && continue

  if [[ -n "${extra_value:-}" ]]; then
    echo "Skipping malformed line (too many fields): $version_id $overlay_file $effect_value $version_name $extra_value"
    continue
  fi

  total_count=$((total_count + 1))

  if [[ "$FILTER_ENABLED" -eq 1 ]]; then
    if [[ -z "${FILTER_SET[$version_id]+x}" ]]; then
      continue
    fi
  fi

  if [[ -z "${overlay_file:-}" ]]; then
    echo "Missing overlay filename for version: $version_id"
    exit 1
  fi

  effect_style="${effect_value:-none}"

  overlay_path="$OVERLAY_DIR/$overlay_file"
  output_subdir=""

  case "$overlay_file" in
    alt/*)
      output_subdir="alt"
      ;;
  esac

  if [[ ! -f "$overlay_path" ]]; then
    echo "Overlay not found for version $version_id: $overlay_file"
    exit 1
  fi

  background_path="$BACKGROUND_FILE"
  output_filename="${version_id}-${version_name}.png"
  overlay_stem="${overlay_file%.png}"
  overlay_suffix="${overlay_stem#${version_id}_}"

  if [[ -n "$output_subdir" ]]; then
    output_path="$OUT_DIR/$output_subdir/$output_filename"
  else
    output_path="$OUT_DIR/$output_filename"
  fi

  output_key="$output_path"
  if [[ -n "${OUTPUT_NAME_SET[$output_key]+x}" ]]; then
    output_filename="${version_id}-${version_name}-${overlay_suffix}.png"
    if [[ -n "$output_subdir" ]]; then
      output_path="$OUT_DIR/$output_subdir/$output_filename"
    else
      output_path="$OUT_DIR/$output_filename"
    fi
    output_key="$output_path"
  fi
  OUTPUT_NAME_SET["$output_key"]=1

  command=(
    "$CREATE_ICON_SCRIPT"
    --background "$background_path"
    --overlay "$overlay_path"
    --version-text "$version_id"
    --effect "$effect_style"
    --output "$output_path"
  )

  if [[ -n "$FONT_ARG" ]]; then
    command+=(--font "$FONT_ARG")
  fi

  "${command[@]}"
  created_count=$((created_count + 1))
done < "$DATA_FILE"

echo "Created $created_count icon(s) from $total_count row(s)."
echo "Output directory: $OUT_DIR"

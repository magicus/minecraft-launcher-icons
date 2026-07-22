#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
CHANGELOG_FILE="${CHANGELOG_FILE:-$ROOT/CHANGELOG.md}"
RELEASES_DIR="${RELEASES_DIR:-$ROOT/releases}"
OUT_DIR="${OUT_DIR:-$ROOT/icons}"
EXTRA_README_FILE="${EXTRA_README_FILE:-$ROOT/resources/README-minecraft-launcher-icons.md}"
CREATE_ALL_SCRIPT="$ROOT/bin/create_all_icons.sh"
VERSION_OVERRIDE=""

usage() {
  echo "Usage: $0 [--version <version>] [--changelog <file>] [--releases-dir <dir>] [--output-dir <dir>] [-- <create_all_icons args...>]"
  echo ""
  echo "By default, version is parsed from the first release heading in CHANGELOG.md:"
  echo "  ## <version> - <date>"
  echo ""
  echo "Example:"
  echo "  $0 -- --only-series mc"
}

resolve_path() {
  local input_path="$1"
  if [[ "$input_path" = /* ]]; then
    echo "$input_path"
  else
    echo "$ROOT/$input_path"
  fi
}

extract_version_from_changelog() {
  local changelog_path="$1"
  local version_line
  version_line="$(grep -m1 '^## ' "$changelog_path" || true)"

  if [[ -z "$version_line" ]]; then
    echo ""
    return
  fi

  sed -E 's/^##[[:space:]]+([^[:space:]]+).*$/\1/' <<< "$version_line"
}

FORWARD_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION_OVERRIDE="$2"
      shift 2
      ;;
    --changelog)
      CHANGELOG_FILE="$2"
      shift 2
      ;;
    --releases-dir)
      RELEASES_DIR="$2"
      shift 2
      ;;
    --output-dir)
      OUT_DIR="$2"
      shift 2
      ;;
    --)
      shift
      FORWARD_ARGS=("$@")
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      FORWARD_ARGS+=("$1")
      shift
      ;;
  esac
done

CHANGELOG_FILE="$(resolve_path "$CHANGELOG_FILE")"
RELEASES_DIR="$(resolve_path "$RELEASES_DIR")"
OUT_DIR="$(resolve_path "$OUT_DIR")"
EXTRA_README_FILE="$(resolve_path "$EXTRA_README_FILE")"

if ! command -v zip >/dev/null 2>&1; then
  echo "Missing required command: zip"
  exit 1
fi

if [[ ! -x "$CREATE_ALL_SCRIPT" ]]; then
  echo "create_all_icons.sh missing or not executable: $CREATE_ALL_SCRIPT"
  exit 1
fi

version="$VERSION_OVERRIDE"
if [[ -z "$version" ]]; then
  if [[ ! -f "$CHANGELOG_FILE" ]]; then
    echo "Changelog not found: $CHANGELOG_FILE"
    exit 1
  fi
  version="$(extract_version_from_changelog "$CHANGELOG_FILE")"
fi

if [[ -z "$version" ]]; then
  echo "Could not determine release version. Use --version or add a changelog heading like: ## <version> - <date>"
  exit 1
fi

mkdir -p "$RELEASES_DIR"

"$CREATE_ALL_SCRIPT" --output-dir "$OUT_DIR" "${FORWARD_ARGS[@]}"

zip_file="$RELEASES_DIR/minecraft-launcher-icons-${version}.zip"

if [[ ! -d "$OUT_DIR" ]]; then
  echo "Output directory not found: $OUT_DIR"
  exit 1
fi

if [[ ! -f "$EXTRA_README_FILE" ]]; then
  echo "Extra README file not found: $EXTRA_README_FILE"
  exit 1
fi

rm -f "$zip_file"
stage_dir="$(mktemp -d)"
trap 'rm -rf "$stage_dir"' EXIT

cp -R "$OUT_DIR"/. "$stage_dir"/
cp "$EXTRA_README_FILE" "$stage_dir/README-minecraft-launcher-icons.md"

(
  cd "$stage_dir"
  zip -rq "$zip_file" .
)

echo "Created release: $zip_file"

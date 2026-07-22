#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --background <background.png> --overlay <overlay.png> --version-text <text> --output <output.png> [--effect none|shadow|glow] [--font <font.ttf>]"
}

resolve_path() {
  local input_path="$1"
  if [[ "$input_path" = /* ]]; then
    echo "$input_path"
  else
    echo "$TOPDIR/$input_path"
  fi
}

TOPDIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"

BACKGROUND_PATH=""
OVERLAY_PATH=""
VERSION_TEXT=""
OUTPUT_PATH=""
EFFECT_STYLE="none"
FONT_PATH="${FONT_PATH:-$TOPDIR/resources/minecraftia.ttf}"
MAGICK="${MAGICK:-magick}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --background)
      BACKGROUND_PATH="$2"
      shift 2
      ;;
    --overlay)
      OVERLAY_PATH="$2"
      shift 2
      ;;
    --version-text)
      VERSION_TEXT="$2"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --effect)
      EFFECT_STYLE="$2"
      shift 2
      ;;
    --font)
      FONT_PATH="$2"
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

if [[ -z "$BACKGROUND_PATH" || -z "$OVERLAY_PATH" || -z "$VERSION_TEXT" || -z "$OUTPUT_PATH" ]]; then
  usage
  exit 1
fi

case "$EFFECT_STYLE" in
  none|shadow|glow)
    ;;
  *)
    echo "Invalid effect: $EFFECT_STYLE"
    echo "Allowed effects: none, shadow, glow"
    exit 1
    ;;
esac

BACKGROUND_PATH="$(resolve_path "$BACKGROUND_PATH")"
OVERLAY_PATH="$(resolve_path "$OVERLAY_PATH")"
OUTPUT_PATH="$(resolve_path "$OUTPUT_PATH")"
FONT_PATH="$(resolve_path "$FONT_PATH")"

if [[ ! -f "$BACKGROUND_PATH" ]]; then
  echo "Background not found: $BACKGROUND_PATH"
  exit 1
fi

if [[ ! -f "$OVERLAY_PATH" ]]; then
  echo "Overlay not found: $OVERLAY_PATH"
  exit 1
fi

if [[ ! -f "$FONT_PATH" ]]; then
  echo "Font not found: $FONT_PATH"
  exit 1
fi

if [[ "$MAGICK" == */* ]]; then
  if [[ ! -x "$MAGICK" ]]; then
    echo "Missing required command: $MAGICK"
    exit 1
  fi
elif ! command -v "$MAGICK" >/dev/null 2>&1; then
  echo "Missing required command: $MAGICK"
  exit 1
fi

OVERLAY_SIZE_EXPECTED="128x128"
OVERLAY_SIZE_ACTUAL="$("$MAGICK" identify -format '%wx%h' "$OVERLAY_PATH")"
if [[ "$OVERLAY_SIZE_ACTUAL" != "$OVERLAY_SIZE_EXPECTED" ]]; then
  echo "Overlay must be $OVERLAY_SIZE_EXPECTED, got: $OVERLAY_SIZE_ACTUAL"
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

CANVAS_SIZE="300"
ICON_POS_X="85"
ICON_POS_Y="135"

DECORATION_SHADOW_SHIFT_Y="8"
DECORATION_SHADOW_FEATHER_BLUR="0x1.6"
DECORATION_SHADOW_ALPHA_MULTIPLIER="0.687500"
DECORATION_SHADOW_MASK_THRESHOLD="1%"

DECORATION_GLOW_SAT_SCALE="0.78"
DECORATION_GLOW_VAL_SCALE="1.25"
DECORATION_GLOW_MASK_THRESHOLD="1%"
DECORATION_GLOW_MASK_DILATE="Octagon:3"
DECORATION_GLOW_MASK_BLUR="0x5"
DECORATION_GLOW_MASK_LEVEL_MAX="92%"

TEXT_BOX_X="54"
TEXT_BOX_Y="50"
TEXT_BOX_W="192"
TEXT_BOX_H="73"
TEXT_POINT_SIZE="72"
TEXT_KERNING="3.6"
TEXT_OUTLINE_RADIUS="5.3"
TEXT_ANNOTATE_OFFSET="+5-4"

if [[ ${#VERSION_TEXT} -gt 4 ]]; then
  TEXT_BOX_X="18"
  TEXT_BOX_W="264"
  TEXT_POINT_SIZE="58"
  TEXT_KERNING="2.4"
  TEXT_ANNOTATE_OFFSET="+5-8"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

OVERLAY_OUTPUT=$TMP_DIR/tmp-1-overlay.png
DECORATION_OUTPUT=$TMP_DIR/tmp-2-decoration.png
TEXT_OUTPUT=$TMP_DIR/tmp-3-text.png
FINAL_OUTPUT=$TMP_DIR/tmp-4-final.png

# Step 1: build full-size overlay component on the same canvas as final output.
CREATE_OVERLAY_CANVAS="-size ${CANVAS_SIZE}x${CANVAS_SIZE} xc:none"
RENDER_OVERLAY="-geometry +${ICON_POS_X}+${ICON_POS_Y} \
  -compose over -composite \
  -define png:color-type=6"

"$MAGICK" $CREATE_OVERLAY_CANVAS "$OVERLAY_PATH" \
  $RENDER_OVERLAY "$OVERLAY_OUTPUT"

# Step 2: build full-size decoration component (none, shadow, glow).
if [[ "$EFFECT_STYLE" == "shadow" ]]; then
  CREATE_SHADOW_CANVAS="-size ${CANVAS_SIZE}x${CANVAS_SIZE} xc:none"
  CREATE_SHADOW_MASK_CANVAS="-size ${CANVAS_SIZE}x${CANVAS_SIZE} xc:black"
  BUILD_SHADOW_MASK="-alpha extract \
      -threshold $DECORATION_SHADOW_MASK_THRESHOLD \
      -blur $DECORATION_SHADOW_FEATHER_BLUR"
  APPLY_SHADOW_OPACITY="-compose copyopacity -composite \
      -channel A -evaluate multiply \
      $DECORATION_SHADOW_ALPHA_MULTIPLIER +channel"
  POSITION_SHADOW="-geometry +0+${DECORATION_SHADOW_SHIFT_Y} \
      -compose over -composite"

  "$MAGICK" $CREATE_SHADOW_CANVAS \
    \( $CREATE_SHADOW_MASK_CANVAS \
      \( $OVERLAY_OUTPUT $BUILD_SHADOW_MASK \) \
      $APPLY_SHADOW_OPACITY \
    \) \
    $POSITION_SHADOW "$DECORATION_OUTPUT"
elif [[ "$EFFECT_STYLE" == "glow" ]]; then
  CALCULATE_GLOW_COLOR="-trim +repage -alpha remove -alpha off -scale 1x1 \
    -colorspace HSB \
    -channel G -evaluate multiply $DECORATION_GLOW_SAT_SCALE +channel \
    -channel B -evaluate multiply $DECORATION_GLOW_VAL_SCALE +channel \
    -colorspace sRGB"
  GLOW_COLOR="$("$MAGICK" $OVERLAY_OUTPUT $CALCULATE_GLOW_COLOR \
    -format '%[pixel:p{0,0}]' info:)"
  CREATE_GLOW_CANVAS="-size ${CANVAS_SIZE}x${CANVAS_SIZE} xc:$GLOW_COLOR"
  BUILD_GLOW="-alpha extract -threshold $DECORATION_GLOW_MASK_THRESHOLD \
      -morphology Dilate $DECORATION_GLOW_MASK_DILATE \
      -blur $DECORATION_GLOW_MASK_BLUR \
      -level 0,$DECORATION_GLOW_MASK_LEVEL_MAX \
      -alpha off"
  COMPOSE_GLOW_AND_OUTPUT="-alpha off -compose CopyOpacity -composite"

  "$MAGICK" $CREATE_GLOW_CANVAS \
    \( $OVERLAY_OUTPUT $BUILD_GLOW \) \
    $COMPOSE_GLOW_AND_OUTPUT "$DECORATION_OUTPUT"
else
  CREATE_EMPTY_CANVAS="-size ${CANVAS_SIZE}x${CANVAS_SIZE} xc:none"
  "$MAGICK" $CREATE_EMPTY_CANVAS "$DECORATION_OUTPUT"
fi

# Step 3: generate text component (white text + black outline) on transparent 300x300.
CREATE_TEXT_CANVAS="-size ${CANVAS_SIZE}x${CANVAS_SIZE} xc:none"
SET_FONT="-font"
CREATE_TEXTBOX_CANVAS="-size ${TEXT_BOX_W}x${TEXT_BOX_H} xc:none"
RENDER_TEXT="+antialias -pointsize $TEXT_POINT_SIZE -kerning $TEXT_KERNING \
  -fill white -stroke none \
  -gravity center -annotate $TEXT_ANNOTATE_OFFSET $VERSION_TEXT +repage"
POSITION_TEXT="-gravity northwest \
  -geometry +${TEXT_BOX_X}+${TEXT_BOX_Y} -compose over -composite \
  +geometry -gravity none +write mpr:text_layer +delete"
CREATE_TEXT_OUTLINE="-size ${CANVAS_SIZE}x${CANVAS_SIZE} xc:black \
  mpr:text_layer -alpha extract \
  -morphology EdgeOut Disk:${TEXT_OUTLINE_RADIUS} \
  -alpha off"
COMPOSE_TEXT="-compose copyopacity -composite \
  mpr:text_layer -compose over -composite"
STRIP_VOLATILE_METADATA="-define png:exclude-chunks=date,time"

"$MAGICK" $CREATE_TEXT_CANVAS \
  \( $SET_FONT "$FONT_PATH" $CREATE_TEXTBOX_CANVAS $RENDER_TEXT \) \
  $POSITION_TEXT $CREATE_TEXT_OUTLINE $COMPOSE_TEXT "$TEXT_OUTPUT"

# Step 4: final composition in one pass: background -> decoration -> overlay -> text.
"$MAGICK" "$BACKGROUND_PATH" \
  $DECORATION_OUTPUT -compose over -composite \
  $OVERLAY_OUTPUT -compose over -composite \
  $TEXT_OUTPUT -compose over -composite \
  $STRIP_VOLATILE_METADATA \
  "$FINAL_OUTPUT"

cp "$FINAL_OUTPUT" "$OUTPUT_PATH"

echo "Created icon: $OUTPUT_PATH"

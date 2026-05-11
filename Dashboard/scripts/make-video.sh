#!/usr/bin/env bash
# make-video.sh — Full pipeline: HTML → frames → TTS → MP4
# Usage: bash scripts/make-video.sh <html-file> <output.mp4> <duration-sec> [narration-file.txt]
set -e

HTML="$1"
OUT="$2"
DUR="${3:-35}"
NARRATION_FILE="${4:-}"

if [ -z "$HTML" ] || [ -z "$OUT" ]; then
  echo "Usage: bash scripts/make-video.sh <html-file> <output.mp4> <duration-sec> [narration-file.txt]"
  exit 1
fi

mkdir -p marketing/output .tmp

FRAMES=".tmp/frames_$$"

echo "=== Step 1/3: Rendering frames ($DUR s) ==="
node scripts/render-frames.js "$HTML" "$FRAMES" "$DUR" 2
echo ""

if [ -n "$NARRATION_FILE" ] && [ -f "$NARRATION_FILE" ]; then
  echo "=== Step 2/3: Generating TTS narration ==="
  NAR_MP3=".tmp/narration_$$.mp3"
  /c/Python314/python.exe scripts/gen-narration.py "$NARRATION_FILE" "$NAR_MP3"
  echo ""
else
  NAR_MP3=""
fi

echo "=== Step 3/3: Compositing video ==="
if [ -n "$NAR_MP3" ] && [ -f "$NAR_MP3" ]; then
  # Video + audio
  ffmpeg -y -framerate 2 -i "$FRAMES/frame_%04d.png" -i "$NAR_MP3" \
    -c:v libx264 -preset fast -crf 23 -pix_fmt yuv420p \
    -c:a aac -b:a 128k -shortest \
    -vf "scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2" \
    "$OUT" </dev/null 2>/dev/null
else
  # Video only
  ffmpeg -y -framerate 2 -i "$FRAMES/frame_%04d.png" \
    -c:v libx264 -preset fast -crf 23 -pix_fmt yuv420p \
    -vf "scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2" \
    "$OUT" </dev/null 2>/dev/null
fi

# Cleanup
rm -rf "$FRAMES" "$NAR_MP3" 2>/dev/null

echo ""
echo "=== Done: $OUT ==="
ls -lh "$OUT" | awk '{print "Size:", $5}'

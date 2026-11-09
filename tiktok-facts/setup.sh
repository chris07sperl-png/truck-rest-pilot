#!/usr/bin/env bash
# Installs everything the renderer needs. Safe to run repeatedly.
set -euo pipefail
cd "$(dirname "$0")"

pip install -q piper-tts cairosvg pillow numpy 2>&1 | grep -v -i "warning" || true

mkdir -p assets/voices assets/twemoji
V=assets/voices/de_DE-thorsten-high
HF=https://huggingface.co/rhasspy/piper-voices/resolve/main/de/de_DE/thorsten/high
[ -s "$V.onnx" ] || curl -sSfL -o "$V.onnx" "$HF/de_DE-thorsten-high.onnx"
[ -s "$V.onnx.json" ] || curl -sSfL -o "$V.onnx.json" "$HF/de_DE-thorsten-high.onnx.json"

if [ ! -f assets/twemoji/1fa90.svg ]; then
  tmp=$(mktemp -d)
  (cd "$tmp" && npm pack @twemoji/svg@15.0.0 --silent >/dev/null)
  tar xzf "$tmp"/twemoji-svg-*.tgz -C "$tmp"
  cp "$tmp"/package/*.svg assets/twemoji/
  rm -rf "$tmp"
fi
echo "setup ok"

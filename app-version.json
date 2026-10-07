#!/bin/bash
# pi-app-store: 1
set -eu
cd -- "$(dirname -- "$0")"
case "${1:-}" in
  install) python3 -m py_compile cview.py
    command -v ffmpeg >/dev/null || { echo "Install ffmpeg first: apt install ffmpeg"; exit 1; }
    command -v ffprobe >/dev/null ;;
  run) read -r -p "Image or video path (blank cancels): " media
    [ -n "$media" ] || exit 0
    [ -f "$media" ] || { echo "File not found"; exit 1; }
    exec python3 cview.py "$media" ;;
  *) echo "Use: bash app-store.sh install OR bash app-store.sh run"; exit 1 ;;
esac

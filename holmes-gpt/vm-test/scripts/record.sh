#!/usr/bin/env bash
# Records a command's terminal output (the VM has no desktop, so this is the screen recording).
#   recordings/<name>.cast  asciinema recording, replay with: asciinema play recordings/<name>.cast
#   recordings/<name>.gif   animated render (skipped when larger than MAX_GIF_MB)
#   docs/img/<name>.png     last frame, for the README
# Usage: scripts/record.sh <name> <command...>
set -uo pipefail
source "$(dirname "$0")/lib.sh"

NAME=$1; shift
COLS=${COLS:-140}
ROWS=${ROWS:-40}
MAX_GIF_MB=${MAX_GIF_MB:-25}
mkdir -p "$HERE/recordings" "$HERE/docs/img"
CAST=$HERE/recordings/$NAME.cast
GIF=$HERE/recordings/$NAME.gif

# A login shell for docker group membership; TERM fixed so the render looks the same anywhere.
TERM=xterm-256color asciinema rec --overwrite -q --cols "$COLS" --rows "$ROWS" \
  -c "sg docker -c $(printf '%q' "cd $HERE && $(printf '%q ' "$@")")" "$CAST" </dev/null
rc=$?

# Long runs: cap idle gaps and speed up so the GIF stays watchable.
agg --idle-time-limit 2 --speed "${GIF_SPEED:-1}" --font-size 14 "$CAST" "$GIF" >/dev/null 2>&1
uv run -q --with pillow python - "$GIF" "$HERE/docs/img/$NAME.png" <<'EOF'
import sys
from PIL import Image
im = Image.open(sys.argv[1])
im.seek(im.n_frames - 1)
im.convert("RGB").save(sys.argv[2], optimize=True)
EOF
if (( $(stat -c %s "$GIF") > MAX_GIF_MB * 1024 * 1024 )); then
  echo "GIF over ${MAX_GIF_MB} MB, keeping only the .cast and the PNG"; rm -f "$GIF"
fi

# The cast holds raw terminal output: never keep the API key in it.
[[ -n ${OPENAI_API_KEY:-} ]] && sed -i "s/${OPENAI_API_KEY}/<redacted>/g" "$CAST"
echo "recorded $NAME (exit $rc): $(ls "$HERE/recordings/$NAME".* "$HERE/docs/img/$NAME.png" 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
exit $rc

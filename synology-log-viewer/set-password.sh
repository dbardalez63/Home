#!/bin/sh
# Define la contraseña del visor HTML (auth.json con SHA-256).
# Uso: sudo sh set-password.sh 'TuClaveSegura' [/volume1/web/familia/accesos]

set -eu
PASS="${1:-}"
DEST="${2:-/volume1/web/familia/accesos}"

if [ -z "$PASS" ]; then
  echo "Uso: sudo sh set-password.sh 'TuClaveSegura'"
  exit 1
fi

HASH="$(printf '%s' "$PASS" | python3 -c 'import sys,hashlib; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')"

mkdir -p "$DEST"
cat > "$DEST/auth.json" <<EOF
{
  "password_sha256": "${HASH}"
}
EOF
chmod 644 "$DEST/auth.json"
echo "OK: $DEST/auth.json"
echo "Abre: .../familia/accesos/  o  .../familia/accesos/visor.html"

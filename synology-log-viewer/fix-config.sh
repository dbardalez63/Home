#!/bin/sh
# Reescribe config.php con una contraseña.
# Uso:
#   sudo sh fix-config.sh 'TuClaveSegura'
#   sudo sh fix-config.sh 'TuClaveSegura' /volume1/web/familia/accesos

set -eu
PASS="${1:-}"
DEST="${2:-/volume1/web/familia/accesos}"
DATA="${DATA_DIR:-/volume1/@appdata/familia-accesos/recent.json}"

if [ -z "$PASS" ]; then
  echo "Uso: sudo sh fix-config.sh 'TuClaveSegura'"
  exit 1
fi

# Escapa comillas simples para PHP: ' -> '\''
PASS_ESC=$(printf "%s" "$PASS" | sed "s/'/'\\\\''/g")

mkdir -p "$DEST"
cat > "$DEST/config.php" <<EOF
<?php
return [
    'password' => '${PASS_ESC}',
    'session_ttl' => 28800,
    'data_file' => '${DATA}',
];
EOF

chmod 640 "$DEST/config.php"
chown http:http "$DEST/config.php" 2>/dev/null || chown Nobody:Nobody "$DEST/config.php" 2>/dev/null || true

echo "Escrito: $DEST/config.php"
if command -v php >/dev/null 2>&1; then
  php -l "$DEST/config.php" || true
  php -l "$DEST/index.php" || true
fi
cat "$DEST/config.php"

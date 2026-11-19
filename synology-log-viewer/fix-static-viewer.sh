#!/bin/sh
# Instala el visor HTML estatico (sin PHP/CGI) y regenera datos.
# Uso: sudo sh fix-static-viewer.sh

set -eu
APP_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
DEST="/volume1/web/familia/accesos"
DATA_DIR="/volume1/@appdata/familia-accesos"
WEB_DATA="${DEST}/data"

mkdir -p "$DEST" "$WEB_DATA" "$DATA_DIR"

cp -f "$APP_DIR/www/visor.html" "$DEST/visor.html"
cp -f "$APP_DIR/www/visor.html" "$DEST/index.html"

# Evitar que PHP/CGI intercepten
[ -f "$DEST/index.php" ] && mv -f "$DEST/index.php" "$DEST/index.php.bak" || true
[ -f "$DEST/index.cgi" ] && mv -f "$DEST/index.cgi" "$DEST/index.cgi.bak" || true

# Sync Python actualizado
cp -f "$APP_DIR/sync-web-access-log.py" /usr/local/bin/familia-sync-web-access-log.py
chmod 755 /usr/local/bin/familia-sync-web-access-log.py

cat > /usr/local/bin/familia-sync-web-access-log.sh <<EOF
#!/bin/sh
export DATA_DIR="${DATA_DIR}"
export WEB_OUT="${WEB_DATA}/recent.json"
export FILTER="\${FILTER-}"
export MAX_LINES="\${MAX_LINES:-800}"
exec python3 /usr/local/bin/familia-sync-web-access-log.py
EOF
chmod 755 /usr/local/bin/familia-sync-web-access-log.sh

# Password por defecto si no existe
if [ ! -f "$DEST/auth.json" ]; then
  HASH="$(printf '%s' 'TuClaveSegura' | python3 -c 'import sys,hashlib; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')"
  cat > "$DEST/auth.json" <<EOF
{
  "password_sha256": "${HASH}"
}
EOF
  echo "==> auth.json creado. Contraseña temporal: TuClaveSegura"
  echo "    Cambiala con: sudo sh set-password.sh 'NuevaClave'"
fi

/usr/local/bin/familia-sync-web-access-log.sh

chmod -R a+rX "$DEST" || true
echo ""
echo "Abre: http://192.168.2.3/familia/accesos/"
echo "  o:  http://192.168.2.3/familia/accesos/visor.html"
echo "Marca 'Solo /familia' para ocultar el ruido de DSM (/webapi)."
